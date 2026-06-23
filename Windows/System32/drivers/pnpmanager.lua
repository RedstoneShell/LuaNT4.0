-- ====================================================================
-- RedstoneShell Windows NT Executive - Plug and Play Manager (pnpmanager.lua)
-- Build: 1381 (Windows NT 4.0 Subsystem)
-- Copyright (C) 2026 RedstoneShell Inc.
-- ====================================================================

local pnp = {}
local etw = nil

pnp.DeviceTree = {}
pnp.ResourceList = {}
pnp.EnumerationCount = 0

pnp.GUID = {
    DISK_DRIVE     = "{4d36e967-e325-11ce-bfc1-08002be10318}",
    NETWORK        = "{4d36e972-e325-11ce-bfc1-08002be10318}", 
    DISPLAY        = "{4d36e968-e325-11ce-bfc1-08002be10318}",
    KEYBOARD       = "{4d36e96b-e325-11ce-bfc1-08002be10318}",
    MOUSE          = "{4d36e96f-e325-11ce-bfc1-08002be10318}",
    SYSTEM         = "{4d36e97d-e325-11ce-bfc1-08002be10318}",
    PROCESSOR      = "{50127dc3-0f36-415e-a6cc-4cb3be910b65}"
}

pnp.ComponentToClass = {
    filesystem  = pnp.GUID.DISK_DRIVE,
    disk_drive  = pnp.GUID.DISK_DRIVE,
    internet    = pnp.GUID.NETWORK,
    tunnel      = pnp.GUID.NETWORK,
    gpu         = pnp.GUID.DISPLAY,
    screen      = pnp.GUID.DISPLAY,
    keyboard    = pnp.GUID.KEYBOARD,
    eeprom      = pnp.GUID.SYSTEM,
    cpu         = pnp.GUID.PROCESSOR
}

pnp.DriverMap = {
    filesystem  = "disk.lua",
    disk_drive  = "disk.lua",
    internet    = "ndiswan.lua",
    tunnel      = "ndiswan.lua",
    gpu         = "videoprt.lua",
    screen      = "videoprt.lua",
    keyboard    = "kbdclass.lua"
}

function pnp.DriverEntry()
    _G.DbgPrint("PnP Manager: Initializing Windows NT Plug-and-Play Subsystem...")
    
    local err
    etw, err = _G.LdrLoadDll("Windows/System32/etw.lua")
    if not etw then
        _G.DbgPrint("PnP Manager: CRITICAL - Failed to load ETW API: " .. tostring(err))
        return nil
    end

    local driverObject = {
        name = "\\Driver\\PnPManager",
        flags = 0x00000012, -- DO_BUFFERED_IO | DO_POWER_PAGABLE
        driverUnload = pnp.DriverUnload
    }
    
    _G.PnPManager = pnp
    _G.Mm.NonPagedPool["\\Driver\\PnPManager"] = driverObject
    
    if _G.RegisterShutdownDriver then
        _G.RegisterShutdownDriver("pnpmanager", pnp)
    end
    
    pnp.ScanForDevices()
    
    return driverObject
end

function pnp.ScanForDevices()
    _G.DbgPrint("PnP Manager: Performing initial bus enumeration...")
    for addr, devType in component.list() do
        pnp.ConfigureDevice(addr, devType, true)
    end
end

function pnp.ConfigureDevice(addr, devType, isInitialBoot)
    local classGuid = pnp.ComponentToClass[devType] or pnp.GUID.SYSTEM
    
    local device = {
        address = addr,
        type = devType,
        classGuid = classGuid,
        instance = pnp.EnumerationCount,
        status = "Started",
        hardwareId = string.format("OC\\%s_%s", devType:upper(), addr:sub(1,4):upper()),
        friendlyName = string.format("%s (%s)", devType:upper(), addr:sub(1,4)),
        service = pnp.DriverMap[devType],
        resources = {}
    }
    
    pnp.AssignResources(device)
    
    pnp.DeviceTree[addr] = device
    pnp.EnumerationCount = pnp.EnumerationCount + 1
    
    pnp.WriteToRegistry(device)
    
    _G.DbgPrint(string.format("PnP Manager: Device configured -> %s [%s]", device.friendlyName, classGuid:sub(1,8)))
    
    if not isInitialBoot then
        pnp.NotifyDeviceChange(device, "Arrival")
        if device.service then
            pnp.LoadDeviceDriver(device)
        end
    end
end

