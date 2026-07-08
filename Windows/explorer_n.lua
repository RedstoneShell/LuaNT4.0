-- explorer_n.lua - File Manager for LuaNT 4.0
-- (C) RedstoneShell 2026
-- Windows NT 4.0 style "My Computer"

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")
local kernel32 = _G.LdrLoadDll("Windows/System32/kernel32.lua")

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
        _G.DbgPrint("MyComputer: " .. tostring(text))
    else
        _G.DbgPrint("MyComputer: " .. tostring(text))
    end
end

local print = printToConsole

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 70, 25
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local clientX = winX + 1
local clientY = winY + 3
local clientW = winW - 2
local clientH = winH - 5

local currentPath = "/"
local selectedIndex = 1
local scrollOffset = 0
local files = {}
local directories = {}
local pathHistory = {"/"}
local historyPos = 1
local showHidden = false
local viewMode = "list" -- "list" or "details"

local COLORS = {
    window_bg = 0xC0C0C0,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    selected = 0x000080,
    selected_text = 0xFFFFFF,
    folder = 0xAA0000,
    file = 0x00FF00,
    status_bg = 0x000080,
    status_text = 0xFFFFFF,
    address_bg = 0xFFFFFF
}

function GetFS()
    local fs = component.proxy(computer.getBootAddress())
    if not fs then
        return nil, "No boot filesystem"
    end
    return fs
end

function ListDirectory(path)
    local fs = GetFS()
    if not fs then
        files = {}
        directories = {}
        return
    end
    
    if not fs.exists(path) then
        print("Path not found: " .. path)
        files = {}
        directories = {}
        return
    end
    
    local items = fs.list(path) or {}
    files = {}
    directories = {}
    
    for _, item in ipairs(items) do
        if showHidden or not item:match("^%.") then
            local fullPath = path .. "/" .. item
            local isDir = false
            local subItems = fs.list(fullPath)
            if subItems and #subItems > 0 then
                isDir = true
            end
            if isDir then
                table.insert(directories, item)
            else
                table.insert(files, item)
            end
        end
    end
    
    table.sort(directories)
    table.sort(files)
    
    if selectedIndex > #directories + #files then
        selectedIndex = 1
    end
end

