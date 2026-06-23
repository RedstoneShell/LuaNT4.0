local rpcOk, args = _G.RpcSs.RpcCliExecute("IConsoleManager", "GetProcessArgs")
args = args or {}

local function print(text)
    if _G.RpcSs then
        _G.RpcSs.RpcCliExecute("IConsoleManager", "WriteStdOut", text)
    else
        _G.DbgPrint("SHUTDOWN: " .. tostring(text))
    end
end

local action = nil
local timeout = 0

for i = 1, #args do
    local arg = args[i]:lower()
    if arg == "-s" then
        action = "shutdown"
    elseif arg == "-r" then
        action = "reboot"
    elseif arg == "-t" and args[i+1] then
        timeout = tonumber(args[i+1]) or 0
    end
end

if not action then
    print("Usage: shutdown [-s | -r] [-t msg_time]")
    print("   -s    Shutdown the computer.")
    print("   -r    Shutdown and restart the computer.")
    print("   -t    Set the time-out period before shutdown to xx seconds.")
    return
end

if timeout > 0 then
    print(string.format("System shutdown in %d seconds...", timeout))
    for i = timeout, 1, -1 do
        _G.KeDelayExecutionThread(1)
    end
end

local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua") or _G.ntdll

if action == "shutdown" then
    print("Shutting down the system...")
    _G.KeDelayExecutionThread(0.5)
    if _G.PerformSystemShutdown then _G.PerformSystemShutdown() end
elseif action == "reboot" then
    print("Restarting the system...")
    _G.KeDelayExecutionThread(0.5)
    if _G.PerformSystemShutdown then _G.RebootSet=true _G.PerformSystemShutdown() end
end