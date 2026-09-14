local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
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
    end
    _G.DbgPrint("MyComputer: " .. tostring(text))
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

local COLORS = {
    window_bg    = 0xC0C0C0,
    window_title = 0x000080,
    client_bg    = 0xFFFFFF,
    text         = 0x000000,
    selected     = 0x000080,
    selected_text= 0xFFFFFF,
    folder       = 0xAA0000,
    file         = 0x008000,
    status_bg    = 0x000080,
    status_text  = 0xFFFFFF,
    address_bg   = 0xFFFFFF,
    close        = 0xFF0000,
    menu_bg      = 0xC0C0C0,
    menu_sel     = 0x000080,
    menu_sel_txt = 0xFFFFFF,
    menu_border  = 0x000000,
    edit_bg      = 0xFFFFFF,
    edit_text    = 0x000000
}

local currentDrive = "C:"
local currentPath  = "My Computer"
local selectedIndex = 1
local scrollOffset  = 0
local files = {}
local directories = {}
local pathHistory = { "My Computer" }
local historyPos = 1
local showHidden = false

local menuOpen = false
local menuIndex = 1
local menuItems = { "New Folder", "New File", "Rename", "Delete", "Refresh", "Cancel" }

local editMode = false
local editBuffer = ""
local editAction = nil
local editTarget = nil

local function NormalizePath(p)
    if not p then return "" end
    p = p:gsub("\\", "/")
    p = p:gsub("/+", "/")
    return p
end

local function SplitDrivePath(path)
    path = NormalizePath(path)
    local drive, rest = path:match("^([A-Za-z]:)/?(.*)$")
    if drive then
        return drive:upper(), rest or ""
    end
    return currentDrive, path
end

local function GetFS(driveLetter)
    driveLetter = (driveLetter or currentDrive or "C:"):upper()
    if not driveLetter:match(":$") then
        driveLetter = driveLetter .. ":"
    end

    if driveLetter == "C:" then
        local fs = component.proxy(computer.getBootAddress())
        if fs then return fs, "C:" end
    end

    local deviceName = _G.Drives and _G.Drives[driveLetter]
    if deviceName then
        local fs = _G.Mm.NonPagedPool[deviceName]
        if fs then return fs, driveLetter end
    end

    local fs = component.proxy(computer.getBootAddress())
    return fs, "C:"
end

