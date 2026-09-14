local explorer = {}
explorer.gdi32 = nil
explorer.s32 = nil
explorer.gpu = nil
explorer.screen = nil
explorer.openedMenu = nil
explorer.modalBtns = nil
explorer.startMenuOpen = false
explorer.startMenuItems = {}
local kernel32, selDsk, currPath, openCoverMenu, skip, rasapi32, event, inetCard, ndiswan = LdrLoadDll("Windows/System32/kernel32.lua"), "", "/", false, true, LdrLoadDll("/Windows/System32/rasapi32.lua"), LdrLoadDll("/Windows/System32/etw.lua"), false, LdrLoadDll("/Windows/System32/drivers/ndiswan.lua")

local LDM = _G.Tier2CM == true
local screenW, screenH = _G.HAL.gpu.w, _G.HAL.gpu.h
local WIN_MULT = LDM and 0.5 or 1.0

function explorer.Desktop(gdi, gpu, s32, profile)
    explorer.gdi32 = gdi
    explorer.gpu = gpu
    explorer.s32 = s32
    explorer.screen = { width = gpu.w, height = gpu.h }

    local LDM = _G.Tier2CM == true

    local hdc = gdi.GetDC(0)

    -- Фон
    local hDeskB = gdi.CreateSolidBrush(0x008080)
    gdi.SelectObject(hdc, hDeskB)
    gdi.PatBlt(hdc, 0, 0, gpu.w, gpu.h, gdi.PATCOPY)

    local tbh = LDM and 3 or 6
    local hTaskB = gdi.CreateSolidBrush(0xCCCCCC)
    gdi.SelectObject(hdc, hTaskB)
    gdi.PatBlt(hdc, 0, gpu.h - tbh + 1, gpu.w, tbh, gdi.PATCOPY)

    _G.StartMenuOpen = false

    local function DrawStartMenu(open)
        local hdc = gdi.GetDC(0)

        local mX, mY, mW, mH
        local menuItems = {}
        local iconW = 12

        if LDM then
            mX, mY, mW, mH = 2, (_G.HAL.h or gpu.h) - 12, 15, 10
            menuItems = {
                { "Task Manager", 1 },
                { "Device Manager", 2 },
                { "User Manager", 3 },
                { "File Manager", 4 },
                { "──────────", 5 },
                { "Run...", 6 },
                { "Shut Down...", 7 },
                { "Color Setup...", 8 },
            }
        else
            mX, mY, mW, mH = 2, (_G.HAL.h or gpu.h) - 19, 20, 14
            menuItems = {
                { "Task Manager", 1 },
                { "Device Manager", 3 },
                { "User Manager", 4 },
                { "File Manager", 6 },
                { "──────────────", 7 },
                { "Run...", 8 },
                { "Color Setup...", 12 },
                { "Shut Down...", 10 },
            }
        end

        if open then
            gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xC0C0C0))
            gdi.PatBlt(hdc, mX, mY, mW, mH, gdi.PATCOPY)

            gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
            gdi.PatBlt(hdc, mX, mY, 2, mH, gdi.PATCOPY)

            gdi.SetTextColor(hdc, 0xFFFFFF)
            gdi.SetBkColor(hdc, 0xC0C0C0)

            for _, item in ipairs(menuItems) do
                gdi.TextOut(hdc, mX + 3, mY + item[2], item[1]:sub(1, mW - 4))
            end

            if LDM then
                s32.RegisterIcon("Start_TaskMgr", mX + 3, mY + 1, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/System32/taskmgr.lua", "taskmgr.exe", 8, { name = "SYSTEM", group = "SYSTEM" })
                    end
                end)

                s32.RegisterIcon("Start_DevMgr", mX + 3, mY + 2, 14, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/System32/devmgr.lua", "devmgr.exe", 8, { name = "Administrator", group = "ADMINS" })
                    end
                end)

                s32.RegisterIcon("Start_UserMgr", mX + 3, mY + 3, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/System32/usrmgr.lua", "usrmgr.exe", 8, { name = "Administrator", group = "ADMINS" })
                    end
                end)

                s32.RegisterIcon("Start_MyComputer", mX + 3, mY + 4, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/explorer_n.lua", "explorer.exe", 8, { name = "Administrator", group = "ADMINS" })
                    end
                end)

                s32.RegisterIcon("Start_Run", mX + 3, mY + 6, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        explorer.RunDialog(gdi, gpu, s32)
                    end
                end)

                s32.RegisterIcon("Start_Shutdown", mX + 3, mY + 7, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        if _G.PerformSystemShutdown then _G.PerformSystemShutdown() else _G.HAL.halt() end
                    end
                end)

                s32.RegisterIcon("Start_Color", mX + 3, mY + 8, 13, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        explorer.ColorSetup(gdi, gpu, s32)
                    end
                end)
            else
                s32.RegisterIcon("Start_TaskMgr", mX + 3, mY + 1, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/System32/taskmgr.lua", "taskmgr.exe", 8, { name = "SYSTEM", group = "SYSTEM" })
                    end
                end)

                s32.RegisterIcon("Start_DevMgr", mX + 3, mY + 3, 14, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/System32/devmgr.lua", "devmgr.exe", 8, { name = "Administrator", group = "ADMINS" })
                    end
                end)

                s32.RegisterIcon("Start_UserMgr", mX + 3, mY + 4, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/System32/usrmgr.lua", "usrmgr.exe", 8, { name = "Administrator", group = "ADMINS" })
                    end
                end)

                s32.RegisterIcon("Start_MyComputer", mX + 3, mY + 6, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        _G.PsCreateSystemThread("Windows/explorer_n.lua", "explorer.exe", 8, { name = "Administrator", group = "ADMINS" })
                    end
                end)

                s32.RegisterIcon("Start_Run", mX + 3, mY + 8, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        explorer.RunDialog(gdi, gpu, s32)
                    end
                end)

                s32.RegisterIcon("Start_Shutdown", mX + 3, mY + 10, 12, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        if _G.PerformSystemShutdown then _G.PerformSystemShutdown() else _G.HAL.halt() end
                    end
                end)

                s32.RegisterIcon("Start_Color", mX + 3, mY + 12, 13, 1, function(a)
                    if a[1] == "OPEN" then
                        _G.StartMenuOpen = false
                        DrawStartMenu(false)
                        explorer.ColorSetup(gdi, gpu, s32)
                    end
                end)
            end
        else
            gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x008080))
            gdi.PatBlt(hdc, mX, mY, mW, mH, gdi.PATCOPY)
            s32.UnregIcon("Start_TaskMgr", mX + 3, mY + 1)
            s32.UnregIcon("Start_DevMgr", mX + 3, mY + 3)
            s32.UnregIcon("Start_UserMgr", mX + 3, mY + 4)
            s32.UnregIcon("Start_Run", mX + 3, mY + 8)
            s32.UnregIcon("Start_Color", mX + 3, mY + 12)
            s32.UnregIcon("Start_Shutdown", mX + 3, mY + 10)

            if s32.DrawDesktopIcons then s32.DrawDesktopIcons() end
        end
    end
    local startW, startH
    if LDM then
        startW, startH = 6, 1
    else
        startW, startH = 9, 1
    end

    s32.DrawIcon(hdc, gdi, 0x0000AA, 2, gpu.h - 3, "StartButton", "Computer")
    s32.RegisterIcon("StartButton", 2, gpu.h - 3, startW, startH, function(args)
        if args[1] == "OPEN" or args[1] == "MENU" then
            _G.StartMenuOpen = not _G.StartMenuOpen
            DbgPrint("EXPLORER: Toggle Start Menu. State: " .. tostring(_G.StartMenuOpen))
            DrawStartMenu(_G.StartMenuOpen)
        end
    end)

    KeDelayExecutionThread(1)

    if LDM then
        s32.DrawIcon(hdc, gdi, 0xFFFFFF, 2, 2, "MyPC", "My PC")
        s32.DrawIcon(hdc, gdi, 0x555555, gpu.w - 10, gpu.h - 3, "NoNetwork", "")
        s32.DrawIcon(hdc, gdi, 0x0000A0, 2, 6, "SetupMgr", "Setup")
        s32.DrawIcon(hdc, gdi, 0x0000A0, 2, 10, "Notepad", "Notepad")
        s32.DrawIcon(hdc, gdi, 0x0000A0, 8, 2, "AppCenter", "SMS")
        s32.DrawIcon(hdc, gdi, 0x000055, gpu.w - 6, 6, "IE", "IE")
    else
        s32.DrawIcon(hdc, gdi, 0xFFFFFF, 2, 2, "MyPC", "My PC")
        s32.DrawIcon(hdc, gdi, 0x555555, gpu.w - 19, gpu.h - 4, "NoNetwork", "")
        s32.DrawIcon(hdc, gdi, 0x0000A0, 2, 8, "SetupMgr", "Setup Mgr")
        s32.DrawIcon(hdc, gdi, 0x0000A0, 2, 14, "Notepad", "Notepad")
        s32.DrawIcon(hdc, gdi, 0x0000A0, 10, 2, "AppCenter", "SMS")
        s32.DrawIcon(hdc, gdi, 0xAA0000, gpu.w - 10, 2, "Minesweeper", "Minesweeper")
        s32.DrawIcon(hdc, gdi, 0x000055, gpu.w - 10, 8, "IE", "Internet Explorer")
    end
    local myPcW, myPcH
    if LDM then
        myPcW, myPcH = 5, 2
    else
        myPcW, myPcH = 5, 4
    end
    s32.RegisterIcon("MyPC", 2, 2, myPcW, myPcH, function(args)
        if args[1] == "OPEN" then
            explorer.OpenMyPc(gdi, gpu, s32)
        elseif args[1] == "MENU" then
            local clickX, clickY = args.click[1] + 1, args.click[2]
            local hdc = explorer.gdi32.GetDC(0)

            explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0xCCCCCC))
            explorer.gdi32.PatBlt(hdc, clickX, clickY, 14, 2, explorer.gdi32.PATCOPY)

            local isInstallAllowed = component.proxy(computer.getBootAddress()).spaceTotal() == 524288

            if isInstallAllowed then
                explorer.gdi32.SetTextColor(hdc, 0x000000)
            else
                explorer.gdi32.SetTextColor(hdc, 0x777777)
            end
            explorer.gdi32.TextOut(hdc, clickX + 1, clickY, "Install To...")

            explorer.gdi32.SetTextColor(hdc, 0x000000)
            explorer.gdi32.TextOut(hdc, clickX + 1, clickY + 1, "Properties")

            explorer.RegisterMenu(clickX, clickY, {
                "Install To..." .. (isInstallAllowed and "" or "_DISABLED"),
                "Properties"
            })

            openCoverMenu = true
        end
    end)
    local netW, netH
    if LDM then
        netW, netH = 5, 2
    else
        netW, netH = 6, 4
    end
    s32.RegisterIcon("NoNetwork", gpu.w - 10, gpu.h - 3, netW, netH, function(args)
        if args[1] == "OPEN" then explorer.INET_PLS(gdi, gpu, s32) end
    end)
    local setupW, setupH
    if LDM then
        setupW, setupH = 5, 2
    else
        setupW, setupH = 6, 4
    end
    s32.RegisterIcon("SetupMgr", 2, 6, setupW, setupH, function(args)
        if args[1] == "OPEN" then explorer.OpenSetupMgr(gdi, gpu, s32) end
    end)
    local appW, appH
    if LDM then
        appW, appH = 5, 2
    else
        appW, appH = 6, 4
    end
    s32.RegisterIcon("AppCenter", 8, 2, appW, appH, function(args)
        if args[1] == "OPEN" then _G.PsCreateSystemThread("Windows/System32/sms.lua", "sms.exe", 8, { name = "USER", group = "USER" }) end
    end)
    local noteW, noteH
    if LDM then
        noteW, noteH = 5, 2
    else
        noteW, noteH = 5, 4
    end
    s32.RegisterIcon("Notepad", 2, 10, noteW, noteH, function(args)
        if args[1] == "OPEN" then _G.PsCreateSystemThread("Windows/notepad.lua", "notepad.exe", 8, { name = "USER", group = "USER" }) end
    end)
    if not LDM then
        s32.RegisterIcon("Minesweeper", gpu.w - 10, 2, 5, 4, function(args)
            if args[1] == "OPEN" then _G.PsCreateSystemThread("Windows/System32/winmine.lua", "winmine.exe", 8, { name = "USER", group = "USER" }) end
        end)
    end
    local ieW, ieH
    if LDM then
        ieW, ieH = 3, 2
    else
        ieW, ieH = 5, 4
    end
    s32.RegisterIcon("IE", gpu.w - 6, 6, ieW, ieH, function(args)
        if args[1] == "OPEN" then _G.PsCreateSystemThread("Windows/System32/IEXPLORE.lua", "IEXPLORE.EXE", 8, { name = "USER", group = "USER" }) end
    end)
