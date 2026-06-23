local kernel32 = {}

function kernel32.NtOpenFile(path, mode)
    local lett = path.sub(1, 2)
    local intPath = path.sub(3)
    local dev = _G.Mm.NonPagedPool[_G.Drives[lett]]
    if not dev then
        return nil, "STATUS_OBJECT_NAME_NOT_FOUND"
    end
    local fd, err = dev.open(intPath, mode or "r")
    if not fd then return nil, err end
    _G.LastHandle=_G.LastHandle+4
    _G.HandleTable[_G.LastHandle] = {
        fd=fd,
        dev=dev,
        path=path
    }
end

function kernel32.GetCurrentProcessId()
    return 50
end

function kernel32.KeQueryTickCount()
    return _G.NTTC
end

function kernel32.NtReadFile(handle, bytes)
    local obj = _G.HandleTable[handle]
    if not obj then return nil, "STATUS_INVALID_HANDLE" end
    return obj.dev.read(obj.fd, bytes)
end

function kernel32.NtWriteFile(handle, data)
    local obj = _G.HandleTable[handle]
    if not obj then return nil, "STATUS_INVALID_HANDLE" end
    return obj.dev.write(obj.fd, data)
end   

function kernel32.NtClose(handle)
    local obj = _G.HandleTable[handle]
    if obj then
        obj.dev.close(obj.fd)
        _G.HandleTable[handle]=nil
        return "STATUS_SUCCESS"
    end
    return "STATUS_INVALID_HANDLE"
end

function kernel32.NtQueryDirectoryFile(path)
    local lett, intPath = path:sub(1,2), path:sub(3)
    local dev = _G.Mm.NonPagedPool[_G.Drives[lett]]
    if not dev then return nil, "STATUS_NO_SUCH_DEVICE" end
    return dev.list(intPath)
end

return kernel32