function pnp.AssignResources(device)
    local irq = math.random(3, 15)
    while pnp.ResourceList["IRQ" .. irq] do irq = math.random(3, 15) end
    device.resources.irq = irq
    pnp.ResourceList["IRQ" .. irq] = device.address

    if device.type == "filesystem" or device.type == "disk_drive" then
        local dma = math.random(1, 7)
        while pnp.ResourceList["DMA" .. dma] do dma = math.random(1, 7) end
        device.resources.dma = dma
        pnp.ResourceList["DMA" .. dma] = device.address
    end
end

function pnp.WriteToRegistry(device)
    if not _G.regedit then return end
    local path = string.format("\\Software\\RedstoneShell\\Windows\\Enum\\%s\\%s", device.classGuid, device.address:gsub("-", ""))
    
    _G.regedit0.SetValue(path, "HardwareID", device.hardwareId)
    _G.regedit0.SetValue(path, "FriendlyName", device.friendlyName)
    _G.regedit0.SetValue(path, "Status", device.status)
    _G.regedit0.SetValue(path, "Instance", device.instance)
    
    if device.resources.irq then _G.regedit0.SetValue(path .. "\\Resources", "IRQ", device.resources.irq) end
    if device.resources.dma then _G.regedit0.SetValue(path .. "\\Resources", "DMA", device.resources.dma) end
    if device.service then _G.regedit0.SetValue(path, "Service", device.service) end
end

function pnp.LoadDeviceDriver(device)
    if not device.service then return end
    _G.DbgPrint("PnP Manager: Requesting driver " .. device.service)
    
    local drv, err = _G.LdrLoadDll("Windows/System32/drivers/" .. device.service)
    if drv then
        device.driver = drv
        _G.DbgPrint("PnP Manager: Driver " .. device.service .. " bound successfully.")
    else
        _G.DbgPrint("PnP Manager: Driver attachment failed: " .. tostring(err))
    end
end

function pnp.PollEvents(sig, addr, arg1)
    local arrivalFilter = etw.PlFltr("component_added")
    local removalFilter = etw.PlFltr("component_removed")
    
    if arrivalFilter(sig, addr, arg1) then
        _G.DbgPrint("PnP Event: Hardware arrival detected on bus -> " .. tostring(addr))
        pnp.ConfigureDevice(addr, arg1, false)
        
    elseif removalFilter(sig, addr, arg1) then
        _G.DbgPrint("PnP Event: Hardware surprise removal -> " .. tostring(addr))
        local device = pnp.DeviceTree[addr]
        if device then
            pnp.NotifyDeviceChange(device, "Removal")
            if device.resources.irq then pnp.ResourceList["IRQ" .. device.resources.irq] = nil end
            if device.resources.dma then pnp.ResourceList["DMA" .. device.resources.dma] = nil end
            pnp.DeviceTree[addr] = nil
        end
    end
end

function pnp.NotifyDeviceChange(device, action)
    local gdi = _G.KRNL_GDI32
    if gdi then
        local hdc = gdi.GetDC(0)
        if hdc then
            local screenWidth = _G.HAL and _G.HAL.w or 80
            local screenHeight = _G.HAL and _G.HAL.h or 25
            
            local text = string.format("PnP: %s -> %s", action:upper(), device.friendlyName)
            
            local xPos = screenWidth - #text - 1
            local yPos = screenHeight - 5
            
            gdi.SetTextColor(hdc, action == "Arrival" and 0x00FF00 or 0xFF0000)
            gdi.TextOut(hdc, xPos, yPos, text)
            
            local function ClearMessage()
                gdi.SetBackgroundColor(hdc, 0x008080)
                gdi.SetTextColor(hdc, 0x008080)
                gdi.TextOut(hdc, xPos, yPos, text)
            end
            
            local function delayedClear()
                local start = computer.uptime()
                while computer.uptime() - start < 3 do
                    computer.pullSignal(0.1)
                end
                pcall(ClearMessage)
            end
            
            local co = coroutine.create(delayedClear)
            coroutine.resume(co)
            if not _G.PnPMessages then
                _G.PnPMessages = {}
            end
            table.insert(_G.PnPMessages, co)
        end
    end
    
    if device.type == "filesystem" or device.type == "disk_drive" then
        if _G.KiInitializeFileSystems then
            pcall(_G.KiInitializeFileSystems)
        end
    end
end

function pnp.DriverUnload()
    _G.DbgPrint("PnP Manager: Subsystem shutting down safely.")
    _G.PnPManager = nil
    return true
end

return pnp.DriverEntry()