end

function explorer.OpenSetupMgr(gdi, gpu, s32)
    local hdc = gdi.GetDC(0)
    local w, h
    if LDM then
        w, h = 46, 12
    else
        w, h = 50, 15
    end
    local x = math.floor((explorer.screen.width - w) / 2)
    local y = math.floor((explorer.screen.height - h) / 2)
    
    local drives = {}
    for addr in component.list("disk_drive") do
        table.insert(drives, component.proxy(addr))
    end
    
    local activeSel = 1
    
    local function redrawMgr()
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xCCCCCC))
        gdi.PatBlt(hdc, x, y, w, h, gdi.PATCOPY)
        
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
        gdi.PatBlt(hdc, x, y, w, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y, 1, h, gdi.PATCOPY)
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x555555))
        gdi.PatBlt(hdc, x + w - 1, y, 1, h, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y + h - 1, w, 1, gdi.PATCOPY)
        
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
        _G.HAL.gpu.setBackground(0xCCCCCC)
        gdi.PatBlt(hdc, x + 1, y + 1, w - 2, 1, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.TextOut(hdc, x + 2, y + 1, "Windows NT Setup Manager")
        
        gdi.SetTextColor(hdc, 0x000000)
        gdi.SetBkMode(hdc, gdi.TRANSPARENT)
        gdi.TextOut(hdc, x + 3, y + 3, "Select Floppy Drive for Installation:")
        gdi.TextOut(hdc, x + 3, y + 4, "Use ^v to select, ENTER to start copying.")
        
        if #drives == 0 then
            gdi.SetTextColor(hdc, 0xFF0000)
            gdi.TextOut(hdc, x + 5, y + 6, "[ No floppy drives detected! ]")
        else
            for i, drv in ipairs(drives) do
                local yPos = y + 5 + i
                local hasMedia = not drv.isEmpty()
                local statusText = hasMedia and string.format("Floppy %d: [ Ready ]", i-1) or string.format("Floppy %d: [ Empty ]", i-1)
                
                if i == activeSel then
                    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
                    gdi.PatBlt(hdc, x + 4, yPos, w - 8, 1, gdi.PATCOPY)
                    gdi.SetTextColor(hdc, 0xFFFFFF)
                else
                    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xCCCCCC))
                    gdi.SetTextColor(hdc, 0x000000)
                end
                gdi.TextOut(hdc, x + 5, yPos, statusText .. " (" .. drv.address:sub(1,6) .. ")")
            end
        end
        
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xCCCCCC))
        gdi.SetTextColor(hdc, 0x555555)
        gdi.TextOut(hdc, x + 3, y + h - 2, "Delete: Abort and close Setup Manager")
    end

    local function copySystemToFloppy(targetFsProxy)
        local sourceFs = component.proxy(computer.getBootAddress())
        local function copyRecursive(dir)
            local list = sourceFs.list(dir)
            for _, item in ipairs(list) do
                local fullPath = dir .. item
                if fullPath ~= "Boot/" and fullPath ~= "/Boot/" then
                    if item:sub(-1) == "/" then
                        targetFsProxy.makeDirectory(fullPath)
                        copyRecursive(fullPath)
                    else
                        local srcFile = sourceFs.open(fullPath, "r")
                        local dstFile = targetFsProxy.open(fullPath, "w")
                        if srcFile and dstFile then
                            repeat
                                local chunk = sourceFs.read(srcFile, 1024)
                                if chunk then targetFsProxy.write(dstFile, chunk) end
                            until not chunk
                            sourceFs.close(srcFile)
                            targetFsProxy.close(dstFile)
                        end
                    end
                end
            end
        end
        copyRecursive("/")
    end

    redrawMgr()

    repeat
        local signal = {event.ReadData(50, "key_down")}
        if #signal > 0 then
            local code = signal[4]
            if code == 208 and #drives > 0 then
                if activeSel < #drives then activeSel = activeSel + 1 else activeSel = 1 end
                redrawMgr()
                computer.beep(880, 0.05)
            end
            
            if code == 200 and #drives > 0 then
                if activeSel > 1 then activeSel = activeSel - 1 else activeSel = #drives end
                redrawMgr()
                computer.beep(880, 0.05)
            end
            
            if code == 211 then
                computer.beep(440, 0.05)
                explorer.Desktop(gdi, gpu, s32)
                return
            end
            
            if code == 28 and #drives > 0 then
                local selectedDrive = drives[activeSel]
                
                if selectedDrive.isEmpty() then
                    computer.beep(440, 0.3)
                    gdi.SetTextColor(hdc, 0xFF0000)
                    gdi.TextOut(hdc, x + 5, y + h - 4, "Error: Insert floppy disk first!   ")
                    KeDelayExecutionThread(1.5)
                    redrawMgr()
                else
                    computer.beep(1000, 0.1)
                    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xCCCCCC))
                    gdi.PatBlt(hdc, x + 3, y + h - 5, w - 6, 2, gdi.PATCOPY)
                    gdi.SetTextColor(hdc, 0x0000FF)
                    gdi.TextOut(hdc, x + 5, y + h - 4, "Copying RedstoneShell files...")
                    
                    local floppyMediaAddr = selectedDrive.media()
                    local floppyFs = component.proxy(floppyMediaAddr)
                    
                    pcall(copySystemToFloppy, floppyFs)
                    
                    local f = floppyFs.open("/UNATTEND.TXT", "w")
                    if f then
                        floppyFs.write(f, "[Unattended]\nMethod=Floppy_Setup\nProductKey=NT40-FLPY-ROBOT-2026\n")
                        floppyFs.close(f)
                    end
                    
                    computer.beep(1200, 0.2)
                    gdi.SetTextColor(hdc, 0x008000)
                    gdi.TextOut(hdc, x + 5, y + h - 4, "Installation disk ready! Press Delete.       ")
                end
            end
        end
    until false
