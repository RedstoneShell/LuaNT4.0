-- wusvc.lua - Windows Update Service for LuaNT 4.0
-- (C) RedstoneShell 2026

local service = {}
local UPDATE_URL = "https://raw.githubusercontent.com/RedstoneShell/LuaNT4.0/main/updatecenterdata.json"
local CURRENT_VERSION = "4.0.1.0"
local SAVE_PATH = "Windows/WinSxS/updates/wusig.json"
local BASE_URL = "https://raw.githubusercontent.com/RedstoneShell/LuaNT4.0/main/"

local CHECK_INTERVAL = 30
local NOTIFICATION_TIMEOUT = 10
local NOTIFICATION_WIDTH = 50
local NOTIFICATION_HEIGHT = 4
local AUTO_INSTALL_DELAY = 5

local notificationVisible = false
local notificationTime = 0
local lastCheck = 0
local pendingUpdate = nil
local installTimer = 0
local installStarted = false
local installComplete = false

local function GetBootFS()
    local addr = computer.getBootAddress()
    if not addr then return nil end
    return component.proxy(addr)
end

local function SaveUpdateData(data)
    local fs = GetBootFS()
    if not fs then
        _G.DbgPrint("WUSVC: Cannot save - boot filesystem not available")
        return false
    end

    local dir = SAVE_PATH:match("(.*)/")
    if dir and not fs.exists(dir) then
        pcall(fs.makeDirectory, dir)
    end

    local handle, err = fs.open(SAVE_PATH, "w")
    if not handle then
        _G.DbgPrint("WUSVC: Failed to open save file: " .. tostring(err))
        return false
    end

    local saveData = {}
    for k, v in pairs(data) do
        if k ~= "latest_version" then
            saveData[k] = v
        end
    end

    local json = "{\n"
    local entries = {}
    for k, v in pairs(saveData) do
        local value
        if type(v) == "string" then
            value = '"' .. tostring(v):gsub('"', '\\"') .. '"'
        elseif type(v) == "table" then
            local items = {}
            for _, item in ipairs(v) do
                items[#items + 1] = '"' .. tostring(item):gsub('"', '\\"') .. '"'
            end
            value = "[" .. table.concat(items, ", ") .. "]"
        else
            value = tostring(v)
        end
        entries[#entries + 1] = string.format('  "%s": %s', k, value)
    end
    json = json .. table.concat(entries, ",\n") .. "\n}"

    fs.write(handle, json)
    fs.close(handle)

    _G.DbgPrint("WUSVC: Saved update data to " .. SAVE_PATH)
    return true
end

local function LoadUpdateData()
    local fs = GetBootFS()
    if not fs then return nil end

    if not fs.exists(SAVE_PATH) then
        return nil
    end

    local handle, err = fs.open(SAVE_PATH, "r")
    if not handle then
        return nil
    end

    local content = ""
    while true do
        local chunk = fs.read(handle, 512)
        if not chunk then break end
        content = content .. chunk
    end
    fs.close(handle)

    local data = {}
    for key, value in content:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
        data[key] = value
    end
    for key, value in content:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
        local trimmed = value:match("^%s*(.-)%s*$")
        if not data[key] then
            if trimmed == "true" then data[key] = true
            elseif trimmed == "false" then data[key] = false
            elseif trimmed:match("^%d+$") then data[key] = tonumber(trimmed)
            else data[key] = trimmed
            end
        end
    end

    return data
end

local function DownloadFile(url, destPath)
    _G.DbgPrint("WUSVC: Downloading " .. url)

    local internetAddr = component.list("internet")()
    if not internetAddr then
        _G.DbgPrint("WUSVC: No Internet Card found")
        return false
    end

    local internet = component.proxy(internetAddr)

    local ok, handle = pcall(function()
        return internet.request(url)
    end)

    if not ok or not handle then
        _G.DbgPrint("WUSVC: Request failed: " .. tostring(handle))
        return false
    end

    local content = ""
    local gotData = false
    local idleReads = 0

    while true do
        local data = handle.read()

        if data and #data > 0 then
            content = content .. data
            gotData = true
            idleReads = 0
        elseif gotData then
            idleReads = idleReads + 1
            if idleReads >= 3 then
                break
            end
        end

        coroutine.yield()
    end

    if handle.close then
        pcall(handle.close)
    end

    if #content == 0 then
        _G.DbgPrint("WUSVC: Empty response for " .. url)
        return false
    end

    local fs = GetBootFS()
    if not fs then
        _G.DbgPrint("WUSVC: No boot filesystem")
        return false
    end

    local dir = destPath:match("(.*)/")
    if dir and not fs.exists(dir) then
        pcall(fs.makeDirectory, dir)
    end

    local handleFile, err = fs.open(destPath, "w")
    if not handleFile then
        _G.DbgPrint("WUSVC: Failed to write " .. destPath .. ": " .. tostring(err))
        return false
    end

    fs.write(handleFile, content)
    fs.close(handleFile)

    _G.DbgPrint("WUSVC: Saved " .. #content .. " bytes to " .. destPath)
    return true
end

local function InstallUpdate(updateData)
    if not updateData or not updateData.files then
        _G.DbgPrint("WUSVC: No files to install")
        return false
    end

    _G.DbgPrint("WUSVC: Starting automatic installation...")
    local total = #updateData.files
    local installed = 0

    for _, filePath in ipairs(updateData.files) do
        local url = BASE_URL .. filePath
        local destPath = "Windows/WinSxS/" .. filePath

        if DownloadFile(url, destPath) then
            installed = installed + 1
        else
            _G.DbgPrint("WUSVC: Failed to download " .. filePath)
        end

        coroutine.yield()
    end

    _G.DbgPrint(string.format("WUSVC: Installation complete: %d/%d files", installed, total))
    return installed == total
end

local function HasInternet()
    local internet = component.list("internet")()
    if internet then return true end
    local tunnel = component.list("tunnel")()
    return tunnel ~= nil
end

local function GetOSVersion()
    local version = _G.regedit0 and _G.regedit0.GetValue("\\Software\\RedstoneShell\\Windows NT\\CurrentVersion", "CurrentVersion")
    if version then
        return version
    end
    return CURRENT_VERSION
end

local function GetGpu()
    return _G.HAL and _G.HAL.gpu
end

local function ShowNotification(title, text)
    local gpu = GetGpu()
    if not gpu then return end

    local sw, sh = gpu.getResolution()
    local x = math.max(1, sw - NOTIFICATION_WIDTH)
    local y = 2

    local oldBg = gpu.getBackground()
    local oldFg = gpu.getForeground()

    gpu.setBackground(0x000080)
    gpu.fill(x, y, NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT, " ")

    gpu.setForeground(0xFFFFFF)
    gpu.set(x, y, "┌" .. string.rep("─", NOTIFICATION_WIDTH - 2) .. "┐")
    gpu.set(x, y + 3, "└" .. string.rep("─", NOTIFICATION_WIDTH - 2) .. "┘")
    gpu.set(x, y + 1, "│")
    gpu.set(x + NOTIFICATION_WIDTH - 1, y + 1, "│")

    gpu.setForeground(0xFFFF00)
    gpu.set(x + 2, y + 1, title)

    gpu.setForeground(0xCCCCCC)
    gpu.set(x + 2, y + 2, text)

    gpu.setBackground(oldBg)
    gpu.setForeground(oldFg)

    notificationVisible = true
    notificationTime = computer.uptime()
end

local function HideNotification()
    local gpu = GetGpu()
    if not gpu then return end

    local sw, sh = gpu.getResolution()
    local x = math.max(1, sw - NOTIFICATION_WIDTH)
    local y = 2

    gpu.setBackground(0x008080)
    gpu.fill(x, y, NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT, " ")

    notificationVisible = false
end

local function ShowInstallingNotification()
    local gpu = GetGpu()
    if not gpu then return end

    local sw, sh = gpu.getResolution()
    local x = math.max(1, sw - NOTIFICATION_WIDTH)
    local y = 2

    local oldBg = gpu.getBackground()
    local oldFg = gpu.getForeground()

    gpu.setBackground(0x000080)
    gpu.fill(x, y, NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT, " ")

    gpu.setForeground(0xFFFFFF)
    gpu.set(x, y, "┌" .. string.rep("─", NOTIFICATION_WIDTH - 2) .. "┐")
    gpu.set(x, y + 3, "└" .. string.rep("─", NOTIFICATION_WIDTH - 2) .. "┘")
    gpu.set(x, y + 1, "│")
    gpu.set(x + NOTIFICATION_WIDTH - 1, y + 1, "│")

    gpu.setForeground(0x00FF00)
    gpu.set(x + 2, y + 1, "Installing update...")

    gpu.setForeground(0xCCCCCC)
    gpu.set(x + 2, y + 2, "Please wait...")

    gpu.setBackground(oldBg)
    gpu.setForeground(oldFg)
end

local function FetchUpdateData()
    if not HasInternet() then
        _G.DbgPrint("WUSVC: No internet connection available")
        return nil
    end

    _G.DbgPrint("WUSVC: Fetching update data from " .. UPDATE_URL)

    local internetAddr = component.list("internet")()
    if not internetAddr then
        _G.DbgPrint("WUSVC: No Internet Card found")
        return nil
    end

    local internet = component.proxy(internetAddr)

    local ok, handle = pcall(function()
        return internet.request(UPDATE_URL)
    end)

    if not ok then
        _G.DbgPrint("WUSVC: Request failed: " .. tostring(handle))
        return nil
    end

    if not handle then
        _G.DbgPrint("WUSVC: Request returned nil handle")
        return nil
    end

    local content = ""
    local gotData = false
    local idleReads = 0

    while true do
        local data = handle.read()

        if data and #data > 0 then
            content = content .. data
            gotData = true
            idleReads = 0
        elseif gotData then
            idleReads = idleReads + 1
            if idleReads >= 3 then
                break
            end
        end

        coroutine.yield()
    end

    if handle.close then
        pcall(handle.close)
    end

    _G.DbgPrint("WUSVC: Downloaded " .. tostring(#content) .. " bytes")

    if #content == 0 then
        _G.DbgPrint("WUSVC: Empty response from server")
        return nil
    end

    _G.DbgPrint("WUSVC: Response preview: " .. content:sub(1, math.min(128, #content)))

    local updateData = {}
    for key, value in content:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
        updateData[key] = value
    end
    for key, value in content:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
        local trimmed = value:match("^%s*(.-)%s*$")
        if not updateData[key] then
            if trimmed == "true" then updateData[key] = true
            elseif trimmed == "false" then updateData[key] = false
            elseif trimmed:match("^%d+$") then updateData[key] = tonumber(trimmed)
            else updateData[key] = trimmed
            end
        end
    end
    local filesBlock = content:match('"files"%s*:%s*(%b[])')

    if filesBlock then
        local files = {}

        for file in filesBlock:gmatch('"([^"]+)"') do
            files[#files + 1] = file
        end

        updateData.files = files
    end

    if not updateData.latest_version then
        _G.DbgPrint("WUSVC: latest_version not found")
        return nil
    end

    _G.DbgPrint("WUSVC: Latest version: " .. updateData.latest_version)
    return updateData
end

local function MainLoop()
    _G.DbgPrint("WUSVC: Update notifier started")

    local savedData = LoadUpdateData()
    if savedData then
        _G.WUSVC = _G.WUSVC or {}
        for k, v in pairs(savedData) do
            if k ~= "_interfaceRegistered" then
                _G.WUSVC[k] = v
            end
        end
        _G.DbgPrint("WUSVC: Restored saved data")
    end

    while true do
        local now = computer.uptime()

        if now - lastCheck >= CHECK_INTERVAL then
            lastCheck = now

            local updateData = FetchUpdateData()
            if updateData and updateData.latest_version then
                local currentVersion = GetOSVersion()
                local isUpdateAvailable = updateData.latest_version ~= currentVersion

                local saveData = {}
                for k, v in pairs(updateData) do
                    if k ~= "latest_version" then
                        saveData[k] = v
                    end
                end

                if next(saveData) then
                    SaveUpdateData(saveData)
                end

                _G.WUSVC = _G.WUSVC or {}
                _G.WUSVC.UpdateAvailable = isUpdateAvailable
                _G.WUSVC.LatestVersion = updateData.latest_version
                _G.WUSVC.CurrentVersion = currentVersion
                _G.WUSVC.UpdateData = updateData
                _G.WUSVC.CheckedAt = os.time()

                if isUpdateAvailable and _G.RpcSs then
                    if not _G.WUSVC._interfaceRegistered then
                        _G.WUSVC._interfaceRegistered = true
                        local IWindowsUpdate = {
                            WinUpdAvailable = function() return _G.WUSVC.UpdateAvailable end,
                            GetLatestVersion = function() return _G.WUSVC.LatestVersion end,
                            GetCurrentVersion = function() return _G.WUSVC.CurrentVersion end,
                            CheckForUpdates = function()
                                _G.DbgPrint("WUSVC: Manual check for updates requested")
                                local newData = FetchUpdateData()
                                if newData then
                                    local saveData = {}
                                    for k, v in pairs(newData) do
                                        if k ~= "latest_version" then
                                            saveData[k] = v
                                        end
                                    end
                                    if next(saveData) then
                                        SaveUpdateData(saveData)
                                    end
                                    _G.WUSVC.UpdateData = newData
                                    _G.WUSVC.LatestVersion = newData.latest_version
                                    _G.WUSVC.UpdateAvailable = (newData.latest_version ~= GetOSVersion())
                                    _G.WUSVC.CheckedAt = os.time()
                                    return _G.WUSVC.UpdateAvailable
                                end
                                return false
                            end,
                            GetUpdateInfo = function() return _G.WUSVC.UpdateData end,
                            GetSavedInfo = function() 
                                local saved = LoadUpdateData()
                                return saved or {}
                            end
                        }
                        _G.RpcSs.RpcServerRegisterIf("IWindowsUpdate", IWindowsUpdate)
                        _G.DbgPrint("WUSVC: RPC interface 'IWindowsUpdate' registered")
                    end
                end

                if isUpdateAvailable then
                    local text = string.format("Version %s available", tostring(updateData.latest_version))
                    if not notificationVisible and not installStarted then
                        _G.DbgPrint("WUSVC: Update available! " .. currentVersion .. " -> " .. updateData.latest_version)
                        ShowNotification("Windows Update", text)
                        pendingUpdate = updateData
                        installTimer = now
                        notificationVisible = true
                        notificationTime = now
                    end
                end
            end
        end

        if notificationVisible and pendingUpdate and not installStarted then
            if now - installTimer >= AUTO_INSTALL_DELAY then
                _G.DbgPrint("WUSVC: Auto-install triggered after " .. AUTO_INSTALL_DELAY .. "s")
                installStarted = true
                notificationVisible = false
                HideNotification()
                ShowInstallingNotification()
                
                local success = InstallUpdate(pendingUpdate)
                
                if success then
                    _G.DbgPrint("WUSVC: Auto-install complete")
                    HideNotification()
                    ShowNotification("Update installed!", "System updated successfully")
                    installComplete = true
                    pendingUpdate = nil
                    local hideTime = computer.uptime()
                    while computer.uptime() - hideTime < 3 do
                        coroutine.yield()
                    end
                    HideNotification()
                    break
                else
                    _G.DbgPrint("WUSVC: Install failed")
                    HideNotification()
                    ShowNotification("Update failed!", "Please try again later")
                end
                
                installStarted = false
            end
        end

        if notificationVisible and not installStarted and now - notificationTime >= NOTIFICATION_TIMEOUT then
            HideNotification()
            notificationVisible = false
        end

        coroutine.yield()
    end
end

function service.Main()
    _G.DbgPrint("WUSVC: Windows Update Service starting...")

    if not HasInternet() then
        _G.DbgPrint("WUSVC: No internet connection. Service running in standby mode.")
    end

    MainLoop()

    _G.DbgPrint("WUSVC: Service initialized successfully")
end

service.Main()

return service