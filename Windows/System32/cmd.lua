local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua") 

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h
local winW, winH = 50, 15
local winX = screenW - winW - 1
local winY = screenH - winH - 6
local clientX = winX + 1
local clientY = winY + 2
local clientW = winW - 2
local clientH = winH - 3
local cursorX, cursorY = 1, 1
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
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000000)
    
    local safeText = tostring(text):sub(1, clientW - 1)
    gdi32.TextOut(hdc, clientX + cursorX - 1, clientY + cursorY - 1, safeText)
    
    cursorY = cursorY + 1
    if cursorY > clientH then
        cursorY = 1
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
        gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
    end
end

local function consoleRead()
    local inp = ""
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000000)
    gdi32.TextOut(hdc, clientX + cursorX + #inp - 1, clientY + cursorY - 1, "_")
    
    repeat
        local signal = { computer.pullSignal(0.2) }
        
        if signal[1] == "key_down" then
            local char, code = signal[3], signal[4]
            if code == 28 then -- ENTER
                gdi32.TextOut(hdc, clientX + cursorX + #inp - 1, clientY + cursorY - 1, " ")
                cursorY = cursorY + 1
                if cursorY > clientH then
                    cursorY = 1
                    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
                    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
                end
                return inp
            elseif code == 14 then -- BACKSPACE
                if #inp > 0 then
                    gdi32.TextOut(hdc, clientX + cursorX + #inp - 1, clientY + cursorY - 1, " ")
                    inp = inp:sub(1, -2)
                end
            elseif char >= 32 and char <= 126 and (#inp + cursorX < clientW) then
                inp = inp .. string.char(char)
            end
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
            gdi32.PatBlt(hdc, clientX + cursorX - 1, clientY + cursorY - 1, clientW - cursorX, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, 0xFFFFFF)
            gdi32.TextOut(hdc, clientX + cursorX - 1, clientY + cursorY - 1, inp .. "_")
        
        else
            coroutine.yield()
        end
    until false
end

DrawWindowFrame()

consolePrint("RedstoneShell(R) Windows NT(R)")
consolePrint("(C) Copyright 2026 RedstoneShell")
consolePrint("")

local currentDirectory = "C:\\Windows\\System32"

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
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000000)
    gdi32.TextOut(hdc, clientX + cursorX - 1, clientY + cursorY - 1, currentDirectory .. ">")
    
    local oldCursorX = cursorX
    cursorX = #currentDirectory + 2
    local input = consoleRead()
    cursorX = oldCursorX
    
    if input and input ~= "" then
        local args = {}
        for word in input:gmatch("%S+") do table.insert(args, word) end
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
                    thread.UniqueProcessId, thread.ImageName:sub(1,12), thread.CurrentPriority))
            end
            
        elseif cmd == "taskkill" then
            if args[2] == "/pid" and args[3] then
                local pid = tonumber(args[3])
                local status = ntdll.NtTerminateProcess(pid)
                if status then
                    consolePrint("SUCCESS: PID " .. tostring(pid) .. " killed.")
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
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
            ntdll.NtTerminateProcess()
            gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
            break
        else
            local path = "Windows/System32/" .. args[1]
            if not path:match("%.lua$") then path = path .. ".lua" end
            local cmdArgs = {}
            for i = 2, #args do table.insert(cmdArgs, args[i]) end
            LastSpawnedArgs = cmdArgs
            local pid, statusString = ntdll.NtCreateUserProcess(path, args[1], 8)
            if statusString == "STATUS_SUCCESS" then
                ntdll.NtDelayExecution() 
            else
                path = "Windows/" .. args[1]
                if not path:match("%.lua$") then path = path .. ".lua" end
                cmdArgs = {}
                for i = 2, #args do table.insert(cmdArgs, args[i]) end
                LastSpawnedArgs = cmdArgs
                pid, statusString = ntdll.NtCreateUserProcess(path, args[1], 8)
                if statusString == "STATUS_SUCCESS" then
                    ntdll.NtDelayExecution() 
                else
                    consolePrint("ERROR: " .. statusString)
                end
            end
        end
    end
until false

if _G.RpcSs then _G.RpcSs.RpcServerUnregisterIf("IConsoleManager") end