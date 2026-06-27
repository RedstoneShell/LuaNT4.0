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

-- Extended file access for multiply disks in system
function ntdll.NtOpenFileEx(path, mode)
    mode = mode or "rb"
    local driveLetter, filePath = path:match("^([A-Za-z]:)\\(.*)$")
    if not driveLetter then
        driveLetter = "C:"
        filePath = path
    end

    driveLetter=driveLetter:upper()
    
    local deviceName = _G.Drives[driveLetter]
    if not deviceName then
        _G.DbgPrint("NtOpenFileEx: Drive " .. driveLetter .. " not found in Drives table")
        return nil, "DRIVE_NOT_FOUND"
    end
    
    local fs = _G.Mm.NonPagedPool[deviceName]
    if not fs then
        _G.DbgPrint("NtOpenFileEx: Device " .. deviceName .. " not found in NonPagedPool")
        return nil, "DEVICE_NOT_FOUND"
    end
    
    if not fs.open then
        _G.DbgPrint("NtOpenFileEx: Device " .. deviceName .. " is not a filesystem")
        return nil, "NOT_A_FILESYSTEM"
    end
    
    local handle, err = fs.open(filePath, mode)
    if not handle then
        _G.DbgPrint("NtOpenFileEx: Failed to open " .. filePath .. " on " .. deviceName .. ": " .. tostring(err))
        return nil, err or "OPEN_FAILED"
    end
    
    return handle, fs
end

function ntdll.NtReadFileEx(handle, fs, bytes)
    if not fs or not fs.read then
        return nil, "INVALID_FILESYSTEM"
    end
    return fs.read(handle, bytes or math.huge)
end

function ntdll.NtWriteFileEx(handle, fs, data)
    if not fs or not fs.write then
        return nil, "INVALID_FILESYSTEM"
    end
    return fs.write(handle, data)
end

function ntdll.NtCloseFileEx(handle, fs)
    if not fs or not fs.close then
        return nil, "INVALID_FILESYSTEM"
    end
    return fs.close(handle)
end

function ntdll.NtListDirectoryEx(path)
    local driveLetter, dirPath = path:match("^([A-Za-z]:)\\(.*)$")
    if not driveLetter then
        driveLetter = "C:"
        dirPath = path
    end
    
    local deviceName = _G.Drives[driveLetter]
    if not deviceName then
        return nil, "DRIVE_NOT_FOUND"
    end
    
    local fs = _G.Mm.NonPagedPool[deviceName]
    if not fs or not fs.list then
        return nil, "DEVICE_NOT_FOUND"
    end
    
    return fs.list(dirPath)
end

function ntdll.NtFileExistsEx(path)
    local driveLetter, filePath = path:match("^([A-Za-z]:)\\(.*)$")
    if not driveLetter then
        driveLetter = "C:"
        filePath = path
    end
    
    local deviceName = _G.Drives[driveLetter]
    if not deviceName then
        return false
    end
    
    local fs = _G.Mm.NonPagedPool[deviceName]
    if not fs or not fs.exists then
        return false
    end
    
    return fs.exists(filePath)
end

-- END

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
            
            local function safeExecutor()
                local env = {}

                local function SafeOpen(path)
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
                
                env._G.DbgPrint = _G.DbgPrint
                env.arg = ntdll.SharedArgs
                env.argv = ntdll.SharedArgs
                env.pairs = pairs
                env.ipairs = ipairs
                env._G.HAL=_G.HAL
                env.type = type
                env.tonumber = tonumber
                env.tostring = tostring
                env.string = string
                env.table = table
                env.math = math
                env.coroutine = coroutine
                env.utf8 = utf8
                env._G.RpcSs=_G.RpcSs
                
                env.error = function(msg, level)
                    _G.DbgPrint("SECURITY: Sandboxed error: " .. tostring(msg))
                    return nil, "0xC0000139: " .. tostring(msg)
                end
                
                env.pcall = function(f, ...)
                    local ok, err = pcall(f, ...)
                    if not ok then
                        _G.DbgPrint("SECURITY: Sandboxed pcall error: " .. tostring(err))
                        return false, "0xC0000139: " .. tostring(err)
                    end
                    return ok, err
                end
                
                env.xpcall = function(f, errhandler, ...)
                    local function wrappedHandler(e)
                        _G.DbgPrint("SECURITY: Sandboxed xpcall error: " .. tostring(e))
                        return errhandler("0xC0000139: " .. tostring(e))
                    end
                    return xpcall(f, wrappedHandler, ...)
                end
                
                env.LdrLoadDll = function(path)
                    local lowerPath = tostring(path):lower()
                    if lowerPath:match("ntoskrnl") or 
                       lowerPath:match("winlogon") or 
                       lowerPath:match("windows/system32/drivers") then
                        _G.DbgPrint("SECURITY: Sandboxed process tried to require: " .. path)
                        return nil
                    end
                    local code, err = SafeOpen(path)
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
                
                env.component = nil
                env._G.KRNL_GDI=_G.KRNL_GDI32
                env.computer=computer
                env.computer.pullSignal = computer.pullSignal
                env.coroutine.yield=coroutine.yield
                env.debug = nil
                env.os = nil
                env.io = nil
                env.loadfile = nil
                env.dofile = nil
                
                local func, err = load(chunk, "=" .. path, "t", env)
                if not func then
                    _G.DbgPrint("SECURITY: Failed to load chunk, " ..err..": "..debug.traceback())
                    return nil, "STATUS_ENTRYPOINT_NOT_FOUND"
                end
                
                local ok, result = pcall(func)
                if not ok then
                    _G.DbgPrint("SECURITY: Chunk execution error: " .. tostring(result))
                    return nil, "0xC0000139: " .. tostring(result)
                end
                return result
            end
            
            return safeExecutor
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
