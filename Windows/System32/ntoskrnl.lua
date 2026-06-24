_G.KeSystemState = "INIT"
_G.Drives = {}
_G.DbgPrint("KePhase0HasOccurred: Multi-processor configuration")
_G.NtOpenFile = function(path)
    local pc_io=component.proxy(computer.getBootAddress())
    local handle, err = pc_io.open(path, "rb")
    if not handle then
        return nil, "Could not open "..path..": "..tostring(err)
    end
    local buf = ""
    repeat
        local chunk = pc_io.read(handle, math.huge)
        buf = buf .. (chunk or "")
    until not chunk
    pc_io.close(handle)
    local func, lda_err = load(buf, "="..path, "t", _G)
    if not func then
        return nil, "Syntax error in " .. path .. ": " .. tostring(lda_err)
    end
    return func
end
_G.LdrLoadDll = function (path)
    local code, err = NtOpenFile(path)
    if not code then
        if not code then
            return nil, "STATUS_DLL_NOT_FOUND"
        end
    end
    local result = table.pack(pcall(code))
    if result[1] then
        return table.unpack(result, 2, result.n)
    else
        return nil, "STATUS_DLL_INIT_FAILED"
    end
end
_G.DbgPrint("Number of Processors: 1, Revision: 060f, Stepping: 0b")
_G.DbgPrint("Ex: Phase 1 Initialization Started")
_G.DbgPrint("Mm: Phase 1 Initialization Started")

function _G.KeDelayExecutionThread(seconds)
    local start = computer.uptime()
    local duration = seconds
    while duration > 0 do
        computer.pullSignal(duration)
        duration = seconds - (computer.uptime() - start)
    end
end

_G.Mm = {
    TotalPhysicalMemory = computer.totalMemory(),
    SystemPool = {},
    PagedPool = {},
    NonPagedPool = {},
    PageFileSize = 0,
    PageFilePath = "pagefile.sys"
}

DbgPrint("Mm: Allocated memory 0x0-"..string.format("0x%x (%d KB)", Mm.TotalPhysicalMemory, Mm.TotalPhysicalMemory/1024))

local regedit, err9 = LdrLoadDll("Windows/System32/regedit.lua")
if not regedit then
    KeBugCheckEx("0x00000067", "CONFIG_INITIALIZATION_FAILED", err9)
end
regedit.LoadHive()
if not _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\BCD00000000"] then
    _G.HAL.gpu.setBackground(0x0000FF)
    _G.HAL.gpu.fill(1,1,_G.HAL.w,_G.HAL.h, " ")
    _G.HAL.cursorY=1
    DbgPrint("Windows Boot Manager > Windows failed to start. A recent hardware or software change might be the cause.")
    DbgPrint("File: Windows\\System32\\config\\BCD")
    DbgPrint("Status: 0xc0000034")
    DbgPrint("Info: An error occurred while attempting to read the boot configuration data.")
    KeDelayExecutionThread(10)
    computer.shutdown(false)
end

-- NT BCD Config
DbgPrint("BCD: Parsing Boot Configuration Data entries...")

local bcdPath = "HKEY_LOCAL_MACHINE\\BCD00000000\\Objects\\{current}\\Elements"

local bcdBootLog = regedit.GetValue(bcdPath .. "\\BootLog", "ElementData")
if bcdBootLog == 1 or bcdBootLog == true then
    _G.DebugMode = true
    DbgPrint("BCD: Boot Logging enabled by configuration.")
else
    _G.DebugMode = false
end

local bcdSafeBoot = regedit.GetValue(bcdPath .. "\\SafeBoot", "ElementData")
if bcdSafeBoot=="true" then
    _G.KeSystemState = "SAFE_BOOT"
    DbgPrint("BCD: WARNING - Windows NT is booting in SAFE MODE (" .. tostring(bcdSafeBoot) .. ")")
else
    _G.KeSystemState = "NORMAL"
end

DbgPrint("BCD: Press [F8] for Advanced Boot Options...")

local evapi = _G.LdrLoadDll("Windows/System32/etw.lua")

local bcdPath = "Objects\\{current}\\Elements"
local bootMenuTriggered = false

local signal = { evapi.ReadData(3.0, "key_down") }

if signal[1] == "key_down" then
    local char, code = signal[3], signal[4]
    if code == 66 or char == 115 then
        bootMenuTriggered = true
    end
end

if bootMenuTriggered then
    _G.HAL.gpu.setBackground(0x000000)
    _G.HAL.gpu.setForeground(0xFFFFFF)
    _G.HAL.gpu.fill(1, 1, _G.HAL.w, _G.HAL.h, " ")
    
    _G.HAL.gpu.set(5, 2, "ADVANCED BOOT OPTIONS - Windows NT 4.0 (Lua Port)")
    _G.HAL.gpu.set(5, 3, "Select alternative boot mode for " .. _G.KeSystemState)
    _G.HAL.gpu.set(5, 5, "1. Normal Startup")
    _G.HAL.gpu.set(5, 7, "2. Debug Mode (Enable verbose DbgPrint output)")
    _G.HAL.gpu.set(5, 9, "Selection: ")
    
    local selection = nil
    local selSignal = { evapi.ReadData(10.0, "key_down") }
    
    if selSignal[1] == "key_down" then
        local char = selSignal[3]
        if char == 49 or char == 50 then
            selection = char
        end
    end
    
    if selection == 50 then -- 2
        _G.DebugMode = true
        _G.HAL.cursorY=1
        regedit.SetValueEx("HKEY_LOCAL_MACHINE\\BCD00000000", bcdPath .. "\\BootLog", "ElementData", "true")
        DbgPrint("BCD: User enabled Boot Logging via Boot Menu.")
    else
        _G.DebugMode=false
        DbgPrint("BCD: Defaulting to Normal Startup (Timeout or Key 1).")
    end
    
    _G.HAL.gpu.setBackground(0x000000)
    _G.HAL.gpu.fill(1, 1, _G.HAL.w, _G.HAL.h, " ")
