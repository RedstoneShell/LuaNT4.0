-- bootpart.lua - init.lua Flash Tool for LuaNT
-- (C) RedstoneShell 2026
-- GUI for toggling init.lua variables

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local LDM = _G.Tier2CM == true

local config = {
    DebugMode = false,
    DbgPrintToFile = true,
    DbgLogFile = "/ntbootdd.log"
}

local function ParseInitLua(content)
    local result = {}

    local debugMode = content:match("_G%.DebugMode%s*=%s*(%a+)")
    if debugMode then
        result.DebugMode = (debugMode == "true")
    end

    local dbgPrintToFile = content:match("_G%.DbgPrintToFile%s*=%s*(%a+)")
    if dbgPrintToFile then
        result.DbgPrintToFile = (dbgPrintToFile == "true")
    end

    local dbgLogFile = content:match('_G%.DbgLogFile%s*=%s*"([^"]+)"')
    if dbgLogFile then
        result.DbgLogFile = dbgLogFile
    end

    return result
end

local function UpdateInitLua(config)
    local fs = component.proxy(computer.getBootAddress())

    local file = fs.open("/init.lua", "r")
    if not file then
        return false, "Cannot open init.lua"
    end

    local content = ""
    while true do
        local chunk = fs.read(file, 4096)
        if not chunk or #chunk == 0 then break end
        content = content .. chunk
    end
    fs.close(file)

    content = content:gsub("_G%.DebugMode%s*=%s*%a+",
        "_G.DebugMode = " .. tostring(config.DebugMode))

    content = content:gsub("_G%.DbgPrintToFile%s*=%s*%a+",
        "_G.DbgPrintToFile = " .. tostring(config.DbgPrintToFile))

    content = content:gsub('_G%.DbgLogFile%s*=%s*"[^"]+"',
        '_G.DbgLogFile = "' .. config.DbgLogFile .. '"')

    content = content:gsub('pc_io%.remove%("/ntbootdd%.log"%)',
        'pc_io.remove("' .. config.DbgLogFile .. '")')

    local outFile = fs.open("/init.lua", "w")
    if not outFile then
        return false, "Cannot write init.lua"
    end

    fs.write(outFile, content)
    fs.close(outFile)

    return true
end

local function DrawWindow()
    local winW, winH
    if LDM then
        winW, winH = 50, 14
    else
        winW, winH = 56, 16
    end

    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2

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
    gdi32.TextOut(hdc, winX + 2, winY + 1, " BootPart - init.lua Flash Tool")
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xC0C0C0)

    local lineY = clientY + 2

    gdi32.TextOut(hdc, clientX + 2, lineY, "DebugMode:")
    gdi32.TextOut(hdc, clientX + 16, lineY,
        "[" .. (config.DebugMode and "X" or " ") .. "] ON/OFF")
    lineY = lineY + 2

    gdi32.TextOut(hdc, clientX + 2, lineY, "DbgPrintToFile:")
    gdi32.TextOut(hdc, clientX + 20, lineY,
        "[" .. (config.DbgPrintToFile and "X" or " ") .. "] ON/OFF")
    lineY = lineY + 2

    gdi32.TextOut(hdc, clientX + 2, lineY, "DbgLogFile:")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, clientX + 2, lineY + 1, winW - 6, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xFFFFFF)
    gdi32.TextOut(hdc, clientX + 3, lineY + 1, config.DbgLogFile .. "_")

    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xC0C0C0)

    local btnY = winY + winH - 3
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
    gdi32.PatBlt(hdc, clientX + winW - 22, btnY, 10, 2, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, clientX + winW - 11, btnY, 10, 2, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xE0E0E0)
    gdi32.TextOut(hdc, clientX + winW - 21, btnY, "[ Save ]")
    gdi32.TextOut(hdc, clientX + winW - 10, btnY, "[Cancel]")

    return winX, winY, winW, winH, clientX, clientY
end

local function RunBootPart()
    local fs = component.proxy(computer.getBootAddress())

    local file = fs.open("/init.lua", "r")
    if not file then
        DbgPrint("BOOTPART: Cannot open init.lua")
        return
    end

    local content = ""
    while true do
        local chunk = fs.read(file, 4096)
        if not chunk or #chunk == 0 then break end
        content = content .. chunk
    end
    fs.close(file)

    local parsed = ParseInitLua(content)
    config.DebugMode = parsed.DebugMode or false
    config.DbgPrintToFile = parsed.DbgPrintToFile or true
    config.DbgLogFile = parsed.DbgLogFile or "/ntbootdd.log"

    local statusText = "Ready"
    local inputMode = false
    local inputBuffer = config.DbgLogFile

    local winX, winY, winW, winH, clientX, clientY = DrawWindow()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 203 then
                return

            elseif inputMode then
                if code == 28 then
                    config.DbgLogFile = inputBuffer
                    inputMode = false
                    statusText = "Path changed: " .. config.DbgLogFile
                    DrawWindow()

                elseif code == 14 then
                    inputBuffer = inputBuffer:sub(1, -2)
                    config.DbgLogFile = inputBuffer
                    DrawWindow()

                elseif char >= 32 and char <= 126 then
                    inputBuffer = inputBuffer .. string.char(char)
                    config.DbgLogFile = inputBuffer
                    DrawWindow()
                end
            end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]

            if ty == winY + 1 and tx >= winX + winW - 5 then
                return
            end

            if ty == clientY + 2 and tx >= clientX + 2 and tx <= clientX + 30 then
                config.DebugMode = not config.DebugMode
                statusText = "DebugMode: " .. (config.DebugMode and "ON" or "OFF")
                DrawWindow()
            end

            if ty == clientY + 4 and tx >= clientX + 2 and tx <= clientX + 30 then
                config.DbgPrintToFile = not config.DbgPrintToFile
                statusText = "DbgPrintToFile: " .. (config.DbgPrintToFile and "ON" or "OFF")
                DrawWindow()
            end
            if ty == clientY + 6 and tx >= clientX + 2 and tx <= clientX + winW - 6 then
                inputMode = true
                inputBuffer = config.DbgLogFile
                statusText = "Enter new log file path"
                DrawWindow()
            end
            if ty == winY + winH - 3 and tx >= clientX + winW - 22 and tx < clientX + winW - 12 then
                local ok, err = UpdateInitLua(config)
                if ok then
                    statusText = "Saved to init.lua! Reboot to apply."
                else
                    statusText = "ERROR: " .. tostring(err)
                end
                DrawWindow()
            end
            if ty == winY + winH - 3 and tx >= clientX + winW - 11 and tx < clientX + winW - 2 then
                return
            end
        end
    end
end

DbgPrint("BOOTPART: Starting BootPart...")
RunBootPart()
DbgPrint("BOOTPART: Closed.")

return true