-- cmd.lua
-- (C) RedstoneShell 2026

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h
local winW, winH = 90, 30
local winX = ((screenW - winW) // 2) + 20
local winY = (screenH - winH) // 2
local clientX = winX + 1
local clientY = winY + 2
local clientW = winW - 2
local clientH = winH - 3
local cursorX, cursorY = 1, 1
local currentDirectory = "C:\\Windows\\System32"

local history = {}
local historyIndex = 0
local currentInput = ""

local function stringWidth(str)
    return #str
end

local function splitLines(text, maxWidth)
    if not text then return {} end
    local lines = {}
    local current = ""
    for i = 1, #text do
        local ch = text:sub(i, i)
        if #current + 1 > maxWidth then
            table.insert(lines, current)
            current = ch
        else
            current = current .. ch
        end
    end
    if #current > 0 then
        table.insert(lines, current)
    end
    return lines
end

local function DrawWindowFrame()
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
    gdi32.TextOut(hdc, winX + 2, winY + 1, " Command Prompt")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
end

local function consolePrint(text)
    if not text then return end

    local maxWidth = clientW - 1
    local lines = splitLines(tostring(text), maxWidth)

    for _, line in ipairs(lines) do
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000000)
        gdi32.TextOut(hdc, clientX + cursorX - 1, clientY + cursorY - 1, line)

        cursorY = cursorY + 1
        if cursorY > clientH then
            cursorY = 1
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
            gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
        end
    end
end

local function clearInputLine(y)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
    gdi32.PatBlt(hdc, clientX, clientY + y - 1, clientW, 1, gdi32.PATCOPY)
end

local function renderInput(input, y, promptLen)
    local maxWidth = clientW - promptLen
    local displayText = input:sub(1, maxWidth)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000000)
    gdi32.TextOut(hdc, clientX + promptLen, clientY + y - 1, displayText .. "_")
end

local function consoleRead()
    local inp = ""
    local prompt = currentDirectory .. ">"
    local promptLen = #prompt

    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000000)
    gdi32.TextOut(hdc, clientX + cursorX - 1, clientY + cursorY - 1, prompt)

    local inputStartX = cursorX + #prompt
    local lineY = cursorY

    renderInput(inp, lineY, inputStartX)

    local historyPos = #history

    repeat
        local signal = { computer.pullSignal(0.1) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]
            local handled = false
            if code == 200 then
                if #history > 0 and historyPos > 0 then
                    if historyPos == #history then
                        currentInput = inp
                    end
                    historyPos = historyPos - 1
                    inp = history[historyPos + 1] or ""
                    clearInputLine(lineY)
                    renderInput(inp, lineY, inputStartX)
                    handled = true
                end
            elseif code == 208 then
                if historyPos < #history then
                    historyPos = historyPos + 1
                    inp = history[historyPos + 1] or currentInput
                    clearInputLine(lineY)
                    renderInput(inp, lineY, inputStartX)
                    handled = true
                elseif historyPos == #history then
                    inp = currentInput
                    clearInputLine(lineY)
                    renderInput(inp, lineY, inputStartX)
                    handled = true
                end
            elseif code == 47 and (signal[5] and signal[5] == 1) then -- Ctrl+V
                local clip = _G.clipboard or ""
                if #clip > 0 then
                    inp = inp .. clip
                    clearInputLine(lineY)
                    renderInput(inp, lineY, inputStartX)
                    handled = true
                end
            elseif code == 28 then
                if #inp > 0 then
                    table.insert(history, inp)
                end
                historyPos = #history
                currentInput = ""
                cursorY = cursorY + 1
                if cursorY > clientH then
                    cursorY = 1
                    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
                    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
                end
                return inp
            elseif code == 14 then
                if #inp > 0 then
                    inp = inp:sub(1, -2)
                    clearInputLine(lineY)
                    renderInput(inp, lineY, inputStartX)
                    handled = true
                end
            elseif char >= 32 and char <= 126 then
                local maxDisplay = clientW - inputStartX
                if #inp < maxDisplay then
                    inp = inp .. string.char(char)
                    clearInputLine(lineY)
                    renderInput(inp, lineY, inputStartX)
                    handled = true
                end
            end
            if not handled then
            end
        elseif event == "clipboard" then
            local value = signal[2] or ""
            if value and #value > 0 then
                value = value:gsub("\r\n", "\n")
                value = value:gsub("\n", " ")
                inp = inp .. value
                clearInputLine(lineY)
                renderInput(inp, lineY, inputStartX)
            end
        end
    until false