end
DbgPrint("BCD: Boot configuration applied successfully.")

DbgPrint("CM: Loading hive Windows\\System32\\config\\SYSTEM...")
local gdi32, err10 = LdrLoadDll("Windows/System32/gdi32.lua")
if err10 then error("NTOSKRNL failed to load GDI32, video-shell activation impossible.") end
if not _G.HAL.gpu then error("NTOSKRNL failed to load HAL table, execution terminated.") end
local screen_gdi = gdi32.GdiDllInitialize(_G.HAL.gpu)
_G.KRNL_GDI32=gdi32
_G.regedit0=regedit

if regedit.KeyExists("\\Software\\RedstoneShell\\Windows\\CurrentVersion\\WinSAT", nil) then
    local winsat,_ = LdrLoadDll("Windows/System32/winsat.lua")
    winsat.start()
end

-- Multi-task init
DbgPrint("KE: KiInitializeDispatcher - Allocating 32 thread priority queues")
local ReadyQueues = {}
for i = 0, 31 do ReadyQueues[i] = {} end

_G.PspActiveProcessList = {}
_G.CurrentThread = nil

-- Deferred Procedure Call Queue
_G.Prcb = {
    IdleCount = 0,
    CycleTime = 0,
    DpcQueue = {}
}

function _G.KeInitializeDpc(dpcObject, deferredRoutine, deferredContext)
    dpcObject.DeferredRoutine = deferredRoutine
    dpcObject.DeferredContext = deferredContext
    dpcObject.SystemArgument1 = nil
    dpcObject.SystemArgument2 = nil
    dpcObject.Inserted = false
end

function _G.KeInsertQueueDpc(dpcObject, sysArg1, sysArg2)
    if dpcObject.Inserted then return false end
    
    dpcObject.SystemArgument1 = sysArg1
    dpcObject.SystemArgument2 = sysArg2
    dpcObject.Inserted = true
    
    table.insert(_G.Prcb.DpcQueue, dpcObject)
    return true
end

function _G.KiDispatchInterrupt()
    while #_G.Prcb.DpcQueue > 0 do
        local dpc = table.remove(_G.Prcb.DpcQueue, 1)
        dpc.Inserted = false
        local status, err = pcall(dpc.DeferredRoutine, 
            dpc, 
            dpc.DeferredContext, 
            dpc.SystemArgument1, 
            dpc.SystemArgument2
        )
        if not status then
            _G.DbgPrint("KE: DPC_WATCHDOG_VIOLATION - Exception in DPC Routine: " .. tostring(err))
            _G.KeBugCheckEx(
                "0x00000133 (DPC_WATCHDOG_VIOLATION)", 
                "0x0000000000000000",
                "Exception in DPC:\n" .. tostring(err)
            )
        end
    end
end

-- END

local HIGH_PRIORITY    = 31
local REALTIME_PRIORITY= 16
local NORMAL_PRIORITY  = 8
local IDLE_PRIORITY    = 0

function _G.KiDispatcherDestroy()
    _G.DbgPrint("KE: KiDispatcherDestroy - Unregistering scheduler and freezing threads.")
    for i = 0, 31 do
        ReadyQueues[i] = {}
    end
    _G.PspActiveProcessList = {}
    _G.CurrentThread = nil
    _G.DispatcherActive = false
    _G.DbgPrint("KE: KiDispatcherDestroy - Core execution queues destroyed. System is single-tasking now.")
end

function _G.PsCreateSystemThread(path, name, priorityClass, token)
    if _G.DispatcherActive == false then return false end
    
    local chunk, err = _G.NtOpenFile(path)
    if not chunk then
        _G.DbgPrint("PS: Failed to load " .. name .. ": " .. tostring(err))
        return false
    end

    local chunkEnv = getfenv and getfenv(chunk) or _G

    local thread = {
        pid = #_G.PspActiveProcessList + 1,
        name = name,
        co = coroutine.create(chunk),
        basePriority = priorityClass or NORMAL_PRIORITY,
        currentPriority = priorityClass or NORMAL_PRIORITY,
        quantumLeft = 6,
        token = token or { name = "SYSTEM", group = "SYSTEM" },
        env = chunkEnv,
        args = chunkEnv.argv
    }

    table.insert(_G.PspActiveProcessList, thread)
    table.insert(ReadyQueues[thread.currentPriority], thread)
    
    _G.DbgPrint("KE: Created Thread '" .. name .. "' at Priority " .. thread.basePriority)
    return thread
end

function _G.PsTerminateThread(pid)
    for i, thread in ipairs(_G.PspActiveProcessList) do
        if thread.pid == pid then
            KiTerminateThread(thread, thread.currentPriority)
            return true
        end
    end
    return false
end

