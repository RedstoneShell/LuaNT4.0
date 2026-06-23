local mraidnt = {}
local regedit = LdrLoadDll("Windows/System32/regedit.lua")
mraidnt.Arrays = {}

local SINGLE_DISK_SIZE = 4194304
mraidnt.Config = {
    MinSizeForRaid = SINGLE_DISK_SIZE + 1,
    SupportedLevels = {0, 1, 5},
    CurrentArray = nil
}

function mraidnt.CheckDiskSize(fs)
    local total = fs.spaceTotal()
    
    if total <= SINGLE_DISK_SIZE then
        DbgPrint("MegaRAID: Disk " .. tostring(fs) .. " size " .. total .. " bytes <= 4MB, skipping")
        return "SINGLE"
    elseif total == SINGLE_DISK_SIZE * 2 then
        DbgPrint("MegaRAID: Detected 8MB array (2x4MB) - possible RAID 0/1")
        return "DUAL"
    elseif total == SINGLE_DISK_SIZE * 3 then
        DbgPrint("MegaRAID: Detected 12MB array (3x4MB) - possible RAID 0/5")
        return "TRIPLE"
    else
        DbgPrint("MegaRAID: Anomalous size " .. total .. " bytes - investigating...")
        return "ANOMALY"
    end
end

function mraidnt.DetectRaidLevel(totalSize, numDisks)
    local expectedSize = numDisks * SINGLE_DISK_SIZE
    
    if totalSize == expectedSize then
        --RAID 0
        return 0, "Striping (RAID 0)"
    elseif totalSize == SINGLE_DISK_SIZE then
        --RAID 1
        return 1, "Mirroring (RAID 1)"
    elseif totalSize == (numDisks - 1) * SINGLE_DISK_SIZE then
        -- RAID 5
        return 5, "Striping with Parity (RAID 5)"
    elseif totalSize == (numDisks / 2) * SINGLE_DISK_SIZE then
        -- RAID 10
        return 10, "Mirror + Striping (RAID 10)"
    else
        return nil, "Unknown configuration"
    end
end

function mraidnt.CreateRaidDevice(fs, totalSize, raidLevel)
    local device = {
        type = "RAID",
        level = raidLevel,
        originalSize = totalSize,
        fs = fs,
        open = function(path, mode)
            DbgPrint("MegaRAID: Opening " .. path .. " on RAID array")
            return fs.open(path, mode)
        end,
        
        read = function(handle, bytes)
            return fs.read(handle, bytes)
        end,
        
        write = function(handle, data)
            return fs.write(handle, data)
        end,
        
        close = function(handle)
            return fs.close(handle)
        end,
        
        list = function(path)
            return fs.list(path)
        end,
        
        spaceTotal = function()
            return totalSize
        end,
        
        spaceUsed = function()
            return fs.spaceUsed()
        end,
        
        getLabel = function()
            return "RAID " .. raidLevel .. " Array"
        end,
        
        isReadOnly = function()
            return fs.isReadOnly()
        end,
        
        remove = function(path)
            return fs.remove(path)
        end,
        
        makeDirectory = function(path)
            return fs.makeDirectory(path)
        end
    }
    
    return device
end

function mraidnt.ScanAndInitialize()
    DbgPrint("MegaRAID: Scanning for disk arrays...")
    
    local foundArrays = {}
    local processedAddrs = {}
    
    for addr in component.list("filesystem") do
        if not processedAddrs[addr] then
            local fs = component.proxy(addr)
            local totalSize = fs.spaceTotal()
            local diskType = mraidnt.CheckDiskSize(fs)
            
            if diskType ~= "SINGLE" then
                local numDisks = totalSize / SINGLE_DISK_SIZE
                local raidLevel, levelName = mraidnt.DetectRaidLevel(totalSize, numDisks)
                
                if raidLevel then
                    DbgPrint(string.format("MegaRAID: Found RAID %d array: %s (size: %d bytes, %d disks)",
                        raidLevel, levelName, totalSize, numDisks))
                    
                    local raidDevice = mraidnt.CreateRaidDevice(fs, totalSize, raidLevel)
                    
                    table.insert(foundArrays, {
                        address = addr,
                        size = totalSize,
                        level = raidLevel,
                        device = raidDevice,
                        numDisks = numDisks
                    })
                    
                    processedAddrs[addr] = true
                else
                    DbgPrint("MegaRAID: Unknown configuration for size " .. totalSize)
                end
            end
        end
    end

    for i, array in ipairs(foundArrays) do
        local deviceName = "\\Device\\MegaRAID" .. i
        
        _G.Mm.NonPagedPool[deviceName] = array.device
        mraidnt.Arrays[deviceName] = array
        
        DbgPrint(string.format("MegaRAID: Registered %s (RAID %d, %d MB)",
            deviceName, array.level, array.size / 1024 / 1024))
        
        if regedit and regedit.SetValue then
            local regPath = "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\MegaRAID\\Array" .. i
            regedit.SetValue(regPath, "DeviceName", deviceName)
            regedit.SetValue(regPath, "Level", array.level)
            regedit.SetValue(regPath, "Size", array.size)
            regedit.SetValue(regPath, "NumDisks", array.numDisks)
            regedit.SetValue(regPath, "SourceAddress", array.address)
        end
    end
    
    if #foundArrays == 0 then
        DbgPrint("MegaRAID: No RAID arrays detected")
    else
        DbgPrint(string.format("MegaRAID: Initialized with %d RAID arrays", #foundArrays))
    end
    
    return foundArrays
end

function mraidnt.DriverEntry()
    DbgPrint("MegaRAID: LSI Logic MegaRAID Driver for RedstoneShell lua Windows NT port")
    DbgPrint("MegaRAID: Version 4.23.03.00 (Build 1381)")
    local arrays = mraidnt.ScanAndInitialize()
    local driverObject = {
        name = "MegaRAID",
        version = "4.23.03.00",
        arrays = mraidnt.Arrays,
        GetArrayInfo = function(index)
            return mraidnt.Arrays["\\Device\\MegaRAID" .. index]
        end,
        GetArrayCount = function()
            return #arrays
        end,
        Rescan = function()
            DbgPrint("MegaRAID: Rescanning for arrays...")
            return mraidnt.ScanAndInitialize()
        end
    }
    _G.Mm.NonPagedPool["\\Driver\\MegaRAID"] = driverObject
    if _G.RegisterShutdownDriver then
        _G.RegisterShutdownDriver("mraidnt", mraidnt)
    end
    DbgPrint("MegaRAID: Initialization complete")
    return driverObject
end

function mraidnt.DriverUnload()
    DbgPrint("MegaRAID: Unloading")
    
    for deviceName, array in pairs(mraidnt.Arrays) do
        if array and array.device and array.device.flush then
            pcall(array.device.flush)
        end
        _G.Mm.NonPagedPool[deviceName] = nil
    end
    
    _G.Mm.NonPagedPool["\\Driver\\MegaRAID"] = nil
    DbgPrint("MegaRAID: Unloaded successfully")
end

return mraidnt.DriverEntry()