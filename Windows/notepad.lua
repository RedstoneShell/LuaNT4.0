-- notepad.lua - Text editor for LuaNT 4.0
-- (C) RedstoneShell 2026

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local args = {}
if _G.RpcSs then
    local rpcOk, result = _G.RpcSs.RpcCliExecute("IConsoleManager", "GetProcessArgs")
    if rpcOk and result then
        args = result
    end
end

local function printToConsole(text)
    if _G.RpcSs then
        _G.RpcSs.RpcCliExecute("IConsoleManager", "WriteStdOut", tostring(text))
    else
        _G.DbgPrint("Notepad: " .. tostring(text))
    end
end

local print = printToConsole

local function ParseArguments(args)
    local fileToOpen = nil
    local showHelp = false
    
    for i, arg in ipairs(args) do
        if arg == "/?" or arg == "-h" or arg == "--help" then
            showHelp = true
        elseif arg:sub(1, 1) ~= "/" and arg:sub(1, 1) ~= "-" then
            fileToOpen = arg
        end
    end
    
    if showHelp then
        print("Notepad - Text Editor for LuaNT 4.0")
        print("")
        print("Usage: notepad [file] [/help]")
        print("")
        print("  [file]   - File to open (relative or absolute path)")
        print("  /?, /help - Show this help message")
        print("")
        print("Commands in Notepad:")
        print("  Ctrl+S   - Save file")
        print("  Insert   - Toggle Insert/Overwrite mode")
        print("  ESC      - Close Notepad")
        print("")
        print("Examples:")
        print("  notepad")
        print("  notepad Windows\\System32\\config\\SYSTEM")
        print("  notepad /help")
        return nil, true
    end
    
    return fileToOpen, false
end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 60, 25
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)
local clientX = winX + 1
local clientY = winY + 2
local clientW = winW - 2
local clientH = winH - 3

local lines = {""}
local cursorLine = 1
local cursorPos = 1
local scrollOffset = 0
local fileName = "Untitled.txt"
local filePath = nil
local isDirty = false
local isInsertMode = true
local lastSaveTime = 0

local COLORS = {
    window_bg = 0xCCCCCC,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    cursor = 0x0000FF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF,
    dirty_marker = 0xFF0000
}

local function DrawWindowFrame()
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.window_bg))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
    gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.window_title))
    gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
    
    local title = "Notepad - " .. fileName
    if isDirty then title = title .. " *" end
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.window_title)
    gdi32.TextOut(hdc, winX + 2, winY + 1, title)
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
end

local function DrawStatusBar()
    local statusY = winY + winH - 1
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.status_bg))
    gdi32.PatBlt(hdc, winX + 1, statusY - 1, winW - 2, 1, gdi32.PATCOPY)
    
    local statusText = string.format("Ln %d, Col %d  %s  %s",
        cursorLine,
        cursorPos,
        isInsertMode and "INS" or "OVR",
        fileName
    )
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.status_bg)
    gdi32.TextOut(hdc, winX + 2, statusY - 1, statusText)
end