local function PathIsDirectory(fs, filePath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end

    if fs.isDirectory then
        local ok, res = pcall(fs.isDirectory, filePath)
        if ok and res ~= nil then
            return res and true or false
        end
    end

    if fs.list then
        local ok, items = pcall(fs.list, filePath)
        if ok and items then return true end
    end

    if fs.open then
        local ok, handle = pcall(fs.open, filePath, "r")
        if ok and handle then
            pcall(fs.close, handle)
            return false
        end
        return true
    end
    return false
end

local function ListItems(driveLetter, filePath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end
    if #filePath > 1 and filePath:sub(-1) == "/" then
        filePath = filePath:sub(1, -2)
    end

    local full = driveLetter .. filePath
    local items = ntdll.NtListDirectoryEx(full)

    if not items then
        items = ntdll.NtListDirectoryEx(filePath)
    end

    if not items then
        local fs = GetFS(driveLetter)
        if fs and fs.list then
            local ok, res = pcall(fs.list, filePath)
            if ok then items = res end
        end
    end

    if not items then return nil end

    if type(items) == "function" or (type(items) == "table" and items.__iterator) then
        local t = {}
        for name in items do
            t[#t + 1] = name
        end
        return t
    end

    return items
end

local function Exists(driveLetter, filePath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end

    local full = driveLetter .. filePath
    local r1 = ntdll.NtFileExistsEx(full)
    if r1 then return true end

    local fs = GetFS(driveLetter)
    if fs and fs.exists then
        local ok, res = pcall(fs.exists, filePath)
        return ok and res or false
    end
    return false
end

local function ListDirectory(path)
    if path == "My Computer" then
        currentPath = "My Computer"
        files = {}
        directories = {}
        if _G.Drives then
            for letter, devName in pairs(_G.Drives) do
                if letter:match("^[A-Z]:$") then
                    local dev = _G.Mm.NonPagedPool[devName]
                    if dev and dev.getLabel then
                        local ok, label = pcall(dev.getLabel)
                        if ok and label ~= "tmpfs" then
                            table.insert(directories,
                                letter .. " (" .. (label or "Local Disk") .. ")")
                        end
                    end
                end
            end
        end
        table.sort(directories)
        if selectedIndex > #directories then selectedIndex = 1 end
        return
    end

    local driveLetter, filePath = SplitDrivePath(path)
    currentDrive = driveLetter

    local items = ListItems(driveLetter, filePath)
    if not items then
        print("Path not found: " .. tostring(filePath) .. " on " .. driveLetter)
        files = {}
        directories = {}
        return
    end

    local fs = GetFS(driveLetter)
    files = {}
    directories = {}

    for _, item in ipairs(items) do
        if showHidden or not item:match("^%.") then
            local sub = (filePath == "" or filePath == "/" or filePath == ".")
                and item or (filePath .. "/" .. item)
            if sub:sub(1, 1) ~= "/" then sub = "/" .. sub end
            if PathIsDirectory(fs, sub) then
                table.insert(directories, item)
            else
                table.insert(files, item)
            end
        end
    end

    table.sort(directories)
    table.sort(files)

    if selectedIndex > #directories + #files then selectedIndex = 1 end
    if selectedIndex < 1 then selectedIndex = 1 end
end

local function GetFullPath(item)
    if currentPath == "My Computer" then
        return item
    end
    local base = NormalizePath(currentPath)
    if base:sub(-1) == "/" then
        return base .. item
    end
    return base .. "/" .. item
end

local function GetCurrentDriveLetter()
    return currentDrive
end

local function ChangeDrive(driveLetter)
    driveLetter = driveLetter:upper()
    if not driveLetter:match("^[A-Z]:$") then
        driveLetter = driveLetter .. ":"
    end

    if _G.Drives and _G.Drives[driveLetter] then
        currentDrive = driveLetter
        currentPath = driveLetter .. "\\"
        table.insert(pathHistory, currentPath)
        historyPos = #pathHistory
        selectedIndex = 1
        scrollOffset = 0
        ListDirectory(currentPath)
        RedrawWindow()
        return true
    end

    print("Drive " .. driveLetter .. " not found")
    return false
end

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
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.window_title)

    local title
    if currentPath == "My Computer" then
        title = "My Computer"
    else
        title = currentDrive .. " - " .. currentPath
    end
    gdi32.TextOut(hdc, winX + 2, winY + 1, title)
    gdi32.SetTextColor(hdc, COLORS.close)
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
        table.insert(allItems, { name = d, isDir = true })
    end
    for _, f in ipairs(files) do
        table.insert(allItems, { name = f, isDir = false })
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

    if editMode then
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.edit_bg))
        gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, COLORS.edit_text)
        gdi32.SetBkColor(hdc, COLORS.edit_bg)
        local label
        if editAction == "rename" then
            label = "Rename: "
        elseif editAction == "newfolder" then
            label = "New folder name: "
        elseif editAction == "newfile" then
            label = "New file name: "
        else
            label = "Name: "
        end
        gdi32.TextOut(hdc, winX + 2, winY + winH - 2, label .. editBuffer .. "_")
    else
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.status_bg))
        gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, COLORS.status_text)
        gdi32.SetBkColor(hdc, COLORS.status_bg)
        gdi32.TextOut(hdc, winX + 2, winY + winH - 2,
            string.format("%d items (%d dirs, %d files)",
                #directories + #files, #directories, #files))
    end

    if menuOpen then
        local mw = 18
        local mh = #menuItems + 2
        local mx = clientX + 2
        local my = clientY + 1
        if my + mh > winY + winH - 3 then
            my = winY + winH - 3 - mh
        end

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.menu_border))
        gdi32.PatBlt(hdc, mx - 1, my - 1, mw + 2, mh + 2, gdi32.PATCOPY)
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.menu_bg))
        gdi32.PatBlt(hdc, mx, my, mw, mh, gdi32.PATCOPY)

        gdi32.SetBkColor(hdc, COLORS.menu_bg)
        for i, label in ipairs(menuItems) do
            local y = my + i - 1
            if i == menuIndex then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.menu_sel))
                gdi32.PatBlt(hdc, mx, y, mw, 1, gdi32.PATCOPY)
                gdi32.SetTextColor(hdc, COLORS.menu_sel_txt)
                gdi32.SetBkColor(hdc, COLORS.menu_sel)
            else
                gdi32.SetTextColor(hdc, COLORS.text)
                gdi32.SetBkColor(hdc, COLORS.menu_bg)
            end
            gdi32.TextOut(hdc, mx + 1, y, label)
        end
    end
