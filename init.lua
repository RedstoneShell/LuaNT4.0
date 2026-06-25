-- Windows NT Boot Loader by RedstoneShell

local c = component
local comp = computer
local screen = component.list("screen", true)()
local gpu = screen and component.list("gpu", true)()
local pc_io = c.proxy(comp.getBootAddress())

pc_io.remove("/ntbootdd.log")

_G.HAL = {
    gpu = c.proxy(gpu),
    screen = screen,
    w = 0, h = 0,
    cursorX = 1, cursorY = 1
}

_G.DebugMode = true
_G.DbgPrintToFile = true
_G.DbgLogFile = "/ntbootdd.log"
local HAL = _G.HAL
local pcall0=pcall
local string0=string.format
_G.DbgPrint = function (text)
    if not HAL.gpu then return end
    if DebugMode then
        HAL.gpu.setForeground(0xAAFFFF)
        HAL.gpu.set(HAL.cursorX, HAL.cursorY, tostring(text))
        HAL.cursorY = HAL.cursorY + 1
        if HAL.cursorY > HAL.h then
            HAL.cursorY = 1
        end
    end
    
    if DbgPrintToFile then
        pcall0(function()
            local bootDisk = component.proxy(computer.getBootAddress())
            if bootDisk and bootDisk.open then
                local f = bootDisk.open(DbgLogFile, "a")
                if f then
                    local timestamp = os.date("[%Y-%m-%d %H:%M:%S] ")
                    bootDisk.write(f, timestamp .. tostring(text) .. "\n")
                    bootDisk.close(f)
                end
            end
        end)
    end

    if _G.KeRelayDbgAtSignal then
        for address in component.list("computer") do
            if address ~= computer.address() then
                local proxy = component.proxy(address)
                if proxy and proxy.pushSignal then
                    pcall(proxy.pushSignal, "DbgPrintRelayMessage", tostring(message))
                end
            end
        end
    end
end

_G._G = _G

_G.NtOpenFile = function(path)
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

function HAL.initVideo()
    if HAL.gpu and screen then
        HAL.gpu.bind(screen);
        HAL.w, HAL.h = HAL.gpu.getResolution()
        HAL.gpu.setBackground(0x000000)
        HAL.gpu.setForeground(0xFFFFFF)
        HAL.gpu.fill(1, 1, HAL.w, HAL.h, " ")
    end
end

local function LoadBootIni()
    _G.KeRelayDbgAtSignal = false
    
    local bootFS = component.proxy(computer.getBootAddress())
    if not bootFS then
        DbgPrint("BOOT: No boot filesystem available")
        return
    end
    
    if not bootFS.exists("/boot.ini") then
        DbgPrint("BOOT: /boot.ini not found, using defaults")
        return
    end
    
    local handle, err = bootFS.open("/boot.ini", "r")
    if not handle then
        DbgPrint("BOOT: Failed to open /boot.ini: " .. tostring(err))
        return
    end
    
    local content = ""
    while true do
        local chunk = bootFS.read(handle, 512)
        if not chunk then break end
        content = content .. chunk
    end
    bootFS.close(handle)
    
    for line in content:gmatch("[^\r\n]+") do
        if not line:match("^%s*;") and not line:match("^%s*$") then
            local key, value = line:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
            if key and value then
                if key == "relayDbgAtSignal" then
                    _G.KeRelayDbgAtSignal = (value:lower() == "true" or value == "1")
                end
            end
        end
    end
end