local function DrawContent()
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local visibleLines = clientH - 1
    local startLine = scrollOffset + 1
    
    for i = startLine, math.min(startLine + visibleLines, #lines) do
        local lineText = lines[i] or ""
        local yPos = clientY + (i - startLine)
        if yPos < clientY + clientH then
            gdi32.TextOut(hdc, clientX + 1, yPos, lineText:sub(1, clientW - 1))
        end
    end
    
    local cursorYPos = clientY + (cursorLine - scrollOffset - 1)
    if cursorYPos >= clientY and cursorYPos < clientY + clientH then
        local cursorXPos = clientX + cursorPos
        if cursorXPos >= clientX and cursorXPos < clientX + clientW then
            gdi32.SetTextColor(hdc, COLORS.cursor)
            gdi32.TextOut(hdc, cursorXPos, cursorYPos, "|")
        end
    end
end

local function RedrawWindow()
    DrawWindowFrame()
    DrawContent()
    DrawStatusBar()
end

local function InsertChar(char)
    if not char or char == "" then return end
    
    local line = lines[cursorLine] or ""
    if cursorPos > #line then
        line = line .. char
    else
        line = line:sub(1, cursorPos - 1) .. char .. line:sub(cursorPos)
    end
    lines[cursorLine] = line
    cursorPos = cursorPos + 1
    isDirty = true
    RedrawWindow()
end

local function DeleteChar()
    local line = lines[cursorLine] or ""
    if cursorPos > #line then
        if cursorLine < #lines then
            lines[cursorLine] = line .. (lines[cursorLine + 1] or "")
            table.remove(lines, cursorLine + 1)
            isDirty = true
            RedrawWindow()
        end
        return
    end
    
    line = line:sub(1, cursorPos - 1) .. line:sub(cursorPos + 1)
    lines[cursorLine] = line
    isDirty = true
    RedrawWindow()
end

local function BackspaceChar()
    if cursorPos > 1 then
        local line = lines[cursorLine] or ""
        line = line:sub(1, cursorPos - 2) .. line:sub(cursorPos)
        lines[cursorLine] = line
        cursorPos = cursorPos - 1
        isDirty = true
        RedrawWindow()
    elseif cursorLine > 1 then
        local prevLine = lines[cursorLine - 1] or ""
        lines[cursorLine - 1] = prevLine .. (lines[cursorLine] or "")
        table.remove(lines, cursorLine)
        cursorLine = cursorLine - 1
        cursorPos = #prevLine + 1
        isDirty = true
        RedrawWindow()
    end
end

local function NewLine()
    local line = lines[cursorLine] or ""
    local newLine = line:sub(cursorPos)
    lines[cursorLine] = line:sub(1, cursorPos - 1)
    table.insert(lines, cursorLine + 1, newLine)
    cursorLine = cursorLine + 1
    cursorPos = 1
    isDirty = true
    RedrawWindow()
end

local function MoveCursor(dx, dy)
    local newLine = cursorLine + dy
    if newLine < 1 then newLine = 1 end
    if newLine > #lines then newLine = #lines end
    
    local line = lines[newLine] or ""
    local newPos = cursorPos + dx
    if newPos < 1 then newPos = 1 end
    if newPos > #line + 1 then newPos = #line + 1 end
    
    cursorLine = newLine
    cursorPos = newPos
    
    if cursorLine <= scrollOffset then
        scrollOffset = cursorLine - 1
    elseif cursorLine > scrollOffset + clientH - 2 then
        scrollOffset = cursorLine - clientH + 2
    end
    
    RedrawWindow()
end

local function SaveFile()
    if not filePath then
        print("Enter file name to save:")
        filePath = "/" .. fileName
    end
    
    local fs = component.proxy(computer.getBootAddress())
    local f, err = fs.open(filePath, "w")
    if not f then
        print("Notepad: Failed to save - " .. tostring(err))
        return false
    end
    
    local content = table.concat(lines, "\n")
    fs.write(f, content)
    fs.close(f)
    
    isDirty = false
    lastSaveTime = computer.uptime()
    print("File saved: " .. filePath)
    RedrawWindow()
    return true
end

local function LoadFile(path)
    local fs = component.proxy(computer.getBootAddress())
    
    if not fs.exists(path) then
        print("Notepad: File not found: " .. path)
        print("Creating new file: " .. path)
        lines = {""}
        filePath = path
        fileName = path:match("^.*/(.+)$") or path
        cursorLine = 1
        cursorPos = 1
        scrollOffset = 0
        isDirty = false
        RedrawWindow()
        return true
    end
    
    local f, err = fs.open(path, "r")
    if not f then
        print("Notepad: Failed to load - " .. tostring(err))
        return false
    end
    
    local content = ""
    while true do
        local chunk = fs.read(f, 4096)
        if not chunk then break end
        content = content .. chunk
    end
    fs.close(f)
    
    lines = {}
    for line in content:gmatch("[^\n]*") do
        table.insert(lines, line)
    end
    if #lines == 0 then lines = {""} end
    
    filePath = path
    fileName = path:match("^.*/(.+)$") or path
    cursorLine = 1
    cursorPos = 1
    scrollOffset = 0
    isDirty = false
    
    print("File loaded: " .. path)
    RedrawWindow()
    return true
end

local function HandleKey(char, code)
    if code == 1 then -- ESC
        return false
    elseif code == 28 then -- ENTER
        NewLine()
    elseif code == 14 then -- BACKSPACE
        BackspaceChar()
    elseif code == 211 then -- DELETE
        DeleteChar()
    elseif code == 200 then -- UP
        MoveCursor(0, -1)
    elseif code == 208 then -- DOWN
        MoveCursor(0, 1)
    elseif code == 203 then -- LEFT
        MoveCursor(-1, 0)
    elseif code == 205 then -- RIGHT
        MoveCursor(1, 0)
    elseif code == 47 then -- CTRL+S
        SaveFile()
    elseif code == 45 then -- INSERT
        isInsertMode = not isInsertMode
        RedrawWindow()
    elseif char >= 32 and char <= 126 then
        if isInsertMode then
            InsertChar(string.char(char))
        else
            local line = lines[cursorLine] or ""
            if cursorPos <= #line then
                line = line:sub(1, cursorPos - 1) .. string.char(char) .. line:sub(cursorPos + 1)
            else
                line = line .. string.char(char)
            end
            lines[cursorLine] = line
            cursorPos = cursorPos + 1
            isDirty = true
            RedrawWindow()
        end
    end
    return true
end

local function NotepadMain()
    _G.DbgPrint("Notepad: Starting...")
    
    local fileToOpen, showHelp = ParseArguments(args)
    
    if showHelp then
        return false
    end
    
    if fileToOpen then
        LoadFile(fileToOpen)
    else
        print("Notepad 4.0 - (C) RedstoneShell 2026")
        print("Type 'notepad /help' for usage information")
    end
    
    RedrawWindow()
    
    while true do
        local signal = { computer.pullSignal(0.1) }
        
        if signal[1] == "key_down" then
            local char = signal[3]
            local code = signal[4]
            
            if not HandleKey(char, code) then
                break
            end
            
        elseif signal[1] == "touch" then
            local x, y = signal[3], signal[4]
            if y == winY + 1 and x >= winX + winW - 3 and x <= winX + winW - 1 then
                if isDirty then
                    if SaveFile() then
                        break
                    end
                else
                    break
                end
            end
        end
    end
    
    _G.DbgPrint("Notepad: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    
    return false
end

local exitCode = NotepadMain()

if not exitCode then
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true