end


function explorer.INET_PLS(gdi, gpu, s32)
    local w,h,y,x,hdc=45,12,explorer.screen.height-18,explorer.screen.width-48,gdi.GetDC(0)
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(gdi.COLOR_DARK_GRAY))
    gdi.PatBlt(hdc,x+1,y+1,w,h,gdi.PATCOPY)
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(gdi.COLOR_GRAY))
    gdi.PatBlt(hdc,x,y,w,h,gdi.PATCOPY)
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(gdi.COLOR_BLUE))
    gdi.PatBlt(hdc,x,y,w,1,gdi.PATCOPY)
    gdi.SetTextColor(gdi.COLOR_WHITE)
    gdi.TextOut(hdc,x+1,y,"Internet Properties")

    gdi.SetTextColor(hdc, gdi.COLOR_BLACK)
    gdi.SetBkMode(gdi.TRANSPARENT)
    local inet   = component.proxy(component.list("internet")()or"")
    local status = inet and "Connected" or "No INET card!"
    gdi.TextOut(hdc,x+2,y+2, "Status: "..status)
    inetCard=true
    if status=="No INET card!" then
        KeDelayExecutionThread(0.8)
        gdi.TextOut(hdc,x+2,y+2, "Trying to Link Card...")
        KeDelayExecutionThread(0.6)
        inet=component.proxy(component.list("tunnel")()or"")
        status = inet and "Connected     " or "No Link Card!        "
        gdi.TextOut(hdc,x+2,y+2, "Status: "..status)
    end
    if inet and not inetCard then 
        gdi.TextOut(hdc,x+2,y+3, "Addr: "..inet.address) 
        rasapi32.CreateNewTunnel()
        local res = rasapi32.LCP_Negotiate()
        if res==2 then gdi.TextOut(hdc,x+2,y+2, "Status: TIMEOUT        ") return end
        gdi.TextOut(hdc,x+2,y+2, "Status: "..rasapi32.ConnectionState.."        ")
        gdi.TextOut(hdc,x+2,y+5, "Enter Password:")
        local pass = explorer.GetTextInput(hdc,x+2,y+6,15)
        status = rasapi32.CHAPHandshake(pass)
        if status=="SUCCESS" then
            gdi.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(explorer.gdi32.COLOR_GRAY))
            gdi.PatBlt(hdc, x+2, y+6, 15, 2, explorer.gdi32.PATCOPY)
            gdi.TextOut(hdc,x+2,y+2, "Status: Authenticating...         ")
            gdi.TextOut(hdc,x+2,y+4, "Server: "..rasapi32.GetLCConnServer()) 
            gdi.TextOut(hdc,x+2,y+5, "                 ") 
            local ipcp=rasapi32.IPCP_Negotiate()
            if ipcp then
                gdi.TextOut(hdc,x+2,y+2, "Status: Connected         ")
                gdi.TextOut(hdc,x+2,y+5, "IP: "..rasapi32.LocalIP)
                s32.UnregIcon("NoNetwork", gpu.w-19, gpu.h-4)
                s32.DrawIcon(hdc, gdi, 0x555555, gpu.w-19, gpu.h-4, "YesNetwork", "")
                s32.RegisterIcon("YesNetwork", gpu.w-19, gpu.h-4, 6, 4, function(args)
                    if args[1]=="OPEN" then explorer.INET_PLS(gdi, gpu, s32) end
                end)
            end
        else
            gdi.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(explorer.gdi32.COLOR_GRAY))
            gdi.PatBlt(hdc, x+2, y+6, 15, 2, explorer.gdi32.PATCOPY)
            gdi.TextOut(hdc,x+2,y+2, "Status: Connection Denied       ")
        end
    end

    if inetCard then
        
    end
end

function explorer.GetTextInput(hdc, x, y, maxLen)
    local inp = ""
    maxLen=maxLen or 20
    local function refreshDispl()
        explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(explorer.gdi32.COLOR_WHITE))
        explorer.gdi32.PatBlt(hdc, x, y, maxLen, 2, explorer.gdi32.PATCOPY)
        explorer.gdi32.SetTextColor(hdc, explorer.gdi32.COLOR_BLACK)
        explorer.gdi32.TextOut(hdc, x+2,y+1, inp.."_")
    end

    repeat
        local signal = {event.ReadData(50, "key_down")}
        if #signal>0 then
            local char, code = signal[3], signal[4]
            if code ==28 then return inp
            elseif code==14 then inp=inp:sub(1, -2)
            elseif char>1 and char<256 and #inp<maxLen then
                inp=inp..string.char(char)
            end
            refreshDispl()
        end
    until #signal==0
    return inp