local print=_G.DbgPrint
_G.KeBugCheckEx = function (bugCheckCode, bugCode0, bugCode1)
    print("***STOP:"..bugCheckCode..", BugCode0: "..bugCode0..", BugCode1: "..bugCode1)
    local cpuaddr = "00000000"
    local raw_id = cpuaddr:sub(1, 8):upper()
    comp.beep(440, 0.3)
    comp.beep(440, 0.3)
    comp.beep(440, 0.3)
    HAL.gpu.setBackground(0x0000FF)
    HAL.gpu.setForeground(0xFFFFFF)
    HAL.gpu.fill(1, 1, HAL.w, HAL.h, " ")
    HAL.gpu.set(5, 5, "STOP: " .. bugCheckCode)
    HAL.gpu.set(5, 7, "A problem has been detected and Windows NT has been shutdown to save all data and prevent of system damage")
    -- CTE = Code Transfer Error
    HAL.gpu.set(5, 9, "Stop codes: "..(bugCode0 or "CTE").." "..(bugCode1 or "CTE"))
    HAL.gpu.set(5,11, "Stack dump for dev-ops:")
    local line_off = 13
    pcall0(function()
        if type(bugCode0)=="string" then
            for str in bugCode0:gmatch("[^\r\n]+") do
                HAL.gpu.set(5, line_off, str)
                line_off=line_off+1
                if line_off>HAL.h-2 then break end
            end
        end
        if type(bugCode1)=="string" then
            for str in bugCode1:gmatch("[^\r\n]+") do
                HAL.gpu.set(5, line_off, str)
                line_off=line_off+1
                if line_off>HAL.h-2 then break end
            end
        end
    end)
    HAL.gpu.set(5, line_off+2, "CPUID: ".. string0("OC-LuaCore %s-%s-%s", raw_id:sub(1, 2), raw_id:sub(3, 4), raw_id:sub(5,5)) .." | Kernel Halt.")
    local function wait(s)
        local start = comp.uptime()
        local duration = s
        while duration > 0 do
            comp.pullSignal(duration)
            duration = s - (comp.uptime() - start)
        end
    end
    wait(10)
    comp.shutdown(true)
end

function _G.errorHandler(e)
    return tostring(e) .. "\n" .. debug.traceback()
end

local function wait(s)
    local start = computer.uptime()
    local duration = s
    while duration > 0 do
        computer.pullSignal(duration)
        duration = s - (computer.uptime() - start)
    end
end

LoadBootIni()



_G.CmosSettings = _G.CmosSettings or {
    haltOnAllErrors = true -- true = All Errors, false = No Errors
}

local function SaveCMOS()
    local io = component.proxy(computer.getBootAddress())
    if io then
        local f = io.open("/Boot/cmos.dat", "w")
        if f then
            local value = _G.CmosSettings.haltOnAllErrors and "1" or "0"
            io.write(f, value)
            io.close(f)
        end
    end
end

local function LoadCMOS()
    _G.CmosSettings = { haltOnAllErrors = true }
    local io = component.proxy(computer.getBootAddress())
    if io and io.exists("/Boot/cmos.dat") then
        local f = io.open("/Boot/cmos.dat", "r")
        if f then
            local data = io.read(f, 1)
            io.close(f)
            if data == "0" then
                _G.CmosSettings.haltOnAllErrors = false
            end
        end
    end
end

LoadCMOS() -- Load CMOS settings from EEPROM


if computer.getArchitecture() ~= "Lua 5.3" and _G.CmosSettings.haltOnAllErrors then
    local w,h=HAL.gpu.getResolution()
    HAL.gpu.fill(1, 1, w, h, " ")
    HAL.gpu.set(1, 1, "POST: Hardware Compatibility Check Failed.")
    HAL.gpu.set(1, 2, "ERROR: Unsupported CPU Architecture Detected!")
    HAL.gpu.set(1, 3, "Required: Lua 5.3 Core")
    HAL.gpu.set(1, 4, "Detected: "..computer.getArchitecture())
    HAL.gpu.set(1, 5, "The current system configuration cannot guarantee data integrity on this CPU.")
    HAL.gpu.set(1, 6, "System Halted. Please upgrade your CPU or EEPROM. Before Uncoverable Error left 5 seconds!")

    HAL.gpu.set(1, 10, "you can disable this check by setting CMOS>Halt On>No Errors. Use this at own risk")
    wait(5)
    goto arch_incombatible
end

computer.beep(1000, 0.1)
HAL.initVideo()
DbgPrint("Windows NT Boot Loader")
DbgPrint("Detecting hardware...")
if not HAL.gpu then
    error("No GPU found! System halted.")
end

wait(2)

local function wait(s)
    local start = computer.uptime()
    local duration = s
    while duration > 0 do
        computer.pullSignal(duration)
        duration = s - (computer.uptime() - start)
    end
end
wait(2)