end

DrawWindowFrame()

consolePrint("RedstoneShell(R) Windows NT(R)")
consolePrint("(C) Copyright 2026 RedstoneShell")
consolePrint("")
consolePrint("Type 'ver' to see version, 'cls' to clear, 'exit' to quit.")
consolePrint("")

local LastSpawnedArgs = {}

if _G.RpcSs then
    local IConsoleInterface = {
        WriteStdOut = function(text)
            consolePrint(text)
            return true
        end,

        ReadStdIn = function()
            return consoleRead()
        end,

        GetProcessArgs = function()
            return LastSpawnedArgs
        end
    }
    _G.RpcSs.RpcServerRegisterIf("IConsoleManager", IConsoleInterface)
end

repeat
    cursorX = 1
    local input = consoleRead()

    if input and input ~= "" then
        local args = {}
        for word in input:gmatch("%S+") do
            table.insert(args, word)
        end
        local cmd = args[1]:lower()

        if cmd == "ver" then
            consolePrint("Windows NT Version 4.0.2026 (LuaNT Secure Build)")

        elseif cmd == "cls" then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
            gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
            cursorY = 1

        elseif cmd == "tasklist" then
            consolePrint(string.format("%-4s %-12s %-4s", "PID", "Image", "Prio"))
            consolePrint("======================================")
            local plist = ntdll.NtQuerySystemInformation()
            for _, thread in ipairs(plist) do
                consolePrint(string.format("%-4d %-12s %-4d",
                    thread.UniqueProcessId, thread.ImageName:sub(1, 12), thread.CurrentPriority))
            end

        elseif cmd == "taskkill" then
            if args[2] == "/pid" and args[3] then
                local pid = tonumber(args[3])
                if pid then
                    local status = ntdll.NtTerminateProcess(pid)
                    if status then
                        consolePrint("SUCCESS: PID " .. tostring(pid) .. " killed.")
                    else
                        consolePrint("ERROR: Failed to kill PID " .. tostring(pid))
                    end
                else
                    consolePrint("ERROR: Invalid PID")
                end
            else
                consolePrint("Usage: taskkill /pid <PID>")
            end

        elseif cmd == "reg" then
            if args[2] == "query" and args[3] then
                local path = args[3]
                local hive = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SYSTEM"]
                if hive and hive[path] then
                    for k, v in pairs(hive[path]) do
                        consolePrint("  " .. k .. "=" .. tostring(v))
                    end
                else
                    consolePrint("Error: Key not found.")
                end
            else
                consolePrint("Usage: reg query <Path>")
            end

        elseif cmd == "exit" then
            consolePrint("")
            consolePrint("Terminating console...")
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
            ntdll.NtTerminateProcess()
            gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
            coroutine.yield()
            break

        else
            local path = "Windows/System32/" .. args[1]
            if not path:match("%.lua$") then
                path = path .. ".lua"
            end

            local cmdArgs = {}
            for i = 2, #args do
                table.insert(cmdArgs, args[i])
            end
            LastSpawnedArgs = cmdArgs

            local pid, statusString = _G.PsCreateSystemThread(path, args[1], 8)
            if statusString == "STATUS_SUCCESS" then
                ntdll.NtDelayExecution()
            else
                path = "Windows/" .. args[1]
                if not path:match("%.lua$") then
                    path = path .. ".lua"
                end
                pid, statusString = _G.PsCreateSystemThread(path, args[1], 8)
                if statusString == "STATUS_SUCCESS" then
                    ntdll.NtDelayExecution()
                else
                    if not path:match("%.lua$") then
                        path = path .. ".lua"
                    end
                    pid, statusString = _G.PsCreateSystemThread(args[1], args[1], 8)
                    if statusString == "STATUS_SUCCESS" then
                        ntdll.NtDelayExecution()
                    else
                        consolePrint("ERROR: " .. statusString)
                    end
                end
            end
        end
    end
until false

if _G.RpcSs then
    _G.RpcSs.RpcServerUnregisterIf("IConsoleManager")
end