end

local yesClk, noClk, okClk, exit_fm, exit_fm0 = false, false, false, false, false
function explorer.HandleClick(x, y)
    if explorer.startMenuOpen then
        if explorer.HandleStartMenuClick(x, y) then
            return
        end
    end
    if explorer.modalBtns then
        for _,item in ipairs(explorer.modalBtns)do
            if y==item.y and x>=item.x and x<(item.x+item.w) then
                if item.btn=="YES" then
                    yesClk=true
                    explorer.FormatAcc()
                    explorer.modalBtns = {}
                elseif item.btn=="NO" then
                    noClk = true
                    explorer.FormatAcc()
                    explorer.modalBtns = {}
                elseif item.btn=="OK" then
                    okClk = true
                    explorer.Props()
                    explorer.modalBtns = {}
                elseif item.btn=="GO_UP" then
                    currPath=currPath:gsub("[^/]+/$", "")
                    explorer.modalBtns = {}
                    explorer.FileWindow()
                elseif item.btn=="EXIT_FM" then
                    exit_fm=true
                    explorer.FileWindow()
                    explorer.modalBtns = {}
                elseif item.btn=="CLOSE_EDT" then
                    exit_fm0=true
                    explorer.FileEditor(fP)
                    explorer.modalBtns = {}
                elseif item.btn=="FILE_ITEM" then
                    if item.isDir then
                        currPath=currPath..item.name
                        explorer.FileWindow()
                    else
                        if skip then skip=not skip return end
                        local fP = currPath..item.name
                        explorer.FileEditor(fP)
                    end
                end
            end
        end
    end
    if explorer.openedMenu then
        for _,item in ipairs(explorer.openedMenu)do
            if y==item.y and x>=item.x and x<(item.x+item.w) then
                if item.disabled then 
                    return 
                end

                if item.btn == "Install To..." then
                    explorer.OpenWinNTSetup(explorer.gdi32, explorer.gpu, explorer.s32)
                    openCoverMenu = false
                    explorer.openedMenu = {}
                elseif item.btn == "Properties" then
                    explorer.ShowSystemProperties(explorer.gdi32, explorer.gpu, explorer.s32)
                    openCoverMenu = false
                    explorer.openedMenu = {}
                elseif item.btn=="Format..." then
                    explorer.FormatAcc()
                    openCoverMenu=true
                elseif item.btn=="Properties0" then
                    explorer.Props()
                    openCoverMenu=true
                elseif item.btn=="Open" then
                    explorer.FileWindow()
                    openCoverMenu=true
                end
            end
        end
    end
    if explorer.startMenuOpen then
        local bounds = explorer.startMenuBounds
        if bounds then
            if x < bounds.x or x > bounds.x + bounds.w or
               y < bounds.y or y > bounds.y + bounds.h then
                explorer.startMenuOpen = false
                explorer.startMenuItems = {}
                
                local hdc = explorer.gdi32.GetDC(0)
                local tbh = 6
                local hTaskB = explorer.gdi32.CreateSolidBrush(0xCCCCCC)
                explorer.gdi32.SelectObject(hdc, hTaskB)
                explorer.gdi32.PatBlt(hdc, 0, explorer.screen.height - tbh + 1, 
                    explorer.screen.width, tbh, explorer.gdi32.PATCOPY)
                explorer.gdi32.SetTextColor(hdc, 0x000000)
                explorer.gdi32.TextOut(hdc, 2, explorer.screen.height - 3, "Start")
            end
        end
    end
end

function explorer.FormatAcc()
    if not noClk or not yesClk then
        explorer.openedMenu={}
        local fsAddr = _G.Mm.NonPagedPool[_G.Drives[selDsk]].address
        local fs     = component.proxy(fsAddr)
        local hdc    = explorer.gdi32.GetDC(0)
        explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0xCCCCCC))
        explorer.gdi32.PatBlt(hdc, 30, 20, 60, 10, explorer.gdi32.PATCOPY)
        explorer.gdi32.SetTextColor(hdc, 0x000000)
        explorer.gdi32.TextOut(hdc,32, 21, "Are you sure to format disk or floppy: "..(fs.getLabel() or "Unformatted"))
        explorer.gdi32.TextOut(hdc,35, 25, "[ Yes ]")
        explorer.gdi32.TextOut(hdc,45, 25, "[ No  ]")
        if not explorer.modalBtns then explorer.modalBtns = {} end
        explorer.modalBtns = {
            {btn = "YES", x=35,y=25,w=7,h=1},
            {btn = "NO",  x=45,y=25,w=7,h=1}
        }
    end

    if noClk==true then
        explorer.OpenMyPc(explorer.gdi32, explorer.gpu, explorer.s32)
        openCoverMenu=false
        noClk=false
    end

    if yesClk==true then
        explorer.OpenMyPc(explorer.gdi32, explorer.gpu, explorer.s32)
        yesClk=false
        explorer.openedMenu={}
        local fsAddr      = _G.Mm.NonPagedPool[_G.Drives[selDsk]].address
        local fs          = component.proxy(fsAddr)
        local hdc, fFiles = explorer.gdi32.GetDC(0), 0
        explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0xCCCCCC))
        explorer.gdi32.PatBlt(hdc, 30, 20, 60, 10, explorer.gdi32.PATCOPY)
        explorer.gdi32.SetTextColor(hdc, 0x000000)
        explorer.gdi32.TextOut(hdc,32, 21, "Formatting ("..(fs.getLabel() or "Unformatted")..")...")
        local list = fs.list("/")
        for _, name in ipairs(list) do fs.remove("/"..name) explorer.gdi32.TextOut(hdc, 32, 25, "Removing "..name.."         ") fFiles=fFiles+1 KeDelayExecutionThread(0.7) end
        KeDelayExecutionThread(1)
        explorer.gdi32.TextOut(hdc, 32, 25, "Formatted "..tostring(fFiles).." files, disk or floppy ready.")
        KeDelayExecutionThread(2)
        if fs.getLabel()==nil then fs.setLabel("Formatted") end
        if fs.makeDirectory~=nil and fs.open~=nil then
            fs.makeDirectory("/System Volume Information")
            local hve = fs.open("/System Volume Information/Syscache.hve", "w")
            if hve then
                fs.write(hve, "NTFS Windows NT  FileSystem "..fs.getLabel())
                fs.close(hve)
            end
        end
        explorer.OpenMyPc(explorer.gdi32, explorer.gpu, explorer.s32)
        openCoverMenu=false
    end
end

function explorer.Props()
    if not okClk then
        explorer.openedMenu={}
        local fsAddr=_G.Mm.NonPagedPool[_G.Drives[selDsk]].address
        local fs    = component.proxy(fsAddr)
        local total, used, label = fs.spaceTotal(), fs.spaceUsed(), fs.getLabel() or "Unnamed"
        local free, hdc = total-used, explorer.gdi32.GetDC(0)
        explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0xCCCCCC))
        explorer.gdi32.PatBlt(hdc, 25, 15, 40, 15, explorer.gdi32.PATCOPY)
        explorer.gdi32.SetTextColor(0x000000)
        explorer.gdi32.TextOut(hdc, 27, 16, "Properties: "..label)
        explorer.gdi32.TextOut(hdc, 27, 17, "----------------------")
        explorer.gdi32.TextOut(hdc, 27, 18, "Used Space: "..tostring(used).." bytes")
        explorer.gdi32.TextOut(hdc, 27, 19, "Free Space: "..tostring(free).." bytes")
        explorer.gdi32.TextOut(hdc, 27, 20, "Capacity: "..tostring(total).." bytes")
        explorer.gdi32.TextOut(hdc, 35, 22, "[  OK  ]")
        explorer.modalBtns = {
            {btn = "OK", x=35,y=22,w=8,h=1}
        }
    end
    if okClk then
        explorer.OpenMyPc(explorer.gdi32, explorer.gpu, explorer.s32)
        okClk=false
        openCoverMenu=false
    end