local sel, oEEP, oADV, oCMOS = 1, false, false, false
local fsList = {}

local function UpdBIOSLabels()
    HAL.gpu.setBackground(0x000080)
    HAL.gpu.fill(5, 5, 45, 12, " ")

    if oEEP then
        if sel==1 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) HAL.gpu.set(5, 5, "Backup BIOS")    else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) HAL.gpu.set(5, 5, "Backup BIOS")    end
        if sel==2 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) HAL.gpu.set(5, 7, "Flash Firmware") else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) HAL.gpu.set(5, 7, "Flash Firmware") end
        if sel==3 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0xFF0000) HAL.gpu.set(5, 9, "Make Read-Only")     else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFF0000) HAL.gpu.set(5, 9, "Make Read-Only")     end
        return
    end

    if oADV then
        HAL.gpu.setForeground(0xAAFFFF)
        HAL.gpu.set(5, 4, "Select Boot Device Address:")
        if #fsList == 0 then
            HAL.gpu.setForeground(0xFF5555)
            HAL.gpu.set(5, 6, "No filesystems found!")
        else
            for i, addr in ipairs(fsList) do
                local yPos = 4 + (i * 2)
                if sel == i then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) end
                HAL.gpu.set(5, yPos, string.format("Disk: [%s...]", addr:sub(1, 12)))
            end
        end
        return
    end

    if oCMOS then
        local sHalt = _G.CmosSettings.haltOnAllErrors and "All Errors" or "No Errors "
        local totalMem = math.floor(computer.totalMemory() / 1024) .. " KB"
        
        local eepromComponent = component.list("eeprom")()
        local sChecksum = "BAD"
        if eepromComponent and component.proxy(eepromComponent).getChecksum() then
            sChecksum = "OK"
        end

        if sel==1 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) end
        HAL.gpu.set(5, 5, string.format("Halt On:         [%s]", sHalt))

        HAL.gpu.setBackground(0x000080)
        HAL.gpu.setForeground(0xBBBBBB)
        HAL.gpu.set(5, 7,  string.format("Base Memory:     [640 KB]"))
        HAL.gpu.set(5, 9,  string.format("Extended Memory: [%s]", totalMem))
        HAL.gpu.set(5, 11, string.format("BIOS Checksum:   [%s]", sChecksum))

        local maxColors = HAL.gpu.maxDepth()
        local sVideo = "Monochrome"
        if maxColors == 8 then sVideo = "8-bit (VGA)"
        elseif maxColors == 4 then sVideo = "4-bit (EGA)"
        elseif maxColors == 1 then sVideo = "Mono (Text)" end

        HAL.gpu.set(5, 13, string.format("Video Type:      [%s]", sVideo))
        return
    end

    if sel==1 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) HAL.gpu.set(5, 5, "Standard CMOS Setup")    else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) HAL.gpu.set(5, 5, "Standard CMOS Setup")   end
    if sel==2 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) HAL.gpu.set(5, 7, "Advanced BIOS Features") else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) HAL.gpu.set(5, 7, "Advanced BIOS Features") end
    if sel==3 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) HAL.gpu.set(5, 9, "Integrated Peripherals") else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) HAL.gpu.set(5, 9, "Integrated Peripherals") end
    if sel==4 then HAL.gpu.setBackground(0xFFFFFF) HAL.gpu.setForeground(0x000000) HAL.gpu.set(5,11, "EEPROM")                 else HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0xFFFFFF) HAL.gpu.set(5,11, "EEPROM")                end
end

