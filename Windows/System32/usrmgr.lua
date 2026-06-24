-- usermgr.lua - User Manager for LuaNT 4.0
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
        _G.DbgPrint("UserMgr: " .. tostring(text))
    end
end
local print = printToConsole

local function ParseArguments(args)
    local showHelp = false
    
    for _, arg in ipairs(args) do
        if arg == "/?" or arg == "-h" or arg == "--help" then
            showHelp = true
        end
    end
    
    if showHelp then
        print("User Manager - Account Management for LuaNT 4.0")
        print("")
        print("Usage: usermgr")
        print("")
        print("Commands in User Manager:")
        print("  ENTER        - Edit selected user")
        print("  INSERT       - Create new user")
        print("  DELETE       - Delete selected user")
        print("  ESC          - Close User Manager")
        print("")
        print("Examples:")
        print("  usermgr")
        return true
    end
    
    return false
end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 55, 20
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)
local clientX = winX + 1
local clientY = winY + 2
local clientW = winW - 2
local clientH = winH - 3

local users = {}
local selectedIndex = 1
local scrollOffset = 0
local viewMode = "list" -- "list", "edit", "create"
local editUser = nil
local editFields = {}
local editFieldIndex = 1
local editInput = ""
local editMode = false

local COLORS = {
    window_bg = 0xCCCCCC,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    selected = 0x000080,
    selected_text = 0xFFFFFF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF,
    good = 0x008000,
    warning = 0xFF8000,
    error = 0xFF0000,
    admin = 0x0000AA,
    guest = 0x666666
}

local function LoadUsers()
    local userList = {}
    local samHive = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SAM"]
    
    if not samHive then
        print("User Manager: SAM hive not loaded!")
        return userList
    end
    
    for path, keys in pairs(samHive) do
        if path:match("^SAM\\Users\\.+$") then
            local userName = path:match("^SAM\\Users\\(.+)$")
            if userName then
                local user = {
                    name = userName,
                    password = keys.Password or "",
                    group = keys.Group or "Users",
                    homeDir = keys.HomeDir or "C:\\Users\\" .. userName,
                    rid = keys.RID or "0",
                    path = path
                }
                table.insert(userList, user)
            end
        end
    end
    
    table.sort(userList, function(a, b)
        return a.name < b.name
    end)
    
    return userList
end

local function SaveUser(user)
    local samHive = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SAM"]
    if not samHive then return false end
    
    local path = "SAM\\Users\\" .. user.name
    
    if not samHive[path] then
        samHive[path] = {}
    end
    
    samHive[path].Password = user.password or ""
    samHive[path].Group = user.group or "Users"
    samHive[path].HomeDir = user.homeDir or "C:\\Users\\" .. user.name
    samHive[path].RID = user.rid or "0"
    
    regedit.Flush()
    return true
end

local function DeleteUser(userName)
    local samHive = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SAM"]
    if not samHive then return false end
    
    local path = "SAM\\Users\\" .. userName
    if samHive[path] then
        samHive[path] = nil
        regedit.Flush()
        return true
    end
    return false
end

local function GetNextRID()
    local maxRID = 500
    for _, user in ipairs(users) do
        local rid = tonumber(user.rid) or 0
        if rid > maxRID then maxRID = rid end
    end
    return maxRID + 1
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
    
    local title = "User Manager"
    if viewMode == "edit" then
        title = "Edit User - " .. editUser.name
    elseif viewMode == "create" then
        title = "Create New User"
    end
    gdi32.TextOut(hdc, winX + 2, winY + 1, title)
    
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
end

local function DrawUserList()
    local visibleItems = clientH - 2
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local header = "Username            Group          RID"
    gdi32.TextOut(hdc, clientX + 1, clientY, header)
    gdi32.TextOut(hdc, clientX + 1, clientY + 1, string.rep("─", clientW - 1))
    
    for i = scrollOffset + 1, math.min(scrollOffset + visibleItems, #users) do
        local user = users[i]
        local yPos = clientY + 2 + (i - scrollOffset - 1)
        local isSelected = (i == selectedIndex)
        
        if isSelected then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.selected))
            gdi32.PatBlt(hdc, clientX, yPos, clientW, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, COLORS.selected_text)
        else
            if user.group == "Administrators" then
                gdi32.SetTextColor(hdc, COLORS.admin)
            elseif user.group == "Guests" then
                gdi32.SetTextColor(hdc, COLORS.guest)
            else
                gdi32.SetTextColor(hdc, COLORS.text)
            end
        end
        gdi32.SetBkColor(hdc, isSelected and COLORS.selected or COLORS.client_bg)
        
        local nameStr = (user.name or "Unknown"):sub(1, 20)
        local groupStr = (user.group or "Users"):sub(1, 14)
        local ridStr = (user.rid or "0"):sub(1, 6)
        
        gdi32.TextOut(hdc, clientX + 3, yPos, 
            string.format("%-20s %-14s %s", nameStr, groupStr, ridStr))
    end
    
    gdi32.SetTextColor(hdc, 0x888888)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    gdi32.TextOut(hdc, clientX + 2, clientY + clientH - 1, 
        "↑↓ Select  ENTER: Edit  INS: New  DEL: Delete  <: Exit")