end

function explorer.FileWindow()
    explorer.openedMenu={}
    local fsAddr=_G.Mm.NonPagedPool[_G.Drives[selDsk]].address
    local fs    = component.proxy(fsAddr)
    local hdc   = explorer.gdi32.GetDC(0)
    if exit_fm then explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0x008080)) explorer.gdi32.PatBlt(hdc, 15, 4, 50, 36, explorer.gdi32.PATCOPY) explorer.OpenMyPc(explorer.gdi32, explorer.gpu, explorer.s32) openCoverMenu=false exit_fm=false return end
    explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0xFAFAFA))
    explorer.gdi32.PatBlt(hdc, 15, 4, 50, 36, explorer.gdi32.PATCOPY)
    explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0x000080))
    explorer.gdi32.PatBlt(hdc, 15, 5, 50, 1, explorer.gdi32.PATCOPY)
    explorer.gdi32.SetTextColor(0xFFFFFF)
    explorer.gdi32.TextOut(hdc, 16, 4, "Exit")
    explorer.gdi32.TextOut(hdc, 16, 5, "Exploring - "..selDsk)
    explorer.gdi32.SetTextColor(0x000000)
    local yOff=7
    if not explorer.modalBtns then explorer.modalBtns={} end
    if currPath~="/" then explorer.gdi32.TextOut(hdc, 17, 6, "[..] Up") end
    table.insert(explorer.modalBtns, {btn="GO_UP", x=17,y=6,w=7,h=1 })
    table.insert(explorer.modalBtns, {btn="EXIT_FM",  x=16,y=4,w=4,h=1 })
    local list = fs.list(currPath)
    if list~=nil and list then
        for _, name in ipairs(list) do
            local isDir = name:sub(-1)=="/"
            explorer.gdi32.TextOut(hdc, 17, yOff, (isDir and "[D] " or "[F] ")..name)
            table.insert(explorer.modalBtns, { btn="FILE_ITEM", name=name, isDir=isDir,x=17,y=yOff,w=#name+4,h=1})
            yOff=yOff+1
            if yOff>38 then break end
        end
    end
end

function explorer.FileEditor(path)
end

function explorer.UpdateTime(PTIME_FIELDS)
    local hdc = explorer.gdi32.GetDC(0)
    local timeStr=string.format("%02d:%02d", PTIME_FIELDS.Hour, PTIME_FIELDS.Minute)
    local dateStr=string.format("%02d.%02d.%04d", PTIME_FIELDS.Day, PTIME_FIELDS.Month, PTIME_FIELDS.Year)
    explorer.gdi32.SetTextColor(0x666666)
    explorer.gdi32.TextOut(hdc, explorer.screen.width-9, explorer.screen.height-3, timeStr)
    explorer.gdi32.TextOut(hdc, explorer.screen.width-11, explorer.screen.height-2, dateStr)
end

function explorer.OpenWinNTSetup(gdi, gpu, s32)
    local hdc = gdi.GetDC(0)
    local w, h = 55, 18
    local x = math.floor((explorer.screen.width - w) / 2)
    local y = math.floor((explorer.screen.height - h) / 2)
    
    local targetDrives = {}
    for letter, devName in pairs(_G.Drives) do
        if letter ~= "A:" and letter ~= "B:" then
            local dev = _G.Mm.NonPagedPool[devName]
            if dev and dev.address ~= computer.getBootAddress() then
                table.insert(targetDrives, {letter = letter, proxy = dev})
            end
        end
    end
    
    local stage = 1
    local activeSel = 1
    local progress = 0

    local function drawWizard()
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xC0C0C0))
        gdi.PatBlt(hdc, x, y, w, h, gdi.PATCOPY)
        
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
        gdi.PatBlt(hdc, x, y, w, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y, 1, h, gdi.PATCOPY)
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x555555))
        gdi.PatBlt(hdc, x + w - 1, y, 1, h, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y + h - 1, w, 1, gdi.PATCOPY)
        
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
        gdi.PatBlt(hdc, x + 1, y + 1, w - 2, 1, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.TextOut(hdc, x + 2, y + 1, "Windows NT Setup Wizard")
        
        gdi.SetBkMode(hdc, gdi.TRANSPARENT)

        if stage == 1 then
            gdi.TextOut(hdc, x + 3, y + 3, "Welcome to the Windows NT Installation Wizard.")
            gdi.TextOut(hdc, x + 3, y + 4, "Please select the target Hard Drive for installation:")
            
            gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
            gdi.PatBlt(hdc, x + 3, y + 6, w - 6, 6, gdi.PATCOPY)
            
            if #targetDrives == 0 then
                gdi.SetTextColor(hdc, 0xFF0000)
                gdi.TextOut(hdc, x + 5, y + 8, "[ No destination hard drives detected ]")
            else
                for i, drv in ipairs(targetDrives) do
                    local yPos = y + 5 + i
                    if i == activeSel then
                        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
                        gdi.PatBlt(hdc, x + 4, yPos, w - 8, 1, gdi.PATCOPY)
                        gdi.SetTextColor(hdc, 0xFFFFFF)
                    else
                        gdi.SetTextColor(hdc, 0x00FF00)
                    end
                    local lbl = drv.proxy.getLabel() or "Local Disk"
                    gdi.TextOut(hdc, x + 5, yPos, string.format("%s - %s (%s...) ", drv.letter, lbl, drv.proxy.address:sub(1,6)))
                end
            end
            
            gdi.SetTextColor(hdc, 0xFFFFFF)
            gdi.TextOut(hdc, x + 3, y + h - 3, "Use [^v] to select, [ENTER] to Install, [ESC] to Cancel")

        elseif stage == 2 then
            gdi.TextOut(hdc, x + 3, y + 4, "Copying Windows NT system files to target drive...")
            gdi.TextOut(hdc, x + 3, y + 6, "Please do not turn off your computer.")
            
            gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x808080))
            gdi.PatBlt(hdc, x + 5, y + 9, w - 10, 2, gdi.PATCOPY)
            
            local progressW = math.floor(((w - 12) * progress) / 100)
            if progressW > 0 then
                gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
                gdi.PatBlt(hdc, x + 6, y + 10, progressW, 1, gdi.PATCOPY)
            end
            
            gdi.SetTextColor(hdc, 0xFFFFFF)
            gdi.TextOut(hdc, x + math.floor(w/2) - 2, y + 12, tostring(progress) .. "%")

        elseif stage == 3 then
            gdi.SetTextColor(hdc, 0x008000)
            gdi.TextOut(hdc, x + 3, y + 4, "SUCCESS! Windows NT has been installed successfully.")
            gdi.SetTextColor(hdc, 0xFFFFFF)
            gdi.TextOut(hdc, x + 3, y + 6, "The boot sector on target drive has been updated.")
            gdi.TextOut(hdc, x + 3, y + 8, "Please remove any floppy disks from the drives.")
            
            gdi.TextOut(hdc, x + 3, y + h - 3, "Press [ENTER] to reboot the system.")
        end
    end

    local function performInstallation(targetFs)
        local sourceFs = component.proxy(computer.getBootAddress())
        
        local allFiles = {}
        local function scan(dir)
            local list = sourceFs.list(dir)
            for _, item in ipairs(list) do
                local fullPath = dir .. item
                table.insert(allFiles, fullPath)
                if item:sub(-1) == "/" then scan(fullPath) end
            end
        end
        scan("/")

        for idx, fullPath in ipairs(allFiles) do
            if fullPath:sub(-1) == "/" then
                targetFs.makeDirectory(fullPath)
            else
                local srcFile = sourceFs.open(fullPath, "r")
                local dstFile = targetFs.open(fullPath, "w")
                if srcFile and dstFile then
                    repeat
                        local chunk = sourceFs.read(srcFile, 2048)
                        if chunk then targetFs.write(dstFile, chunk) end
                    until not chunk
                    sourceFs.close(srcFile)
                    targetFs.close(dstFile)
                end
            end
            
            progress = math.floor((idx / #allFiles) * 100)
            drawWizard()
            KeDelayExecutionThread(0.05)
        end
        
        if targetFs.makeDirectory then
            targetFs.makeDirectory("/System Volume Information")
            local bootIni = targetFs.open("/boot.ini", "w")
            if bootIni then
                targetFs.write(bootIni, "[boot loader]\ntimeout=30\ndefault=multi(0)disk(0)rdisk(0)partition(1)\\WINNT\n")
                targetFs.close(bootIni)
            end
        end
    end

    drawWizard()

    repeat
        local signal = {event.ReadData(50, "key_down")}
        if #signal > 0 then
            local code = signal[4]
            
            if stage == 1 then
                if code == 208 and #targetDrives > 0 then
                    if activeSel < #targetDrives then activeSel = activeSel + 1 else activeSel = 1 end
                    drawWizard()
                    computer.beep(880, 0.03)
                elseif code == 200 and #targetDrives > 0 then
                    if activeSel > 1 then activeSel = activeSel - 1 else activeSel = #targetDrives end
                    drawWizard()
                    computer.beep(880, 0.03)
                elseif code == 1 or code == 211 then
                    computer.beep(440, 0.05)
                    explorer.Desktop(gdi, gpu, s32)
                    return
                elseif code == 28 and #targetDrives > 0 then
                    stage = 2
                    drawWizard()
                    computer.beep(1000, 0.1)
                    
                    local success, err = pcall(performInstallation, targetDrives[activeSel].proxy)
                    
                    if success then
                        stage = 3
                    else
                        stage = 1
                        error("Setup failed: " .. tostring(err))
                    end
                    drawWizard()
                end
                
            elseif stage == 3 then
                if code == 28 then
                    computer.beep(1200, 0.5)
                    computer.shutdown(true)
                end
            end
        end
    until false
end

function explorer.RegisterMenu(x, y, buttons)
    explorer.openedMenu={}
    local maxW=0
    for _, name in ipairs(buttons) do
        local cleanName = name:gsub("_DISABLED$", "")
        if #cleanName>maxW then maxW=#cleanName end
    end

    for i, name in ipairs(buttons) do
        local isDisabled = name:find("_DISABLED$") ~= nil
        local btnAction = name:gsub("_DISABLED$", "")
        
        table.insert(explorer.openedMenu, {
            btn=btnAction, disabled=isDisabled, x=x, y=y+i-1, w=maxW, h=1
        })
    end
end

function explorer.OpenMyPc(gdi, gpu, s32)
    if s32.DeskIcon then
        s32.DeskIcon["Drive"] = nil
        s32.DeskIcon["CloseMyPC"] = nil
    end
    local hdc = gdi.GetDC(0)
    local hddc, yOff, diskOffs, regDsks = 0, 19, {}, {}
    local LDM = _G.Tier2CM == true
    local winX, winY, winW, winH
    local titleY, closeX
    local iconX, iconTextX
    local yStart, yStep
    
    if LDM then
        winX, winY, winW, winH = 3, 3, 74, 19
        titleY = winY
        closeX = winX + winW - 3
        iconX = winX + 3
        iconTextX = winX + 12
        yStart = winY + 4
        yStep = 3
    else
        winX, winY, winW, winH = 20, 10, 80, 20
        titleY = winY
        closeX = winX + winW - 3
        iconX = winX + 5
        iconTextX = winX + 16
        yStart = winY + 9
        yStep = 5
    end
    
    yOff = yStart
    
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFAFAFA))
    gdi.PatBlt(hdc, winX, winY, winW, winH, gdi.PATCOPY)
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
    gdi.PatBlt(hdc, winX, titleY, winW, 1, gdi.PATCOPY)
    gdi.SetTextColor(hdc, 0xFFFFFF)
    gdi.SetBkColor(hdc, 0x000080)
    gdi.TextOut(hdc, winX + 2, titleY, "My Computer")
    gdi.SetTextColor(hdc, 0xFF0000)
    gdi.TextOut(hdc, closeX, titleY, "[X]")
    s32.RegisterIcon("CloseMyPC", closeX, titleY, 3, 1, function(args)
        if args[1] == "OPEN" then
            computer.beep(440, 0.05)
            s32.DeskIcon["Drive"] = nil
            s32.DeskIcon["CloseMyPC"] = nil
            explorer.Desktop(gdi, gpu, s32)
        end
    end)
    for l, devName in pairs(_G.Drives) do
        if l and type(l) == "string" and #l >= 2 then
            if l:sub(2, 2) == ":" then
                local dev = _G.Mm.NonPagedPool[devName]
                if dev and dev.getLabel ~= nil then
                    local fd = dev.getLabel()
                    if l == "A:" or l == "B:" then
                        table.insert(diskOffs, yOff)
                        local fullLabel
                        if fd then
                            fullLabel = fd .. " (" .. l .. ")"
                        else
                            fullLabel = "Floppy" .. " (" .. l .. ")"
                        end
                        table.insert(regDsks, l)
                        s32.DrawIcon(hdc, gdi, 0xAABBCC, iconX, yOff, "Floppy", l)
                        gdi.SetTextColor(hdc, 0x000000)
                        gdi.SetBkColor(hdc, 0xFAFAFA)
                        gdi.TextOut(hdc, iconTextX, yOff + 1, fullLabel)
                        yOff = yOff + yStep
                        hddc = hddc + 1
                    end
                    if fd then
                        if l == "A:" or l == "B:" then goto continue end
                        table.insert(diskOffs, yOff)
                        table.insert(regDsks, l)
                        local fullLabel = fd .. " (" .. l .. ")"
                        s32.DrawIcon(hdc, gdi, 0xAABBCC, iconX, yOff, "Drive", l)
                        gdi.SetTextColor(hdc, 0x000000)
                        gdi.SetBkColor(hdc, 0xFAFAFA)
                        gdi.TextOut(hdc, iconTextX, yOff + 1, fullLabel)
                        yOff = yOff + yStep
                        hddc = hddc + 1
                    else
                        if l == "A:" or l == "B:" then goto continue end
                        table.insert(diskOffs, yOff)
                        table.insert(regDsks, l)
                        local fullLabel = "Local Disk" .. " (" .. l .. ")"
                        s32.DrawIcon(hdc, gdi, 0xAABBCC, iconX, yOff, "Drive_Error", l)
                        gdi.SetTextColor(hdc, 0xFF0000)
                        gdi.SetBkColor(hdc, 0xFAFAFA)
                        gdi.TextOut(hdc, iconTextX, yOff + 1, fullLabel)
                        yOff = yOff + yStep
                        hddc = hddc + 1
                    end
                end
            end
        end
        ::continue::
    end
    gdi.SetTextColor(hdc, 0x113399)
    gdi.SetBkColor(hdc, 0xFAFAFA)
    if LDM then
        gdi.TextOut(hdc, winX + 2, winY + 2, "Hard disk drives (" .. hddc .. ")")
    else
        gdi.TextOut(hdc, winX + 5, winY + 5, "Hard disk drives (" .. hddc .. ")")
    end
    s32.RegisterIcon("Drive", iconX, diskOffs, 8, 4, function(args)
        if args[1] == "MENU" and not openCoverMenu then
            selDsk = regDsks[args[2]]
            local hdc = explorer.gdi32.GetDC(0)
            local clickX = args.click[1] + 1
            local clickY = args.click[2]
            explorer.gdi32.SelectObject(hdc, explorer.gdi32.CreateSolidBrush(0xCCCCCC))
            explorer.gdi32.PatBlt(hdc, clickX, clickY, 14, 4, explorer.gdi32.PATCOPY)
            explorer.gdi32.SetTextColor(hdc, 0x000000)
            explorer.gdi32.SetBkColor(hdc, 0xCCCCCC)
            explorer.gdi32.TextOut(hdc, clickX + 1, clickY, "Open")
            explorer.gdi32.TextOut(hdc, clickX + 1, clickY + 1, "Explore")
            explorer.gdi32.TextOut(hdc, clickX + 1, clickY + 2, "Format...")
            explorer.gdi32.TextOut(hdc, clickX + 1, clickY + 3, "Properties")
            explorer.RegisterMenu(clickX, clickY, { "Open", "Explore", "Format...", "Properties0" })
        end
    end)
