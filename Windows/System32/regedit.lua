local regedit = {}
local cDisk = component.proxy(computer.getBootAddress())

local hiveFiles = {
    ["HKEY_LOCAL_MACHINE\\SYSTEM"] = "Windows/System32/config/SYSTEM",
    ["HKEY_LOCAL_MACHINE\\SAM"]    = "Windows/System32/config/SAM",
    ["HKEY_LOCAL_MACHINE\\BCD00000000"] = "Windows/System32/config/BCD"
}

local function lines(handle)
    local buf = ""
    repeat
        local chunk = cDisk.read(handle, math.huge)
        buf = buf .. (chunk or "")
    until not chunk
    return buf:gmatch("[^\r\n]+")
end

local function loadHiveFile(hiveName, path)
    local f = cDisk.open(path, "r")
    if not f then return false end
    
    _G.Mm.NonPagedPool[hiveName] = {}
    local hive = _G.Mm.NonPagedPool[hiveName]
    
    for line in lines(f) do
        local p, k, v = line:match("^(%S+)%s+(%S+)%s+(.+)$")
        if p and k and v then
            if not hive[p] then hive[p] = {} end
            hive[p][k] = v
        end
    end
    cDisk.close(f)
    return true
end

function regedit.LoadHive()
    _G.DbgPrint("CM: Initializing Configuration Manager Hives...")
    
    loadHiveFile("HKEY_LOCAL_MACHINE\\SYSTEM", hiveFiles["HKEY_LOCAL_MACHINE\\SYSTEM"])
    
    if not loadHiveFile("HKEY_LOCAL_MACHINE\\SAM", hiveFiles["HKEY_LOCAL_MACHINE\\SAM"]) then
        _G.DbgPrint("CM: SAM hive not found. CM create template, you can see this error if load WinNT at first time...")
    end

    local samHive = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SAM"]

    if next(samHive) == nil then
        _G.DbgPrint("CM: SAM is empty! Writing default Security Account Manager template...")
    
        local root = "SAM\\Users"
        
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Administrator", "Password", "admin123")
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Administrator", "Group", "Administrators")
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Administrator", "HomeDir", "C:\\Users\\Administrator")
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Administrator", "RID", "500")
        
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Guest", "Password", "")
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Guest", "Group", "Guests")
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Guest", "HomeDir", "C:\\Users\\Guest")
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", root .. "\\Guest", "RID", "501")
        
        local compRoot = "SAM\\ComponentUpdates\\BuiltIn"
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SAM", compRoot, "Administrators", "544")
        
        regedit.Flush()
        _G.DbgPrint("CM: Default SAM template flushed to disk successfully.")
    end

    loadHiveFile("HKEY_LOCAL_MACHINE\\BCD00000000", hiveFiles["HKEY_LOCAL_MACHINE\\BCD00000000"])
end

function regedit.GetValue(path, key)
    return regedit.GetValueEx("HKEY_LOCAL_MACHINE\\SYSTEM", path, key)
end

function regedit.SetValue(path, key, value)
    return regedit.SetValueEx("HKEY_LOCAL_MACHINE\\SYSTEM", path, key, value)
end

function regedit.KeyExists(path, key)
    return regedit.KeyExistsEx("HKEY_LOCAL_MACHINE\\SYSTEM", path, key)
end

function regedit.GetValueEx(hiveName, path, key)
    local hive = _G.Mm.NonPagedPool[hiveName]
    if hive and hive[path] then
        return hive[path][key]
    end
    return nil
end

function regedit.SetValueEx(hiveName, path, key, value)
    local hive = _G.Mm.NonPagedPool[hiveName]
    if not hive then return false end
    if not hive[path] then hive[path] = {} end
    
    if type(value) ~= "table" then 
        hive[path][key] = value 
    else 
        hive[path][key] = table.concat(value, ",") 
    end
    return true
end

function regedit.KeyExistsEx(hiveName, path, key)
    local hive = _G.Mm.NonPagedPool[hiveName]
    if not hive or not hive[path] then return false end
    if not key then return true end
    return hive[path][key] ~= nil
end

function regedit.Flush()
    for hiveName, filePath in pairs(hiveFiles) do
        local hive = _G.Mm.NonPagedPool[hiveName]
        if hive then
            local f = cDisk.open(filePath, "w")
            if f then
                for pN, keys in pairs(hive) do
                    for keyName, val in pairs(keys) do
                        cDisk.write(f, string.format("%s %s %s\n", pN, keyName, tostring(val)))
                    end
                end
                cDisk.close(f)
            end
        end
    end
    return true
end

return regedit