end

function RedrawWindow()
    local ok, err = pcall(DrawWindowFrame)
    if not ok then
        _G.DbgPrint("DrawWindowFrame ERROR: " .. tostring(err))
    end
end

local function NavigateTo(newPath)
    currentPath = newPath
    table.insert(pathHistory, currentPath)
    historyPos = #pathHistory
    selectedIndex = 1
    scrollOffset = 0
    ListDirectory(currentPath)
    RedrawWindow()
end

local function GoUp()
    if currentPath == "My Computer" then return end

    local isRoot = currentPath:match("^[A-Za-z]:[\\/]?$")
    if isRoot then
        NavigateTo("My Computer")
        return
    end

    local p = NormalizePath(currentPath)
    local newPath = p:match("^(.*)/[^/]+$") or "/"
    if newPath:match("^[A-Za-z]:$") then
        newPath = newPath .. "/"
    end
    if newPath == "" then
        newPath = currentDrive .. "/"
    end
    NavigateTo(newPath)
end

local function RefreshCurrent()
    ListDirectory(currentPath)
    RedrawWindow()
end

local function StartRename()
    local allItems = {}
    for _, d in ipairs(directories) do table.insert(allItems, d) end
    for _, f in ipairs(files) do table.insert(allItems, f) end

    local name = allItems[selectedIndex]
    if not name then return end

    editMode = true
    editAction = "rename"
    editTarget = name
    editBuffer = name
    RedrawWindow()
end

local function StartNewFolder()
    editMode = true
    editAction = "newfolder"
    editTarget = nil
    editBuffer = "New Folder"
    RedrawWindow()
end

local function StartNewFile()
    editMode = true
    editAction = "newfile"
    editTarget = nil
    editBuffer = "New File.txt"
    RedrawWindow()
end

local function CancelEdit()
    editMode = false
    editAction = nil
    editTarget = nil
    editBuffer = ""
    RedrawWindow()
end