end

function explorer.RunDialog(gdi, gpu, s32)
    local hdc = gdi.GetDC(0)
    local w, h
    if LDM then
        w, h = 36, 6
    else
        w, h = 40, 7
    end
    local x = math.floor((explorer.screen.width - w) / 2)
    local y = math.floor((explorer.screen.height - h) / 2)

    local input = ""

    local function redraw()
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xC0C0C0))
        gdi.PatBlt(hdc, x, y, w, h, gdi.PATCOPY)

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
        gdi.PatBlt(hdc, x, y, w, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y, 1, h, gdi.PATCOPY)
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x555555))
        gdi.PatBlt(hdc, x + w - 1, y, 1, h, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y + h - 1, w, 1, gdi.PATCOPY)

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
        gdi.PatBlt(hdc, x + 1, y + 1, w - 2, 1, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.SetBkColor(hdc, 0x000080)
        gdi.TextOut(hdc, x + 2, y + 1, "Run")

        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.SetBkColor(hdc, 0xC0C0C0)
        gdi.TextOut(hdc, x + 2, y + 3, "Type the name of a program, and")
        gdi.TextOut(hdc, x + 2, y + 4, "LuaNT will open it for you.")

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
        gdi.PatBlt(hdc, x + 2, y + 5, w - 4, 1, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0x000000)
        gdi.SetBkColor(hdc, 0xFFFFFF)
        gdi.TextOut(hdc, x + 3, y + 5, input .. "_")
    end

    redraw()

    repeat
        local signal = { computer.pullSignal(0.1) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then  -- ENTER
                if #input > 0 then
                    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x008080))
                    gdi.PatBlt(hdc, x, y, w, h, gdi.PATCOPY)
                    local fs = component.proxy(computer.getBootAddress())
                    local path = input

                    path = path:gsub("^/", "")

                    if not path:match("%.lua$") then
                        path = path .. ".lua"
                    end

                    local foundPath = nil
                    local searchPaths = {
                        path,
                        "Windows/System32/" .. path,   -- System32
                        "Windows/" .. path,            -- Windows
                        "Program Files/" .. path,      -- Program Files
                    }

                    for _, tryPath in ipairs(searchPaths) do
                        if fs.exists(tryPath) then
                            foundPath = tryPath
                            break
                        end
                    end

                    if foundPath then
                        DbgPrint("RUN: Starting " .. foundPath)
                        local thread = _G.PsCreateSystemThread(foundPath, input, 8,
                            { name = "Administrator", group = "ADMINS" })
                        if not thread then
                            DbgPrint("RUN: Failed to create thread for " .. foundPath)
                        end
                    else
                        DbgPrint("RUN: File not found: " .. input)
                        if _G.RpcSs then
                            _G.RpcSs.RpcCliExecute("IErrorHandler", "ShowError",
                                "Run", "File Not Found",
                                "Cannot find the file '" .. input .. "'",
                                "SHELL32")
                        end
                    end
                end
                return

            elseif code == 203 then  -- <
                return

            elseif code == 14 then  -- BACKSPACE
                if #input > 0 then
                    input = input:sub(1, -2)
                end

            elseif char >= 32 and char <= 126 and #input < w - 6 then
                input = input .. string.char(char)
            end

            redraw()
        end
    until false
