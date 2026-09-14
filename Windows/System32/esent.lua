-- esent.lua - Jet Blue compatible ESE-style storage engine for LuaNT
-- (C) RedstoneShell 2026
--
-- API COMPATIBILITY:
--   The exported function names and argument lists are intentionally unchanged.
--   Internal storage, WAL, transactions, cursors and page management are replaceable.
--
-- NOTE:
--   This is a LuaNT Jet/ESE-compatible API layer, not Microsoft's native ESE binary
--   database format. It preserves the API used by the original LuaNT DHCP service.

local esent = {}

-- ============================================================
-- Constants
-- ============================================================

local PAGE_SIZE       = 4096
local MAX_PAGES       = 64
local PAGE_HEADER     = 40
local TAG_SIZE        = 8
local MAX_TAG_COUNT   = 64
local FORMAT_MAGIC    = "LJTB"
local FORMAT_VERSION  = 1

local DB_STATE_CLEAN  = 0
local DB_STATE_DIRTY  = 1

-- ============================================================
-- Global state
-- ============================================================

local g_instance = nil
local g_sessions = {}
local g_next_session = 1

-- ============================================================
-- Small compatibility helpers
-- ============================================================

local function Debug(msg)
    if DbgPrint then
        DbgPrint(msg)
    end
end

local function NormalizePath(path)
    if type(path) ~= "string" then
        return path
    end

    path = path:gsub("^%a:\\\\", "/")
    path = path:gsub("^%a:/", "/")
    path = path:gsub("\\\\", "/")
    path = path:gsub("\\", "/")

    return path
end

local function GetFS()
    return component.proxy(computer.getBootAddress())
end

