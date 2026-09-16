-- RedstoneShell Windows NT Executive - Plug and Play Manager
-- Copyright (C) 2026 RedstoneShell
local pnp = {}
local etw = nil

pnp.DeviceTree = {}
pnp.ResourceList = {}
pnp.EnumerationCount = 0
pnp.EventQueue = {}
pnp.InterruptObject = nil

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

local function CreateDeviceExtension()
    return {
        WorkItem = {},
        StopWorker = false,
        WorkerActive = 0,
        StopEvent = {}
    }
end

local function MyTickWorker(Context)
    local devExt = Context
    if not devExt then return end

    if devExt.StopWorker then
        devExt.WorkerActive = 0
        if _G.KeSetEvent then
            _G.KeSetEvent(devExt.StopEvent, 0, false)
        end
        _G.DbgPrint("PnP Worker: Stopped")
        return
    end

    local hasWork = false

    if pnp.EnumerationCount == 0 then
        pnp.ScanForDevices()
        hasWork = true
    end

    if #pnp.EventQueue > 0 then
        pnp.ProcessQueue()
        hasWork = true
    end

    if _G.PnPMessages and #_G.PnPMessages > 0 then
        pnp.PumpMessages()
        hasWork = true
    end

    if hasWork and not devExt.StopWorker then
        if _G.ExQueueWorkItem then
            _G.ExQueueWorkItem(devExt.WorkItem, 1)
        end
    else
        devExt.WorkerActive = 0
        _G.DbgPrint("PnP Worker: Idle")
    end
end

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
        flags = 0x00000012,
        driverUnload = pnp.DriverUnload
    }

    _G.PnPManager = pnp
    _G.Mm.NonPagedPool["\\Driver\\PnPManager"] = driverObject

    if _G.RegisterShutdownDriver then
        _G.RegisterShutdownDriver("pnpmanager", pnp)
    end

    if _G.IoConnectInterrupt then
        pnp.InterruptObject = _G.IoConnectInterrupt(pnp.OnInterrupt)
        if pnp.InterruptObject then
            _G.DbgPrint("PnP Manager: Registered interrupt at \\Structures\\" .. pnp.InterruptObject)
        end
    end

    pnp.DeviceExtension = CreateDeviceExtension()
    pnp.StartWorker()

    return driverObject
end

function pnp.StartWorker()
    local devExt = pnp.DeviceExtension
    if not devExt then return false end

    devExt.StopWorker = false
    devExt.WorkerActive = 1

    if _G.KeInitializeEvent then
        _G.KeInitializeEvent(devExt.StopEvent, 0, false)
    end

    if _G.ExInitializeWorkItem then
        _G.ExInitializeWorkItem(devExt.WorkItem, MyTickWorker, devExt)
    end

    if _G.ExQueueWorkItem then
        _G.ExQueueWorkItem(devExt.WorkItem, 1)
        _G.DbgPrint("PnP: Worker started (WorkItem queued)")
        return true
    end

    _G.DbgPrint("PnP: WARNING - ExQueueWorkItem not available")
    return false
end

function pnp.StopWorker()
    local devExt = pnp.DeviceExtension
    if not devExt then return end

    devExt.StopWorker = true
    _G.DbgPrint("PnP: Worker stop requested")
end

function pnp.WakeWorker()
    local devExt = pnp.DeviceExtension
    if not devExt then return end
    if devExt.WorkerActive == 1 then return end

    devExt.WorkerActive = 1
    devExt.WorkItem.Inserted = false
    if _G.ExQueueWorkItem then
        _G.ExQueueWorkItem(devExt.WorkItem, 1)
    end
end

function pnp.OnInterrupt(struct, sig, addr, arg1, arg2, arg3, arg4)
    if sig == "component_added" or sig == "component_removed" then

        for _, evt in ipairs(pnp.EventQueue) do
            if evt.addr == addr and evt.sig == sig then
                _G.DbgPrint("PnP: Duplicate event ignored: " .. tostring(sig) .. " " .. tostring(addr))
                return
            end
        end

        table.insert(pnp.EventQueue, {
            sig = sig, addr = addr,
            arg1 = arg1, arg2 = arg2, arg3 = arg3, arg4 = arg4,
            timestamp = computer.uptime()
        })
        _G.DbgPrint("PnP: Event queued: " .. tostring(sig) .. " addr=" .. tostring(addr))
        pnp.WakeWorker()
    end
end

