local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local function DbgPrint(...)
    if _G.DbgPrint then
        _G.DbgPrint(...)
    end
end

if not _G.Mm then _G.Mm = { NonPagedPool = {} } end
if not _G.Mm.NonPagedPool then _G.Mm.NonPagedPool = {} end
if not _G.Drives then _G.Drives = {} end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local PORT_PING = 455
local PORT_WORK = 456
local PROTOCOL_TIMEOUT = 3

local LDM = _G.Tier2CM == true

local discoveredServers = {}
local selectedServer = nil

local function escape(s)
    if type(s) ~= "string" then s = tostring(s) end
    s = s:gsub("\\", "\\\\")
    s = s:gsub(";", "\\s")
    s = s:gsub("=", "\\e")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    return s
end

local function unescape(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("\\r", "\r")
    s = s:gsub("\\n", "\n")
    s = s:gsub("\\e", "=")
    s = s:gsub("\\s", ";")
    s = s:gsub("\\\\", "\\")
    return s
end

local function serialize(tbl)
    if type(tbl) ~= "table" then return escape(tostring(tbl)) end
    local parts = {}
    for k, v in pairs(tbl) do
        local vType = type(v)
        local key = escape(tostring(k))
        if vType == "string" then
            table.insert(parts, key .. "=S:" .. escape(v))
        elseif vType == "number" then
            table.insert(parts, key .. "=N:" .. tostring(v))
        elseif vType == "boolean" then
            table.insert(parts, key .. "=B:" .. tostring(v))
        end
    end
    return table.concat(parts, ";")
end

local function deserialize(str)
    if type(str) ~= "string" then return nil end
    local tbl = {}
    for pair in str:gmatch("[^;]+") do
        local key, vType, value = pair:match("([^=]+)=([SNB]):(.*)")
        if key and vType then
            key = unescape(key)
            if vType == "S" then
                tbl[key] = unescape(value)
            elseif vType == "N" then
                tbl[key] = tonumber(value) or 0
            elseif vType == "B" then
                tbl[key] = (value == "true")
            end
        end
    end
    return tbl
end

local function GetModem()
    local modem_addr = component.list("modem")()
    if not modem_addr then
        return nil, "No modem found"
    end
    return component.proxy(modem_addr), nil
end

local function SearchNetHDD()
    local modem, err = GetModem()
    if not modem then
        return false, err
    end

    modem.open(PORT_PING)
    modem.open(PORT_WORK)

    local myUUID = computer.address()
    modem.broadcast(PORT_PING, "NETDISK_PING", myUUID)

    discoveredServers = {}
    local timeout = computer.uptime() + PROTOCOL_TIMEOUT

    while computer.uptime() < timeout do
        local sig, _, remoteAddr, port, _, cmd, uuid, serverID = computer.pullSignal(0.5)

        if sig == "modem_message" and port == PORT_PING then
            if cmd == "NETDISK_PONG" and uuid == myUUID and serverID and remoteAddr then
                if not discoveredServers[serverID] then
                    discoveredServers[serverID] = {
                        address = remoteAddr,
                        serverID = serverID
                    }
                    DbgPrint("NFS: Found server " .. serverID ..
                        " at " .. tostring(remoteAddr):sub(1, 8))
                end
            end
        end
    end

    modem.close(PORT_PING)
    modem.close(PORT_WORK)

    return true, nil
end

local function SendCommand(server, action, name, data)
    local modem, err = GetModem()
    if not modem then
        return false, err
    end

    if not server or not server.address then
        return false, "Invalid server"
    end

    modem.open(PORT_WORK)

    local request = serialize({
        action = action,
        name = name or "",
        data = data or ""
    })

    modem.send(server.address, PORT_WORK, "NETDISK_WORK", request)

    if action == "LIST" or action == "READ" or action == "ISDIR" then
        local timeout = computer.uptime() + PROTOCOL_TIMEOUT
        while computer.uptime() < timeout do
            local sig, _, remoteAddr, port, _, cmd, response = computer.pullSignal(0.5)

            if sig == "modem_message" and port == PORT_WORK then
                if cmd == "NETDISK_ACC" and response then
                    local decoded = deserialize(response)
                    if decoded then
                        modem.close(PORT_WORK)
                        return true, decoded
                    end
                end
            end
        end
        modem.close(PORT_WORK)
        return false, "Timeout"
    end

    modem.close(PORT_WORK)
    return true, nil
end

local function RegisterNetworkDisk(letter, server)
    local function normalize(p)
        if not p then return "/" end
        p = tostring(p):gsub("\\", "/")
        p = p:gsub("^[A-Za-z]:", "")
        p = p:gsub("/+", "/")
        if p == "" then p = "/" end
        if p:sub(1, 1) ~= "/" then p = "/" .. p end
        if #p > 1 and p:sub(-1) == "/" then p = p:sub(1, -2) end
        return p
    end

    local fs = {}

    fs.open = function(path, mode)
        mode = mode or "r"
        path = normalize(path)

        if mode == "r" or mode == "rb" then
            local ok, result = SendCommand(server, "READ", path, nil)
            if not ok then return nil, result end
            if type(result) ~= "table" then
                return nil, "READ_FAILED"
            end
            if result.error then
                return nil, result.error
            end
            return {
                data = tostring(result.data or ""),
                position = 1,
                path = path,
                mode = mode,
                _dirty = false,
                _isNetwork = true
            }
        end

        local initial = ""
        if mode == "a" or mode == "ab" then
            local ok, result = SendCommand(server, "READ", path, nil)
            if ok and type(result) == "table" and not result.error then
                initial = tostring(result.data or "")
            end
        end

        return {
            data = initial,
            position = #initial + 1,
            path = path,
            mode = mode,
            _dirty = false,
            _isNetwork = true
        }
    end

    fs.read = function(handle, bytes)
        if not handle or not handle.data then return nil end
        bytes = bytes or math.huge
        if bytes <= 0 then return nil end
        local data = handle.data:sub(handle.position, handle.position + bytes - 1)
        handle.position = handle.position + #data
        if #data == 0 then return nil end
        return data
    end

    fs.write = function(handle, data)
        if not handle or not handle.path then return false, "INVALID_HANDLE" end
        if data == nil then return false, "NO_DATA" end

        local str = tostring(data)

        if handle.mode == "a" or handle.mode == "ab" then
            handle.data = (handle.data or "") .. str
            handle.position = #handle.data + 1
        else
            handle.data = (handle.data or "") .. str
            handle.position = #handle.data + 1
        end

        handle._dirty = true
        return true
    end

    fs.close = function(handle)
        if not handle then return true end

        local path = handle.path
        local payload = handle.data or ""
        local mode = handle.mode or "r"

        local shouldWrite = false
        if handle._dirty then
            shouldWrite = true
        elseif mode == "w" or mode == "wb" then
            shouldWrite = true
        end

        if not shouldWrite then return true end

        handle._dirty = false

        local ok, result = SendCommand(server, "WRITE", path, payload)
        if not ok then
            handle._dirty = true
            return false, tostring(result or "WRITE_FAILED")
        end

        if type(result) == "table" and result.error then
            handle._dirty = true
            return false, tostring(result.error)
        end

        return true
    end

    fs.list = function(path)
        path = normalize(path)
        local ok, result = SendCommand(server, "LIST", path, nil)
        if not ok or type(result) ~= "table" then return {} end

        local packed = result.data
        if type(packed) ~= "string" or packed == "" then return {} end

        local out = {}
        for name in packed:gmatch("[^\n]+") do
            table.insert(out, name)
        end
        return out
    end

    fs.exists = function(path)
        path = normalize(path)
        if path == "/" then return true end

        local ok, result = SendCommand(server, "ISDIR", path, nil)
        if ok and type(result) == "table" and result.isdir == true then
            return true
        end

        local ok2, res2 = SendCommand(server, "READ", path, nil)
        if ok2 and type(res2) == "table" and res2.error == nil then
            return true
        end
        return false
    end

    fs.isDirectory = function(path)
        path = normalize(path)
        if path == "/" then return true end

        local ok, result = SendCommand(server, "ISDIR", path, nil)
        if not ok or type(result) ~= "table" then return false end
        return result.isdir == true
    end

    fs.makeDirectory = function(path)
        path = normalize(path)
        local ok, _ = SendCommand(server, "MAKEDIR", path, nil)
        return ok and true or false
    end

    fs.remove = function(path)
        path = normalize(path)
        local ok, _ = SendCommand(server, "MAKE", path, nil)
        return ok and true or false
    end

    fs.rename = function(from, to)
        from = normalize(from)
        to = normalize(to)
        local ok, _ = SendCommand(server, "RENAME", from, to)
        return ok and true or false
    end

    fs.getLabel = function()
        return server.serverID or "Network Disk"
    end

    fs.isReadOnly = function()
        return false
    end

    fs.spaceTotal = function()
        return 1024 * 1024
    end

    fs.spaceUsed = function()
        return 0
    end

    fs.address = server.address
    fs._isNetwork = true
    fs._server = server

    local deviceName = "\\Device\\NetworkDisk" .. letter:sub(1, 1) .. "\\Partition0"
    _G.Mm.NonPagedPool[deviceName] = fs
    _G.Drives[letter] = deviceName

    DbgPrint("NFS: Mounted " .. tostring(server.serverID) .. " as " .. letter)
    return true
end

local function SelectMountLetter(server)
    local winW, winH = 40, 8
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local input = ""
    local errorMsg = nil

    local function DrawDialog()
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)
        gdi32.TextOut(hdc, winX + 2, winY + 1, " Mount Network Disk")

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, winX + 2, winY + 3, "Server: " .. server.serverID)

        local display = input ~= "" and input or "_"
        gdi32.TextOut(hdc, winX + 2, winY + 5, "Mount as: " .. display .. ":")

        if errorMsg then
            gdi32.SetTextColor(hdc, 0xFF0000)
            gdi32.TextOut(hdc, winX + 2, winY + 6, errorMsg:sub(1, winW - 4))
        end

        local btnY = winY + winH - 2
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
        gdi32.PatBlt(hdc, winX + winW - 18, btnY, 7, 2, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX + winW - 10, btnY, 8, 2, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xE0E0E0)
        gdi32.TextOut(hdc, winX + winW - 17, btnY, "[ OK ]")
        gdi32.TextOut(hdc, winX + winW - 9, btnY, "[Cancel]")
    end

    DrawDialog()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then
                if #input > 0 then
                    local letter = input:upper():sub(1, 1) .. ":"
                    if not _G.Drives[letter] then
                        if RegisterNetworkDisk(letter, server) then
                            return letter
                        else
                            errorMsg = "Mount failed!"
                            DrawDialog()
                        end
                    else
                        errorMsg = "Letter already in use!"
                        DrawDialog()
                    end
                end

            elseif code == 14 then
                input = input:sub(1, -2)
                errorMsg = nil
                DrawDialog()

            elseif char >= 32 and char <= 126 then
                local upperChar = string.char(char):upper()
                if upperChar:match("^[A-Z]$") then
                    input = upperChar
                    errorMsg = nil
                end
                DrawDialog()
            end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = winY + winH - 2

            if ty >= btnY and ty <= btnY + 1 then
                if tx >= winX + winW - 18 and tx < winX + winW - 11 then
                    if #input > 0 then
                        local letter = input:upper():sub(1, 1) .. ":"
                        if not _G.Drives[letter] then
                            if RegisterNetworkDisk(letter, server) then
                                return letter
                            else
                                errorMsg = "Mount failed!"
                                DrawDialog()
                            end
                        else
                            errorMsg = "Letter already in use!"
                            DrawDialog()
                        end
                    end
                elseif tx >= winX + winW - 10 and tx < winX + winW - 2 then
                    return nil
                end
            end
        end
    end