function _G.PsSetPriority(pid, newPriority)
    for _, thread in ipairs(_G.PspActiveProcessList) do
        if thread.pid == pid then
            for i, t in ipairs(ReadyQueues[thread.currentPriority]) do
                if t == thread then 
                    table.remove(ReadyQueues[thread.currentPriority], i) 
                    break 
                end
            end
            
            thread.currentPriority = newPriority
            table.insert(ReadyQueues[newPriority], thread)
            return true
        end
    end
    return false
end

function KiSelectNextThread()
    if _G.DispatcherActive == false then return nil, 0 end
    for prio = 31, 0, -1 do
        if #ReadyQueues[prio] > 0 then
            return ReadyQueues[prio][1], prio
        end
    end
    return nil, 0
end

function KiTerminateThread(thread, prio)
    for i, t in ipairs(ReadyQueues[prio]) do
        if t == thread then table.remove(ReadyQueues[prio], i) break end
    end
    for i, t in ipairs(_G.PspActiveProcessList) do
        if t == thread then 
            table.remove(_G.PspActiveProcessList, i) 
            break 
        end
    end
    _G.MmZeroThreadMemory(thread)
end

_G.DispatcherActive = true

_G.PsCreateSystemThread("Windows/System32/idle.lua", "System Idle Process", IDLE_PRIORITY)
DbgPrint("KE: KiInitializeScheduler - SystemIdleProcess registered at Priority 0.")

-- LuaNT Garbage Collector. Create by RedstoneShell. DO NOT CHANGE OR SYSTEM CAN WORK UNSTABLE
_G.GCInProgress = false
function _G.MmZeroThreadMemory(thread)
    if not thread then return end

    _G.DbgPrint(
        "MM: Freeing resources for Thread: "
        .. tostring(thread.name)
    )

    thread.co = nil
    thread.args = nil
    thread.env = nil

    for k in pairs(thread) do
        thread[k] = nil
    end
end

_G.ThreadGC = {
    Enabled = true,
    Interval = 100,
    Counter = 0,
    MaxCrashes = 1,
    CrashHistory = {}
}

function _G.KiCheckThreadHealth(thread)
    if not thread or not thread.co then return false end
    
    local status = coroutine.status(thread.co)
    
    if status == "dead" then
        _G.DbgPrint(string.format("KE: Thread %s (PID: %d) has finished normally.", 
            thread.name, thread.pid))
        return "dead"
    end
    
    return "alive"
end

function _G.KiCleanDeadThreads()
    if _G.GCInProgress then return 0 end
    _G.GCInProgress = true
    
    if not _G.DispatcherActive then 
        _G.GCInProgress = false
        return 0 
    end
    
    local deadThreads = {}
    
    for i, thread in ipairs(_G.PspActiveProcessList) do
        local status = _G.KiCheckThreadHealth(thread)
        if status == "dead" then
            table.insert(deadThreads, thread)
        end
    end
    
    for _, thread in ipairs(deadThreads) do
        _G.DbgPrint(string.format("KE: GC - Cleaning dead thread %s (PID: %d)", 
            thread.name, thread.pid))
        
        for prio = 0, 31 do
            for i, t in ipairs(ReadyQueues[prio]) do
                if t == thread then
                    table.remove(ReadyQueues[prio], i)
                    break
                end
            end
        end
        
        for i, t in ipairs(_G.PspActiveProcessList) do
            if t == thread then
                table.remove(_G.PspActiveProcessList, i)
                break
            end
        end
        
        _G.MmZeroThreadMemory(thread)
    end
    
    _G.GCInProgress = false
    return #deadThreads
end

function _G.KiHandleCrashedThread(thread, err)
    if not thread then return end
    
    if not _G.ThreadGC.CrashHistory[thread.pid] then
        _G.ThreadGC.CrashHistory[thread.pid] = 0
    end
    _G.ThreadGC.CrashHistory[thread.pid] = _G.ThreadGC.CrashHistory[thread.pid] + 1
    
    _G.DbgPrint(string.format("KE: Thread %s crashed (PID: %d) - Error: %s", 
        thread.name, thread.pid, tostring(err)))
    
    if _G.ThreadGC.CrashHistory[thread.pid] >= _G.ThreadGC.MaxCrashes then
        _G.DbgPrint(string.format("KE: Thread %s (PID: %d) exceeded crash limit - terminating.", 
            thread.name, thread.pid))
        _G.PsTerminateThread(thread.pid)
        _G.ThreadGC.CrashHistory[thread.pid] = nil
    else
        for prio = 0, 31 do
            for i, t in ipairs(ReadyQueues[prio]) do
                if t == thread then
                    table.remove(ReadyQueues[prio], i)
                    if _G.ThreadGC.Enabled then
                        thread.currentPriority = math.max(0, thread.currentPriority - 1)
                        table.insert(ReadyQueues[thread.currentPriority], thread)
                        _G.DbgPrint(string.format("KE: Thread %s (PID: %d) requeued with priority %d", 
                            thread.name, thread.pid, thread.currentPriority))
                    end
                    break
                end
            end
        end
    end
end


-- END



-- DRIVER INIT SEGMENT
local sysBootDisk = component.proxy(computer.getBootAddress())
local drivers = sysBootDisk.list("Windows/System32/drivers")

