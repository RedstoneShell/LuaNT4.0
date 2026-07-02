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

### shell32.RegisterIcon(icon, x, y, w, h, callback): void               shell32.lua
Registers a new desktop icon with specified position, size, and event handler. The icon is drawn using predefined ASCII-art from shell32.Icons table. Supports multiple Y-positions via table for creating icon stacks or columns. First param is string, name of icon from shell32.Icons table. Second is number, X-coordinate on screen. Third is number or table, Y-coordinate or array of Y-coordinates for multiple instances. Fourth is number, width of icon in characters. Fifth is number, height of icon in lines. Sixth is function, callback that receives event table when icon is interacted with. Returns nothing.

### shell32.UnregIcon(icon, x, y): void                                  shell32.lua
Unregisters a desktop icon at specified coordinates. First param is string, name of registered icon. Second is number, X-coordinate to match. Third is number, Y-coordinate to match. Removes callback from the icon if found at exact coordinates. Returns nothing.

### shell32.DrawIcon(hdc, gdi, bkColor, x, y, iconName, label): boolean  shell32.lua
Renders an icon from the predefined set onto a graphics device context. First param is userdata, handle to device context (HDC). Second is table, GDI object for graphics operations. Third is number, background or text color to use. Fourth is number, X-coordinate for drawing. Fifth is number, Y-coordinate for drawing. Sixth is string, icon name from shell32.Icons to draw. Seventh is string|nil, optional label text displayed below the icon. Returns true if icon was found and drawn, false if icon name doesn't exist in shell32.Icons.

### shell32.Icons: table                                                 shell32.lua
Predefined table containing ASCII-art icon definitions for system elements. Each icon is stored as an array of strings (4 lines x 6 characters). Available icons: "MyPC", "YesNetwork", "NoNetwork", "RecycleBin", "Drive", "Drive_Error", "Floppy", "SetupMgr", "StartButton", "Notepad". Used as source for DrawIcon and RegisterIcon functions.

### shell32.DeskIcon: table                                              shell32.lua
Internal storage table holding all registered desktop icons. Each entry contains: x (number), y (number|table), w (number), h (number), callback (function). Called by HandleClick to detect icon interactions.



### _G.WUSVC.UpdateAvailable: boolean                                    wusvc.lua
Indicates whether a newer version is available. Set automatically during update checks. Read-only property, updated by service each check interval.

### _G.WUSVC.LatestVersion: string                                       wusvc.lua
Latest version string available from update server. Example: "4.0.2.0". Read-only property, populated from update center data.

### _G.WUSVC.CurrentVersion: string                                      wusvc.lua
Current running OS version retrieved from registry or default value. Read-only property, used to compare with LatestVersion.

### _G.WUSVC.UpdateData: table                                           wusvc.lua
Complete update data from server containing version info and file list. Includes fields like latest_version, files (array of file paths), and other metadata. Read-only property, updated after each successful check.

### _G.WUSVC.CheckedAt: number                                           wusvc.lua
Timestamp (os.time) of last successful update check. Read-only property, automatically updated after each fetch.

### IWindowsUpdate.WinUpdAvailable(): boolean
Returns true if update is available, false if system is up to date.
Example:

```lua
local ok, available = _G.RpcSs.RpcCliExecute("IWindowsUpdate", "WinUpdAvailable")
if ok and available then _G.DbgPrint("Update available!") end
```

### IWindowsUpdate.GetLatestVersion(): string
Returns latest version string from update server.
Example:
```lua
local ok, version = _G.RpcSs.RpcCliExecute("IWindowsUpdate", "GetLatestVersion")
if ok then _G.DbgPrint("Latest:", version) end
```

