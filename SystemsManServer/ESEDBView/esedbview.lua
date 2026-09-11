-- ESEDBView.lua - ESENT Database Viewer для LuaNT
-- (C) RedstoneShell 2026
-- Перегляд структури .mdb (сторінки, теги, записи)

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

-- ===== Константи =====
local PAGE_SIZE      = 4096
local MAX_PAGES      = 64
local PAGE_HEADER    = 40
local TAG_SIZE       = 8
local FORMAT_MAGIC   = "LJTB"
local FORMAT_VERSION = 1

-- ===== Читання файлу =====
local function ReadFile(fs, path)
    if not fs.exists(path) then
        return nil, "File not found: " .. path
    end

    local file = fs.open(path, "rb")
    if not file then
        return nil, "Cannot open file"
    end

    local chunks = {}
    while true do
        local chunk = fs.read(file, 8192)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    fs.close(file)

    return table.concat(chunks)
end

-- ===== ReadUInt32 =====
local function ReadUInt32(buf, pos)
    local b1 = string.byte(buf, pos) or 0
    local b2 = string.byte(buf, pos + 1) or 0
    local b3 = string.byte(buf, pos + 2) or 0
    local b4 = string.byte(buf, pos + 3) or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- ===== Парсинг сторінки =====
local function ParsePage(buf, pageNo)
    local page = {
        pageNumber = pageNo,
        magic      = buf:sub(1, 4),
        version    = 0,
        checksum   = 0,
        treeId     = 0,
        freeSpace  = 0,
        tagCount   = 0,
        tags       = {},
        records    = {},
        valid      = false
    }

    if #buf < PAGE_HEADER then
        return page
    end

    if page.magic == FORMAT_MAGIC then
        page.version    = ReadUInt32(buf, 5)
        page.pageNumber = ReadUInt32(buf, 9)
        page.checksum   = ReadUInt32(buf, 13)
        page.treeId     = ReadUInt32(buf, 17)
        page.freeSpace  = ReadUInt32(buf, 21)
        page.tagCount   = ReadUInt32(buf, 25)
        page.firstTag   = 33
        page.valid      = (page.version == FORMAT_VERSION)
    else
        page.pageNumber = ReadUInt32(buf, 1)
        page.checksum   = ReadUInt32(buf, 5)
        page.treeId     = ReadUInt32(buf, 9)
        page.freeSpace  = ReadUInt32(buf, 13)
        page.tagCount   = ReadUInt32(buf, 17)
        page.firstTag   = 21
        page.valid      = true
    end

    if page.tagCount > 0 and page.tagCount <= 64 then
        for i = 1, page.tagCount do
            local p = page.firstTag + (i - 1) * TAG_SIZE
            local offset = ReadUInt32(buf, p)
            local length = ReadUInt32(buf, p + 4)

            table.insert(page.tags, {
                index = i,
                offset = offset,
                length = length
            })

            if offset > 0 and length > 0 and offset + length <= #buf then
                local record = buf:sub(offset + 1, offset + length)
                table.insert(page.records, record)
            end
        end
    end

    return page
end

