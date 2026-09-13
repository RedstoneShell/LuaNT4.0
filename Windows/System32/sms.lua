-- sms.lua - Systems Management Server for LuaNT 4.0
-- (C) RedstoneShell 2026
-- Centralized package management system

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local wininet = _G.LdrLoadDll("Windows/System32/wininet.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")

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
        _G.DbgPrint("SMS: " .. tostring(text))
    end
end

local print = printToConsole

local SMS = {
    BaseURL = "https://raw.githubusercontent.com/RedstoneShell/LuaNT4.0/main/SystemsManServer/",
    Packages = {},
    CurrentPackage = nil,
    InstallPath = nil
}

local function WrapText(text, maxWidth)
    maxWidth = maxWidth or 42
    text = tostring(text or "")
    local lines = {}
    local current = ""

    for word in text:gmatch("%S+") do
        if current == "" then
            current = word
        elseif #current + 1 + #word <= maxWidth then
            current = current .. " " .. word
        else
            table.insert(lines, current)
            current = word
        end

        while #current > maxWidth do
            table.insert(lines, current:sub(1, maxWidth))
            current = current:sub(maxWidth + 1)
        end
    end

    if current ~= "" then
        table.insert(lines, current)
    end

    if #lines == 0 then
        lines = {""}
    end

    return lines
end

local function ParseConfig(content)
    local config = {}
    for line in content:gmatch("[^\r\n]+") do
        if line:match("^[^%s#]") then
            local key, value = line:match("^([^=]+)%s*=%s*(.+)$")
            if key and value then
                key = key:gsub("%s+$", ""):gsub("^%s+", "")
                value = value:gsub("%s+$", ""):gsub("^%s+", "")
                if key == "files" then
                    local files = {}
                    for file in value:gmatch('"([^"]+)"') do
                        table.insert(files, file)
                    end
                    config.files = files
                else
                    config[key] = value
                end
            end
        end
    end
    return config
end

