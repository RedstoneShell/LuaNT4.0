local rpcOk, args = _G.RpcSs.RpcCliExecute("IConsoleManager", "GetProcessArgs")
args = args or {}

local command = args[1]
local serviceName = args[2]

function print(text)
    if _G.RpcSs then
        _G.RpcSs.RpcCliExecute("IConsoleManager", "WriteStdOut", text)
    else
        _G.DbgPrint("NET: RpcSs missing! Log: " .. tostring(text))
    end
end

if not command then
    print("The syntax of this command is:")
    print("NET [ START | STOP ]")
    return
end

command = command:lower()

if not _G.RpcSs then
    print("System error: RPC Subsystem (RpcSs) is not responding. Service control unavailable.")
    return
end

if command == "start" then
    if not serviceName then
        local rpcOk, runningList = _G.RpcSs.RpcCliExecute("IServiceControlManager", "EnumRunningServices")
        
        if not rpcOk or not runningList then
            print("Failed to enumerate running services via RPC.")
            return
        end
        
        print("These Windows services are running:")
        print("--------------------------------------------------")
        
        if #runningList == 0 then
            print("  (No active services found)")
        else
            for _, svc in ipairs(runningList) do
                print("   " .. tostring(svc))
            end
        end
        print("The command completed successfully.")
        return
    end

    print(string.format("The %s service is starting...", serviceName))
    
    local rpcOk, success = _G.RpcSs.RpcCliExecute("IServiceControlManager", "StartService", serviceName)
    
    if not rpcOk then
        print("RPC Error: " .. tostring(success))
    elseif success then
        print(string.format("The %s service was started successfully.", serviceName))
    else
        print(string.format("System error: Failed to start the %s service. Check registry ImagePath or system logs.", serviceName))
    end
elseif command == "stop" then
    if not serviceName then
        print("Usage: net stop [service_name]")
        return
    end

    print(string.format("The %s service is attempting to stop...", serviceName))
    
    local rpcOk, success = _G.RpcSs.RpcCliExecute("IServiceControlManager", "StopService", serviceName)
    
    if not rpcOk then
        print("RPC Error: " .. tostring(success))
    elseif success then
        print(string.format("The %s service was stopped successfully.", serviceName))
    else
        print(string.format("System error: Failed to stop the %s service. It might not be running.", serviceName))
    end
else
    print(string.format("An invalid option was specified: '%s'", args[1]))
    print("The syntax of this command is:")
    print("NET [ START | STOP ]")
end