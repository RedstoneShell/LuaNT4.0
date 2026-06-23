local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 45, 16
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local clientX = winX + 1
local clientY = winY + 4
local clientW = winW - 2
local clientH = winH - 5

local currentTab = "PROCESSES"
local selectedIndex = 1

local function DrawTaskMgr()
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
    gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
    gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000080)
    gdi32.TextOut(hdc, winX + 2, winY + 1, " Windows Task Manager")
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xC0C0C0)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "[X]")
    gdi32.SetTextColor(hdc, 0x000000)
    if currentTab == "PROCESSES" then
        gdi32.SetBkColor(hdc, 0xFFFFFF)
        gdi32.TextOut(hdc, winX + 2, winY + 2, " [Processes] ")
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, winX + 15, winY + 2, " Performance ")
    else
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, winX + 2, winY + 2, " Processes ")
        gdi32.SetBkColor(hdc, 0xFFFFFF)
        gdi32.TextOut(hdc, winX + 15, winY + 2, " [Performance] ")
    end
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
    gdi32.PatBlt(hdc, winX + 1, winY + 3, winW - 2, 1, gdi32.PATCOPY)

    if currentTab == "PROCESSES" then
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
        gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH - 2, gdi32.PATCOPY)
        
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000000)
        gdi32.TextOut(hdc, clientX + 1, clientY, string.format("%-4s %-15s %-4s", "PID", "Image Name", "Prio"))
        gdi32.TextOut(hdc, clientX + 1, clientY + 1, "─────────────────────────────────────────")

        local plist = ntdll.NtQuerySystemInformation() or {}
        if selectedIndex > #plist then selectedIndex = #plist end
        if selectedIndex < 1 then selectedIndex = 1 end

        for idx, thread in ipairs(plist) do
            if idx <= clientH - 5 then
                if idx == selectedIndex then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x00A8A8))
                gdi32.PatBlt(hdc, clientX + 1, clientY + 1 + idx, clientW - 2, 1, gdi32.PATCOPY)
                
                gdi32.SetTextColor(hdc, 0x000000)
                gdi32.SetBkColor(hdc, 0x00A8A8)
            else
                gdi32.SetTextColor(hdc, 0xFFFFFF)
                gdi32.SetBkColor(hdc, 0x000000)
            end
                            
                local line = string.format("%-4d %-15s %-4d", thread.UniqueProcessId, thread.ImageName:sub(1, 15), thread.CurrentPriority)
                gdi32.TextOut(hdc, clientX + 1, clientY + 1 + idx, line)
            end
        end

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, winX + winW - 12, winY + winH - 2, "[End Task]")

    elseif currentTab == "PERFORMANCE" then
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000000))
        gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x00FF00)
        gdi32.SetBkColor(hdc, 0x000000)
        gdi32.TextOut(hdc, clientX + 2, clientY + 1, "System Performance Monitor")
        gdi32.TextOut(hdc, clientX + 2, clientY + 2, "───────────────────────────────────────")
        _G.LastCpuTime = _G.LastCpuTime or os.clock()
        _G.LastCpuPercent = _G.LastCpuPercent or 0
        local currentTime = os.clock()
        local delta = currentTime - _G.LastCpuTime
        _G.LastCpuTime = currentTime
        local cpuPercent = math.floor((delta / 0.1) * 100)
        if cpuPercent > 100 then cpuPercent = 100 end
        if cpuPercent < 0 then cpuPercent = 0 end
        _G.LastCpuPercent = math.floor((_G.LastCpuPercent * 0.4) + (cpuPercent * 0.6))
        local totalMem = computer.totalMemory()
        local freeMem = computer.freeMemory()
        local usedMem = totalMem - freeMem
        local ramPercent = math.floor((usedMem / totalMem) * 100)
        gdi32.TextOut(hdc, clientX + 2, clientY + 4, "CPU Usage: [")
        local barW = 20
        local cpuFilled = math.floor((_G.LastCpuPercent / 100) * barW)
        local cpuBar = string.rep("█", cpuFilled) .. string.rep(" ", barW - cpuFilled)
        gdi32.TextOut(hdc, clientX + 14, clientY + 4, cpuBar .. "] " .. _G.LastCpuPercent .. "%")
        gdi32.TextOut(hdc, clientX + 2, clientY + 6, "RAM Usage: [")
        local ramFilled = math.floor((ramPercent / 100) * barW)
        local ramBar = string.rep("█", ramFilled) .. string.rep(" ", barW - ramFilled)
        gdi32.TextOut(hdc, clientX + 14, clientY + 6, ramBar .. "] " .. ramPercent .. "%")
        gdi32.TextOut(hdc, clientX + 2, clientY + 8, string.format("Total RAM: %5d KB", math.floor(totalMem / 1024)))
        gdi32.TextOut(hdc, clientX + 2, clientY + 9, string.format("Used  RAM: %5d KB", math.floor(usedMem / 1024)))
        gdi32.TextOut(hdc, clientX + 2, clientY + 10, string.format("Free  RAM: %5d KB", math.floor(freeMem / 1024)))
    end
end

DrawTaskMgr()

repeat
    local signal = { computer.pullSignal(0.5) }
    local event = signal[1]

    if event == "touch" then
        local cx, cy = signal[3], signal[4]

        if cy == winY + 1 and (cx >= winX + winW - 3 and cx <= winX + winW - 1) then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
            gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
            break
        end

        if cy == winY + 2 then
            if cx >= winX + 2 and cx <= winX + 13 then
                currentTab = "PROCESSES"
                DrawTaskMgr()
            elseif cx >= winX + 15 and cx <= winX + 27 then
                currentTab = "PERFORMANCE"
                DrawTaskMgr()
            end
        end

        if currentTab == "PROCESSES" then
            if cy >= clientY + 2 and cy <= clientY + clientH - 3 then
                local clickedIdx = cy - (clientY + 1)
                local plist = ntdll.NtQuerySystemInformation() or {}
                if clickedIdx <= #plist then
                    selectedIndex = clickedIdx
                    DrawTaskMgr()
                end
            end

            if cy == winY + winH - 2 and (cx >= winX + winW - 12 and cx <= winX + winW - 2) then
                local plist = ntdll.NtQuerySystemInformation() or {}
                local targetProcess = plist[selectedIndex]
                if targetProcess and targetProcess.UniqueProcessId > 1 then
                    _G.PsTerminateThread(targetProcess.UniqueProcessId)
                    selectedIndex = 1
                    DrawTaskMgr()
                end
            end
        end

    elseif event == "key_down" then
        local code = signal[4]
        
        if currentTab == "PROCESSES" then
            if code == 200 then
                selectedIndex = selectedIndex - 1
                DrawTaskMgr()
            elseif code == 208 then
                selectedIndex = selectedIndex + 1
                DrawTaskMgr()
            elseif code == 211 then
                local plist = ntdll.NtQuerySystemInformation() or {}
                local targetProcess = plist[selectedIndex]
                if targetProcess and targetProcess.UniqueProcessId > 1 then
                    _G.PsTerminateThread(targetProcess.UniqueProcessId)
                    DrawTaskMgr()
                end
            end
        end
    
    elseif currentTab == "PERFORMANCE" then
        DrawTaskMgr()
    end

until false