### IWindowsUpdate.GetCurrentVersion(): string
Returns current running OS version string.
Example:
```lua
local ok, version = _G.RpcSs.RpcCliExecute("IWindowsUpdate", "GetCurrentVersion")
if ok then _G.DbgPrint("Current:", version) end

### IWindowsUpdate.CheckForUpdates(): boolean
Manually triggers update check. Returns true if update available, false if up to date or error.
Example:
```lua
local ok, hasUpdate = _G.RpcSs.RpcCliExecute("IWindowsUpdate", "CheckForUpdates")
if ok and hasUpdate then _G.DbgPrint("New update found!") end
```

### IWindowsUpdate.GetUpdateInfo(): table
Returns complete update data table from server (latest_version, files, etc.).
Example:

```lua
local ok, info = _G.RpcSs.RpcCliExecute("IWindowsUpdate", "GetUpdateInfo")
if ok and info then _G.DbgPrint("Files:", #info.files) end
```

### IWindowsUpdate.GetSavedInfo(): table
Returns previously saved update data from local storage (Windows/WinSxS/updates/wusig.json). Useful for accessing cached update information.
Example:
```lua
local ok, saved = _G.RpcSs.RpcCliExecute("IWindowsUpdate", "GetSavedInfo")
if ok and saved then _G.DbgPrint("Saved data found") end
```



### evapi.PlFltr(name, ...): function|nil                                etw.lua
Creates a filter function for event matching. First param is string, event name pattern (Lua pattern matching). Subsequent params are filter values for event arguments. Returns a filter function that accepts a signal and returns true if matches all criteria. Returns nil if no name provided and no filters specified.
Parameters:
  - name (string|nil) - Pattern to match against event[1] (event name)
  - ... (any) - Additional values to match against event[2], event[3], etc.

Returns: function(signal) -> boolean or nil
Example:
```lua
local filter = evapi.PlFltr("mouse_click", 1)  -- Matches left mouse clicks only
if filter({"mouse_click", 1, 100, 200}) then
    -- Matched!
end
```

### evapi.ReadData(...): any                                             etw.lua
High-level function to read events with filtering. Supports two calling patterns:
ReadData(name, filters...) - Creates filter from name and values
ReadData(timeout, filter) - Uses existing filter function with timeout
Parameters:
  - Pattern 1: name (string), ... (filter values) - Event name pattern and arguments to match
  - Pattern 2: timeout (number|nil), filter (function) - Timeout in seconds and filter function
Returns: Event signal as multiple return values, or nil on timeout
Example:

```lua
-- Simple event reading with filter
local event = evapi.ReadData("key_down", 1)  -- Wait for '1' key press
-- Or with timeout
local ev = evapi.ReadData(5, function(s) return s[1] == "mouse_click" end)
```

### evapi.ReadETWFiltered(...): any                                      etw.lua
Core function for reading events with timeout and filter. Blocks until event matches filter or timeout expires. Uses computer.pullSignal for event retrieval.
Parameters:
  - timeout (number|nil) - Maximum seconds to wait (default: math.huge)
  - filter (function|nil) - Filter function that returns true for matching events
Returns: Event signal as multiple return values, or nil on timeout



### GDI Constants
Colors:
  - GDI.COLOR_BLUE (0x0000AA) - Standard blue
  - GDI.COLOR_GRAY (0xAAAAAA) - Standard gray
  - GDI.COLOR_WHITE (0xFFFFFF) - White
  - GDI.COLOR_DARK_GRAY (0x555555) - Dark gray
  - GDI.COLOR_BLACK (0x000000) - Black

Background Modes:
  - GDI.TRANSPARENT (1) - Transparent background (text without background fill)
  - GDI.OPAQUE (2) - Opaque background (text with background fill)

Raster Operations (ROP codes):

  - GDI.PATCOPY (3160021) - Copy brush pattern
  - GDI.PATINVERT (3600049) - Invert brush pattern
  - GDI.DSTINVERT (3550009) - Invert destination
  - GDI.BLACKNESS (3000042) - Fill with black
  - GDI.WHITENESS (3176062) - Fill with white


### GDI.CreateDC(gpu_proxy): integer                                     gdi32.lua
Creates a new device context (DC) for drawing operations. First param is userdata, GPU component proxy to associate with DC. Returns integer handle to the new DC. Each DC maintains independent color settings and bounds.

Example:
```lua
local hdc = GDI.CreateDC(gpu)
```

### GDI.GetDC(hwnd): table|nil                                           gdi32.lua
Retrieves GDI object table entry for given handle. First param is integer, handle to query (0 for system DC). Returns table with object properties or nil if invalid. Use for inspecting DC state.

### GDI.PatBlt(hdc, x, y, w, h, dwRop): boolean                          gdi32.lua
Fills a rectangle with brush pattern using specified raster operation. First param is integer, device context handle. Second is number, X-coordinate. Third is number, Y-coordinate. Fourth is number, width. Fifth is number, height. Sixth is number, ROP code. Returns true on success.

ROP Effects:
  - PATCOPY - Fills with current brush color
  - BLACKNESS - Fills with black (0x000000)
  - WHITENESS - Fills with white (0xFFFFFF)
  - DSTINVERT - Inverts background color
  - PATINVERT - Inverts brush color

Example:
```lua
GDI.PatBlt(hdc, 10, 10, 20, 5, GDI.PATCOPY)  -- Draw brush-colored rectangle
GDI.PatBlt(hdc, 50, 50, 30, 10, GDI.BLACKNESS)  -- Black rectangle
```

### GDI.SetTextColor(hdc, color): number|nil                             gdi32.lua
Sets text color for device context. First param is integer, device context handle. Second is number, RGB color value. Returns previous text color or nil on error.

Example:
```lua
local oldColor = GDI.SetTextColor(hdc, 0xFF0000)  -- Red text
```

### GDI.CreateSolidBrush(clr): table                                     gdi32.lua
Creates a solid brush object with specified color. First param is number, RGB color value. Returns brush object table with type "BRUSH" and color property. Use with SelectObject to apply brush to DC.

Example:
```lua
local brush = GDI.CreateSolidBrush(0x00FF00)  -- Green brush
```

### GDI.SelectObject(hdc, hObj): table|nil                               gdi32.lua
Selects a GDI object (brush) into device context. First param is integer, device context handle. Second is table, brush object from CreateSolidBrush. Returns previous brush object or nil. Automatically updates DC's brushColor.

Example:
```lua
local brush = GDI.CreateSolidBrush(0xFF0000)
local oldBrush = GDI.SelectObject(hdc, brush)
-- Draw with red brush
GDI.PatBlt(hdc, 10, 10, 20, 20, GDI.PATCOPY)
GDI.SelectObject(hdc, oldBrush)  -- Restore previous brush
```

### GDI.SetBkMode(hdc, mode): number                                     gdi32.lua
Sets background mode for text rendering. First param is integer, device context handle. Second is number, mode (TRANSPARENT=1 or OPAQUE=2). Returns previous background mode.

Modes:
  - TRANSPARENT - Text drawn without background fill
  - OPAQUE - Text drawn with background fill using bkColor

Example:
``` lua
GDI.SetBkMode(hdc, GDI.TRANSPARENT)  -- Transparent text
GDI.SetBkMode(hdc, GDI.OPAQUE)       -- Opaque text with background
```

### GDI.SetBkColor(hdc, clr): number|nil                                 gdi32.lua
Sets background color for device context. First param is integer, device context handle. Second is number, RGB color value. Returns previous background color or nil. Affects text background when bkMode is OPAQUE.

Example:
```lua
GDI.SetBkColor(hdc, 0x000080)  -- Dark blue background
GDI.SetBkMode(hdc, GDI.OPAQUE)
GDI.TextOut(hdc, 10, 10, "Text with blue background")
```

### GDI.TextOut(hdc, x, y, text): boolean                                gdi32.lua
Outputs text at specified position using current text color and background mode. First param is integer, device context handle. Second is number, X-coordinate. Third is number, Y-coordinate. Fourth is string, text to display. Returns true on success, false if no text.

Behavior:
Uses textColor for foreground
If bkMode is OPAQUE, fills background with bkColor
If bkMode is TRANSPARENT, no background fill

Text overwrites existing characters at position
Example:
```lua
GDI.SetTextColor(hdc, 0xFFFFFF)  -- White text
GDI.SetBkColor(hdc, 0x000000)    -- Black background
GDI.SetBkMode(hdc, GDI.OPAQUE)
GDI.TextOut(hdc, 5, 10, "Hello Windows NT!")

GDI.SetBkMode(hdc, GDI.TRANSPARENT)
GDI.TextOut(hdc, 5, 12, "Transparent text overlay")
```



## Kernel-Mode
WARNING: If you make some error in user-mode script, he just crash, and Kernel Thread Garbage Collector clear data about this proccess, without crash of system. BUT if you make some ERROR is Kernel script, LuaNT immedantly CRASH with BSOD!
**ALL FUCTIONS HERE, DON'T ACCESSABLE FROM USER-MODE, ONLY IN DRIVERS, USE AT OWN RISK, SOME FUNCTIONS USAGE, CAN MAKE SYSTEM UNSTABLE, IF YOU CALL HE INCORRECTLY**

### _G.Mm: table                                                         ntoskrnl.lua
Memory Manager subsystem with the following fields:
  - TotalPhysicalMemory (number) - Total system memory in bytes
  - SystemPool (table) - System memory pool
  - PagedPool (table) - Paged memory pool (can be swapped)
  - NonPagedPool (table) - Non-paged memory pool (always in RAM)
  - PageFileSize (number) - Size of pagefile in bytes
  - PageFilePath (string) - Path to pagefile ("pagefile.sys")

### _G.Mm.AllocateNonPaged(key, value): void                             ntoskrnl.lua
Allocates memory in non-paged pool (always resident in RAM). First param is string, key identifier. Second is any value to store. Used for critical system objects that cannot be paged out.

Example:
```lua
Mm.AllocateNonPaged("\\Device\\Null", { open = function() return 999 end })
```

### _G.Mm.AllocatePaged(key, value): void                                ntoskrnl.lua
Allocates memory in paged pool (can be swapped to pagefile when memory is low). First param is string, key identifier. Second is any value to store. Automatically handles pagefile swapping when free memory falls below 32KB.

### _G.Mm.GetFreeMemory(): number                                        ntoskrnl.lua
Returns current free memory in bytes. Wrapper for computer.freeMemory().

### _G.MmZeroThreadMemory(thread): void                                  ntoskrnl.lua
Cleans up thread resources during termination. Sets thread.co, thread.args, thread.env to nil and clears all table fields. Called by garbage collector and thread termination routines.

### _G.PspActiveProcessList: table                                       ntoskrnl.lua
List of active thread objects. Each entry contains: pid, name, co (coroutine), basePriority, currentPriority, quantumLeft, token, env, args.

### _G.PsCreateSystemThread(path, name, priority, token): table|nil      ntoskrnl.lua
Creates a new system thread from Lua file. First param is string, path to Lua script. Second is string, thread name. Third is number, priority class (0-31). Fourth is table, security token. Returns thread object with PID or nil on failure.

Priorities:
  - IDLE_PRIORITY (0) - Idle process
  - NORMAL_PRIORITY (8) - Normal priority
  - REALTIME_PRIORITY (16) - Real-time priority
  - HIGH_PRIORITY (31) - Highest priority

Example:
```lua
local thread = PsCreateSystemThread("Windows/System32/services.lua", "services.exe", 8, { name = "SYSTEM" })
```

### _G.PsTerminateThread(pid): boolean                                   ntoskrnl.lua
Terminates thread by PID. First param is integer, process ID. Returns true if thread found and terminated, false otherwise. Removes thread from ready queues and active process list.

### _G.PsSetPriority(pid, newPriority): boolean                          ntoskrnl.lua
Changes priority of existing thread. First param is integer, PID. Second is integer, new priority (0-31). Moves thread to appropriate ready queue. Returns true on success.

### ReadyQueues: table                                                   ntoskrnl.lua
Internal priority-based ready queues (0-31). Each queue contains threads ready for execution. Scheduler selects highest priority non-empty queue.

### _G.CurrentThread: table                                              ntoskrnl.lua
Currently executing thread object. Used by scheduler for context tracking.

### KiSelectNextThread(): table, number                                  ntoskrnl.lua
Selects next thread for execution using priority-based scheduling. Returns thread object and its priority. Scans from highest priority (31) to lowest (0).

### KiTerminateThread(thread, prio): void                                ntoskrnl.lua
Internal function to remove thread from scheduling. Removes from ready queue and active process list. Calls MmZeroThreadMemory for cleanup.

### _G.Prcb: table                                                       ntoskrnl.lua
Processor Control Block containing DPC management:
  - IdleCount (number) - Idle cycle counter
  - CycleTime (number) - Total processor time
  - DpcQueue (table) - Queue of pending DPC objects

### _G.KeInitializeDpc(dpcObject, deferredRoutine, deferredContext): void ntoskrnl.lua
Initializes a DPC object. First param is table, DPC object. Second is function, deferred routine to execute. Third is any, context data passed to routine. Sets Inserted flag to false.

### _G.KeInsertQueueDpc(dpcObject, sysArg1, sysArg2): boolean            ntoskrnl.lua
Queues a DPC for execution. First param is table, initialized DPC object. Second and third are any, system arguments passed to routine. Returns true if inserted, false if already queued. DPCs are executed during interrupt dispatch.

### _G.KiDispatchInterrupt(): void                                       ntoskrnl.lua
Executes all pending DPCs from the queue. Called by kernel interrupt handler. Processes DPCs in FIFO order. Triggers KeBugCheckEx if DPC routine throws an exception.

Example:

```lua
local dpc = {}
KeInitializeDpc(dpc, function(obj, ctx, arg1, arg2)
    print("DPC executed with context:", ctx)
end, "my_context")
KeInsertQueueDpc(dpc, "arg1", "arg2")
```

### _G.NtOpenFile(path): function|nil, string                            ntoskrnl.lua
Opens and loads a Lua file from boot disk. First param is string, file path (relative to boot disk root). Returns compiled Lua function or nil with error message. Used internally by LdrLoadDll.

### _G.LdrLoadDll(path): table|nil, string                               ntoskrnl.lua
Loads a DLL/library file. First param is string, path to file. Executes loaded code and returns its return values. Returns nil with "STATUS_DLL_NOT_FOUND" if file missing, or "STATUS_DLL_INIT_FAILED" on execution error.

### KiInitializeFileSystems(): void                                      ntoskrnl.lua
Initializes file system devices and drive letter mappings. Detects floppy drives (A:, B:) and hard disks (C:, D:, etc.). Creates device objects in NonPagedPool and symbolic links in Drives table. Also writes disk geometry information to registry.

Drive Detection:
  - Floppy drives: \\Device\\Floppy0\\Partition0 → A:
  - Hard disks: \\Device\\Harddisk0\\Partition0 → C:
  - Media detection via disk_drive component

### _G.CreateNoMedia(): table                                            ntoskrnl.lua
Creates dummy filesystem object for empty drives. Returns table with open returning "STATUS_NO_MEDIA_IN_DEVICE", empty list, and nil media.

### _G.RegisterShutdownDriver(serviceName, driverObject): void           ntoskrnl.lua
Registers a driver to receive shutdown notification. Driver object should have DriverUnload method called during shutdown.

### _G.PerformSystemShutdown(): void                                     ntoskrnl.lua
Executes complete system shutdown sequence. Displays shutdown screens, notifies subsystems, flushes registry, unloads drivers in reverse priority order, cleans memory pools, removes temporary files, and finally powers off.

### KiInterruptDispatch(sig, addr, arg1, arg2, arg3, arg4): void         ntoskrnl.lua
Main interrupt dispatcher for system events. Handles key_down, touch, and shutdown signals.

Signal Handling:
  - key_down - Passes to winlogon and explorer
  - touch - Routes to shell32 and explorer
  - shutdown - Flushes registry and beeps

### _G.KRNL_ETW: table                                                   ntoskrnl.lua
Event Tracing for Windows subsystem. Contains signalQueue for event distribution. Used by etw.lua API.

### _G.GCInProgress: boolean                                             ntoskrnl.lua
Prevents recursive garbage collection. Set to true during GC cycles.

### _G.ThreadGC: table                                                   ntoskrnl.lua
Thread garbage collector configuration:
  - Enabled (boolean) - Enable/disable GC
  - Interval (number) - GC cycle interval (100 ticks)
  - Counter (number) - Current tick counter
  - MaxCrashes (number) - Max crashes before termination (1)
  - CrashHistory (table) - Per-thread crash counter

### _G.KiCheckThreadHealth(thread): string                               ntoskrnl.lua
Checks thread coroutine status. Returns "alive" or "dead".

### _G.KiCleanDeadThreads(): number                                      ntoskrnl.lua
Scans for and removes dead threads. Returns number of cleaned threads. Called automatically by GC scheduler.

### _G.KiHandleCrashedThread(thread, err): void                          ntoskrnl.lua
Handles crashed threads by decrementing priority and requeuing. If crash limit exceeded, terminates thread permanently.

### _G.KeDelayExecutionThread(seconds): void                             ntoskrnl.lua
Delays current thread execution. First param is number, seconds to sleep. Uses computer.pullSignal for cooperative multitasking.

### _G.HAL.HalQueryRealTimeClock(PTIME_FIELDS): void                     ntoskrnl.lua
Queries current system time. Called by explorer for clock updates. Fills table with: Year, Month, Day, Hour, Minute, Second, Milliseconds, Weekday.

