-- notepad.lua - Text editor for LuaNT 4.0
-- (C) RedstoneShell 2026
-- Full version with Menu, Clipboard, Find/Replace, Print, Word Wrap

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local printer = _G.LdrLoadDll("Windows/System32/winprint.lua")
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
        _G.DbgPrint("Notepad: " .. tostring(text))
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
        print("  Ctrl+N   - New file")
        print("  Ctrl+O   - Open file")
        print("  Ctrl+S   - Save file")
        print("  Ctrl+P   - Print")
        print("  Ctrl+F   - Find")
        print("  Ctrl+H   - Replace")
        print("  Ctrl+G   - Go to line")
        print("  Ctrl+A   - Select all")
        print("  Ctrl+C   - Copy")
        print("  Ctrl+X   - Cut")
        print("  Ctrl+V   - Paste")
        print("  Ctrl+Z   - Undo")
        print("  Insert   - Toggle Insert/Overwrite")
        print("  ESC      - Close Notepad")
        return nil, true
    end
    
    return fileToOpen, false
end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 70, 30
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)
local clientX = winX + 1
local clientY = winY + 3
local clientW = winW - 2
local clientH = winH - 5

local lines = {""}
local cursorLine = 1
local cursorPos = 1
local scrollOffset = 0
local fileName = "Untitled.txt"
local filePath = nil
local isDirty = false
local isInsertMode = true
local wordWrap = false
local showStatusBar = true
local lastSaveTime = 0
local selectedText = nil
local selectionStart = nil
local selectionEnd = nil
local clipboard = ""

local undoStack = {}
local undoLimit = 50
local currentUndoPos = 0

local COLORS = {
    window_bg = 0xC0C0C0,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    cursor = 0x0000FF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF,
    dirty_marker = 0xFF0000,
    menu_bg = 0xC0C0C0,
    menu_text = 0x000000,
    menu_highlight = 0x000080,
    menu_highlight_text = 0xFFFFFF,
    selection = 0x000080,
    selection_text = 0xFFFFFF
}

local menuItems = {
    { "File", {
        { "New", "Ctrl+N", function() NewFile() end },
        { "Open...", "Ctrl+O", function() OpenFile() end },
        { "Save", "Ctrl+S", function() SaveFile() end },
        { "Save As...", "", function() SaveFileAs() end },
        { "-" },
        { "Print", "Ctrl+P", function() PrintFile() end },
        { "-" },
        { "Exit", "", function() NotepadExit() end },
    }},
    { "Edit", {
        { "Undo", "Ctrl+Z", function() Undo() end },
        { "-" },
        { "Cut", "Ctrl+X", function() CutText() end },
        { "Copy", "Ctrl+C", function() CopyText() end },
        { "Paste", "Ctrl+V", function() PasteText() end },
        { "Delete", "Del", function() DeleteText() end },
        { "-" },
        { "&Find...", "Ctrl+F", function() FindText() end },
        { "Find&Next", "F3", function() FindNext() end },
        { "Replace...", "Ctrl+H", function() ReplaceText() end },
        { "Go To...", "Ctrl+G", function() GoToLine() end },
        { "-" },
        { "Select All", "Ctrl+A", function() SelectAll() end },
    }},
    { "Format", {
        { "Word Wrap", "", function() ToggleWordWrap() end },
        { "Font...", "", function() ChangeFont() end },
    }},
    { "View", {
        { "Status Bar", "", function() ToggleStatusBar() end },
    }},
    { "Help", {
        { "About Notepad", "", function() ShowAbout() end },
    }},
}

local menuOpen = false
local menuX = winX
local menuY = winY + 1
local selectedMenu = 1
local selectedSubMenu = 1