end

-- ===== Color Setup Dialog =====
function explorer.ColorSetup(gdi, gpu, s32)
    local hdc = gdi.GetDC(0)
    local w, h
    if LDM then
        w, h = 40, 10
    else
        w, h = 44, 12
    end
    local x = math.floor((explorer.screen.width - w) / 2)
    local y = math.floor((explorer.screen.height - h) / 2)

    local currentMode = 2
    local fs = component.proxy(computer.getBootAddress())
    local iniPath = "Windows/System32/screen.ini"

    if fs.exists(iniPath) then
        local file = fs.open(iniPath, "r")
        if file then
            local content = fs.read(file, math.huge) or ""
            fs.close(file)
            local mode = content:match("screen=(%d+)")
            if mode then currentMode = tonumber(mode) end
        end
    end

    local modes = {
        { id = 0, name = "Monochrome (1-bit)",  desc = "Black & White only" },
        { id = 1, name = "16 colors (4-bit)",   desc = "Classic CGA palette" },
        { id = 2, name = "256 colors (8-bit)",  desc = "Full color palette" }
    }

    local selected = currentMode + 1
    local statusText = "Current: " .. modes[selected].name

    local function SaveMode(modeId)
        local file = fs.open(iniPath, "w")
        if file then
            fs.write(file, "screen=" .. tostring(modeId) .. "\n")
            fs.close(file)
            DbgPrint("COLOR: Saved screen=" .. tostring(modeId) .. " to " .. iniPath)
            return true
        end
        return false
    end

    local function DrawDialog()
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xC0C0C0))
        gdi.PatBlt(hdc, x, y, w, h, gdi.PATCOPY)

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
        gdi.PatBlt(hdc, x, y, w, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, x, y, 1, h, gdi.PATCOPY)
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x808080))
        gdi.PatBlt(hdc, x, y + h - 1, w, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, x + w - 1, y, 1, h, gdi.PATCOPY)

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
        gdi.PatBlt(hdc, x + 1, y + 1, w - 2, 1, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.SetBkColor(hdc, 0x000000)
        gdi.TextOut(hdc, x + 2, y + 1, " Display Properties - Color Setup")
        gdi.SetTextColor(hdc, 0xFF0000)
        gdi.TextOut(hdc, x + w - 4, y + 1, "[X]")

        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.SetBkColor(hdc, 0x808080)
        gdi.SetBkMode(1)
        gdi.TextOut(hdc, x + 2, y + 3, "Select color depth for this display:")
        gdi.TextOut(hdc, x + 2, y + 4, "──────────────────────────────────")

        for i, mode in ipairs(modes) do
            local lineY = y + 4 + i
            local marker = (i == selected) and "> " or "  "

            if i == selected then
                gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
                gdi.PatBlt(hdc, x + 2, lineY, w - 4, 1, gdi.PATCOPY)
                gdi.SetTextColor(hdc, 0x00FF00)
            else
                gdi.SetTextColor(hdc, 0xFFFFFF)
            end

            gdi.TextOut(hdc, x + 3, lineY,
                marker .. mode.name .. " - " .. mode.desc)
        end

        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.SetBkColor(hdc, 0xC0C0C0)
        gdi.TextOut(hdc, x + 2, y + h - 4, "Status: " .. statusText:sub(1, w - 10))

        local btnY = y + h - 2
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xE0E0E0))
        gdi.PatBlt(hdc, x + w - 22, btnY, 9, 2, gdi.PATCOPY)
        gdi.PatBlt(hdc, x + w - 11, btnY, 9, 2, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0x000000)
        gdi.SetBkColor(hdc, 0xE0E0E0)
        gdi.TextOut(hdc, x + w - 21, btnY, "[  OK  ]")
        gdi.TextOut(hdc, x + w - 10, btnY, "[Cancel]")
    end

    DrawDialog()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 203 then  -- <
                gdi.SetBkColor(hdc, 0x008080)
                gdi.PatBlt(hdc, x, y, w, 1, gdi.PATCOPY)
                gdi.PatBlt(hdc, x, y, 1, h, gdi.PATCOPY)
                return

            elseif code == 200 then  -- UP
                if selected > 1 then
                    selected = selected - 1
                    statusText = "Selected: " .. modes[selected].name
                    DrawDialog()
                end

            elseif code == 208 then  -- DOWN
                if selected < #modes then
                    selected = selected + 1
                    statusText = "Selected: " .. modes[selected].name
                    DrawDialog()
                end

            elseif code == 28 then  -- ENTER
                local modeId = modes[selected].id
                if SaveMode(modeId) then
                    statusText = "Applied: " .. modes[selected].name .. ", reboot for apply."
                else
                    statusText = "ERROR: Could not save screen.ini"
                end
                DrawDialog()

            elseif char == 49 then selected = 1 statusText = modes[1].name DrawDialog()
            elseif char == 50 then selected = 2 statusText = modes[2].name DrawDialog()
            elseif char == 51 then selected = 3 statusText = modes[3].name DrawDialog()
            end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = y + h - 2

            if ty == y + 1 and tx >= x + w - 5 then
                gdi.SetBkColor(hdc, 0x008080)
                gdi.PatBlt(hdc, x, y, w, 1, gdi.PATCOPY)
                gdi.PatBlt(hdc, x, y, 1, h, gdi.PATCOPY)
                return
            end

            for i = 1, #modes do
                local lineY = y + 4 + i
                if ty == lineY and tx >= x + 2 and tx <= x + w - 3 then
                    selected = i
                    statusText = "Selected: " .. modes[i].name
                    DrawDialog()
                    break
                end
            end

            if ty == btnY and tx >= x + w - 22 and tx < x + w - 13 then
                local modeId = modes[selected].id
                if SaveMode(modeId) then
                    statusText = "Applied: " .. modes[selected].name .. ", reboot for apply."
                else
                    statusText = "ERROR: Could not save screen.ini"
                end
                DrawDialog()

            elseif ty == btnY and tx >= x + w - 11 and tx < x + w - 2 then
                return
            end

            coroutine.yield()
        end
    end