end

local function RunNFS()
    local winW, winH
    if LDM then
        winW, winH = 50, 12
    else
        winW, winH = 56, 14
    end

    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2

    local statusText = "Searching for NetHDD..."
    local selectedIndex = 1
    local serverList = {}
    local searchDone = false

    local function DrawButtons()
        local btnY = winY + winH - 2
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
        gdi32.PatBlt(hdc, clientX + winW - 22, btnY, 10, 2, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, clientX + winW - 11, btnY, 10, 2, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xE0E0E0)
        gdi32.TextOut(hdc, clientX + winW - 21, btnY, "[Search]")
        gdi32.TextOut(hdc, clientX + winW - 10, btnY, "[Cancel]")
    end

    local function DrawWindow()
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
        gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)
        gdi32.TextOut(hdc, winX + 2, winY + 1, " Search NetHDD's...")
        gdi32.SetTextColor(hdc, 0xFF0000)
        gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 2, clientY + 1, "Found servers:")

        if #serverList == 0 then
            gdi32.SetTextColor(hdc, 0x808080)
            gdi32.TextOut(hdc, clientX + 2, clientY + 3, "(No servers found)")
        else
            for i, server in ipairs(serverList) do
                local yPos = clientY + 2 + i
                if i == selectedIndex then
                    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
                    gdi32.PatBlt(hdc, clientX, yPos, winW - 2, 1, gdi32.PATCOPY)
                    gdi32.SetTextColor(hdc, 0xFFFFFF)
                else
                    gdi32.SetTextColor(hdc, 0x000000)
                end
                gdi32.TextOut(hdc, clientX + 2, yPos, server.serverID:sub(1, winW - 6))
            end
        end

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 2, winY + winH - 3, statusText:sub(1, winW - 6))

        DrawButtons()
    end

    local function DoSearch()
        statusText = "Searching..."
        DrawWindow()

        local ok, err = SearchNetHDD()
        if ok then
            serverList = {}
            for _, server in pairs(discoveredServers) do
                table.insert(serverList, server)
            end
            table.sort(serverList, function(a, b) return a.serverID < b.serverID end)

            if #serverList == 0 then
                statusText = "No NetHDD's found. Press Search again."
            else
                statusText = "Found " .. #serverList .. " server(s). Select and press ENTER."
            end
        else
            statusText = "ERROR: " .. tostring(err)
        end

        searchDone = true
        selectedIndex = 1
        DrawWindow()
    end

    DrawWindow()
    coroutine.yield()

    DoSearch()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 203 then
                return

            elseif code == 200 then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    DrawWindow()
                end

            elseif code == 208 then
                if selectedIndex < #serverList then
                    selectedIndex = selectedIndex + 1
                    DrawWindow()
                end

            elseif code == 28 then
                if #serverList > 0 then
                    selectedServer = serverList[selectedIndex]
                    local letter = SelectMountLetter(selectedServer)
                    if letter then
                        statusText = "Mounted as " .. letter
                    else
                        statusText = "Mount cancelled"
                    end
                    selectedServer = nil
                    DrawWindow()
                end
            end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = winY + winH - 2

            if ty == winY + 1 and tx >= winX + winW - 5 then
                return
            end

            if ty == btnY and tx >= clientX + winW - 22 and tx < clientX + winW - 12 then
                DoSearch()
            end

            if ty == btnY and tx >= clientX + winW - 11 and tx < clientX + winW - 1 then
                return
            end

            for i = 1, #serverList do
                local yPos = clientY + 2 + i
                if ty == yPos then
                    selectedIndex = i
                    DrawWindow()
                    break
                end
            end
        end
    end
end

DbgPrint("NFS: Starting Network FileSystem client...")
RunNFS()
DbgPrint("NFS: Closed.")

return true