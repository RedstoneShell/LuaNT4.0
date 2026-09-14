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

local function ParsePath(path)
    if not path then
        return "C:", "/"
    end
    local original = path
    path = path:gsub("\\", "/")
    local drive, rest = path:match("^([A-Za-z]:)/?(.*)$")
    if drive then
        if rest == nil or rest == "" then
            rest = "/"
        end
        return drive:upper(), rest
    end
    if path == "" then path = "/" end
    return "C:", path
end

local function GetDeviceFS(driveLetter)
    if not _G.Drives then
        return nil, "DRIVES_TABLE_MISSING"
    end

    local deviceName = _G.Drives[driveLetter]
    if not deviceName then
        return nil, "DRIVE_NOT_FOUND"
    end

    if not _G.Mm or not _G.Mm.NonPagedPool then
        return nil, "POOL_MISSING"
    end

    local fs = _G.Mm.NonPagedPool[deviceName]
    if not fs then
        return nil, "DEVICE_NOT_FOUND"
    end

    return fs
end

function ntdll.NtOpenFileEx(path, mode)
    mode = mode or "rb"
    local driveLetter, filePath = ParsePath(path)

    local fs, err = GetDeviceFS(driveLetter)
    if not fs then
        return nil, err
    end

    if not fs.open then
        return nil, "NOT_A_FILESYSTEM"
    end

    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end

    local handle, oerr = fs.open(filePath, mode)
    if not handle then
        return nil, oerr or "OPEN_FAILED"
    end
    return handle, fs
end

function ntdll.NtReadFileEx(handle, fs, bytes)
    if not fs or not fs.read then return nil, "INVALID_FILESYSTEM" end
    return fs.read(handle, bytes or math.huge)
end

function ntdll.NtWriteFileEx(handle, fs, data)
    if not fs or not fs.write then return nil, "INVALID_FILESYSTEM" end
    return fs.write(handle, data)
end

function ntdll.NtCloseFileEx(handle, fs)
    if not fs or not fs.close then return nil, "INVALID_FILESYSTEM" end
    return fs.close(handle)
end

function ntdll.NtListDirectoryEx(path)
    local driveLetter, dirPath = ParsePath(path)

    local fs, err = GetDeviceFS(driveLetter)
    if not fs then
        return nil, err
    end
    if not fs.list then
        return nil, "NOT_A_FILESYSTEM"
    end

    if dirPath == "" then dirPath = "/" end
    if dirPath:sub(1, 1) ~= "/" then dirPath = "/" .. dirPath end

    local ok, items = pcall(fs.list, dirPath)

    if not ok then
        return nil, "LIST_FAILED"
    end

    if not items then
        return nil, "LIST_FAILED"
    end

    if type(items) == "table" then
        return items
    end

    if type(items) == "function" then
        local t = {}
        local n = 0
        for name in items do
            n = n + 1
            t[n] = name
            if n > 500 then
                break
            end
        end
        return t
    end

    return nil, "UNEXPECTED_TYPE"
end

function ntdll.NtFileExistsEx(path)
    local driveLetter, filePath = ParsePath(path)

    local fs = GetDeviceFS(driveLetter)
    if not fs then
        return false
    end
    if not fs.exists then
        return false
    end

    if filePath == "" then filePath = "/" end
    if filePath:sub(1, 1) ~= "/" then filePath = "/" .. filePath end

    local ok, res = pcall(fs.exists, filePath)
    return ok and res or false
end

function ntdll.NtTerminateProcess(pid)
    local success = _G.PsTerminateThread(pid)
    if success then
        return true, "STATUS_SUCCESS"
    else
        return false, "STATUS_OBJECT_NAME_NOT_FOUND"
    end
end

function ntdll.NtDelayExecution()
    coroutine.yield()
end

return ntdll