local function EnsureDirectory(fs, path)
    local dir = path and path:match("(.+)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDirectory(dir)
    end
end

local function SafeToString(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

-- ============================================================
-- Integer serialization without requiring Lua bit operators
-- ============================================================

local function UInt32(v)
    v = tonumber(v) or 0
    v = math.floor(v)

    if v < 0 then
        v = v + 4294967296
    end

    return v % 4294967296
end

local function WriteUInt32(v)
    v = UInt32(v)

    local b1 = v % 256
    v = math.floor(v / 256)

    local b2 = v % 256
    v = math.floor(v / 256)

    local b3 = v % 256
    v = math.floor(v / 256)

    local b4 = v % 256

    return string.char(b1, b2, b3, b4)
end

local function ReadUInt32(buf, pos)
    local b1 = string.byte(buf, pos) or 0
    local b2 = string.byte(buf, pos + 1) or 0
    local b3 = string.byte(buf, pos + 2) or 0
    local b4 = string.byte(buf, pos + 3) or 0

    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function WriteString(s)
    s = s or ""
    return WriteUInt32(#s) .. s
end

local function ReadString(buf, pos)
    local length = ReadUInt32(buf, pos)
    pos = pos + 4

    if length <= 0 then
        return "", pos
    end

    if pos + length - 1 > #buf then
        return nil, pos
    end

    return buf:sub(pos, pos + length - 1), pos + length
end

-- ============================================================
-- Record encoding
--
-- The old implementation used:
--     column=value;column=value;
--
-- Keep that logical representation for QueryRecords,
-- JetRetrieveColumn and DeleteRecord compatibility.
-- Escape ';' and '=' inside values so records remain parseable.
-- ============================================================

local function EscapeValue(value)
    value = SafeToString(value)

    value = value:gsub("%%", "%%25")
    value = value:gsub(";", "%%3B")
    value = value:gsub("=", "%%3D")

    return value
end

local function UnescapeValue(value)
    if value == nil then
        return nil
    end

    value = value:gsub("%%3[Dd]", "=")
    value = value:gsub("%%3[Bb]", ";")
    value = value:gsub("%%25", "%%")

    return value
end

local function EncodeRecord(record)
    local keys = {}

    for k, _ in pairs(record) do
        keys[#keys + 1] = tostring(k)
    end

    table.sort(keys)

    local parts = {}

    for i = 1, #keys do
        local key = keys[i]
        local value = record[key]

        parts[#parts + 1] =
            EscapeValue(key) .. "=" .. EscapeValue(value) .. ";"
    end

    return table.concat(parts)
end

local function GetColumn(record, columnName)
    if type(record) ~= "string" or type(columnName) ~= "string" then
        return nil
    end

    local escaped = columnName:gsub("([%%%.%+%-%*%?%^%$%(%)%[%]])", "%%%1")

    local value = record:match("(^" .. escaped .. "=([^;]*);)")
    if value then
        return UnescapeValue(record:match("^" .. escaped .. "=([^;]*);"))
    end

    value = record:match(";" .. escaped .. "=([^;]*);")
    return UnescapeValue(value)
end

-- ============================================================
-- Page
-- ============================================================

local function CreatePage(pageNo)
    return {
        pageNumber = pageNo,
        checksum   = 0,
        treeId     = 0,
        data       = {},
        tags       = {},
        freeSpace  = PAGE_SIZE - PAGE_HEADER,
        isDirty    = false
    }
end

local function CalculateChecksum(page)
    local sum = 0

    for i = 1, #page.data do
        local record = page.data[i]

        for j = 1, #record do
            sum = (sum + string.byte(record, j)) % 4294967296
        end
    end

    return sum
end

local function RebuildPageMetadata(page)
    page.tags = {}
    page.freeSpace = PAGE_SIZE - PAGE_HEADER

    -- The tag array itself consumes TAG_SIZE bytes per record.
    -- Records are logically packed after the header + tag array.
    local count = #page.data
    local dataOffset = PAGE_HEADER + count * TAG_SIZE

    for i = 1, count do
        local record = page.data[i]
        local length = #record

        page.tags[i] = {
            offset = dataOffset,
            length = length
        }

        dataOffset = dataOffset + length
        page.freeSpace = page.freeSpace - TAG_SIZE - length
    end

    if page.freeSpace < 0 then
        page.freeSpace = 0
    end

    page.checksum = CalculateChecksum(page)
end

-- ============================================================
-- Page serialization
--
-- Layout:
--   0x00  magic/version
--   0x08  page number
--   0x0C  checksum
--   0x10  tree ID
--   0x14  free space
--   0x18  tag count
--   0x1C  reserved
--   0x20  tags
--   ...   records
--
-- Exactly PAGE_SIZE bytes are emitted.
-- ============================================================

local function SerializePage(page)
    RebuildPageMetadata(page)

    local buf = {}
    local total = 0

    local function Add(s)
        buf[#buf + 1] = s
        total = total + #s
    end

    Add(FORMAT_MAGIC)
    Add(WriteUInt32(FORMAT_VERSION))
    Add(WriteUInt32(page.pageNumber))
    Add(WriteUInt32(page.checksum))
    Add(WriteUInt32(page.treeId))
    Add(WriteUInt32(page.freeSpace))
    Add(WriteUInt32(#page.tags))
    Add(WriteUInt32(0))

    for i = 1, #page.tags do
        local tag = page.tags[i]
        Add(WriteUInt32(tag.offset))
        Add(WriteUInt32(tag.length))
    end

    for i = 1, #page.data do
        Add(page.data[i])
    end

    if total < PAGE_SIZE then
        Add(string.rep("\0", PAGE_SIZE - total))
    end

    return table.concat(buf):sub(1, PAGE_SIZE)
end

local function DeserializePage(buf, pageNo)
    local page = CreatePage(pageNo)

    if type(buf) ~= "string" or #buf < PAGE_HEADER then
        return page
    end

    -- Accept the new format.
    local hasMagic = buf:sub(1, 4) == FORMAT_MAGIC

    local tagCount
    local firstTag

    if hasMagic then
        local version = ReadUInt32(buf, 5)

        if version ~= FORMAT_VERSION then
            Debug("ESENT: Unsupported page version " .. tostring(version))
            return page
        end

        page.pageNumber = ReadUInt32(buf, 9)
        page.checksum   = ReadUInt32(buf, 13)
        page.treeId     = ReadUInt32(buf, 17)
        page.freeSpace  = ReadUInt32(buf, 21)
        tagCount        = ReadUInt32(buf, 25)
        firstTag        = 33
    else
        -- Backward reader for the original LJTB page layout.
        page.pageNumber = ReadUInt32(buf, 1)
        page.checksum   = ReadUInt32(buf, 5)
        page.treeId     = ReadUInt32(buf, 9)
        page.freeSpace  = ReadUInt32(buf, 13)
        tagCount        = ReadUInt32(buf, 17)
        firstTag        = 21
    end

    if tagCount < 0 then
        tagCount = 0
    end

    if tagCount > MAX_TAG_COUNT then
        tagCount = MAX_TAG_COUNT
    end

    local maxTagsByPage = math.floor((PAGE_SIZE - firstTag + 1) / TAG_SIZE)

    if tagCount > maxTagsByPage then
        tagCount = maxTagsByPage
    end

    for i = 1, tagCount do
        local p = firstTag + (i - 1) * TAG_SIZE

        local offset = ReadUInt32(buf, p)
        local length = ReadUInt32(buf, p + 4)

        if offset >= PAGE_HEADER and length > 0 and
           offset + length <= #buf then

            page.tags[#page.tags + 1] = {
                offset = offset,
                length = length
            }
        end
    end

    for i = 1, #page.tags do
        local tag = page.tags[i]
        local startPos = tag.offset + 1
        local endPos = tag.offset + tag.length

        if startPos <= #buf and endPos <= #buf and
           endPos >= startPos then

            page.data[#page.data + 1] = buf:sub(startPos, endPos)
        end
    end

    -- Ignore corrupt metadata rather than poisoning the whole instance.
    if page.treeId < 0 then
        page.treeId = 0
    end

    page.freeSpace = PAGE_SIZE - PAGE_HEADER -
                     (#page.data * TAG_SIZE)

    for i = 1, #page.data do
        page.freeSpace = page.freeSpace - #page.data[i]
    end

    if page.freeSpace < 0 then
        page.freeSpace = 0
    end

    return page
end

-- ============================================================
-- Database instance
-- ============================================================

local function CreateInstance()
    local instance = {
        pages        = {},
        logBuffer    = {},
        checkpoint   = 0,
        state        = DB_STATE_CLEAN,
        attachedDBs  = {},
        catalog      = {},
        cursors      = {},
        nextCursorId = 1
    }

    for i = 0, MAX_PAGES - 1 do
        instance.pages[i] = CreatePage(i)
    end

    -- DHCP/LuaNT catalog retained exactly.
    instance.catalog = {
        ["Leases"] = {
            columns = {
                "IPAddress",
                "UniqueIdentifier",
                "HostName",
                "LeaseExpirationTime",
                "ClientType"
            },
            rootPage = 3
        },

        ["Exclusions"] = {
            columns = {
                "StartIP",
                "EndIP",
                "Reason"
            },
            rootPage = 4
        },

        ["Config"] = {
            columns = {
                "PoolStart",
                "PoolEnd",
                "LeaseTime",
                "Gateway",
                "DNS",
                "SubnetMask"
            },
            rootPage = 5
        },

        ["Scopes"] = {
            columns = {
                "Name",
                "StartIP",
                "EndIP",
                "SubnetMask",
                "State"
            },
            rootPage = 6
        }
    }

    return instance
end

function esent.SetCatalog(catalog)
    if not g_instance then
        return false, "Instance not initialized"
    end
    g_instance.catalog = catalog
    return true
end

-- ============================================================
-- Session helpers
-- ============================================================

local function GetSession(sesid)
    if type(sesid) ~= "number" then
        return nil
    end

    return g_sessions[sesid]
end

-- ============================================================
-- Initialization
-- ============================================================

function esent.JetInit()
    if g_instance ~= nil then
        return true
    end

    g_instance = CreateInstance()

    Debug("ESENT: JetInit - Instance initialized with " ..
          MAX_PAGES .. " pages (" ..
          (MAX_PAGES * PAGE_SIZE / 1024) .. " KB)")

    return true
end

-- ============================================================
-- Session
-- ============================================================

function esent.JetBeginSession()
    if not g_instance then
        esent.JetInit()
    end

    local sesid = g_next_session
    g_next_session = g_next_session + 1

    g_sessions[sesid] = {
        id                = sesid,
        transactionActive = false,
        transactionDepth  = 0,
        savepoints        = {},
        currentTable      = nil,
        currentRecord     = {},
        prepType          = nil,
        currentDbPath     = nil
    }

    Debug("ESENT: JetBeginSession - Session " .. sesid .. " created")

    return sesid
end

-- ============================================================
-- Open database
-- ============================================================

function esent.JetOpenDatabase(sesid, path)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    if not g_instance then
        return false, "Instance not initialized"
    end

    path = NormalizePath(path)

    if type(path) ~= "string" or path == "" then
        return false, "Invalid database path"
    end

    local fs = GetFS()

    if fs.exists(path) then
        local file = fs.open(path, "rb")

        if not file then
            return false, "Could not open database"
        end

        local chunks = {}

        while true do
            local chunk = fs.read(file, 8192)

            if not chunk or #chunk == 0 then
                break
            end

            chunks[#chunks + 1] = chunk
        end

        fs.close(file)

        local buf = table.concat(chunks)

        local offset = 1
        local pageNo = 0

        while offset <= #buf and pageNo < MAX_PAGES do
            local pageBuf = buf:sub(offset, offset + PAGE_SIZE - 1)

            if #pageBuf > 0 then
                g_instance.pages[pageNo] =
                    DeserializePage(pageBuf, pageNo)
            end

            offset = offset + PAGE_SIZE
            pageNo = pageNo + 1
        end

        Debug("ESENT: JetOpenDatabase - Loaded " ..
              pageNo .. " pages from disk")
    else
        Debug("ESENT: JetOpenDatabase - New database will be created at " ..
              path)
    end

    g_instance.attachedDBs[path] = true
    session.currentDbPath = path

    Debug("ESENT: JetOpenDatabase - Database '" ..
          path .. "' opened")

    return true
end

-- ============================================================
-- Transaction
-- ============================================================

local function ClonePage(page)
    local copy = {
        pageNumber = page.pageNumber,
        checksum   = page.checksum,
        treeId     = page.treeId,
        data       = {},
        tags       = {},
        freeSpace  = page.freeSpace,
        isDirty    = page.isDirty
    }

    for i = 1, #page.data do
        copy.data[i] = page.data[i]
    end

    for i = 1, #page.tags do
        copy.tags[i] = {
            offset = page.tags[i].offset,
            length = page.tags[i].length
        }
    end

    return copy
end

local function SnapshotPages()
    local snapshot = {}

    for i = 0, MAX_PAGES - 1 do
        snapshot[i] = ClonePage(g_instance.pages[i])
    end

    return snapshot
end

local function RestorePages(snapshot)
    for i = 0, MAX_PAGES - 1 do
        g_instance.pages[i] = snapshot[i]
    end
end

function esent.JetBeginTransaction(sesid)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    if not g_instance then
        return false, "Instance not initialized"
    end

    session.transactionActive = true
    session.transactionDepth =
        session.transactionDepth + 1

    table.insert(session.savepoints, {
        logPosition = #g_instance.logBuffer,
        checkpoint  = g_instance.checkpoint,
        pages       = SnapshotPages()
    })

    g_instance.state = DB_STATE_DIRTY

    Debug("ESENT: JetBeginTransaction - Session " ..
          sesid .. " started transaction")

    return true
end

-- ============================================================
-- Prepare update
-- ============================================================

function esent.JetPrepareUpdate(sesid, tableName, prepType)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    if not g_instance.catalog[tableName] then
        Debug("ESENT: ERROR - Table '" ..
              tostring(tableName) .. "' does not exist")

        return false, "Table not found"
    end

    session.currentTable = tableName
    session.currentRecord = {}
    session.prepType = prepType or "Insert"

    Debug("ESENT: JetPrepareUpdate - Prepared " ..
          tostring(session.prepType) ..
          " for table " .. tableName)

    return true
end

-- ============================================================
-- Set column
-- ============================================================

function esent.JetSetColumn(sesid, columnName, value)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    if type(columnName) ~= "string" or columnName == "" then
        return false, "Invalid column name"
    end

    session.currentRecord[columnName] = SafeToString(value)

    return true
end

-- ============================================================
-- Page allocation
-- ============================================================

local function RequiredSpace(recordLength)
    return TAG_SIZE + recordLength
end

local function FindFreePage(treeId, recordLength)
    local needed = RequiredSpace(recordLength)

    -- Prefer pages already owned by this table.
    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page and page.treeId == treeId and
           page.freeSpace >= needed then

            return page
        end
    end

    -- Then claim an empty page.
    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page and page.treeId == 0 and
           page.freeSpace >= needed then

            page.treeId = treeId
            return page
        end
    end

    return nil
end

local function DecodeRecord(record)
    if type(record) ~= "string" then
        return {}
    end

    local result = {}

    for key, value in record:gmatch("([^=;]+)=([^;]*);") do
        result[key] = UnescapeValue(value)
    end

    return result
end

local function LoadRecordTables(tableName)
    local raw = esent.QueryRecords(tableName)
    local result = {}

    for i = 1, #raw do
        result[#result + 1] = DecodeRecord(raw[i])
    end

    return result
end

local function SaveRecords(tableName, records)
    if not g_instance then
        return false, "Instance not initialized"
    end

    local catalog = g_instance.catalog[tableName]

    if not catalog then
        return false, "Table not found"
    end

    local treeId = catalog.rootPage
    local encoded = {}

    -- Encode everything first.
    for i = 1, #records do
        local record = records[i]

        if type(record) == "table" then
            encoded[#encoded + 1] = EncodeRecord(record)
        elseif type(record) == "string" then
            encoded[#encoded + 1] = record
        end
    end

    -- Check that all records can fit before destroying old pages.
    local requiredPages = 0
    local used = 0

    for i = 1, #encoded do
        local length = #encoded[i]

        if length + TAG_SIZE > PAGE_SIZE - PAGE_HEADER then
            return false, "Record too large"
        end

        if used == 0 or
           used + TAG_SIZE + length > PAGE_SIZE - PAGE_HEADER then

            requiredPages = requiredPages + 1
            used = length + TAG_SIZE
        else
            used = used + TAG_SIZE + length
        end
    end

    local freePages = 0

    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page.treeId == 0 or page.treeId == treeId then
            freePages = freePages + 1
        end
    end

    if requiredPages > freePages then
        return false, "Database full"
    end

    -- Remove old pages belonging to this table.
    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page.treeId == treeId then
            page.treeId = 0
            page.data = {}
            page.tags = {}
            page.freeSpace = PAGE_SIZE - PAGE_HEADER
            page.checksum = 0
            page.isDirty = true
        end
    end

    -- Rebuild pages.
    local currentPage = nil

    for i = 1, #encoded do
        local record = encoded[i]

        if not currentPage or
           currentPage.freeSpace < TAG_SIZE + #record then

            currentPage = FindFreePage(treeId, #record)

            if not currentPage then
                return false, "Database full"
            end
        end

        currentPage.data[#currentPage.data + 1] = record
        currentPage.isDirty = true

        RebuildPageMetadata(currentPage)
    end

    g_instance.state = DB_STATE_DIRTY

    return true
end

-- ============================================================
-- Insert/update record
-- ============================================================

function esent.JetUpdate(sesid)
    local session = g_sessions[sesid]

    if not session then
        DbgPrint("ESENT: JetUpdate - invalid session")
        return false
    end

    if not session.currentTable then
        DbgPrint("ESENT: JetUpdate - no prepared table")
        return false
    end

    local tableName = session.currentTable
    local prepType = session.prepType or "Insert"
    local record = session.currentRecord or {}

    local tree = g_instance.catalog[tableName]

    if not tree then
        DbgPrint("ESENT: JetUpdate - table not found: " .. tostring(tableName))
        return false
    end

    local records = LoadRecordTables(tableName)

    -- DELETE
    if prepType == "Delete" then
        local deleteKey = nil
        local deleteColumn = nil

        if record.IPAddress then
            deleteKey = record.IPAddress
            deleteColumn = "IPAddress"
        elseif record.StartIP then
            deleteKey = record.StartIP
            deleteColumn = "StartIP"
        elseif record.UniqueIdentifier then
            deleteKey = record.UniqueIdentifier
            deleteColumn = "UniqueIdentifier"
        end

        if deleteKey then
            local newRecords = {}

            for i = 1, #records do
                local value = records[i][deleteColumn]

                if tostring(value) ~= tostring(deleteKey) then
                    table.insert(newRecords, records[i])
                end
            end

            SaveRecords(tableName, newRecords)
        end

        session.currentRecord = nil
        session.currentTable = nil
        session.prepType = nil

        DbgPrint("ESENT: JetUpdate - Deleted record from " .. tableName)
        return true
    end

    -- UPDATE
    if prepType == "Update" then
        local updated = false

        for i = 1, #records do
            local match = false

            if record.IPAddress and
               records[i].IPAddress == record.IPAddress then
                match = true
            elseif record.UniqueIdentifier and
                   records[i].UniqueIdentifier == record.UniqueIdentifier then
                match = true
            elseif tableName == "Config" then
                match = (i == 1)
            elseif record.StartIP and
                   records[i].StartIP == record.StartIP then
                match = true
            end

            if match then
                records[i] = record
                updated = true
                break
            end
        end

        if not updated then
            table.insert(records, record)
        end

        SaveRecords(tableName, records)

        session.currentRecord = nil
        session.currentTable = nil
        session.prepType = nil

        DbgPrint("ESENT: JetUpdate - Updated record in " .. tableName)
        return true
    end

    -- INSERT
    table.insert(records, record)
    SaveRecords(tableName, records)

    session.currentRecord = nil
    session.currentTable = nil
    session.prepType = nil

    DbgPrint("ESENT: JetUpdate - Inserted record into " .. tableName)

    return true
end

-- ============================================================
-- Commit
-- ============================================================

function esent.JetCommitTransaction(sesid, grbit)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    if not session.transactionActive then
        return false, "No active transaction"
    end

    if #session.savepoints > 0 then
        table.remove(session.savepoints, #session.savepoints)
    end

    session.transactionDepth =
        session.transactionDepth - 1

    if session.transactionDepth <= 0 then
        session.transactionDepth = 0
        session.transactionActive = false

        g_instance.logBuffer = {}
        g_instance.checkpoint =
            g_instance.checkpoint + 1
        g_instance.state = DB_STATE_CLEAN
    end

    Debug("ESENT: JetCommitTransaction - Committed " ..
          "(checkpoint: " .. g_instance.checkpoint .. ")")

    return true
end

-- ============================================================
-- Rollback
-- ============================================================

function esent.JetRollback(sesid)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    if not session.transactionActive then
        return false, "No active transaction"
    end

    local index = #session.savepoints
    local savepoint = session.savepoints[index]

    if savepoint then
        RestorePages(savepoint.pages)

        while #g_instance.logBuffer > savepoint.logPosition do
            table.remove(g_instance.logBuffer)
        end

        g_instance.checkpoint = savepoint.checkpoint
        table.remove(session.savepoints, index)
    end

    session.transactionDepth =
        session.transactionDepth - 1

    if session.transactionDepth <= 0 then
        session.transactionDepth = 0
        session.transactionActive = false
        g_instance.state = DB_STATE_CLEAN
    end

    Debug("ESENT: JetRollback - Transaction rolled back")

    return true
end

-- ============================================================
-- Close database
-- ============================================================

function esent.JetCloseDatabase(sesid, path)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    path = NormalizePath(path)

    if type(path) ~= "string" or path == "" then
        return false, "Invalid database path"
    end

    if not g_instance then
        return false, "Instance not initialized"
    end

    local fs = GetFS()

    EnsureDirectory(fs, path)

    local file = fs.open(path, "wb")

    if not file then
        Debug("ESENT: ERROR - Could not open file for writing: " ..
              path)

        return false, "Could not open database for writing"
    end

    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page then
            fs.write(file, SerializePage(page))
            page.isDirty = false
        end
    end

    fs.close(file)

    g_instance.attachedDBs[path] = nil

    if session.currentDbPath == path then
        session.currentDbPath = nil
    end

    g_instance.state = DB_STATE_CLEAN

    Debug("ESENT: JetCloseDatabase - Wrote " ..
          MAX_PAGES .. " pages to " .. path)

    return true
end

-- ============================================================
-- Cursor
-- ============================================================

function esent.JetOpenTable(sesid, tableName)
    local session = GetSession(sesid)

    if not session then
        return false, "Invalid session"
    end

    local catalog = g_instance.catalog[tableName]

    if not catalog then
        Debug("ESENT: ERROR - Table '" ..
              tostring(tableName) .. "' not found")

        return false, "Table not found"
    end

    local cursorId = g_instance.nextCursorId
    g_instance.nextCursorId =
        g_instance.nextCursorId + 1

    g_instance.cursors[cursorId] = {
        id       = cursorId,
        table    = tableName,
        treeId   = catalog.rootPage,
        position = 0,
        records  = {},
        loaded   = false
    }

    Debug("ESENT: JetOpenTable - Cursor " ..
          cursorId .. " opened for " .. tableName)

    return cursorId
end

local function LoadRecordsForCursor(cursor)
    if cursor.loaded then
        return
    end

    cursor.records = {}

    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page and page.treeId == cursor.treeId then
            for j = 1, #page.data do
                cursor.records[#cursor.records + 1] =
                    page.data[j]
            end
        end
    end

    cursor.loaded = true
end

function esent.JetMove(cursorId, direction)
    local cursor = g_instance.cursors[cursorId]

    if not cursor then
        return false, "Invalid cursor"
    end

    LoadRecordsForCursor(cursor)

    if direction == "Next" or direction == 1 then
        if cursor.position < #cursor.records then
            cursor.position =
                cursor.position + 1

            return true
        end

        return false
    end

    if direction == "Prev" or direction == -1 then
        if cursor.position > 1 then
            cursor.position =
                cursor.position - 1

            return true
        end

        return false
    end

    if direction == "First" then
        if #cursor.records > 0 then
            cursor.position = 1
            return true
        end

        cursor.position = 0
        return false
    end

    if direction == "Last" then
        if #cursor.records > 0 then
            cursor.position = #cursor.records
            return true
        end

        cursor.position = 0
        return false
    end

    return false
end

function esent.JetRetrieveColumn(sesid, cursorId, columnName)
    local session = g_sessions[sesid]

    if not session then
        return nil
    end

    if not g_instance then
        return nil
    end

    -- Legacy/table mode:
    -- JetRetrieveColumn(sesid, "Leases", "IPAddress")
    if type(cursorId) == "string" and
       g_instance.catalog[cursorId] then

        local tableName = cursorId

        if not session.legacyQuery or
           session.legacyQuery.table ~= tableName then

            session.legacyQuery = {
                table = tableName,
                position = 1
            }
        end

        local records = esent.QueryRecords(tableName)
        local pos = session.legacyQuery.position

        if pos > #records then
            session.legacyQuery = nil
            return nil
        end

        local rawRecord = records[pos]

        local value = GetColumn(rawRecord, columnName)

        session.legacyQuery.position = pos + 1

        return value
    end

    -- Normal cursor mode
    local cursor = g_instance.cursors[cursorId]

    if not cursor or cursor.position < 1 then
        return nil
    end

    local record = cursor.records[cursor.position]

    if not record then
        return nil
    end

    return GetColumn(record, columnName)
end

function esent.JetCloseTable(cursorId)
    if not g_instance then
        return false
    end

    if not g_instance.cursors[cursorId] then
        return false
    end

    g_instance.cursors[cursorId] = nil

    return true
end

-- ============================================================
-- Direct query API
-- ============================================================

function esent.QueryRecords(tableName)
    if not g_instance then
        return {}
    end

    local catalog = g_instance.catalog[tableName]

    if not catalog then
        return {}
    end

    local records = {}

    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page and page.treeId == catalog.rootPage then
            for j = 1, #page.data do
                records[#records + 1] = page.data[j]
            end
        end
    end

    return records
end

-- ============================================================
-- Delete
-- ============================================================

function esent.DeleteRecord(tableName, keyColumn, keyValue)
    if not g_instance then
        return false
    end

    local catalog = g_instance.catalog[tableName]

    if not catalog then
        return false
    end

    keyValue = SafeToString(keyValue)

    for i = 0, MAX_PAGES - 1 do
        local page = g_instance.pages[i]

        if page and page.treeId == catalog.rootPage then
            for idx = 1, #page.data do
                local record = page.data[idx]
                local value = GetColumn(record, keyColumn)

                if value == keyValue then
                    table.remove(page.data, idx)

                    RebuildPageMetadata(page)
                    page.isDirty = true
                    g_instance.state = DB_STATE_DIRTY

                    Debug("ESENT: DeleteRecord - Removed from " ..
                          tableName)

                    return true
                end
            end
        end
    end

    return false
end

-- ============================================================
-- End session
-- ============================================================

function esent.JetEndSession(sesid)
    if not g_sessions[sesid] then
        return false, "Invalid session"
    end

    g_sessions[sesid] = nil

    Debug("ESENT: JetEndSession - Session " ..
          sesid .. " ended")

    return true
end

-- ============================================================
-- Termination
-- ============================================================

function esent.JetTerm()
    if not g_instance then
        g_sessions = {}
        return true
    end

    -- Do not silently discard an active dirty instance.
    -- The caller remains responsible for JetCloseDatabase.
    if g_instance.state == DB_STATE_DIRTY then
        Debug("ESENT: JetTerm - Warning: dirty instance terminated")
    end

    g_instance = nil
    g_sessions = {}
    g_next_session = 1

    Debug("ESENT: JetTerm - Instance terminated")

    return true
end

-- ============================================================
-- Flush compatibility
-- ============================================================

function esent.JetFlushFileBuffers(sesid, path)
    return esent.JetCloseDatabase(sesid, path)
end

-- ============================================================
-- Export
-- ============================================================

return esent