local bootDrivers = {}
local systemDrivers = {}
local autoDrivers = {}
local manualDrivers = {}
for _, file in ipairs(drivers) do
    if file:match("%.lua$") then
        local serviceName = file:gsub("%.lua$", "")
        local regPath = "\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Services\\" .. serviceName
        local startType = regedit.GetValue(regPath, "Start")
        if startType == nil then
            if serviceName=="mraidnt" then
                startType=0
                regedit.SetValue(regPath, "Start", 0)
                regedit.SetValue(regPath, "Type", 1)
                regedit.SetValue(regPath, "ErrorControl", 3)
                regedit.SetValue(regPath, "ImagePath", "system32\\drivers\\" .. file)
                regedit.SetValue(regPath, "Group", "SCSI miniport")
                regedit.SetValue(regPath, "DependOnService", "PCI,pci,disk")
                regedit.SetValue(regPath, "LastBootGood", 1)
                regedit.SetValue(regPath .. "\\Parameters", "NumberOfArrays", 0)
                regedit.SetValue(regPath .. "\\Parameters", "EnableCache", 1)
                regedit.SetValue(regPath .. "\\Parameters", "WritePolicy", "WriteBack")
                regedit.SetValue(regPath .. "\\Parameters", "DriverVersion", "4.23.03.00")
                regedit.SetValue(regPath .. "\\Parameters", "Vendor", "LSI Logic")
            elseif serviceName=="pnpmanager" then
                startType=0
                regedit.SetValue(regPath, "Start", 0)        -- Boot driver
                regedit.SetValue(regPath, "Type", 1)         -- Kernel driver
                regedit.SetValue(regPath, "ErrorControl", 1) -- Normal error handling
                regedit.SetValue(regPath, "ImagePath", "system32\\drivers\\pnpmanager.lua")
                regedit.SetValue(regPath, "Group", "PnP")
                regedit.SetValue(regPath, "DependOnService", "PCI,pci")
                regedit.SetValue(regPath, "LastBootGood", 1)
            else
                startType = 0
                regedit.SetValue(regPath, "Start", startType)
                regedit.SetValue(regPath, "Type", 1)
                regedit.SetValue(regPath, "ErrorControl", 1)
                regedit.SetValue(regPath, "ImagePath", "system32\\drivers\\" .. file)
                regedit.SetValue(regPath, "Group", "PPP")
                regedit.SetValue(regPath, "DependOnService", "PCI,pci")
                regedit.SetValue(regPath, "LastBootGood", 1)
                regedit.SetValue(regPath .. "\\Parameters", "Default", 0)
            end
        end

        if startType then
            startType = tonumber(startType) or startType
        end
        
        if startType == 0 then
            table.insert(bootDrivers, file)
        elseif startType == 1 then
            table.insert(systemDrivers, file)
        elseif startType == 2 then
            table.insert(autoDrivers, file)
        else
            table.insert(manualDrivers, file)
        end
    end
end

local function LoadDriver(file)
    local serviceName = file:gsub("%.lua$", "")
    local drv_path = "Windows/System32/drivers/" .. file
    local errorControl = regedit.GetValue("\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Services\\" .. serviceName, "ErrorControl")
    if errorControl == nil then
        errorControl = 1
    end
    DbgPrint("ntoskrnl: Loading driver \\SystemRoot\\System32\\drivers\\" .. file)
    
    local drv_code, err = NtOpenFile(drv_path)
    if not drv_code then
        DbgPrint("ntoskrnl: Failed to load " .. file .. " - " .. tostring(err))
        if serviceName=="acpi" then KeBugCheckEx("ACPI_BIOS_ERROR", "0x000000A5", "") return false end
        if errorControl == 3 then
            KeBugCheckEx("DRIVER_LOAD_FAILED", serviceName, err)
        elseif errorControl == 2 then
            regedit.SetValue(regPath, "LastBootGood", 0)
            return false
        elseif errorControl == 1 then
            regedit.SetValue(regPath, "LastBootGood", 0)
            return false
        else
            return false
        end
    end
    
    local ok, result = pcall(drv_code)
    if ok then
        _G.Mm.NonPagedPool["\\Device\\" .. serviceName] = result
        DbgPrint("ntoskrnl: Driver " .. serviceName .. " loaded successfully")
        return true
    else
        DbgPrint("ntoskrnl: Driver " .. serviceName .. " failed - " .. tostring(result))
        if serviceName=="acpi" then KeBugCheckEx("ACPI_BIOS_ERROR", "0x000000A5", "") return false end
        if errorControl == 3 then
            KeBugCheckEx("DRIVER_EXCEPTION", serviceName, result)
        elseif errorControl == 2 then
            regedit.SetValue(regPath, "LastBootGood", 0)
            DbgPrint("ntoskrnl: Driver " .. serviceName .. " marked as failed (Severe)")
            return false
        elseif errorControl == 1 then
            regedit.SetValue(regPath, "LastBootGood", 0)
            DbgPrint("ntoskrnl: Driver " .. serviceName .. " failed (Normal)")
            return false
        else
            DbgPrint("ntoskrnl: Driver " .. serviceName .. " failed (Ignored)")
            return false
        end
    end
end

-- Services setup
local rpcRegPath = "\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Services\\RpcSs"

if regedit.GetValue(rpcRegPath, "Start") == nil then
    DbgPrint("CM: RpcSs service keys not found. Writing to SYSTEM hive...")
    regedit.SetValue(rpcRegPath, "Start", 2)
    regedit.SetValue(rpcRegPath, "Type", 32)         -- 32 = WIN32_OWN_PROCESS
    regedit.SetValue(rpcRegPath, "ErrorControl", 3)   -- 3 = Critical
    regedit.SetValue(rpcRegPath, "ImagePath", "Windows/System32/RpcSs.lua")
    regedit.SetValue(rpcRegPath, "DisplayName", "Remote Procedure Call (RPC)")
    regedit.SetValue(rpcRegPath, "Description", "Provides process isolation and inter-process communication (IPC).")