local function HandleBIOSOpen(eeprom)
    if sel==1 and not oEEP and not oADV and not oCMOS then
        oCMOS = true
        sel = 1
        UpdBIOSLabels()
        return
    end

    if oCMOS then
        if sel == 1 then
            _G.CmosSettings.haltOnAllErrors = not _G.CmosSettings.haltOnAllErrors
            computer.beep(880, 0.05)
            SaveCMOS()
            UpdBIOSLabels()
        end
        return
    end

    if sel==2 and not oEEP and not oADV and not oCMOS then
        oADV = true
        fsList = {}
        for address in component.list("filesystem") do table.insert(fsList, address) end
        sel = 1
        UpdBIOSLabels()
        return
    end

    if oADV then
        if fsList[sel] then
            local target_disk = fsList[sel]
            computer.beep(880, 0.1)
            eeprom.setData(target_disk)
            HAL.gpu.setBackground(0x000080) HAL.gpu.setForeground(0x55FF55)
            HAL.gpu.set(5, HAL.h-12, "Boot disk address saved to EEPROM!")
            wait(1.5)
            HAL.gpu.set(5, HAL.h-12, string.rep(" ", 40))
        end
        return
    end

    if sel==4 and not oEEP and not oADV and not oCMOS then
        oEEP = true
        sel = 1
        UpdBIOSLabels()
        return
    end

    if sel==1 and oEEP then
        local code = eeprom.get()
        local io = component.proxy(computer.getBootAddress())
        computer.beep(1000, 0.3)
        local f = io.open("/Boot/bios.lua", "w")
        if f then io.write(f, code) io.close(f) end
        f=io.open("/Boot/dataDump.rom", "w")
        if f then
            local data=eeprom.getData()
            computer.beep(450, 0.3)
            io.write(f, data) io.close(f)
        end
    end
    if sel==2 and oEEP then
        local io = component.proxy(computer.getBootAddress())
        local f = io.open("/Boot/bios.lua", "r")
        local data = io.read(f, 4096)
        io.close(f)
        if #data<=4096 then eeprom.set(data) HAL.gpu.fill(0, 0, HAL.w+1, HAL.h+1, " ") HAL.gpu.set(50, 9, "BIOS Updated! Computer rebooted...") wait(3) computer.shutdown(true) end
    end
    if sel==3 and oEEP then
        computer.beep(1000, 0.3) computer.beep(550, 1)
        eeprom.makeReadonly(eeprom.getChecksum())
    end
end

