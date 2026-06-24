local rpc = {}

local RegisteredInterfaces = {}

function rpc.RpcServerRegisterIf(interfaceName, methodsTable)
    if RegisteredInterfaces[interfaceName] then
        _G.DbgPrint("RPC: ERROR - Interface " .. interfaceName .. " already registered.")
        return false
    end
    RegisteredInterfaces[interfaceName] = methodsTable
    _G.DbgPrint("RPC: Interface '" .. interfaceName .. "' successfully registered.")
    return true
end

function rpc.RpcServerUnregisterIf(interfaceName)
    if not RegisteredInterfaces[interfaceName] then
        _G.DbgPrint("RPC: ERROR - Interface " .. interfaceName .. " not found.")
        return false
    end
    RegisteredInterfaces[interfaceName] = nil
    _G.DbgPrint("RPC: Interface '" .. interfaceName .. "' successfully unregistered.")
    return true
end

function rpc.RpcCliExecute(interfaceName, methodName, ...)
    local iface = RegisteredInterfaces[interfaceName]
    if not iface then
        return false, "RPC_S_UNKNOWN_IF (Interface not found)"
    end
    
    local method = iface[methodName]
    if not method then
        return false, "RPC_S_PROCNUM_OUT_OF_RANGE (Method not found)"
    end
    
    local status, ret = pcall(method, ...)
    
    if not status then
        return false, "RPC_S_SERVER_UNAVAILABLE: " .. tostring(ret)
    end
    
    return true, ret
end

_G.RpcSs = rpc
repeat
    coroutine.yield()
until false