end

DbgPrint("ntoskrnl: Loading BOOT drivers...")
for _, file in ipairs(bootDrivers) do
    LoadDriver(file)
end

DbgPrint("ntoskrnl: Spawning Service Control Manager thread...")
local scmThread = _G.PsCreateSystemThread(
    "Windows/System32/services.lua", 
    "services.exe", 
    8, 
    { name = "SYSTEM", group = "SERVICES" }
)

if scmThread then
    DbgPrint("ntoskrnl: SCM (services.exe) successfully spawned with PID: " .. scmThread.pid)
else
    KeBugCheckEx("STATUS_IMAGE_CHECKSUM_MISMATCH", "services.lua", "SCM failed to initialize")
end

function Mm.GetFreeMemory()
    return computer.freeMemory()
end

function Mm.AllocateNonPaged(key, value)
    Mm.NonPagedPool[key] = value
end

function Mm.AllocatePaged(key, value)
    local free = computer.freeMemory()
    if free < 1024*32 then
        DbgPrint("Mm: Too low memory, swapping "..key.." to "..Mm.PageFilePath)
        local f = io.open(Mm.PageFilePath, "a")
        if f then
            f:write(key .. "=" .. tostring(value) .. "\n")
            f:close()
        end
    else
        Mm.PagedPool[key] = value
    end
end

function _G.CreateNoMedia()
    return {
        open = function(a, b) return nil, "STATUS_NO_MEDIA_IN_DEVICE" end,
        list = function() return {} end,
        media = function() return nil end
    }
end

-- Memory Manager load data in RAM
Mm.AllocateNonPaged("\\Device\\Null", {
    open  = function() return 999 end,
    write = function() return true end,
    read  = function() return "" end,
    close = function() return true end,
    list  = function() return {} end
})

Mm.AllocateNonPaged("\\Device\\Video", {
    Address=_G.HAL.gpu, Mode="NT_GUI"
})

-- SCM RPC init (idk why, but this not creates RPC table in services.lua, and I moved this code here)

function KiInitializeFileSystems()
    local c, bAddr = component, computer.getBootAddress()
    local floppyDrv, regStP = {}, "\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Control\\Class\\{4d36e967-e325-11ce-bfc1-08002be10318}"
    for addr in c.list("disk_drive") do
        table.insert(floppyDrv, c.proxy(addr))
    end
    local floppyL = {"A:", "B:"}
    for i, drive in ipairs(floppyDrv) do
        if i>2 then break end
        local l = floppyL[i]
        local mediaAddr = drive.media()
        if mediaAddr then
            Mm.AllocateNonPaged("\\Device\\Floppy"..(i-1).."\\Partition0", c.proxy(mediaAddr))
            DbgPrint("Ob: Registered \\Device\\Floppy"..(i-1).."\\Partition0")
            Drives[l]="\\Device\\Floppy"..(i-1).."\\Partition0"
            DbgPrint("Ob: Symbolic link \\DosDevices\\"..l.."-> \\Device\\Floppy"..(i-1).."\\Partition0")
        else
            Mm.AllocateNonPaged("\\Device\\Floppy"..(i-1).."\\Partition0", CreateNoMedia())
            DbgPrint("Ob: Registered \\Device\\Floppy"..(i-1).."\\Partition0")
            Drives[l]="\\Device\\Floppy"..(i-1).."\\Partition0"
            DbgPrint("Ob: Symbolic link \\DosDevices\\"..l.."-> \\Device\\Floppy"..(i-1).."\\Partition0")
        end
    end
    local cLC = string.byte("C")
    for addr in c.list("filesystem") do
        local isFl = false
        for _, fDrive in ipairs(floppyDrv) do
            if fDrive.media()==addr then isFl=true end
        end
        if not isFl then
            local diskProxy = component.proxy(addr)
            local totalBytes = diskProxy.spaceTotal()
            local bytesPerSector = 512
            local sectorsPerTrack = 8
            local tracksPerCylinder = 2
            local heads = tracksPerCylinder
            local sectors = sectorsPerTrack
            local cylinders = math.floor(totalBytes / (bytesPerSector * sectorsPerTrack * tracksPerCylinder)) if cylinders == 0 then cylinders = 1 end
            local l = string.char(cLC)..":"
            local devName = "\\Device\\Harddisk"..(cLC-67).."\\Partition0"
            Mm.AllocateNonPaged(devName, c.proxy(addr))
            DbgPrint("Ob: Registered "..devName)
            Drives[l]=devName
            DbgPrint("Ob: Symbolic link \\DosDevices\\"..l.." -> "..devName)
            regedit.SetValue(regStP, "Class", "DiskDrive")
            regedit.SetValue(regStP, "ClassDesc", "@disk.inf,%disk.desc%;Disk drives")
            regedit.SetValue(regStP, "Installer32", "StorProp.lua,DiskClassInstaller")
            regedit.SetValue(regStP, "NoInstallClass", 1)
            regedit.SetValue(regStP, "SilentInstall", 1)
            regedit.SetValue(regStP, "UpperFilters", "partmgr")
            regedit.SetValue(regStP, "LowerFilters", "EhStorClass")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "DriverDesc", "Apacer ADM III 4MB")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "DriverVersion", "1.8.9")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "InfPath", "disk.inf")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "InfSection", "disk_install")
            local deviceId = ""
            if totalBytes == 4194304 then
                deviceId = "scsi\\\\disk_______apacer_hdd_3________"
            elseif totalBytes == 65535 then
                deviceId = "scsi\\\\disk_______tmpfs_64kb__________"
            else
                deviceId = "scsi\\\\disk_______generic_flash______"
            end
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "MatchingDeviceId", deviceId)
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "DeviceType", 7)
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "ClassGUID", "{4d36e967-e325-11ce-bfc1-08002be10318}")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "ServiceName", "disk")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "LocationInformation", "PCIROOT(0)#PCI(0100)#PCI(0000)#ATA(C00T00L00)")
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "PhysicalDriveNumber", cLC-67)
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "DeviceCharacteristics", 0x100)
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "Capabilities", 0x00000010)
            regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "RemovalPolicy", 3)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk", cLC-67), "UserMaxAlign", 1)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk", cLC-67), "DiskAddress", "0:0:0:0")
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk", cLC-67), "Port", 0)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk", cLC-67), "Bus", 0)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk", cLC-67), "TargetId", 0)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk\\DiskGeometry", cLC-67), "BytesPerSector", bytesPerSector)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk\\DiskGeometry", cLC-67), "SectorsPerTrack", sectorsPerTrack)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk\\DiskGeometry", cLC-67), "TracksPerCylinder", tracksPerCylinder)
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk\\DiskGeometry", cLC-67), "Cylinders", cylinders)
            if totalBytes < 1024 * 1024 then
                regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "FriendlyName", "Small Storage Device (TMPFS)")
                regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk\\DiskGeometry", cLC-67), "MediaType", 11)
            else
                regedit.SetValue(regStP..string.format("\\%04d", cLC-67), "FriendlyName", "Hard Disk (Tier 3) (" .. math.floor(totalBytes / 1024) .. " KB)")
                regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Disk\\DiskGeometry", cLC-67), "MediaType", 12)
            end
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Storage Management", cLC-67), "DeviceName", "\\\\\\\\.\\\\PhysicalDrive"..(cLC-67))
            regedit.SetValue(regStP..string.format("\\%04d\\Device Parameters\\Storage Management", cLC-67), "UniqueId", "{"..addr.."}")
            cLC=cLC+1
        end
    end

    for letter, addr in ipairs(_G.Drives) do
        if letter=="C:" then
            KiMarkDriveDirty(addr)
        end
    end
