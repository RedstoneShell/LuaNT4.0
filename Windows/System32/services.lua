local regedit = _G.LdrLoadDll("Windows/System32/regedit.lua")

local SCM = {}
SCM.RunningServices = {}
_G.DbgPrint("SCM: Service Control Manager initializing...")

local SERVICES_REG = "\\Software\\RedstoneShell\\Windows\\CurrentControlSet\\Services\\"

function SCM.StartService(serviceName)
    if SCM.RunningServices[serviceName] then
        _G.DbgPrint("SCM: Service " .. serviceName .. " is already running.")
        return true
    end

    local path = SERVICES_REG .. serviceName
    local imagePath = regedit.GetValue(path, "ImagePath")
    local errCtrl = tonumber(regedit.GetValue(path, "ErrorControl")) or 1

    if not imagePath then
        _G.DbgPrint("SCM: Failed to start " .. serviceName .. " - ImagePath missing in Registry.")
        return false
    end

    _G.DbgPrint("SCM: Starting service from Registry: " .. serviceName .. " (" .. imagePath .. ")...")

    local pid = _G.PsCreateSystemThread(imagePath, serviceName .. ".exe", 8, { name = "SYSTEM", group = "SERVICES" })

    if pid then
        SCM.RunningServices[serviceName] = pid
        _G.DbgPrint("SCM: Service " .. serviceName .. " started successfully with PID: " .. pid.pid)
        return true
    else
        _G.DbgPrint("SCM: Execution failed for " .. serviceName)
        if errCtrl >= 2 then
            _G.KeBugCheckEx("SERVICE_BOOT_FAILURE", serviceName, "Critical service failed")
        end
        return false
    end
end

function SCM.StopService(serviceName)
    local threadObj = SCM.RunningServices[serviceName]
    if not threadObj then
        _G.DbgPrint("SCM: Service " .. serviceName .. " is not running.")
        return false
    end

    local numericPid = threadObj.pid
    _G.DbgPrint("SCM: Stopping service: " .. serviceName .. " [PID: " .. numericPid .. "]")
    
    local success = _G.PsTerminateThread(numericPid)
    if success then
        SCM.RunningServices[serviceName] = nil
        return true
    end
    return false
end

function SCM.AutoStart()
    _G.DbgPrint("SCM: Parsing HKLM\\SYSTEM\\Services for AUTOMATIC startup...")
    
    local hive = _G.Mm.NonPagedPool["HKEY_LOCAL_MACHINE\\SYSTEM"]
    if not hive then 
        _G.DbgPrint("SCM: CRITICAL ERROR - SYSTEM hive not loaded in NonPagedPool!")
        return 
    end

    local searchPattern = "^" .. SERVICES_REG:gsub("%\\", "%%\\")

    for path, keys in pairs(hive) do
        if path:find(searchPattern) then
            local svcName = path:match("([^%\\#]+)$")
            
            if svcName and path == SERVICES_REG .. svcName then
                local startType = tonumber(keys["Start"])
                
                if startType == 2 then -- Automatic
                    SCM.StartService(svcName)
                end
            end
        end
    end
end

_G.KRNL_SCM = SCM
SCM.AutoStart()

while true do
    coroutine.yield()
end