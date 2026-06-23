local ntdll = {}

function ntdll.NtQuerySystemInformation()
    local processList = {}
    
    if _G.PspActiveProcessList then
        for i, thread in ipairs(_G.PspActiveProcessList) do
            table.insert(processList, {
                UniqueProcessId = thread.pid,
                ImageName = thread.name,
                BasePriority = thread.basePriority,
                CurrentPriority = thread.currentPriority,
                Environment = thread.token and thread.token.name or "SYSTEM"
            })
        end
    end
    
    return processList
end

function ntdll.NtTerminateProcess(pid)
    local success = _G.PsTerminateThread(pid)
    if success then
        return true, "STATUS_SUCCESS"
    else
        return false, "STATUS_OBJECT_NAME_NOT_FOUND"
    end
end

function ntdll.NtCreateUserProcess(path, name, priority, commandLineArgs)
    priority = priority or 8
    commandLineArgs = commandLineArgs or {}
    
    if not _G.PsCreateSystemThread then 
        return nil, "STATUS_PROCESS_IS_TERMINATING" 
    end
    ntdll.SharedArgs = commandLineArgs
    local originalNtOpenFile = _G.NtOpenFile
    _G.NtOpenFile = function(p)
        if p == path then
            local chunk, err = originalNtOpenFile(p)
            if not chunk then return nil, err end
            local sandboxedEnv = {}
            setmetatable(sandboxedEnv, { __index = _G })
            sandboxedEnv["error"] = nil
            sandboxedEnv["debug"] = nil
            sandboxedEnv["component"] = nil
            sandboxedEnv["computer"] = nil
            sandboxedEnv["_G"] = sandboxedEnv
            sandboxedEnv.argv = ntdll.SharedArgs
            sandboxedEnv.arg = ntdll.SharedArgs
            sandboxedEnv.LdrLoadDll = function(dllPath)
                local lowerPath = dllPath:lower()
                if lowerPath:match("ntoskrnl") or 
                   lowerPath:match("winlogon") or 
                   lowerPath:match("windows/system32/drivers") then
                    _G.DbgPrint("SECURITY: Sandboxed process tried to access: " .. dllPath)
                    return nil, "STATUS_NOT_FOUND"
                end
                return _G.LdrLoadDll(dllPath)
            end
            --setfenv(chunk, sandboxedEnv) He didn't work here..
            return chunk
        end
        return originalNtOpenFile(p)
    end
    local thread = _G.PsCreateSystemThread(path, name, priority)
    _G.NtOpenFile = originalNtOpenFile
    ntdll.SharedArgs = nil
    if thread then
        return thread.pid, "STATUS_SUCCESS"
    else
        return nil, "STATUS_PROCESS_IS_TERMINATING"
    end
end

function ntdll.NtDelayExecution()
    coroutine.yield()
end

return ntdll
