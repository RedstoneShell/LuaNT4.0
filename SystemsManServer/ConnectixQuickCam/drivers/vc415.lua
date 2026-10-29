local vc415 = {}
local regedit = LdrLoadDll("Windows/System32/regedit.lua")
local fs_proxy = component.proxy(computer.getBootAddress())

vc415.Cameras = {}

vc415.Config = {
    MaxDistance = 32,
    Resolution = 160,
    Brightness = 50,
    Saturation = 50,
    Contrast = 50,
    WhiteBalance = 50,
    FOV = 60
}

local CONFIG_FILE = "QUICKCAM.INI"

function vc415.LoadConfig()
    local ok, file = pcall(fs_proxy.open, CONFIG_FILE, "r")
    if ok and file then
        local data = ""
        while true do
            local chunk = fs_proxy.read(file, 1024)
            if not chunk or #chunk == 0 then break end
            data = data .. chunk
        end
        fs_proxy.close(file)
        
        for key, value in data:gmatch("([^=]+)=([^\n]+)") do
            local num = tonumber(value)
            if num then
                if key == "resolution" then vc415.Config.Resolution = num
                elseif key == "brightness" then vc415.Config.Brightness = num
                elseif key == "saturation" then vc415.Config.Saturation = num
                elseif key == "contrast" then vc415.Config.Contrast = num
                elseif key == "whitebalance" then vc415.Config.WhiteBalance = num
                elseif key == "fov" then vc415.Config.FOV = num
                end
            end
        end
        DbgPrint("vc415: Config loaded from " .. CONFIG_FILE)
    end
end

function vc415.SaveConfig()
    local ok, file = pcall(fs_proxy.open, CONFIG_FILE, "w")
    if ok and file then
        local data = ""
        for k, v in pairs(vc415.Config) do
            data = data .. string.lower(k) .. "=" .. tostring(v) .. "\n"
        end
        fs_proxy.write(file, data)
        fs_proxy.close(file)
        DbgPrint("vc415: Config saved to " .. CONFIG_FILE)
        return true
    end
    return false
end

function vc415.CreateCameraDevice(component, address)
    local device = {
        type = "vc415",
        address = address,
        component = component,

        renderFrame = function(w, h, fov)
            local frame = {}
            local fovRad = math.rad(fov or vc415.Config.FOV)
            
            for py = 1, h do
                local row = {}
                for px = 1, w do
                    local xAngle = ((px / w) * 2 - 1) * math.tan(fovRad / 2)
                    local yAngle = ((py / h) * 2 - 1) * math.tan(fovRad / 2)
                    
                    local dist = component.distance(xAngle, yAngle)
                    
                    local val = 0
                    if dist and dist >= 0 then
                        val = 1.0 - (dist / vc415.Config.MaxDistance)
                        if val < 0 then val = 0 end
                    end
                    
                    local b = vc415.Config.Brightness / 100
                    local c = vc415.Config.Contrast / 100
                    val = val * (0.5 + c) + (b - 0.5)
                    
                    if val < 0 then val = 0 end
                    if val > 1 then val = 1 end
                    
                    row[px] = val
                end
                frame[py] = row
            end
            return frame
        end,

        getSettings = function()
            return vc415.Config
        end,

        setSetting = function(key, value)
            if vc415.Config[key] ~= nil then
                vc415.Config[key] = tonumber(value) or vc415.Config[key]
                return true
            end
            return false
        end,

        saveSettings = function()
            return vc415.SaveConfig()
        end
    }
    return device
end

function vc415.ScanAndInitialize()
    local foundCameras = {}
    local processedAddrs = {}

    for addr in component.list("camera") do
        if not processedAddrs[addr] then
            local component = component.proxy(addr)
            if component then
                local device = vc415.CreateCameraDevice(component, addr)
                table.insert(foundCameras, { address = addr, device = device })
                processedAddrs[addr] = true
            end
        end
    end

    for i, cam in ipairs(foundCameras) do
        local deviceName = "\\Device\\vc415" .. i
        _G.Mm.NonPagedPool[deviceName] = cam.device
        vc415.Cameras[deviceName] = cam
    end
    return foundCameras
end

function vc415.DriverEntry()
    vc415.LoadConfig()
    local cameras = vc415.ScanAndInitialize()
    local driverObject = {
        name = "vc415",
        version = "2.0",
        cameras = vc415.Cameras,
        GetCameraInfo = function(i) return vc415.Cameras["\\Device\\vc415" .. i] end,
        GetCameraCount = function() return #cameras end,
        GetConfig = function() return vc415.Config end,
        SetConfig = function(k, v) 
            if vc415.Config[k] ~= nil then vc415.Config[k] = tonumber(v) or vc415.Config[k]; return true end 
            return false 
        end,
        SaveConfig = function() return vc415.SaveConfig() end
    }
    _G.Mm.NonPagedPool["\\Driver\\vc415"] = driverObject
    return driverObject
end

return vc415.DriverEntry()