-- ===== Парсинг всього файлу =====
local function ParseDatabase(fs, path)
    local buf, err = ReadFile(fs, path)
    if not buf then
        return nil, err
    end

    local db = {
        path      = path,
        size      = #buf,
        pageCount = math.floor(#buf / PAGE_SIZE),
        pages     = {},
        valid     = true
    }

    for i = 0, math.min(db.pageCount - 1, MAX_PAGES - 1) do
        local offset = i * PAGE_SIZE + 1
        local pageBuf = buf:sub(offset, offset + PAGE_SIZE - 1)

        if #pageBuf > 0 then
            db.pages[i] = ParsePage(pageBuf, i)
        end
    end

    return db
end

-- ===== Список .mdb файлів у папці =====
local function ListMDBFiles(fs, dir)
    local files = {}

    if not fs.exists(dir) then
        return files
    end

    local items = fs.list(dir)
    for _, item in ipairs(items) do
        if item:match("%.mdb$") then
            table.insert(files, dir .. item)
        end
    end

    return files
end

-- ===== GUI =====
local function RunViewer()
    local winW = math.min(76, screenW - 2)
    local winH = math.min(24, screenH - 2)
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2
    local clientW = winW - 2
    local clientH = winH - 3

    local fs = component.proxy(computer.getBootAddress())

    local db = nil
    local err = nil
    local dbPath = nil
    local currentPage = 0
    local scrollOffset = 0
    local statusText = "No file opened"

    -- Режим: 1 = Pages, 2 = Records, 3 = File Picker
    local mode = 1

    -- File picker
    local mdbFiles = {}
    local pickerIndex = 1

    -- ===== Завантаження =====
    local function LoadDB(path)
        statusText = "Loading " .. path .. "..."
        dbPath = path
        db, err = ParseDatabase(fs, path)

        if db then
            statusText = string.format("Loaded %s (%d pages, %d bytes)",
                path, db.pageCount, db.size)
            currentPage = 0
            scrollOffset = 0
        else
            statusText = "ERROR: " .. tostring(err)
        end
    end

    -- ===== Сканування .mdb =====
    local function ScanMDB()
        mdbFiles = {}
        local searchDirs = {
            "Windows/System32/dhcp/",
            "Windows/System32/",
            "Windows/",
            "/",
        }

        for _, dir in ipairs(searchDirs) do
            local files = ListMDBFiles(fs, dir)
            for _, f in ipairs(files) do
                -- Уникаємо дублікатів
                local exists = false
                for _, existing in ipairs(mdbFiles) do
                    if existing == f then exists = true break end
                end
                if not exists then
                    table.insert(mdbFiles, f)
                end
            end
        end

        pickerIndex = 1
        DbgPrint("ESEDBVIEW: Found " .. #mdbFiles .. " .mdb files")
    end

    -- ===== Малювання =====
    local function DrawWindow()
        -- Фон вікна
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)

        -- 3D-рамка
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
        gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)

        -- Заголовок
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)

        local title = " ESEDBView"
        if mode == 1 then title = title .. " - Pages"
        elseif mode == 2 then title = title .. " - Records"
        elseif mode == 3 then title = title .. " - Open File"
        end
        if dbPath then title = title .. " [" .. dbPath .. "]" end

        gdi32.TextOut(hdc, winX + 2, winY + 1, title:sub(1, winW - 8))
        gdi32.SetTextColor(hdc, 0xFF0000)
        gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        -- Клієнтська область
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
        gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)

        gdi32.SetTextColor(hdc, 0xC0C0C0)
        gdi32.SetBkColor(hdc, 0x000000)

        local line = 0
        local function WriteLine(text)
            if line >= clientH then return end
            if line >= scrollOffset then
                gdi32.TextOut(hdc, clientX + 1, clientY + line - scrollOffset, tostring(text))
            end
            line = line + 1
        end

        -- ===== File Picker =====
        if mode == 3 then
            WriteLine("=== Open .mdb File ===")
            WriteLine("")

            if #mdbFiles == 0 then
                WriteLine("  No .mdb files found")
                WriteLine("")
                WriteLine("  Searched in:")
                WriteLine("    Windows/System32/dhcp/")
                WriteLine("    Windows/System32/")
                WriteLine("    Windows/")
            else
                WriteLine("  Found " .. #mdbFiles .. " file(s):")
                WriteLine("")

                for i, f in ipairs(mdbFiles) do
                    local prefix = (i == pickerIndex) and "> " or "  "
                    WriteLine(prefix .. f)
                end
            end

            WriteLine("")
            WriteLine("  [ENTER] Open  [ESC] Cancel  [R] Refresh")

        -- ===== Pages Mode =====
        elseif mode == 1 then
            if not db then
                WriteLine("")
                WriteLine("  No file opened.")
                WriteLine("")
                WriteLine("  Press [O] to open a .mdb file")
            else
                WriteLine("=== ESENT Database Viewer ===")
                WriteLine("")
                WriteLine("  File:       " .. dbPath)
                WriteLine("  Size:       " .. db.size .. " bytes")
                WriteLine("  Pages:      " .. db.pageCount)
                WriteLine("  Page size:  " .. PAGE_SIZE .. " bytes")
                WriteLine("")

                local p0 = db.pages[0]
                if p0 then
                    WriteLine("--- File Header (Page 0) ---")
                    WriteLine("  Magic:      " .. p0.magic)
                    WriteLine("  Version:    " .. p0.version)
                    WriteLine("  Checksum:   0x" .. string.format("%08X", p0.checksum))
                    WriteLine("  Tree ID:    " .. p0.treeId)
                    WriteLine("  Free space: " .. p0.freeSpace .. " bytes")
                    WriteLine("  Tags:       " .. p0.tagCount)
                    WriteLine("")
                end

                WriteLine("--- Pages ---")
                WriteLine("Page  Tree  Tags  Free   Valid  Records")
                WriteLine("-----------------------------------------")

                for i = 0, db.pageCount - 1 do
                    local p = db.pages[i]
                    if p then
                        local validMark = p.valid and "OK " or "BAD"
                        local recordCount = #p.records

                        local prefix = (i == currentPage) and ">" or " "
                        WriteLine(string.format("%s%4d  %4d  %4d  %5d  %s   %d",
                            prefix, i, p.treeId, p.tagCount, p.freeSpace, validMark, recordCount))
                    end
                end
            end

        -- ===== Records Mode =====
        elseif mode == 2 then
            if not db then
                WriteLine("")
                WriteLine("  No file opened.")
            else
                local curPage = db.pages[currentPage]
                if curPage then
                    WriteLine("=== Page " .. currentPage .. " Records ===")
                    WriteLine("")
                    WriteLine("  Tree ID:     " .. curPage.treeId)
                    WriteLine("  Tag count:   " .. curPage.tagCount)
                    WriteLine("  Free space:  " .. curPage.freeSpace .. " bytes")
                    WriteLine("")

                    if #curPage.records == 0 then
                        WriteLine("  (No records on this page)")
                    else
                        for ri, rec in ipairs(curPage.records) do
                            WriteLine("--- Record " .. ri .. " ---")

                            -- Розбиваємо запис на поля
                            local fields = {}
                            for pair in rec:gmatch("[^;]+") do
                                table.insert(fields, pair)
                            end

                            for _, field in ipairs(fields) do
                                WriteLine("  " .. field)
                            end
                            WriteLine("")
                        end
                    end
                end
            end
        end

        -- Статус-бар
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)

        local statusLine = statusText
        if mode == 1 then
            statusLine = statusLine .. " | [O]pen [R]ecords [Tab]"
        elseif mode == 2 then
            statusLine = statusLine .. " | Page " .. currentPage .. "/" .. (db and db.pageCount or 0) .. " | [←→] page [Tab]"
        elseif mode == 3 then
            statusLine = "Select file: " .. pickerIndex .. "/" .. #mdbFiles
        end

        gdi32.TextOut(hdc, winX + 2, winY + winH - 2, statusLine:sub(1, winW - 4))
    end

    -- ===== Обробка клавіш =====
    local function HandleKey(char, code)
        -- ===== File Picker =====
        if mode == 3 then
            if code == 200 then  -- UP
                if pickerIndex > 1 then pickerIndex = pickerIndex - 1 end
            elseif code == 208 then  -- DOWN
                if pickerIndex < #mdbFiles then pickerIndex = pickerIndex + 1 end
            elseif code == 28 then  -- ENTER
                if mdbFiles[pickerIndex] then
                    LoadDB(mdbFiles[pickerIndex])
                    mode = 1
                end
            elseif char == 114 or char == 82 then  -- R
                ScanMDB()
            end
            return
        end

        -- ===== No DB =====
        if not db then
            if char == 111 or char == 79 then  -- O
                ScanMDB()
                mode = 3
            end
            return
        end

        -- ===== Pages / Records =====
        if code == 200 then  -- UP
            if scrollOffset > 0 then
                scrollOffset = scrollOffset - 1
            end
        elseif code == 208 then  -- DOWN
            if scrollOffset < 200 then
                scrollOffset = scrollOffset + 1
            end
        elseif code == 203 then  -- LEFT
            if currentPage > 0 then
                currentPage = currentPage - 1
                scrollOffset = 0
            end
        elseif code == 205 then  -- RIGHT
            if currentPage < db.pageCount - 1 then
                currentPage = currentPage + 1
                scrollOffset = 0
            end
        elseif code == 201 then  -- PAGE UP
            scrollOffset = math.max(0, scrollOffset - 10)
        elseif code == 209 then  -- PAGE DOWN
            scrollOffset = scrollOffset + 10
        elseif code == 199 then  -- HOME
            scrollOffset = 0
        elseif code == 207 then  -- END
            scrollOffset = 200
        elseif code == 15 then  -- TAB
            if mode == 1 then mode = 2
            elseif mode == 2 then mode = 1 end
            scrollOffset = 0
        elseif char == 111 or char == 79 then  -- O
            ScanMDB()
            mode = 3
        end
    end

    -- ===== Запуск =====
    ScanMDB()
    DrawWindow()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 1 then  -- ESC
                if mode == 3 then
                    mode = 1
                else
                    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
                    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
                    return
                end

            elseif code == 116 then  -- F5
                if dbPath then LoadDB(dbPath) end

            else
                HandleKey(char, code)
            end

            DrawWindow()

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]

            if ty == winY + 1 and tx >= winX + winW - 5 then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
                gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
                return
            end

            DrawWindow()
        end
    end
end

DbgPrint("ESEDBVIEW: Starting ESEDBView...")
RunViewer()
DbgPrint("ESEDBVIEW: Closed.")

return true