local function ReadString(prompt, maxLen, default)
    maxLen = maxLen or 64
    local input = default or ""
    
    local tempX = winX
    local tempY = winY
    local tempW = winW
    local tempH = winH
    
    local function DrawInputDialog()
        local dialogW = 50
        local dialogH = 6
        local dialogX = math.floor((screenW - dialogW) / 2)
        local dialogY = math.floor((screenH - dialogH) / 2)
        
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, dialogX, dialogY, dialogW, dialogH, gdi32.PATCOPY)
        
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, dialogX, dialogY, dialogW, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)
        gdi32.TextOut(hdc, dialogX + 2, dialogY, " Input")
        
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, dialogX + 2, dialogY + 2, prompt)
        
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, dialogX + 2, dialogY + 3, 46, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)
        gdi32.TextOut(hdc, dialogX + 3, dialogY + 3, input .. "|")
    end
    
    DrawInputDialog()
    
    while true do
        local signal = { computer.pullSignal(0.1) }
        
        if signal[1] == "key_down" then
            local char = signal[3]
            local code = signal[4]
            
            if code == 28 then -- ENTER
                return input
            elseif code == 14 then -- BACKSPACE
                input = input:sub(1, -2)
                DrawInputDialog()
            elseif code == 203 then -- <
                return nil
            elseif char >= 32 and char <= 126 and #input < maxLen then
                input = input .. string.char(char)
                DrawInputDialog()
            end
        end
    end
end

function GetLineText(line)
    return lines[line] or ""
end

function SetLineText(line, text)
    if line >= 1 and line <= #lines then
        lines[line] = text
    end
end

function InsertText(text, pos)
    local line = GetLineText(cursorLine)
    if pos > #line then
        line = line .. text
    else
        line = line:sub(1, pos - 1) .. text .. line:sub(pos)
    end
    SetLineText(cursorLine, line)
    cursorPos = cursorPos + #text
end

function DeleteTextRange(startLine, startPos, endLine, endPos)
    if startLine == endLine then
        local line = GetLineText(startLine)
        line = line:sub(1, startPos - 1) .. line:sub(endPos)
        SetLineText(startLine, line)
        cursorLine = startLine
        cursorPos = startPos
    else
        local firstLine = GetLineText(startLine):sub(1, startPos - 1)
        local lastLine = GetLineText(endLine):sub(endPos)
        for i = startLine + 1, endLine - 1 do
            firstLine = firstLine .. GetLineText(i)
        end
        firstLine = firstLine .. lastLine
        SetLineText(startLine, firstLine)
        for i = startLine + 1, endLine do
            table.remove(lines, startLine + 1)
        end
        cursorLine = startLine
        cursorPos = startPos
    end
end

function GetSelectedText()
    if not selectionStart or not selectionEnd then return nil end
    local startLine, startPos = table.unpack(selectionStart)
    local endLine, endPos = table.unpack(selectionEnd)
    
    if startLine == endLine then
        return GetLineText(startLine):sub(startPos, endPos - 1)
    end
    
    local result = {}
    for i = startLine, endLine do
        if i == startLine then
            table.insert(result, GetLineText(i):sub(startPos))
        elseif i == endLine then
            table.insert(result, GetLineText(i):sub(1, endPos - 1))
        else
            table.insert(result, GetLineText(i))
        end
    end
    return table.concat(result, "\n")
end

function ClearSelection()
    selectionStart = nil
    selectionEnd = nil
    selectedText = nil
end