end

function explorer.ShowSystemProperties(gdi, gpu, s32)
    local hdc = gdi.GetDC(0)
    local screenW, screenH = _G.HAL.w, _G.HAL.h

    local winW, winH
    if LDM then
        winW, winH = 50, 14
    else
        winW, winH = 56, 18
    end
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2
    local clientW = winW - 2
    local clientH = winH - 3

    local regedit = _G.regedit0

    local version = "Unknown"
    if regedit then
        version = regedit.GetValue("\\Software\\RedstoneShell\\Windows NT\\CurrentVersion", "CurrentVersion") or "Unknown"
    end

    -- GPU
    local gpu_proxy = component.proxy(component.list("gpu")())
    local maxDepth = gpu_proxy.maxDepth and gpu_proxy.maxDepth() or "N/A"
    local curDepth = gpu_proxy.getDepth and gpu_proxy.getDepth() or "N/A"

    local w, h = gpu_proxy.getResolution()
    local resolution = w .. "x" .. h

    local architecture = computer.getArchitecture() or "Unknown"

    local modemStatus = "Not Installed"
    local modem_addr = component.list("modem")()
    if modem_addr then
        local modem = component.proxy(modem_addr)
        if modem.isWireless then
            modemStatus = modem.isWireless() and "WiFi" or "ADSL"
        else
            modemStatus = "Wired"
        end
    end

    local inetStatus = {"N/A","N/A"}
    local inet_addr = component.list("internet")()
    if inet_addr then
        local inet = component.proxy(inet_addr)
        inetStatus[1] = tostring(inet.isTcpEnabled()) or "N/A"
        inetStatus[2] = tostring(inet.isHttpEnabled()) or "N/A"
    end

    local function DrawWindow()
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xC0C0C0))
        gdi.PatBlt(hdc, winX, winY, winW, winH, gdi.PATCOPY)

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
        gdi.PatBlt(hdc, winX, winY, winW, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, winX, winY, 1, winH, gdi.PATCOPY)
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x808080))
        gdi.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi.PATCOPY)
        gdi.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi.PATCOPY)

        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
        gdi.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0xFFFFFF)
        gdi.SetBkColor(hdc, 0x000080)
        gdi.TextOut(hdc, winX + 2, winY + 1, " System & Hardware Info")
        gdi.SetTextColor(hdc, 0xFF0000)
        gdi.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        local lines = {
            { "Operation System:", "LuaNT " .. version, 0xFFFFFF },
            { "Manufacturer:", "RedstoneShell", 0xFFFFFF },
            { "", "", 0xFFFFFF },
            { "Max Depth:", tostring(maxDepth), 0xFFFFFF },
            { "Current Depth:", tostring(curDepth), 0xFFFFFF },
            { "Screen resolution:", resolution, 0xFFFFFF },
            { "", "", 0xFFFFFF },
            { "Architecture:", architecture, 0xFFFFFF },
            { "DHCP Modem:", modemStatus, 0xFFFFFF },
            { "", "", 0xFFFFFF },
            { "TCP:", inetStatus[1], 0xFFFFFF },
            { "HTTP(S):", inetStatus[2], 0xFFFFFF }
        }

        local lineY = clientY
        for _, line in ipairs(lines) do
            if line[1] ~= "" then
                gdi.SetTextColor(hdc, 0xFFFFFF)
                gdi.SetBkColor(hdc, 0xC0C0C0)
                gdi.TextOut(hdc, clientX + 2, lineY, line[1])

                gdi.SetTextColor(hdc, line[3])
                gdi.TextOut(hdc, clientX + 22, lineY, line[2]:sub(1, clientW - 24))
            end
            lineY = lineY + 1
        end

        local btnY = winY + winH - 2
        gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xE0E0E0))
        gdi.PatBlt(hdc, winX + winW - 12, btnY, 10, 2, gdi.PATCOPY)
        gdi.SetTextColor(hdc, 0x000000)
        gdi.SetBkColor(hdc, 0xE0E0E0)
        gdi.TextOut(hdc, winX + winW - 11, btnY, "[  OK  ]")
    end

    DrawWindow()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local code = signal[4]
            if code == 1 or code == 28 then
                gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x008080))
                gdi.PatBlt(hdc, winX, winY, winW, winH, gdi.PATCOPY)
                return
            end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = winY + winH - 2

            if ty == winY + 1 and tx >= winX + winW - 5 then
                gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x008080))
                gdi.PatBlt(hdc, winX, winY, winW, winH, gdi.PATCOPY)
                return
            end

            if ty == btnY and tx >= winX + winW - 12 and tx < winX + winW - 2 then
                gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x008080))
                gdi.PatBlt(hdc, winX, winY, winW, winH, gdi.PATCOPY)
                return
            end
        end
    end
end

return explorer
