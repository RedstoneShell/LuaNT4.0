local acpi = {}
local regedit = LdrLoadDll("Windows/System32/regedit.lua")

acpi.PowerState = {
    S0 = "Working",      -- Norm Work
    S1 = "Sleep",        -- CPU zzz
    S2 = "Deep Sleep",   -- deep zzz
    S3 = "Standby",      -- standby (RAM save)
    S4 = "Hibernate",
    S5 = "Soft Off"      -- Pwr Off
}

acpi.CurrentState = "S0"

function acpi.SetPowerState(state)
    DbgPrint("ACPI: Changing power state to " .. state)
    
    if state == "S3" or state == "Standby" then
        acpi.CurrentState = "S3"
        DbgPrint("ACPI: Entering standby mode...")
        acpi.SaveSystemState()
        return true
    elseif state == "S4" or state == "Hibernate" then
        acpi.CurrentState = "S4"
        DbgPrint("ACPI: Hibernating...")
        acpi.Hibernate()
        return true
    elseif state == "S5" or state == "Shutdown" then
        acpi.CurrentState = "S5"
        DbgPrint("ACPI: Shutting down...")
        computer.shutdown()
        return true
    elseif state == "Reboot" then
        DbgPrint("ACPI: Rebooting...")
        computer.shutdown(true)
        return true
    end
    
    return false
end

function acpi.SaveSystemState()
    local hiberFile = io.open("/hiberfil.sys", "wb")
    if hiberFile then
        local memoryDump = {
            pagedPool = _G.Mm.PagedPool,
            nonPagedPool = _G.Mm.NonPagedPool,
            registry = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SYSTEM"],
            timestamp = computer.uptime()
        }
        
        local serialized = table.serialize(memoryDump)
        hiberFile:write(serialized)
        hiberFile:close()
        DbgPrint("ACPI: System state saved to hiberfil.sys")
        return true
    end
    return false
end

function acpi.RestoreFromHibernate()
    local hiberFile = io.open("/system/hiberfil.sys", "rb")
    if hiberFile then
        local data = hiberFile:read("*all")
        hiberFile:close()
        
        local memoryDump = table.unserialize(data)
        if memoryDump then
            _G.Mm.PagedPool = memoryDump.pagedPool
            _G.Mm.NonPagedPool = memoryDump.nonPagedPool
            DbgPrint("ACPI: System state restored from hibernation")
            return true
        end
    end
    return false
end

function acpi.PowerButtonPressed()
    DbgPrint("ACPI: Power button pressed")
    
    local powerAction = regedit.GetValue(
        "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\ACPI",
        "PowerButtonAction"
    ) or "Shutdown"
    
    if powerAction == "Shutdown" then
        acpi.SetPowerState("S5")
    elseif powerAction == "Sleep" then
        acpi.SetPowerState("S3")
    elseif powerAction == "Hibernate" then
        acpi.SetPowerState("S4")
    elseif powerAction == "Nothing" then
        DbgPrint("ACPI: Power button ignored")
    end
end

function acpi.SetWakeTimer(seconds)
    local wakeTime = computer.uptime() + seconds
    _G.Mm.NonPagedPool["\\ACPI\\WakeTimer"] = wakeTime
    
    DbgPrint(string.format("ACPI: Wake timer set to %d seconds", seconds))
    return true
end

function acpi.DriverEntry()
    DbgPrint("ACPI.sys: Initializing Advanced Configuration and Power Interface")
    local acpiDevice = {
        version = "1.0",
        vendor = "RedstoneShell",
        setPowerState = acpi.SetPowerState,
        powerButton = acpi.PowerButtonPressed,
        setWakeTimer = acpi.SetWakeTimer,
        systemInfo = {
            memory = {
                total = computer.totalMemory(),
                free = computer.freeMemory()
            },
            uptime = computer.uptime()
        }
    }
    _G.Mm.NonPagedPool["\\Device\\ACPI"] = acpiDevice
    regedit.SetValue(
        "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\ACPI",
        "Version",
        "1.0"
    )
    regedit.SetValue(
        "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\ACPI",
        "WakeOnLAN",
        false
    )
    if _G.RegisterShutdownDriver then
        _G.RegisterShutdownDriver("acpi", acpi)
    end
    
    DbgPrint("ACPI.sys: Initialization complete")
    return acpiDevice
end

function acpi.DriverUnload()
    DbgPrint("ACPI.sys: Unloading")
    
    local powerState = acpi.CurrentState or "S0"
    regedit.SetValue(
        "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\ACPI",
        "LastPowerState",
        powerState
    )
    regedit.Flush()
    
    _G.Mm.NonPagedPool["\\Device\\ACPI"] = nil
    DbgPrint("ACPI.sys: Unloaded successfully")
end


return acpi.DriverEntry()