function SelectAll()
    selectionStart = {1, 1}
    selectionEnd = {#lines, #GetLineText(#lines) + 1}
    selectedText = table.concat(lines, "\n")
    RedrawWindow()
end

function CopyText()
    clipboard = GetSelectedText() or ""
    if clipboard ~= "" then
        print("Copied: " .. #clipboard .. " characters")
    end
end

function CutText()
    if not selectionStart or not selectionEnd then return end
    clipboard = GetSelectedText() or ""
    if clipboard == "" then return end
    local startLine, startPos = table.unpack(selectionStart)
    local endLine, endPos = table.unpack(selectionEnd)
    DeleteTextRange(startLine, startPos, endLine, endPos)
    ClearSelection()
    isDirty = true
    RedrawWindow()
    print("Cut: " .. #clipboard .. " characters")
end

function PasteText()
    if clipboard == "" then return end
    local linesToInsert = {}
    for line in clipboard:gmatch("[^\n]*") do
        table.insert(linesToInsert, line)
    end
    if #linesToInsert == 1 then
        local line = GetLineText(cursorLine)
        line = line:sub(1, cursorPos - 1) .. linesToInsert[1] .. line:sub(cursorPos)
        SetLineText(cursorLine, line)
        cursorPos = cursorPos + #linesToInsert[1]
    else
        local currentLine = GetLineText(cursorLine)
        local firstPart = currentLine:sub(1, cursorPos - 1)
        local lastPart = currentLine:sub(cursorPos)
        SetLineText(cursorLine, firstPart .. linesToInsert[1])
        for i = 2, #linesToInsert do
            table.insert(lines, cursorLine + i - 1, linesToInsert[i])
        end
        table.insert(lines, cursorLine + #linesToInsert, lastPart)
        cursorLine = cursorLine + #linesToInsert
        cursorPos = #linesToInsert[#linesToInsert] + 1
    end
    isDirty = true
    RedrawWindow()
end

function DeleteText()
    if selectionStart and selectionEnd then
        local startLine, startPos = table.unpack(selectionStart)
        local endLine, endPos = table.unpack(selectionEnd)
        DeleteTextRange(startLine, startPos, endLine, endPos)
        ClearSelection()
        isDirty = true
        RedrawWindow()
    end
end

function SaveUndoState()
    local state = {
        lines = {},
        cursorLine = cursorLine,
        cursorPos = cursorPos,
        scrollOffset = scrollOffset
    }
    for i, line in ipairs(lines) do
        state.lines[i] = line
    end
    currentUndoPos = currentUndoPos + 1
    undoStack[currentUndoPos] = state
    if #undoStack > undoLimit then
        table.remove(undoStack, 1)
        currentUndoPos = currentUndoPos - 1
    end
end

function Undo()
    if currentUndoPos <= 1 then return end
    currentUndoPos = currentUndoPos - 1
    local state = undoStack[currentUndoPos]
    lines = {}
    for i, line in ipairs(state.lines) do
        lines[i] = line
    end
    cursorLine = state.cursorLine
    cursorPos = state.cursorPos
    scrollOffset = state.scrollOffset
    isDirty = true
    RedrawWindow()
end

function NewFile()
    if isDirty then
        if not SaveFilePrompt() then return end
    end
    lines = {""}
    cursorLine = 1
    cursorPos = 1
    scrollOffset = 0
    fileName = "Untitled.txt"
    filePath = nil
    isDirty = false
    ClearSelection()
    RedrawWindow()
end

function OpenFile()
    if isDirty then
        if not SaveFilePrompt() then return end
    end
    
    local path = ReadString("Enter file path to open:", 128)
    if path and path ~= "" then
        LoadFile(path)
    end
end

function SaveFile()
    if not filePath then
        return SaveFileAs()
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

function SaveFileAs()
    local name = ReadString("Enter file name to save:", 64, fileName)
    if not name or name == "" then
        print("Save cancelled")
        return false
    end
    if not name:match("/") then
        name = "/" .. name
    end
    if not name:match("%.txt$") then
        name = name .. ".txt"
    end
    filePath = name
    fileName = name:match("^.*/(.+)$") or name
    return SaveFile()
end

function SaveFilePrompt()
    local response = ReadString("File has unsaved changes. Save? (Y/N):", 1)
    if response and response:lower() == "y" then
        return SaveFile()
    end
    return true
end

function LoadFile(path)
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
        ClearSelection()
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
    ClearSelection()
    
    print("File loaded: " .. path)
    RedrawWindow()
    return true
end

local findText = ""
local replaceText = ""
local lastFindPos = nil

function FindText()
    local text = ReadString("Find what:", 128)
    if text and text ~= "" then
        findText = text
        FindNext()
    end
end

function FindNext()
    if findText == "" then
        print("No text to find. Use Ctrl+F first.")
        return
    end
    
    local searchFromLine = cursorLine
    local searchFromPos = cursorPos
    
    if lastFindPos then
        searchFromLine = lastFindPos[1]
        searchFromPos = lastFindPos[2] + 1
    end
    
    for i = searchFromLine, #lines do
        local line = GetLineText(i)
        local startPos = 1
        if i == searchFromLine then
            startPos = searchFromPos
        end
        local pos = line:find(findText, startPos, true)
        if pos then
            cursorLine = i
            cursorPos = pos
            lastFindPos = {i, pos}
            selectionStart = {i, pos}
            selectionEnd = {i, pos + #findText}
            selectedText = findText
            RedrawWindow()
            return
        end
    end
    
    print("Text not found: " .. findText)
    lastFindPos = nil
end

function ReplaceText()
    local find = ReadString("Find what:", 128)
    if not find or find == "" then return end
    findText = find
    
    local replace = ReadString("Replace with:", 128)
    if not replace then return end
    replaceText = replace
    
    local count = 0
    for i = 1, #lines do
        local line = GetLineText(i)
        local newLine, num = line:gsub(findText, replaceText, 1)
        if num > 0 then
            SetLineText(i, newLine)
            count = count + num
        end
    end
    print("Replaced " .. count .. " occurrences")
    isDirty = true
    RedrawWindow()
end

function GoToLine()
    local num = ReadString("Enter line number:", 8)
    if not num then return end
    local lineNum = tonumber(num)
    if not lineNum or lineNum < 1 then
        print("Invalid line number")
        return
    end
    if lineNum > #lines then
        print("Line " .. lineNum .. " not found. Last line: " .. #lines)
        lineNum = #lines
    end
    cursorLine = lineNum
    cursorPos = 1
    RedrawWindow()
end

function PrintFile()
    if _G.RpcSs then
        coroutine.yield()
        local text = table.concat(lines, "\n")
        local _,jobId = _G.RpcSs.RpcCliExecute("IPrintSpooler", "AddJob", text, "left", 0x000000)
        if jobId then
            print("Document sent to printer. Job #" .. jobId)
            printer.PrintText(text, "left", 0x000000)
        else
            print("Print failed. Is printer available?")
        end
    else
        print("Print Spooler not available")
    end
end

function ToggleWordWrap()
    wordWrap = not wordWrap
    print("Word Wrap: " .. (wordWrap and "ON" or "OFF"))
    RedrawWindow()
end

function ToggleStatusBar()
    showStatusBar = not showStatusBar
    RedrawWindow()
end

function ChangeFont()
    print("Font selection not implemented yet")
end

function ShowAbout()
    print("Notepad for LuaNT 4.0")
    print("(C) RedstoneShell 2026")
    print("Based on Windows NT 4.0 Notepad")
end

function NotepadExit()
    if isDirty then
        if not SaveFilePrompt() then return end
    end
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return true
end

function DrawMenuBar()
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.menu_bg))
    gdi32.PatBlt(hdc, winX, winY + 1, winW, 1, gdi32.PATCOPY)
    
    local x = winX + 2
    for i, menu in ipairs(menuItems) do
        local text = menu[1]
        local isSelected = menuOpen and i == selectedMenu
        if isSelected then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.menu_highlight))
            gdi32.PatBlt(hdc, x - 1, winY + 1, #text + 2, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, COLORS.menu_highlight_text)
        else
            gdi32.SetTextColor(hdc, COLORS.menu_text)
        end
        gdi32.SetBkColor(hdc, COLORS.menu_bg)
        gdi32.TextOut(hdc, x, winY + 1, text)
        x = x + #text + 4
    end
end

function DrawWindowFrame()
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
    
    DrawMenuBar()
    DrawSubMenu()
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
end

function DrawStatusBar()
    if not showStatusBar then return end
    local statusY = winY + winH - 1
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.status_bg))
    gdi32.PatBlt(hdc, winX + 1, statusY - 1, winW - 2, 1, gdi32.PATCOPY)
    
    local statusText = string.format("Ln %d, Col %d  %s  %s  %s",
        cursorLine,
        cursorPos,
        isInsertMode and "INS" or "OVR",
        wordWrap and "WRAP" or "",
        fileName
    )
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.status_bg)
    gdi32.TextOut(hdc, winX + 2, statusY - 1, statusText)