end

function _G.RegisterShutdownDriver(serviceName, driverObject)
    if not _G.ShutdownDrivers then
        _G.ShutdownDrivers = {}
    end
    _G.ShutdownDrivers[serviceName] = driverObject
    DbgPrint(string.format("SHUTDOWN: Registered driver %s for shutdown", serviceName))
end

local function KiMarkDriveDirty(dev)
    if not dev.isReadOnly() then
        local f = dev.open("/system.dirty", "w")
        if f then dev.write(f, "DIRTY") dev.close(f) end
    end
end

_G.HandleTable={}
_G.KRNLGCT = 1
_G.LastHandle=100

KiInitializeFileSystems() -- HDD and Floppy



if screen_gdi then screen_gdi = gdi32.GetDC(0) DbgPrint("GDI32: Video-shell initialization...") else error("NTOSKRNL, giving a screen HDC failed, GDI32 error.") end
KeDelayExecutionThread(1)

DbgPrint("ntoskrnl: Loading SYSTEM drivers...")
for _, file in ipairs(systemDrivers) do
    LoadDriver(file)
end

DbgPrint("ntoskrnl: Loading AUTO drivers...")
for _, file in ipairs(autoDrivers) do
    LoadDriver(file)
end

DbgPrint("ntoskrnl: " .. #manualDrivers .. " manual drivers registered")

KeDelayExecutionThread(2)
regedit.Flush()
-- DRIVER END

gdi32.PatBlt(screen_gdi, 1, 1, HAL.w, HAL.h, gdi32.PATCOPY)
gdi32.SetBkMode(screen_gdi, 1)
gdi32.SetTextColor(screen_gdi, 0xFFFFFF)
gdi32.TextOut(screen_gdi, 2, 2, "RedstoneShell(R) Windows NT(TM) Version 4.0 (LuaNT)")

local csrss, err11 = LdrLoadDll("Windows/System32/csrss.lua")
if not csrss then
    KeBugCheckEx("STATUS_SYSTEM_PROCESS_TERMINATED", 0xC000021A, 0x00000002)
end
local krnl32, err13 = LdrLoadDll("Windows/System32/kernel32.lua")
if not krnl32 then KeBugCheckEx("STATUS_SYSTEM_PROCESS_TERMINATED", err13, "kernel32.dll") end
_G.ClientServerRuntime=csrss
_G.Kernel = krnl32

local ntstartargs = {
    "-scrRes",
    HAL.w,
    HAL.h,
    gdi = gdi32
}
local csr_suc = csrss.CsrServerInitialization(#ntstartargs, ntstartargs)

if not csr_suc then KeBugCheckEx("STATUS_SYSTEM_PROCESS_TERMINATED", 0xC000021A, 0x00000002) end

local function DrawShutdownScreen(statusText, isFinal)
    local gpu = _G.HAL.gpu
    local w, h = gpu.getResolution()
    
    if isFinal then
        gpu.setBackground(0x000000)
        gpu.fill(1, 1, w, h, " ")
        
        gpu.setForeground(0xFF8000)
        local text1 = "It is now safe to turn off your computer."
        local text2 = "If you want to restart, press Ctrl+Alt+Del."
        
        gpu.set(math.floor((w - #text1)/2), math.floor(h/2) - 1, text1)
        gpu.setForeground(0xBBBBBB)
        gpu.set(math.floor((w - #text2)/2), math.floor(h/2) + 1, text2)
    else
        gpu.setBackground(0x000080)
        gpu.fill(1, 1, w, h, " ")
        
        local winW, winH = 40, 6
        local winX = math.floor((w - winW) / 2)
        local winY = math.floor((h - winH) / 2)
        
        gpu.setBackground(0xCCCCCC)
        gpu.fill(winX, winY, winW, winH, " ")
        
        gpu.setForeground(0xFFFFFF)
        gpu.fill(winX, winY, winW, 1, "━")
        gpu.fill(winX, winY, 1, winH, "┃")
        
        gpu.setForeground(0x555555)
        gpu.fill(winX, winY + winH - 1, winW, 1, "━")
        gpu.fill(winX + winW - 1, winY, 1, winH, "┃")
        
        gpu.setBackground(0x000080)
        gpu.fill(winX + 2, winY + 1, winW - 4, 1, " ")
        gpu.setForeground(0xFFFFFF)
        gpu.set(winX + 3, winY + 1, "Shutdown Computer")
        
        gpu.setBackground(0xCCCCCC)
        gpu.setForeground(0x000000)
        gpu.set(math.floor(winX + (winW - #statusText)/2), winY + 3, statusText)
    end
end

_G.RebootSet=false

function _G.PerformSystemShutdown()
    DbgPrint("SHUTDOWN: Phase 1 - Notifying all subsystems")
    _G.ShutdownPhase = 1
    
    DrawShutdownScreen("Saving your settings...", false)

    if _G.ClientServerRuntime and _G.ClientServerRuntime.NotifyShutdown then
        pcall(_G.ClientServerRuntime.NotifyShutdown)
    end
    
    KeDelayExecutionThread(1)
    _G.ShutdownPhase = 2
    DbgPrint("SHUTDOWN: Phase 2 - Flushing registry")
    
    DrawShutdownScreen("Flushing registry to disk...", false)
    
    if regedit and regedit.Flush then
        regedit.Flush()
        DbgPrint("SHUTDOWN: Registry flushed to disk")
    end
    
    KeDelayExecutionThread(0.5)
    _G.ShutdownPhase = 3
    DbgPrint("SHUTDOWN: Phase 3 - Unloading drivers")
    
    local shutdownOrder = {}
    for name, _ in pairs(_G.ShutdownDrivers) do
        table.insert(shutdownOrder, name)
    end
    
    table.sort(shutdownOrder, function(a, b)
        local startA = regedit.GetValue(
            "\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Services\\" .. a, 
            "Start"
        ) or 2
        local startB = regedit.GetValue(
            "\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Services\\" .. b, 
            "Start"
        ) or 2
        return startA > startB
    end)
    
    for _, name in ipairs(shutdownOrder) do
        DrawShutdownScreen("Unloading: " .. string.sub(name, 1, 20), false)
        
        local driver = _G.ShutdownDrivers[name]
        if driver and driver.DriverUnload then
            DbgPrint(string.format("SHUTDOWN: Unloading driver %s", name))
            local ok, err = pcall(driver.DriverUnload)
            if not ok then
                DbgPrint(string.format("SHUTDOWN: Error unloading %s: %s", name, tostring(err)))
            end
        end
        KeDelayExecutionThread(0.1)
    end
    
    KeDelayExecutionThread(0.5)
    _G.ShutdownPhase = 4
    DbgPrint("SHUTDOWN: Phase 4 - Cleaning memory pools")
    
    DrawShutdownScreen("Cleaning memory pools...", false)
    
    if _G.Mm and _G.Mm.PagedPool then
        local count = 0
        for key, _ in pairs(_G.Mm.PagedPool) do
            _G.Mm.PagedPool[key] = nil
            count = count + 1
        end
        DbgPrint(string.format("SHUTDOWN: PagedPool cleaned (%d entries)", count))
    end
    
    if _G.Mm and _G.Mm.NonPagedPool then
        local count = 0
        local keepKeys = {
            "HKEY_LOCAL_MACHINE\\SYSTEM",
            "\\Driver\\PnPManager",
        }
        
        for key, _ in pairs(_G.Mm.NonPagedPool) do
            local keep = false
            for _, keepKey in ipairs(keepKeys) do
                if key == keepKey then
                    keep = true
                    break
                end
            end
            if not keep then
                _G.Mm.NonPagedPool[key] = nil
                count = count + 1
            end
        end
        DbgPrint(string.format("SHUTDOWN: NonPagedPool cleaned (%d entries)", count))
    end
    local bootDisk = component.proxy(computer.getBootAddress())
    if bootDisk and bootDisk.remove then
        pcall(bootDisk.remove, "/system.dirty")
        pcall(bootDisk.remove, "/pagefile.sys")
        DbgPrint("SHUTDOWN: Temporary files removed")
    end
    KeDelayExecutionThread(0.5)
    _G.ShutdownPhase = 5
    DbgPrint("SHUTDOWN: Phase 5 - Finalizing shutdown")
    _G.KiDispatcherDestroy()
    computer.beep(440, 0.3)
    computer.beep(440, 0.3)
    computer.beep(440, 0.5)
    DrawShutdownScreen("", true)
    DbgPrint("SHUTDOWN: Powering off...")
    KeDelayExecutionThread(2.0)
    if not _G.RebootSet then computer.shutdown(false) else computer.shutdown(true) end
end

local winlogon, err12 = LdrLoadDll("Windows/System32/winlogon.lua")
if err12 then
    KeBugCheckEx("STATUS_SYSTEM_PROCESS_TERMINATED", 0xC000021A, 0x00000001)
end
local s32 = LdrLoadDll("Windows/System32/shell32.lua")

local ntwla = { 
    gdi = gdi32,
    halt= HAL,
    csr = csrss,
    shell = s32
}
_G.DebugMode=false
_G.ShutdownPhase = 0
_G.ShutdownDrivers = {}
if not _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SAM"] then
    KeBugCheckEx("C0000218", "{Registry File Failure}", "The registry cannot load the hive (file): \\SystemRoot\\System32\\Config\\SAM.")
end

winlogon.Main(ntwla)
local wls, explorerTimeUpd = true, nil

function KiInterruptDispatch(sig, addr, arg1, arg2, arg3, arg4)
    if _G.PnPManager and _G.PnPManager.PollEvents then
        _G.PnPManager.PollEvents(sig, addr, arg1, arg2, arg3, arg4)
    end
    
    if sig == "key_down" then
        if wls then
            local exp = winlogon.HandleKey(arg1, arg2)
            if exp then
                explorerTimeUpd = exp
                wls = false
            end
        end
    elseif sig == "touch" then
        if s32 and s32.HandleClick then 
            s32.HandleClick(arg1, arg2, arg3) 
        end
        
        if not wls and explorerTimeUpd and explorerTimeUpd.HandleClick then
            explorerTimeUpd.HandleClick(arg1, arg2)
        end
    elseif sig == "shutdown" then
        computer.beep(1000, 1)
        regedit.Flush()
    end
end

_G.NTTC=0

_G.HAL.HalQueryRealTimeClock = function (PTIME_FIELDS)
    local t = os.date("*t", os.time())
    PTIME_FIELDS.Year=t.year
    PTIME_FIELDS.Month=t.month
    PTIME_FIELDS.Day=t.day
    PTIME_FIELDS.Hour=t.hour
    PTIME_FIELDS.Minute=t.min
    PTIME_FIELDS.Second=t.sec
    PTIME_FIELDS.Milliseconds=math.floor((computer.uptime()%1)*1000)
    PTIME_FIELDS.Weekday=t.wday-1
end

local tTable = {}
local lastRegSave=30
_G.InThreadResume = false
while true do
    _G.NTTC=_G.NTTC+1
    local sig, addr, arg1, arg2, arg3, arg4 = computer.pullSignal(0.01)
    if sig then
        if _G.KRNL_ETW and _G.KRNL_ETW.PushSignal then
            _G.KRNL_ETW.PushSignal(sig, addr, arg1, arg2, arg3, arg4)
        end
        if KiInterruptDispatch then
            _G.KiInterruptDispatch(sig, addr, arg1, arg2, arg3, arg4)
        end
    end
    
    if not wls and explorerTimeUpd and explorerTimeUpd.UpdateTime then
        _G.HAL.HalQueryRealTimeClock(tTable)
        explorerTimeUpd.UpdateTime(tTable)
    end

    -- Threads updates in ntoskrnl.lua, TODO: pullSignal downleveled from 0.2 to 0.01 for minimal freezing of threads
    local nextThread, activePrio = KiSelectNextThread()
    if nextThread then
        if _G.InThreadResume then
            _G.DbgPrint("KE: Recursive thread resume detected! Skipping...")
            goto skip_thread
        end
        
        _G.InThreadResume = true
        nextThread.quantumLeft = nextThread.quantumLeft - 1
        
        local success, err = xpcall(
            function()
                return coroutine.resume(nextThread.co, sig, addr, arg1, arg2, arg3, arg4)
            end,
            function(e)
                return "Thread error: " .. tostring(e) .. "\n" .. debug.traceback()
            end
        )
        
        _G.InThreadResume = false
        
        if not success then
            _G.KiHandleCrashedThread(nextThread, err)
        elseif coroutine.status(nextThread.co) == "dead" then
            _G.DbgPrint(string.format("KE: Thread %s (PID: %d) finished normally.", 
                nextThread.name, nextThread.pid))
            table.remove(ReadyQueues[activePrio], 1)
        else
            if nextThread.quantumLeft <= 0 then
                nextThread.quantumLeft = 6
                table.remove(ReadyQueues[activePrio], 1)
                table.insert(ReadyQueues[activePrio], nextThread)
            end
        end
    end
    
    ::skip_thread::
    
    if not _G.GCInProgress then
        _G.ThreadGC.Counter = _G.ThreadGC.Counter + 1
        if _G.ThreadGC.Counter >= _G.ThreadGC.Interval then
            _G.ThreadGC.Counter = 0
            local cleaned = _G.KiCleanDeadThreads()
            if cleaned > 0 then
                _G.DbgPrint(string.format("KE: GC cleaned %d dead threads", cleaned))
            end
        end
    end
        
    local time = computer.uptime()
    if time>=lastRegSave then regedit.Flush() lastRegSave=time+30 end
end