local function DoRename(oldName, newName)
    if not oldName or not newName or newName == "" then return false end
    if oldName == newName then return true end

    local driveLetter, filePath = SplitDrivePath(currentPath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end
    if #filePath > 1 and filePath:sub(-1) == "/" then
        filePath = filePath:sub(1, -2)
    end

    local fromPath = (filePath == "/" or filePath == "")
        and ("/" .. oldName)
        or (filePath .. "/" .. oldName)
    local toPath = (filePath == "/" or filePath == "")
        and ("/" .. newName)
        or (filePath .. "/" .. newName)

    local fs = GetFS(driveLetter)
    if not fs or not fs.rename then
        print("Rename not supported")
        return false
    end

    local ok, res = pcall(fs.rename, fromPath, toPath)
    if not ok or not res then
        print("Rename failed: " .. tostring(fromPath) .. " -> " .. tostring(toPath))
        return false
    end
    return true
end

local function DoCreateFolder(name)
    if not name or name == "" then return false end

    local driveLetter, filePath = SplitDrivePath(currentPath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end
    if #filePath > 1 and filePath:sub(-1) == "/" then
        filePath = filePath:sub(1, -2)
    end

    local target = (filePath == "/" or filePath == "")
        and ("/" .. name)
        or (filePath .. "/" .. name)

    local fs = GetFS(driveLetter)
    if not fs or not fs.makeDirectory then
        print("makeDirectory not supported")
        return false
    end

    local ok, res = pcall(fs.makeDirectory, target)
    if not ok or not res then
        print("Create folder failed: " .. target)
        return false
    end
    return true
end

local function DoCreateFile(name)
    if not name or name == "" then return false end

    local driveLetter, filePath = SplitDrivePath(currentPath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end
    if #filePath > 1 and filePath:sub(-1) == "/" then
        filePath = filePath:sub(1, -2)
    end

    local target = (filePath == "/" or filePath == "")
        and ("/" .. name)
        or (filePath .. "/" .. name)

    local fs = GetFS(driveLetter)
    if not fs or not fs.open then
        print("open not supported")
        return false
    end

    local ok, handle = pcall(fs.open, target, "w")
    if not ok or not handle then
        print("Create file failed: " .. target)
        return false
    end
    pcall(fs.close, handle)
    return true
end

local function DoDelete()
    local allItems = {}
    for _, d in ipairs(directories) do table.insert(allItems, d) end
    for _, f in ipairs(files) do table.insert(allItems, f) end

    local name = allItems[selectedIndex]
    if not name then return end

    local driveLetter, filePath = SplitDrivePath(currentPath)
    filePath = NormalizePath(filePath)
    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end
    if #filePath > 1 and filePath:sub(-1) == "/" then
        filePath = filePath:sub(1, -2)
    end

    local target = (filePath == "/" or filePath == "")
        and ("/" .. name)
        or (filePath .. "/" .. name)

    local fs = GetFS(driveLetter)
    if not fs or not fs.remove then
        print("remove not supported")
        return
    end

    local ok, res = pcall(fs.remove, target)
    if not ok or not res then
        print("Delete failed: " .. target)
        return
    end

    RefreshCurrent()
end

local function FinishEdit(commit)
    if not editMode then return end

    local action = editAction
    local target = editTarget
    local value = editBuffer

    editMode = false
    editAction = nil
    editTarget = nil
    editBuffer = ""

    if not commit then
        RedrawWindow()
        return
    end

    if value == "" then
        RedrawWindow()
        return
    end

    if action == "rename" and target then
        DoRename(target, value)
    elseif action == "newfolder" then
        DoCreateFolder(value)
    elseif action == "newfile" then
        DoCreateFile(value)
    end

    RefreshCurrent()
end

local function OpenMenu()
    menuOpen = true
    menuIndex = 1
    RedrawWindow()
end

local function CloseMenu()
    menuOpen = false
    RedrawWindow()
end

local function ActivateMenuItem()
    local action = menuItems[menuIndex]
    menuOpen = false

    if action == "New Folder" then
        StartNewFolder()
    elseif action == "New File" then
        StartNewFile()
    elseif action == "Rename" then
        StartRename()
    elseif action == "Delete" then
        DoDelete()
    elseif action == "Refresh" then
        RefreshCurrent()
    else
        RedrawWindow()
    end
end

local function OpenItem(item)
    if currentPath == "My Computer" then
        local driveLetter = item:match("^([A-Za-z]:)")
        if driveLetter then
            ChangeDrive(driveLetter)
        end
        return
    end

    local fullPath = GetFullPath(item)
    local driveLetter, filePath = SplitDrivePath(fullPath)

    local fs = GetFS(driveLetter)
    if not fs then
        print("No filesystem for " .. tostring(driveLetter))
        return
    end

    if not Exists(driveLetter, filePath) then
        print("Not found: " .. fullPath)
        return
    end

    if PathIsDirectory(fs, filePath) then
        local nav = driveLetter .. "/" .. filePath
        nav = nav:gsub("/+", "/")
        if #nav > 2 and nav:sub(-1) == "/" then
            nav = nav:sub(1, -2)
        end
        NavigateTo(nav)
        return
    end

    local lower = item:lower()
    if lower:match("%.txt$") or lower:match("%.lua$") or
       lower:match("%.ini$") or lower:match("%.cfg$") then
        local notepadPath = "Windows/notepad.lua"
        if Exists("C:", notepadPath) then
            _G.LastSpawnedArgs = { fullPath }
            _G.PsCreateSystemThread(notepadPath, "notepad.exe", 8,
                { name = "Administrator", group = "ADMINS" })
        else
            print("Notepad not found: " .. notepadPath)
        end
    else
        print("Cannot open: " .. item)
    end
end

local function HandleEditKey(char, code)
    if code == 28 then
        FinishEdit(true)
        return true
    elseif code == 1 then
        FinishEdit(false)
        return true
    elseif code == 14 then
        if #editBuffer > 0 then
            editBuffer = editBuffer:sub(1, -2)
            RedrawWindow()
        end
        return true
    elseif char and char >= 32 and char <= 126 then
        editBuffer = editBuffer .. string.char(char)
        RedrawWindow()
        return true
    end
    return true
end

local function HandleMenuKey(code)
    if code == 200 then
        menuIndex = menuIndex - 1
        if menuIndex < 1 then menuIndex = #menuItems end
        RedrawWindow()
        return true
    elseif code == 208 then
        menuIndex = menuIndex + 1
        if menuIndex > #menuItems then menuIndex = 1 end
        RedrawWindow()
        return true
    elseif code == 28 then
        ActivateMenuItem()
        return true
    elseif code == 1 then
        CloseMenu()
        return true
    end
    return true
end

local function HandleKey(char, code)
    if editMode then
        return HandleEditKey(char, code)
    end

    if menuOpen then
        return HandleMenuKey(code)
    end

    local allItems = {}
    for _, d in ipairs(directories) do table.insert(allItems, d) end
    for _, f in ipairs(files) do table.insert(allItems, f) end

    if code == 211 then
        return false
    elseif code == 15 then
        OpenMenu()
    elseif code == 28 then
        if selectedIndex >= 1 and selectedIndex <= #allItems then
            OpenItem(allItems[selectedIndex])
        end
    elseif code == 14 then
        GoUp()
    elseif code == 200 then
        if selectedIndex > 1 then
            selectedIndex = selectedIndex - 1
            if selectedIndex <= scrollOffset then
                scrollOffset = selectedIndex - 1
            end
            RedrawWindow()
        end
    elseif code == 208 then
        if selectedIndex < #allItems then
            selectedIndex = selectedIndex + 1
            if selectedIndex > scrollOffset + clientH - 2 then
                scrollOffset = selectedIndex - clientH + 2
            end
            RedrawWindow()
        end
    elseif code == 203 then
        if historyPos > 1 then
            historyPos = historyPos - 1
            currentPath = pathHistory[historyPos]
            selectedIndex = 1
            scrollOffset = 0
            ListDirectory(currentPath)
            RedrawWindow()
        end
    elseif code == 205 then
        if historyPos < #pathHistory then
            historyPos = historyPos + 1
            currentPath = pathHistory[historyPos]
            selectedIndex = 1
            scrollOffset = 0
            ListDirectory(currentPath)
            RedrawWindow()
        end
    elseif char and char >= 32 and char <= 126 then
        local charLower = string.char(char):lower()
        local function trySelect(i)
            if allItems[i]:lower():sub(1, 1) == charLower then
                selectedIndex = i
                if selectedIndex > scrollOffset + clientH - 2 then
                    scrollOffset = selectedIndex - clientH + 2
                elseif selectedIndex <= scrollOffset then
                    scrollOffset = selectedIndex - 1
                end
                RedrawWindow()
                return true
            end
            return false
        end
        for i = selectedIndex + 1, #allItems do
            if trySelect(i) then return true end
        end
        for i = 1, selectedIndex do
            if trySelect(i) then return true end
        end
    end

    return true
end

function MyComputerMain()
    _G.DbgPrint("MyComputer: Starting...")

    currentPath = "My Computer"
    files = {}
    directories = {}
    ListDirectory(currentPath)
    RedrawWindow()

    while true do
        local signal = { computer.pullSignal(0.1) }

        if signal[1] == "key_down" then
            local char = signal[3]
            local code = signal[4]
            if code == 15 then
                HandleKey(char, code)
            elseif code == 15 and char == 9 then
                HandleKey(char, code)
            elseif not HandleKey(char, code) then
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