function GetFullPath(item)
    if currentPath == "/" then
        return "/" .. item
    end
    return currentPath .. "/" .. item
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
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.window_title)
    gdi32.TextOut(hdc, winX + 2, winY + 1, "My Computer - " .. currentPath)
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.address_bg))
    gdi32.PatBlt(hdc, clientX, winY + 2, clientW, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.address_bg)
    gdi32.TextOut(hdc, clientX + 1, winY + 2, currentPath)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local allItems = {}
    for _, d in ipairs(directories) do
        table.insert(allItems, {name = d, isDir = true})
    end
    for _, f in ipairs(files) do
        table.insert(allItems, {name = f, isDir = false})
    end
    
    local maxLines = clientH - 2
    for i = 1, math.min(#allItems, maxLines) do
        local idx = i + scrollOffset
        local item = allItems[idx]
        if item then
            local yPos = clientY + i - 1
            local isSelected = (idx == selectedIndex)
            
            if isSelected then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.selected))
                gdi32.PatBlt(hdc, clientX, yPos, clientW, 1, gdi32.PATCOPY)
                gdi32.SetTextColor(hdc, COLORS.selected_text)
            else
                gdi32.SetTextColor(hdc, item.isDir and COLORS.folder or COLORS.file)
            end
            
            local prefix = item.isDir and "[DIR] " or "[FILE]"
            local displayName = item.name
            if #displayName > clientW - 10 then
                displayName = displayName:sub(1, clientW - 13) .. "..."
            end
            gdi32.TextOut(hdc, clientX + 2, yPos, prefix .. displayName)
        end
    end
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.status_bg))
    gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.status_bg)
    gdi32.TextOut(hdc, winX + 2, winY + winH - 2, 
        string.format("%d items (%d dirs, %d files)", 
        #directories + #files, #directories, #files))
end

function RedrawWindow()
    local ok, err = pcall(DrawWindowFrame)
if not ok then
    DbgPrint("DrawWindowFrame ERROR: " .. tostring(err))
end
end

function HandleKey(char, code)
    local allItems = {}
    for _, d in ipairs(directories) do table.insert(allItems, d) end
    for _, f in ipairs(files) do table.insert(allItems, f) end
    
    if code == 211 then -- DEL
        return false
    elseif code == 28 then -- ENTER
        if selectedIndex >= 1 and selectedIndex <= #allItems then
            OpenItem(allItems[selectedIndex])
        end
    elseif code == 14 then -- BACKSPACE
        if currentPath ~= "/" then
            local newPath = currentPath:match("^(.*)/[^/]+$") or "/"
            if newPath == "" then newPath = "/" end
            currentPath = newPath
            table.insert(pathHistory, currentPath)
            historyPos = #pathHistory
            selectedIndex = 1
            scrollOffset = 0
            ListDirectory(currentPath)
            RedrawWindow()
        end
    elseif code == 200 then -- UP
        if selectedIndex > 1 then
            selectedIndex = selectedIndex - 1
            if selectedIndex <= scrollOffset then
                scrollOffset = selectedIndex - 1
            end
            RedrawWindow()
        end
    elseif code == 208 then -- DOWN
        if selectedIndex < #allItems then
            selectedIndex = selectedIndex + 1
            if selectedIndex > scrollOffset + clientH - 2 then
                scrollOffset = selectedIndex - clientH + 2
            end
            RedrawWindow()
        end
    elseif code == 203 then -- LEFT
        if historyPos > 1 then
            historyPos = historyPos - 1
            currentPath = pathHistory[historyPos]
            selectedIndex = 1
            scrollOffset = 0
            ListDirectory(currentPath)
            RedrawWindow()
        end
    elseif code == 205 then -- RIGHT
        if historyPos < #pathHistory then
            historyPos = historyPos + 1
            currentPath = pathHistory[historyPos]
            selectedIndex = 1
            scrollOffset = 0
            ListDirectory(currentPath)
            RedrawWindow()
        end
    elseif char >= 32 and char <= 126 then
        local charLower = string.char(char):lower()
        for i = selectedIndex + 1, #allItems do
            if allItems[i]:lower():sub(1, 1) == charLower then
                selectedIndex = i
                if selectedIndex > scrollOffset + clientH - 2 then
                    scrollOffset = selectedIndex - clientH + 2
                end
                RedrawWindow()
                return true
            end
        end
        for i = 1, selectedIndex do
            if allItems[i]:lower():sub(1, 1) == charLower then
                selectedIndex = i
                if selectedIndex <= scrollOffset then
                    scrollOffset = selectedIndex - 1
                end
                RedrawWindow()
                return true
            end
        end
    end
    return true
end

function OpenItem(item)
    _G.DbgPrint("OpenItem: "..tostring(item))

    local fullPath = GetFullPath(item)
    _G.DbgPrint("FullPath: "..fullPath)

    local fs = GetFS()
    if not fs then
        _G.DbgPrint("No FS")
        return
    end

    _G.DbgPrint("Calling fs.list")

    local subItems = fs.list(fullPath)

    _G.DbgPrint("fs.list returned "..tostring(subItems))
    if subItems and #subItems > 0 then
        isDir = true
    end
    
    if isDir then
        currentPath = fullPath
        table.insert(pathHistory, currentPath)
        historyPos = #pathHistory
        selectedIndex = 1
        scrollOffset = 0
        ListDirectory(currentPath)
        RedrawWindow()
    else
        if item:match("%.txt$") or item:match("%.lua$") then
            local handle = fs.open(fullPath, "r")
            if handle then
                local content = ""
                while true do
                    local chunk = fs.read(handle, 4096)
                    if not chunk then break end
                    content = content .. chunk
                end
                fs.close(handle)
                print("File content (" .. item .. "):")
                print(content:sub(1, 500))
            end
        else
            print("Cannot open: " .. item)
        end
    end
end

function MyComputerMain()
    _G.DbgPrint("MyComputer: Starting...")
    
    ListDirectory(currentPath)
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
                break
            end
        end
    end
    
    _G.DbgPrint("MyComputer: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return false
end

local exitCode = MyComputerMain()

if not exitCode then
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true