end

function DrawContent()
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local visibleLines = clientH - 1
    local startLine = scrollOffset + 1
    
    for i = startLine, math.min(startLine + visibleLines, #lines) do
        local lineText = lines[i] or ""
        if wordWrap and #lineText > clientW - 2 then
            for j = 1, #lineText, clientW - 2 do
                local wrapped = lineText:sub(j, j + clientW - 3)
                local yPos = clientY + (i - startLine) + math.floor((j - 1) / (clientW - 2))
                if yPos < clientY + clientH then
                    gdi32.TextOut(hdc, clientX + 1, yPos, wrapped)
                end
            end
        else
            local yPos = clientY + (i - startLine)
            if yPos < clientY + clientH then
                gdi32.TextOut(hdc, clientX + 1, yPos, lineText:sub(1, clientW - 1))
            end
        end
    end
    
    if selectionStart and selectionEnd then
        local startLine, startPos = table.unpack(selectionStart)
        local endLine, endPos = table.unpack(selectionEnd)
        for i = startLine, endLine do
            local yPos = clientY + (i - scrollOffset - 1)
            if yPos >= clientY and yPos < clientY + clientH then
                local line = GetLineText(i)
                local s = (i == startLine) and startPos or 1
                local e = (i == endLine) and endPos - 1 or #line
                if s <= e then
                    local text = line:sub(s, e)
                    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.selection))
                    gdi32.PatBlt(hdc, clientX + s, yPos, #text, 1, gdi32.PATCOPY)
                    gdi32.SetTextColor(hdc, COLORS.selection_text)
                    gdi32.SetBkColor(hdc, COLORS.selection)
                    gdi32.TextOut(hdc, clientX + s, yPos, text)
                end
            end
        end
        gdi32.SetBkColor(hdc, COLORS.client_bg)
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

function DrawSubMenu()
    if not menuOpen then return end
    
    local subMenu = menuItems[selectedMenu][2]
    local subX = winX + 2
    local subY = winY + 2
    local subW = 25
    local subH = #subMenu + 1
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.menu_bg))
    gdi32.PatBlt(hdc, subX, subY, subW, subH, gdi32.PATCOPY)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
    gdi32.PatBlt(hdc, subX, subY, subW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, subX, subY, 1, subH, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, subX + subW - 1, subY, 1, subH, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, subX, subY + subH - 1, subW, 1, gdi32.PATCOPY)
    
    gdi32.SetTextColor(hdc, COLORS.menu_text)
    gdi32.SetBkColor(hdc, COLORS.menu_bg)
    
    for i, item in ipairs(subMenu) do
        local yPos = subY + i - 1
        if item[1] == "-" then
            gdi32.TextOut(hdc, subX + 2, yPos, "──────────────")
        else
            local text = item[1]
            if item[2] and item[2] ~= "" then
                text = text .. "  " .. item[2]
            end
            gdi32.TextOut(hdc, subX + 2, yPos, text)
        end
    end