local sig, addr, arg1, arg2 = computer.pullSignal(0.1)
if arg2==211 then
    local label = "OCBIOS EEPROM SIMPLE SETUP UTILITY - (C) 2026 RedstoneShell"
    HAL.gpu.setBackground(0x000080)
    HAL.gpu.fill(0, 0, HAL.w+1, HAL.h+1, " ")
    HAL.gpu.set(math.floor((HAL.w-#label)/2), 1, label)
    for i=3,HAL.h do
        if i==HAL.h-10 then HAL.gpu.set(0, i, "╚") HAL.gpu.set(HAL.w, i, "╝") break
        else HAL.gpu.set(1, i, "║") HAL.gpu.set(HAL.w, i, "║") end
    end
    for i=1,HAL.w do
        if i==1 then HAL.gpu.set(i, 2, "╔") HAL.gpu.set(i, HAL.h-10, "╚")
        elseif i==HAL.w then HAL.gpu.set(i, 2, "╗") HAL.gpu.set(i, HAL.h-10, "╝")
        else HAL.gpu.set(i, 2, "═") HAL.gpu.set(i, HAL.h-10, "═") end
    end
    for i=2,HAL.h do if i==2 then HAL.gpu.set(math.floor((HAL.w-1)/2), i, "╤") goto cont end HAL.gpu.set(math.floor((HAL.w-1)/2), i, "┃") if i==HAL.h-10 then HAL.gpu.set(math.floor((HAL.w-1)/2), i, "╧") break end ::cont:: end
    
    UpdBIOSLabels()
    local eeprom = component.proxy(component.list("eeprom")())
    
    local function drawSystemInfo()
        HAL.gpu.setBackground(0x000080)
        HAL.gpu.setForeground(0xFFFFFF)
        HAL.gpu.set(5, 25, "System Info:")
        HAL.gpu.set(5, 26, "Address:       "..eeprom.address)
        HAL.gpu.set(5, 27, "Type:          "..eeprom.type.."   ("..eeprom.getLabel()..")")
        local saved_boot = eeprom.getData()
        if saved_boot == "" then saved_boot = "None (Auto)" end
        HAL.gpu.set(5, 28, "Boot Address:  "..saved_boot)
    end
    drawSystemInfo()

    HAL.gpu.setBackground(0x555555)
    HAL.gpu.fill(1, HAL.h-8, HAL.w, 13, " ")
    HAL.gpu.set(3, HAL.h-7, "F10: Exit       ^v: Select       ENTER: Open/Toggle       <: Back")

    while true do 
        local sig, addr, arg1, arg2 = computer.pullSignal(0.1) 
        
        if arg2==208 then 
            local maxLimit = 4
            if oEEP then maxLimit = 3 elseif oADV then maxLimit = #fsList elseif oCMOS then maxLimit = 1 end
            if sel < maxLimit then sel=sel+1 else sel=1 end 
            UpdBIOSLabels() wait(0.15) 
        end
        
        if arg2==200 then 
            local maxLimit = 4
            if oEEP then maxLimit = 3 elseif oADV then maxLimit = #fsList elseif oCMOS then maxLimit = 1 end
            if sel > 1 then sel=sel-1 else sel=maxLimit end 
            UpdBIOSLabels() wait(0.15) 
        end
        
        if arg2==203 then
            if oEEP or oADV or oCMOS then
                if oADV then sel = 2 elseif oCMOS then sel = 1 else sel = 4 end
                oEEP = false oADV = false oCMOS = false
                UpdBIOSLabels()
                drawSystemInfo()
                wait(0.2)
            end
        end
        
        if arg2==68 then HAL.gpu.setBackground(0x000000) HAL.gpu.fill(0, 0, HAL.w+1, HAL.h+1, " ") break end 
        
        if arg2==28 then 
            HandleBIOSOpen(eeprom) 
            drawSystemInfo()
            wait(0.2) 
        end
    end
end

local function ApplyWinSxSUpdates()
    DbgPrint("LuaNT Update: Checking for pending updates in WinSxS...")
    
    local bootFS = pc_io
    if not bootFS or not bootFS.exists then
        DbgPrint("LuaNT Update: Boot filesystem not available")
        return
    end

    if not bootFS.exists("Windows/WinSxS") then
        DbgPrint("LuaNT Update: No WinSxS directory found")
        return
    end

    local items = bootFS.list("Windows/WinSxS")
    if not items or #items == 0 then
        DbgPrint("LuaNT Update: WinSxS is empty")
        return
    end

    local hasUpdates = false
    for _, item in ipairs(items) do
        if item ~= "updates" then
            hasUpdates = true
            break
        end
    end

    if not hasUpdates then
        DbgPrint("LuaNT Update: No pending updates found (only updates folder)")
        return
    end
    
    HAL.gpu.setBackground(0x000080)
    HAL.gpu.setForeground(0xFFFF00)
    HAL.gpu.fill(1, 1, HAL.w, 3, " ")
    HAL.gpu.set(1, 1, "LuaNT Update: Updating system, don't shutdown our PC or data corrupted!")
    HAL.gpu.set(1, 2, "Please wait...")
    
    wait(2)

    local function CopyDirectory(src, dst)
        if not bootFS.exists(src) or src=="Windows/WinSxS/update/wusig.json" then return end
        
        local srcItems = bootFS.list(src)
        if not srcItems then return end
        
        if not bootFS.exists(dst) then
            pcall(bootFS.makeDirectory, dst)
        end
        
        for _, item in ipairs(srcItems) do
            local srcPath = src .. "/" .. item
            local dstPath
            
            if src == "Windows/WinSxS" then
                dstPath = item
            else
                dstPath = dst .. "/" .. item
            end
            
            local isDir = false
            local subItems = bootFS.list(srcPath)
            if subItems and #subItems > 0 then
                isDir = true
            end
            
            if isDir then
                CopyDirectory(srcPath, dstPath)
            else
                DbgPrint("LuaNT Update: Copying " .. srcPath .. " -> " .. dstPath)
                
                local srcHandle = bootFS.open(srcPath, "rb")
                if srcHandle then
                    local content = ""
                    while true do
                        local chunk = bootFS.read(srcHandle, 4096)
                        if not chunk then break end
                        content = content .. chunk
                    end
                    bootFS.close(srcHandle)
                    
                    local dstHandle = bootFS.open(dstPath, "w")
                    if dstHandle then
                        bootFS.write(dstHandle, content)
                        bootFS.close(dstHandle)
                        DbgPrint("LuaNT Update: Copied " .. item)
                    else
                        DbgPrint("LuaNT Update: Failed to write " .. dstPath)
                    end
                else
                    DbgPrint("LuaNT Update: Failed to open " .. srcPath)
                end
            end
        end
    end

    local itemsToCopy = {}
    for _, item in ipairs(items) do
        if item ~= "updates" then
            table.insert(itemsToCopy, item)
        end
    end

    for _, item in ipairs(itemsToCopy) do
        local srcPath = "Windows/WinSxS/" .. item
        local dstPath = item
        
        if bootFS.isDirectory and bootFS.isDirectory(srcPath) then
            CopyDirectory(srcPath, dstPath)
        else
            DbgPrint("LuaNT Update: Copying " .. srcPath .. " -> " .. dstPath)
            local srcHandle = bootFS.open(srcPath, "rb")
            if srcHandle then
                local content = ""
                while true do
                    local chunk = bootFS.read(srcHandle, 4096)
                    if not chunk then break end
                    content = content .. chunk
                end
                bootFS.close(srcHandle)
                
                local dstHandle = bootFS.open(dstPath, "w")
                if dstHandle then
                    bootFS.write(dstHandle, content)
                    bootFS.close(dstHandle)
                    DbgPrint("LuaNT Update: Copied " .. item)
                else
                    DbgPrint("LuaNT Update: Failed to write " .. dstPath)
                end
            else
                DbgPrint("LuaNT Update: Failed to open " .. srcPath)
            end
        end
    end

    DbgPrint("LuaNT Update: All updates applied successfully!")

    DbgPrint("LuaNT Update: Removing WinSxS directory...")
    
    local function RemoveDirectory(path)
        if not bootFS.exists(path) then return end
        
        local items = bootFS.list(path)
        if items then
            for _, item in ipairs(items) do
                local fullPath = path .. "/" .. item
                local subItems = bootFS.list(fullPath)
                if subItems and #subItems > 0 then
                    RemoveDirectory(fullPath)
                else
                    pcall(bootFS.remove, fullPath)
                end
            end
        end
        pcall(bootFS.remove, path)
    end
    
    RemoveDirectory("Windows/WinSxS")
    DbgPrint("LuaNT Update: WinSxS removed successfully!")
    DbgPrint("LuaNT Update: Rebooting system...")
    HAL.gpu.setBackground(0x000080)
    HAL.gpu.setForeground(0x00FF00)
    HAL.gpu.fill(1, 1, HAL.w, 3, " ")
    HAL.gpu.set(1, 1, "LuaNT Update: System updated successfully!")
    HAL.gpu.set(1, 2, "Rebooting...")
    wait(2)
    
    computer.shutdown(true)
end


ApplyWinSxSUpdates()
pc_io.remove("Windows/WinSxS")

DbgPrint("Loading 'ntoskrnl', waiting 3 seconds for initializing OpenComputers hardware...")
wait(3)
local krnl_file="Windows/System32/ntoskrnl.lua"
local krnl_func, load_err = NtOpenFile(krnl_file)

if not krnl_func then
    -- Alternate method to load "ntoskrnl.lua", if NtOpenFile didn't work by strange reason.
    -- Thx OpenOS for this loader from /init.lua
    do
        local addr, invoke = computer.getBootAddress(), component.invoke
        local function loadfile(file)
            local handle = assert(invoke(addr, "open", file))
            local buffer = ""
            repeat
            local data = invoke(addr, "read", handle, math.maxinteger or math.huge)
            buffer = buffer .. (data or "")
            until not data
            invoke(addr, "close", handle)
            return load(buffer, "=" .. file, "bt", _G)
        end
        krnl_func = loadfile("/Windows/System32/ntoskrnl.lua")
        if not krnl_func then
            KeBugCheckEx("0x00000021", "LDR_SYNTAX_ERROR", tostring(load_err)..", or OpenComputers hardware not initialized, PC reboot after 10s.")
        end
    end
end

local BSOD = _G.KeBugCheckEx
DbgPrint("Receiving control to 'ntoskrnl'")
local status, err = xpcall(krnl_func, errorHandler)
if not status then
    BSOD("0x00000021", err, "")
end

::arch_incombatible::
