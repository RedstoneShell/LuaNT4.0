# API Documentation for LuaNT 4.0
**WARNING: This Documentation for user-mode, and kernel-mode programs, more functions from kernel is UNACCESSABLE for user-mode! Use kernel functions at own risk!!!**

## User-mode
Big count of API maked for user/kernel mode, here, everything what you accessable.
Format:        \/ Func                                      File \/
### ntdll.NtQuerySystemInformation(): table                 ntdll.lua
Simple function to get information of currently runned processes (Co-routine Task Manager, with Time Controlled Process Lifecycle). Format
```lua
table: {
  UniqueProcessId: integer,
  ImageName: string,
  BasePriority: integer,
  CurrentPriority: integer,
  Environment: string
}
```

Where:
  - UniqueProcessId, is PID of process that runs
  - ImageName, is name of this thread
  - Base/CurrentPriority, is a Priority of thread (see also, _G.sCreateSystemThread)
  - Environment, is a token of thread

### ntdll.NtOpenFileEx(path, mode): table|nil, string|table    ntdll.lua
Extended NtOpenFile but for disks, example "C:/Windows/System32/ntdll.lua" or "E:/lib/core/boot.lua". First param is string, just path with disk letter at start (see disk to access in MyPC menu, or registry).
Second is mode to open, it's string, parameters also from OpenOS, if you know, it's easy. Returns data, first is a handle of file, or "nil" at error, second is a filesystem object, just component.proxy of filesystem of disk selected by letter.

### ntdll.NtReadFileEx(handle, fs, bytes): string|nil, string  ntdll.lua
ONLY WORKS with NtOpenFileEx!
Read file by his handle at first agr, second arg is "filesystem" getted by NtOpenFileEx, third arg is so many bytes read. Returns at first arg a data or nil at error, second is error "INVALID_FILESYSTEM", if filesystem that you place, is invalid.

### ntdll.NtWriteFileEx(handle, fs, data): boolean|nil, string ntdll.lua
ONLY WORKS with NtOpenFileEx!
Is a copy of NtReadFileEx, but third arg is data, what you need to write. Returns "true" if OK, nil and error of NOT OK.

### ntdll.NtListDirectoryEx(path): func->string|nil, string    ntdll.lua
Is copy of NtOpenFileEx, but returns an iterator over all elements in the directory at the specified path.
Returns nil and an error messages if the path is invalid or some other error occurred.

### ntdll.NtFileExistsEx(path): boolean                        ntdll.lua
Is copy of NtOpenFileEx, but check if file at this path exists. Returns "true" if exists, "false" is not.

### ntdll.NtTerminateProcess(pid): boolean, string             ntdll.lua
Terminates process by his PID, returns "true" and STATUS_SUCCESS if OK, "false" and "STATUS_OBJECT_NAME_NOT_FOUND" in NOT OK

### ntdll.NtCreateUserProcess(path, name, priority, commandLineArgs): integer|nil, string  ntdll.lua
WARNING! Unsupport disk letters, only disk C: (Boot Disk)!
The longest function in "ntdll.lua", he start proccess by path in first, and name in second arg, by priority at third args (see also: Process Priorities) and arguments in fourth.
Function launch proccess in isolated system where critical functions inaccessable.
Returns process PID if OK, nil and error if NOT OK,

### ntdll.NtDelayExecution()                                   ntdll.lua
Just call "coroutine.yield" for Multi-Task Controller get work to other processes.



### _G.RpcSs.RpcServerRegisterIf(interfaceName, methodsTable): boolean RpcSs.lua
Creates a interface, with name in first arg, and methods is second arg, example
```lua
-- Src, cmd.lua
if _G.RpcSs then
    local IConsoleInterface = {
        WriteStdOut = function(text)
            consolePrint(text)
            return true
        end,
        
        ReadStdIn = function()
            return consoleRead()
        end,

        GetProcessArgs = function()
            return LastSpawnedArgs
        end
    }
    _G.RpcSs.RpcServerRegisterIf("IConsoleManager", IConsoleInterface)
end
```
Returns true if interface created, false if NOT.

### _G.RpcSs.RpcServerUnregisterIf(interfaceName): boolean     RpcSs.lua
Unregister interface by name at first arg, returns "true", if removed, "false", in error, example:
```lua
-- Src, cmd.lua
if _G.RpcSs then _G.RpcSs.RpcServerUnregisterIf("IConsoleManager") end
```

### _G.RpcSs.RpcCliExecute(interfaceName, methodName, ...): boolean, void RpsSs.lua
Creates Protected Call to interface in first args, method in second arg and arguments in "..."(big count of args), returns "true" if ok and "void" is a return type provided by method that you call.
Example, get arguments received by Console (cmd.lua):
```lua
-- Src, net.lua
local rpcOk, args = _G.RpcSs.RpcCliExecute("IConsoleManager", "GetProcessArgs")
args = args or {}
local command = args[1]
local serviceName = args[2]
...
```