end

function RedrawWindow()
    DrawWindowFrame()
    DrawContent()
    DrawStatusBar()
end

local function InsertChar(char)
    if not char or char == "" then return end
    local line = GetLineText(cursorLine)
    line = line:sub(1, cursorPos - 1) .. char .. line:sub(cursorPos)
    SetLineText(cursorLine, line)
    cursorPos = cursorPos + 1
    isDirty = true
    RedrawWindow()
end

local function DeleteChar()
    if cursorLine > #lines then return end
    local line = GetLineText(cursorLine)
    if cursorPos > #line then
        if cursorLine < #lines then
            SetLineText(cursorLine, line .. GetLineText(cursorLine + 1))
            table.remove(lines, cursorLine + 1)
            isDirty = true
            RedrawWindow()
        end
        return
    end
    line = line:sub(1, cursorPos - 1) .. line:sub(cursorPos + 1)
    SetLineText(cursorLine, line)
    isDirty = true
    RedrawWindow()
end

local function BackspaceChar()
    if cursorPos > 1 then
        local line = GetLineText(cursorLine)
        line = line:sub(1, cursorPos - 2) .. line:sub(cursorPos)
        SetLineText(cursorLine, line)
        cursorPos = cursorPos - 1
        isDirty = true
        RedrawWindow()
    elseif cursorLine > 1 then
        local prevLine = GetLineText(cursorLine - 1)
        SetLineText(cursorLine - 1, prevLine .. GetLineText(cursorLine))
        table.remove(lines, cursorLine)
        cursorLine = cursorLine - 1
        cursorPos = #prevLine + 1
        isDirty = true
        RedrawWindow()
    end
end

local function NewLine()
    local line = GetLineText(cursorLine)
    local newLine = line:sub(cursorPos)
    SetLineText(cursorLine, line:sub(1, cursorPos - 1))
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
    local line = GetLineText(newLine)
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
    ClearSelection()
    RedrawWindow()
