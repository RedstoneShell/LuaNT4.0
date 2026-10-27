local dat4mm = {}
local regedit = LdrLoadDll("Windows/System32/regedit.lua")

dat4mm.Tapes = {}

dat4mm.Config = {
    MaxTransferSize = 256,
    CurrentTape = nil,
    DDSGenerations = {
        DDS1 = 2 * 1024 * 1024,
        DDS2 = 4 * 1024 * 1024,
        DDS3 = 12 * 1024 * 1024,
        DDS4 = 20 * 1024 * 1024,
        DDS5 = 36 * 1024 * 1024
    }
}

function dat4mm.CreateTapeDevice(component, address)
    local device = {
        type = "4mmDAT",
        address = address,
        component = component,

        isEnd = function()
            return component.isEnd()
        end,

        isReady = function()
            return component.isReady()
        end,

        getSize = function()
            return component.getSize()
        end,

        getPosition = function()
            return component.getPosition()
        end,

        setLabel = function(label)
            DbgPrint("4mmDAT: setLabel('" .. tostring(label) .. "') at " .. address)
            return component.setLabel(label)
        end,

        getLabel = function()
            return component.getLabel()
        end,

        seek = function(length)
            DbgPrint("4mmDAT: seek(" .. tostring(length) .. ") at " .. address)
            return component.seek(length)
        end,

        read = function(length)
            local n = length or 1
            return component.read(n)
        end,

        write = function(data)
            DbgPrint("4mmDAT: write(" .. type(data) .. ") at " .. address)
            return component.write(data)
        end,

        play = function()
            DbgPrint("4mmDAT: play() at " .. address)
            return component.play()
        end,

        stop = function()
            DbgPrint("4mmDAT: stop() at " .. address)
            return component.stop()
        end,

        setSpeed = function(speed)
            DbgPrint("4mmDAT: setSpeed(" .. tostring(speed) .. ") at " .. address)
            return component.setSpeed(speed)
        end,

        setVolume = function(volume)
            DbgPrint("4mmDAT: setVolume(" .. tostring(volume) .. ") at " .. address)
            return component.setVolume(volume)
        end,

        getState = function()
            return component.getState()
        end,

        getDDSGeneration = function()
            local size = component.getSize()
            for gen, capacity in pairs(dat4mm.Config.DDSGenerations) do
                if size <= capacity then
                    return gen, capacity
                end
            end
            return "UNKNOWN", size
        end
    }

    return device
end

function dat4mm.ScanAndInitialize()
    DbgPrint("4mmDAT: Scanning Tape Drives...")

    local foundTapes = {}
    local processedAddrs = {}

    for addr in component.list("tape_drive") do
        if not processedAddrs[addr] then
            local component = component.proxy(addr)
            if component then
                local device = dat4mm.CreateTapeDevice(component, addr)
                local gen, cap = device.getDDSGeneration()
                table.insert(foundTapes, {
                    address = addr,
                    device = device,
                    generation = gen,
                    capacity = cap
                })
                processedAddrs[addr] = true
                DbgPrint(string.format(
                    "4mmDAT: Founded steamer at addr %s (gen: %s)", addr, gen))
            else
                DbgPrint("4mmDAT: Cannot get proxy for " .. addr)
            end
        end
    end

    for i, tape in ipairs(foundTapes) do
        local deviceName = "\\Device\\4mmDAT" .. i

        _G.Mm.NonPagedPool[deviceName] = tape.device
        dat4mm.Tapes[deviceName] = tape

        DbgPrint(string.format("4mmDAT: Reg %s (addr: %s, gen: %s)",
            deviceName, tape.address, tape.generation))

        if regedit and regedit.SetValue then
            local regPath = "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\4mmDAT\\Device" .. i
            regedit.SetValue(regPath, "DeviceName", deviceName)
            regedit.SetValue(regPath, "SourceAddress", tape.address)
            regedit.SetValue(regPath, "DDSGeneration", tape.generation)
            regedit.SetValue(regPath, "Capacity", tape.capacity)
        end
    end

    if #foundTapes == 0 then
        DbgPrint("4mmDAT: Don't found any streamer :(")
    else
        DbgPrint(string.format("4mmDAT: Init %d streamers", #foundTapes))
    end

    return foundTapes
end

function dat4mm.DriverEntry()
    local tapes = dat4mm.ScanAndInitialize()
    local driverObject = {
        name = "4mmDAT",
        version = "1.0",
        tapes = dat4mm.Tapes,

        GetTapeInfo = function(index)
            return dat4mm.Tapes["\\Device\\4mmDAT" .. index]
        end,

        GetTapeCount = function()
            return #tapes
        end,

        Rescan = function()
            DbgPrint("4mmDAT: Rescanning tape drives...")
            return dat4mm.ScanAndInitialize()
        end
    }

    _G.Mm.NonPagedPool["\\Driver\\4mmDAT"] = driverObject

    if _G.RegisterShutdownDriver then
        _G.RegisterShutdownDriver("4mmdat", dat4mm)
    end

    DbgPrint("4mmDAT: Init")
    return driverObject
end

function dat4mm.DriverUnload()
    for deviceName, tape in pairs(dat4mm.Tapes) do
        if tape and tape.device and tape.device.stop then
            pcall(tape.device.stop)
        end
        _G.Mm.NonPagedPool[deviceName] = nil
    end

    _G.Mm.NonPagedPool["\\Driver\\4mmDAT"] = nil
    DbgPrint("4mmDAT: Unload")
end

return dat4mm.DriverEntry()