local function FetchPackageList()
    print("SMS: Fetching package list from server...")
    
    local url = SMS.BaseURL .. "packages.cfg"
    local ok, content = wininet.HttpGet(url)
    
    if not ok then
        print("SMS: Failed to fetch package list: " .. tostring(content))
        return false
    end
    
    if not content or content == "" then
        print("SMS: Empty package list")
        return false
    end
    
    SMS.Packages = {}
    for line in content:gmatch("[^\r\n]+") do
        local packageName = line:match("^%s*(.-)%s*$")
        if packageName and packageName ~= "" then
            table.insert(SMS.Packages, packageName)
        end
    end
    
    print(string.format("SMS: Found %d packages", #SMS.Packages))
    return true
end

local function FetchPackageConfig(packageName)
    local url = SMS.BaseURL .. packageName .. "/config.cfg"
    local ok, content = wininet.HttpGet(url)
    
    if not ok then
        print("SMS: Failed to fetch config for " .. packageName .. ": " .. tostring(content))
        return nil
    end
    
    local config = ParseConfig(content)
    config.name = config.name or packageName
    config.desc = config.desc or "No description"
    config.ver = config.ver or "1.0"
    config.files = config.files or {}
    config.installPath = config.installPath or "Windows/System32/"
    
    return config
end

local function DownloadFile(url, destPath)
    print("SMS: Downloading " .. url)
    
    local ok, content = wininet.HttpGet(url)
    if not ok then
        print("SMS: Failed to download: " .. tostring(content))
        return false
    end
    
    local fs = component.proxy(computer.getBootAddress())
    if not fs then
        print("SMS: No boot filesystem")
        return false
    end
    
    local dir = destPath:match("(.*)/")
    if dir and not fs.exists(dir) then
        pcall(fs.makeDirectory, dir)
    end
    
    local handle = fs.open(destPath, "w")
    if not handle then
        print("SMS: Failed to write " .. destPath)
        return false
    end
    
    fs.write(handle, content)
    fs.close(handle)
    
    print("SMS: Downloaded " .. #content .. " bytes to " .. destPath)
    return true
end

local function InstallPackage(packageName, config)
    print(string.format("SMS: Installing package: %s (%s)", config.name, config.ver))
    
    local basePath = config.installPath or "Windows/System32/"
    if basePath:sub(-1) ~= "/" then
        basePath = basePath .. "/"
    end
    
    local success = true
    for _, file in ipairs(config.files) do
        local url = SMS.BaseURL .. packageName .. "/" .. file
        local destPath = basePath .. file
        if not DownloadFile(url, destPath) then
            success = false
            print("SMS: Failed to install " .. file)
        end
    end
    
    if success then
        print("SMS: Package installed successfully")
    else
        print("SMS: Package installation completed with errors")
    end
    
    return success
end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 60, 20
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local clientX = winX + 1
local clientY = winY + 3
local clientW = winW - 2
local clientH = winH - 5

local selectedIndex = 1
local scrollOffset = 0
local viewMode = "list" -- "list", "details"

local COLORS = {
    window_bg = 0xC0C0C0,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    selected = 0x000080,
    selected_text = 0xFFFFFF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF
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
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.window_title)
    
    if viewMode == "list" then
        gdi32.TextOut(hdc, winX + 2, winY + 1, "Systems Management Server - Packages")
    else
        gdi32.TextOut(hdc, winX + 2, winY + 1, "Package Details")
    end
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    if viewMode == "list" then
        local maxLines = clientH - 2
        for i = 1, math.min(#SMS.Packages, maxLines) do
            local idx = i + scrollOffset
            local pkg = SMS.Packages[idx]
            if pkg then
                local yPos = clientY + i - 1
                local isSelected = (idx == selectedIndex)
                
                if isSelected then
                    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.selected))
                    gdi32.PatBlt(hdc, clientX, yPos, clientW, 1, gdi32.PATCOPY)
                    gdi32.SetTextColor(hdc, COLORS.selected_text)
                else
                    gdi32.SetTextColor(hdc, COLORS.text)
                end
                
                gdi32.TextOut(hdc, clientX + 2, yPos, pkg)
            end
        end
    else
        local config = SMS.CurrentPackage
        if config then
            local y = clientY
            local maxW = clientW - 4

            local function PutLine(label, value)
                local text = label .. tostring(value)
                local wrapped = WrapText(text, maxW)
                for _, ln in ipairs(wrapped) do
                    if y < clientY + clientH - 2 then
                        gdi32.TextOut(hdc, clientX + 2, y, ln)
                        y = y + 1
                    end
                end
            end

            PutLine("Name: ", config.name or "Unknown")
            PutLine("Version: ", config.ver or "Unknown")
            PutLine("Description: ", config.desc or "No description")
            PutLine("Files: ", #(config.files or {}))
            PutLine("Install Path: ", config.installPath or "Default")

            y = y + 1

            gdi32.SetTextColor(hdc, 0x00AA00)
            gdi32.TextOut(hdc, clientX + 2, y, "[ENTER] - Install")
            y = y + 1
            gdi32.SetTextColor(hdc, COLORS.text)
            gdi32.TextOut(hdc, clientX + 2, y, "[<] - Back")
        end
    end
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.status_bg))
    gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.status_bg)
    
    if viewMode == "list" then
        gdi32.TextOut(hdc, winX + 2, winY + winH - 2, 
            string.format("%d packages", #SMS.Packages))
    else
        gdi32.TextOut(hdc, winX + 2, winY + winH - 2, "Press ENTER to install, < to go back")
    end
end

local function RedrawWindow()
    DrawWindowFrame()
end

local function HandleKey(char, code)
    if viewMode == "list" then
        if code == 211 then -- DEL
            return false
        elseif code == 28 then -- ENTER
            if selectedIndex >= 1 and selectedIndex <= #SMS.Packages then
                local pkg = SMS.Packages[selectedIndex]
                local config = FetchPackageConfig(pkg)
                if config then
                    SMS.CurrentPackage = config
                    viewMode = "details"
                    RedrawWindow()
                end
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
            if selectedIndex < #SMS.Packages then
                selectedIndex = selectedIndex + 1
                if selectedIndex > scrollOffset + clientH - 2 then
                    scrollOffset = selectedIndex - clientH + 2
                end
                RedrawWindow()
            end
        end
    else -- details
        if code == 211 then -- DEL
            return false
        elseif code == 28 then -- ENTER
            if SMS.CurrentPackage then
                InstallPackage(SMS.Packages[selectedIndex], SMS.CurrentPackage)
                viewMode = "list"
                RedrawWindow()
            end
        elseif code == 203 then -- LEFT
            viewMode = "list"
            RedrawWindow()
        end
    end
    return true
end

function SMSMain()
    _G.DbgPrint("SMS: Starting Systems Management Server...")
    
    if not FetchPackageList() then
        print("SMS: Failed to fetch package list. Check internet connection.")
        return false
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
                break
            end
        end
    end
    
    _G.DbgPrint("SMS: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return false
end

local exitCode = SMSMain()

if not exitCode then
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true