end

local function HandleKey(char, code)
    local ok, err = pcall(function()
        if code ~= 0 then
            if code == 203 then -- LEFT
                if menuOpen then
                    menuOpen = false
                    RedrawWindow()
                    return true
                end
                NotepadExit()
                return false
            elseif code == 28 then -- ENTER
                SaveUndoState()
                NewLine()
                return true
            elseif code == 14 then -- BACKSPACE
                if selectionStart and selectionEnd then
                    DeleteText()
                else
                    SaveUndoState()
                    BackspaceChar()
                end
                return true
            elseif code == 211 then -- DELETE
                if selectionStart and selectionEnd then
                    DeleteText()
                else
                    SaveUndoState()
                    DeleteChar()
                end
                return true
            elseif code == 200 then -- UP
                MoveCursor(0, -1)
                return true
            elseif code == 208 then -- DOWN
                MoveCursor(0, 1)
                return true
            elseif code == 205 then -- RIGHT
                MoveCursor(1, 0)
                return true
            elseif code == 45 then -- INSERT
                isInsertMode = not isInsertMode
                RedrawWindow()
                return true
            elseif code == 60 then -- F3
                FindNext()
                return true
            end
        end
        
        if char >= 1 and char <= 26 then
            local ctrl = char
            if ctrl == 14 then -- Ctrl+N
                NewFile()
            elseif ctrl == 15 then -- Ctrl+O
                OpenFile()
            elseif ctrl == 19 then -- Ctrl+S
                SaveFile()
            elseif ctrl == 16 then -- Ctrl+P
                PrintFile()
            elseif ctrl == 6 then -- Ctrl+F
                FindText()
            elseif ctrl == 8 then -- Ctrl+H
                ReplaceText()
            elseif ctrl == 7 then -- Ctrl+G
                GoToLine()
            elseif ctrl == 1 then -- Ctrl+A
                SelectAll()
            elseif ctrl == 3 then -- Ctrl+C
                CopyText()
            elseif ctrl == 24 then -- Ctrl+X
                CutText()
            elseif ctrl == 22 then -- Ctrl+V
                PasteText()
            elseif ctrl == 26 then -- Ctrl+Z
                Undo()
            end
            return true
        end
        
        if char >= 32 and char <= 126 then
            if selectionStart and selectionEnd then
                DeleteText()
                ClearSelection()
            end
            SaveUndoState()
            if isInsertMode then
                InsertChar(string.char(char))
            else
                local line = GetLineText(cursorLine)
                if cursorPos <= #line then
                    line = line:sub(1, cursorPos - 1) .. string.char(char) .. line:sub(cursorPos + 1)
                else
                    line = line .. string.char(char)
                end
                SetLineText(cursorLine, line)
                cursorPos = cursorPos + 1
                isDirty = true
                RedrawWindow()
            end
            return true
        end
    end)

    if not ok then
        _G.DbgPrint("HandleKey ERROR: " .. tostring(err))
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
                    if SaveFilePrompt() then
                        break
                    end
                else
                    break
                end
            end
            
            if y == winY + 1 then
                local menuX = winX + 2
                for i, menu in ipairs(menuItems) do
                    local text = menu[1]
                    if x >= menuX and x < menuX + #text + 4 then
                        if menuOpen and selectedMenu == i then
                            menuOpen = false
                        else
                            menuOpen = true
                            selectedMenu = i
                            selectedSubMenu = 1
                        end
                        RedrawWindow()
                        break
                    end
                    menuX = menuX + #text + 4
                end
            end
            
            if menuOpen then
                local subMenu = menuItems[selectedMenu][2]
                local subX = winX + 2
                local subY = winY + 2
                local subW = 25
                local subH = #subMenu + 1
                
                if x >= subX and x < subX + subW and y >= subY and y < subY + subH then
                    local itemIndex = y - subY + 1
                    if itemIndex >= 1 and itemIndex <= #subMenu then
                        local item = subMenu[itemIndex]
                        if item[3] and type(item[3]) == "function" then
                            item[3]()
                            menuOpen = false
                            RedrawWindow()
                        end
                    end
                else
                    menuOpen = false
                    RedrawWindow()
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
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true