end

local function DrawEditForm()
    if not editUser then return end
    
    local fields = {
        {label = "Username", key = "name", value = editUser.name},
        {label = "Password", key = "password", value = editUser.password},
        {label = "Group", key = "group", value = editUser.group},
        {label = "HomeDir", key = "homeDir", value = editUser.homeDir}
    }
    
    local line = 0
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    gdi32.TextOut(hdc, clientX + 2, clientY + line, "Edit User Account")
    line = line + 2
    
    for i, field in ipairs(fields) do
        local prefix = "  " .. field.label .. ": "
        local value = field.value or ""
        
        if i == editFieldIndex then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFAA))
            gdi32.PatBlt(hdc, clientX + 2, clientY + line, clientW - 4, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, COLORS.text)
            gdi32.SetBkColor(hdc, 0xFFFFAA)
        else
            gdi32.SetTextColor(hdc, COLORS.text)
            gdi32.SetBkColor(hdc, COLORS.client_bg)
        end
        
        local displayValue = value
        if field.key == "password" and value ~= "" then
            displayValue = string.rep("*", #value)
        end
        
        gdi32.TextOut(hdc, clientX + 2, clientY + line, prefix .. displayValue)
        line = line + 1
    end
    
    line = line + 1
    gdi32.SetTextColor(hdc, 0x888888)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    gdi32.TextOut(hdc, clientX + 2, clientY + line, 
        "↑↓ Select field  ENTER: Edit value  <: Save and exit")
end

local function DrawCreateForm()
    local fields = {
        {label = "Username", key = "name", value = ""},
        {label = "Password", key = "password", value = ""},
        {label = "Group", key = "group", value = "Users"},
        {label = "HomeDir", key = "homeDir", value = ""}
    }
    
    if #editFields == 0 then
        editFields = fields
        editFieldIndex = 1
        editInput = ""
        editMode = false
    end
    
    local line = 0
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    gdi32.TextOut(hdc, clientX + 2, clientY + line, "Create New User Account")
    line = line + 2
    
    for i, field in ipairs(editFields) do
        local prefix = "  " .. field.label .. ": "
        local value = field.value or ""
        
        if i == editFieldIndex and editMode then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFAA))
            gdi32.PatBlt(hdc, clientX + 2, clientY + line, clientW - 4, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, COLORS.text)
            gdi32.SetBkColor(hdc, 0xFFFFAA)
            value = value .. "_"
        elseif i == editFieldIndex then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xEEEEFF))
            gdi32.PatBlt(hdc, clientX + 2, clientY + line, clientW - 4, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, COLORS.text)
            gdi32.SetBkColor(hdc, 0xEEEEFF)
        else
            gdi32.SetTextColor(hdc, COLORS.text)
            gdi32.SetBkColor(hdc, COLORS.client_bg)
        end
        
        local displayValue = value
        if field.key == "password" and value ~= "" and not editMode then
            displayValue = string.rep("*", #value)
        end
        
        gdi32.TextOut(hdc, clientX + 2, clientY + line, prefix .. displayValue)
        line = line + 1
    end
    
    line = line + 1
    gdi32.SetTextColor(hdc, 0x888888)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    gdi32.TextOut(hdc, clientX + 2, clientY + line, 
        "↑↓ Select  ENTER: Edit  <: Cancel")
end

local function RedrawWindow()
    DrawWindowFrame()
    
    if viewMode == "list" then
        DrawUserList()
    elseif viewMode == "edit" then
        DrawEditForm()
    elseif viewMode == "create" then
        DrawCreateForm()
    end
end

local function HandleKey(char, code)
    if viewMode == "list" then
        if code == 200 then -- UP
            if selectedIndex > 1 then
                selectedIndex = selectedIndex - 1
                if selectedIndex <= scrollOffset then
                    scrollOffset = selectedIndex - 1
                end
                RedrawWindow()
            end
        elseif code == 208 then -- DOWN
            if selectedIndex < #users then
                selectedIndex = selectedIndex + 1
                if selectedIndex > scrollOffset + clientH - 3 then
                    scrollOffset = selectedIndex - clientH + 3
                end
                RedrawWindow()
            end
        elseif code == 28 then -- ENTER
            viewMode = "edit"
            editUser = users[selectedIndex]
            editFieldIndex = 1
            editMode = false
            RedrawWindow()
        elseif code == 210 then -- INSERT
            viewMode = "create"
            editFields = {}
            editFieldIndex = 1
            editMode = false
            RedrawWindow()
        elseif code == 211 then -- DELETE
            local user = users[selectedIndex]
            if user then
                if DeleteUser(user.name) then
                    print("User deleted: " .. user.name)
                    users = LoadUsers()
                    if selectedIndex > #users then selectedIndex = #users end
                    RedrawWindow()
                else
                    print("Error deleting user: " .. user.name)
                end
            end
        elseif code == 203 then -- <
            return false
        end
        
    elseif viewMode == "edit" then
        if code == 200 or code == 208 then -- UP/DOWN
            if code == 200 and editFieldIndex > 1 then
                editFieldIndex = editFieldIndex - 1
            elseif code == 208 and editFieldIndex < 4 then
                editFieldIndex = editFieldIndex + 1
            end
            editMode = false
            RedrawWindow()
        elseif code == 28 then -- ENTER
            editMode = true
            local fields = {
                {label = "Username", key = "name"},
                {label = "Password", key = "password"},
                {label = "Group", key = "group"},
                {label = "HomeDir", key = "homeDir"}
            }
            local field = fields[editFieldIndex]
            if field then
                editInput = editUser[field.key] or ""
                editMode = true
                RedrawWindow()
            end
        elseif code == 203 then -- <
            viewMode = "list"
            users = LoadUsers()
            RedrawWindow()
        end
        
    elseif viewMode == "create" then
        if code == 200 or code == 208 then -- UP/DOWN
            if code == 200 and editFieldIndex > 1 then
                editFieldIndex = editFieldIndex - 1
            elseif code == 208 and editFieldIndex < #editFields then
                editFieldIndex = editFieldIndex + 1
            end
            editMode = false
            RedrawWindow()
        elseif code == 28 then -- ENTER
            if editMode then
                local field = editFields[editFieldIndex]
                if field then
                    field.value = editInput
                    editMode = false
                end
                local allFilled = true
                for _, f in ipairs(editFields) do
                    if f.key == "name" and (f.value == "" or f.value == nil) then
                        allFilled = false
                        break
                    end
                end
                if allFilled then
                    local newUser = {
                        name = editFields[1].value,
                        password = editFields[2].value or "",
                        group = editFields[3].value or "Users",
                        homeDir = editFields[4].value or "C:\\Users\\" .. editFields[1].value,
                        rid = tostring(GetNextRID())
                    }
                    if SaveUser(newUser) then
                        print("User created: " .. newUser.name)
                        users = LoadUsers()
                        viewMode = "list"
                        RedrawWindow()
                    else
                        print("Error creating user")
                    end
                else
                    print("Username is required!")
                end
            else
                editMode = true
                local field = editFields[editFieldIndex]
                if field then
                    editInput = field.value or ""
                end
                RedrawWindow()
            end
        elseif code == 14 and editMode then -- BACKSPACE
            editInput = editInput:sub(1, -2)
            local field = editFields[editFieldIndex]
            if field then
                field.value = editInput
            end
            RedrawWindow()
        elseif char >= 32 and char <= 126 and editMode then
            editInput = editInput .. string.char(char)
            local field = editFields[editFieldIndex]
            if field then
                field.value = editInput
            end
            RedrawWindow()
        elseif code == 203 then -- <
            viewMode = "list"
            users = LoadUsers()
            RedrawWindow()
        end
    end
    return true
end

local function HandleEditInput(char, code)
    if code == 14 then -- BACKSPACE
        editInput = editInput:sub(1, -2)
        local fields = {
            {label = "Username", key = "name"},
            {label = "Password", key = "password"},
            {label = "Group", key = "group"},
            {label = "HomeDir", key = "homeDir"}
        }
        local field = fields[editFieldIndex]
        if field then
            editUser[field.key] = editInput
        end
        RedrawWindow()
        return true
    elseif char >= 32 and char <= 126 then
        editInput = editInput .. string.char(char)
        local fields = {
            {label = "Username", key = "name"},
            {label = "Password", key = "password"},
            {label = "Group", key = "group"},
            {label = "HomeDir", key = "homeDir"}
        }
        local field = fields[editFieldIndex]
        if field then
            editUser[field.key] = editInput
        end
        RedrawWindow()
        return true
    elseif code == 28 then -- ENTER
        editMode = false
        SaveUser(editUser)
        users = LoadUsers()
        viewMode = "list"
        RedrawWindow()
        return true
    elseif code == 203 then -- <
        editMode = false
        RedrawWindow()
        return true
    end
    return false
end

local function UserMgrMain()
    _G.DbgPrint("UserMgr: Starting...")
    
    if ParseArguments(args) then
        return false
    end
    
    users = LoadUsers()
    if #users == 0 then
        print("User Manager: No users found in SAM!")
        return false
    end
    
    print("User Manager: Found " .. #users .. " users")
    print("Press < to exit, ENTER to edit, INS to create, DEL to delete")
    
    RedrawWindow()
    
    while true do
        local signal = { computer.pullSignal(0.1) }
        
        if signal[1] == "key_down" then
            local char = signal[3]
            local code = signal[4]
            
            if viewMode == "edit" and editMode then
                if not HandleEditInput(char, code) then
                end
            else
                if not HandleKey(char, code) then
                    break
                end
            end
            
        elseif signal[1] == "touch" then
            local x, y = signal[3], signal[4]
            if y == winY + 1 and x >= winX + winW - 3 and x <= winX + winW - 1 then
                break
            end
        end
    end
    
    _G.DbgPrint("UserMgr: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return false
end

local ahh=UserMgrMain()
if not ahh then
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true