function pnp.ProcessQueue()
    while #pnp.EventQueue > 0 do
        local evt = table.remove(pnp.EventQueue, 1)

        _G.DbgPrint("PnP: Processing event: " .. tostring(evt.sig) ..
            " addr=" .. tostring(evt.addr))

        if evt.sig == "component_added" then
            if pnp.DeviceTree[evt.addr] then
                _G.DbgPrint("PnP: Device already in tree, skipping arrival: " .. tostring(evt.addr))
            else
                pnp.ConfigureDevice(evt.addr, evt.arg1, false)
            end
        elseif evt.sig == "component_removed" then
            if not pnp.DeviceTree[evt.addr] then
                _G.DbgPrint("PnP: Device not in tree, skipping removal: " .. tostring(evt.addr))
            else
                pnp.HandleRemoval(evt.addr)
            end
        end
    end
end

function pnp.HandleRemoval(addr)
    local device = pnp.DeviceTree[addr]
    if not device then return end

    _G.DbgPrint("PnP: Device removal -> " .. tostring(device.friendlyName))
    pnp.NotifyDeviceChange(device, "Removal")

    if device.resources.irq then
        pnp.ResourceList["IRQ" .. device.resources.irq] = nil
    end
    if device.resources.dma then
        pnp.ResourceList["DMA" .. device.resources.dma] = nil
    end

    pnp.DeviceTree[addr] = nil
end

function pnp.ScanForDevices()
    _G.DbgPrint("PnP Manager: Performing initial bus enumeration...")

    for addr, devType in component.list() do
        pnp.ConfigureDevice(addr, devType, true)
    end

    _G.DbgPrint("PnP Manager: Initial enumeration complete")
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

    _G.DbgPrint(string.format("PnP Manager: Device configured -> %s [%s]",
        device.friendlyName, classGuid:sub(1,8)))

    if not isInitialBoot then
        pnp.NotifyDeviceChange(device, "Arrival")

        if device.service then
            pnp.LoadDeviceDriver(device)
        end
    end
end

function pnp.AssignResources(device)
    local irq = 3
    local attempts = 0
    local maxAttempts = 64

    while pnp.ResourceList["IRQ" .. irq] and attempts < maxAttempts do
        irq = irq + 1
        if irq > 15 then irq = 3 end
        attempts = attempts + 1
    end

    if attempts < maxAttempts then
        device.resources.irq = irq
        pnp.ResourceList["IRQ" .. irq] = device.address
    else
        _G.DbgPrint("PnP: WARNING - No free IRQ for " .. tostring(device.address))
    end

    if device.type == "filesystem" or device.type == "disk_drive" then
        local dma = 1
        local dmaAttempts = 0
        while pnp.ResourceList["DMA" .. dma] and dmaAttempts < 16 do
            dma = dma + 1
            if dma > 7 then dma = 1 end
            dmaAttempts = dmaAttempts + 1
        end

        if dmaAttempts < 16 then
            device.resources.dma = dma
            pnp.ResourceList["DMA" .. dma] = device.address
        end
    end
end

function pnp.WriteToRegistry(device)
    if not _G.regedit0 then return end

    local path = string.format(
        "\\Software\\RedstoneShell\\Windows\\Enum\\%s\\%s",
        device.classGuid,
        device.address:gsub("-", "")
    )

    _G.regedit0.SetValue(path, "HardwareID", device.hardwareId)
    _G.regedit0.SetValue(path, "FriendlyName", device.friendlyName)
    _G.regedit0.SetValue(path, "Status", device.status)
    _G.regedit0.SetValue(path, "Instance", device.instance)

    if device.resources.irq then
        _G.regedit0.SetValue(path .. "\\Resources", "IRQ", device.resources.irq)
    end
    if device.resources.dma then
        _G.regedit0.SetValue(path .. "\\Resources", "DMA", device.resources.dma)
    end
    if device.service then
        _G.regedit0.SetValue(path, "Service", device.service)
    end
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

            local co = coroutine.create(function()
                local start = computer.uptime()
                while computer.uptime() - start < 3 do
                    coroutine.yield()
                end

                pcall(function()
                    gdi.SetBackgroundColor(hdc, 0x008080)
                    gdi.SetTextColor(hdc, 0x008080)
                    gdi.TextOut(hdc, xPos, yPos, text)
                end)
            end)

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

function pnp.PumpMessages()
    if not _G.PnPMessages then return end

    for i = #_G.PnPMessages, 1, -1 do
        local co = _G.PnPMessages[i]
        if coroutine.status(co) == "dead" then
            table.remove(_G.PnPMessages, i)
        else
            local ok, err = coroutine.resume(co)
            if not ok then
                _G.DbgPrint("PnP: Message coroutine error: " .. tostring(err))
                table.remove(_G.PnPMessages, i)
            end
        end
    end
end

function pnp.DriverUnload()
    _G.DbgPrint("PnP Manager: Subsystem shutting down safely.")

    pnp.StopWorker()

    if pnp.InterruptObject and _G.IoDisconnectInterrupt then
        _G.IoDisconnectInterrupt(pnp.InterruptObject)
        pnp.InterruptObject = nil
    end

    _G.PnPManager = nil
    return true
end

return pnp.DriverEntry()