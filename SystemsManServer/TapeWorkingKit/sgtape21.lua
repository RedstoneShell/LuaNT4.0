local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local function DbgPrint(...)
    if _G.DbgPrint then _G.DbgPrint(...) end
end

if not _G.Mm then _G.Mm = { NonPagedPool = {} } end
if not _G.Mm.NonPagedPool then _G.Mm.NonPagedPool = {} end
if not _G.Drives then _G.Drives = {} end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local LDM = _G.Tier2CM == true

local C_BG = 0xC0C0C0
local C_BTN = 0xE0E0E0
local C_WHITE = 0xFFFFFF
local C_BLACK = 0x000000
local C_TITLE = 0x000080
local C_DARK = 0x808080
local C_RED = 0xFF0000
local C_GREEN = 0x008000
local C_GRAY = 0x808080

local drives = {}
local selectedIndex = 1
local currentTab = 1
local tabSelection = { 1, 1, 1 }
local TAB_NAMES = { "Diagnostics", "Functions", "Report" }
local logLines = {}
local stats = { soft = 0, hard = 0, tracking = 0 }
local totalWritten = 0
local totalRead = 0
local loopCycles = 1
local statusText = "Ready"
local runningTest = nil
local needsRedraw = true

local CHUNK_SIZE = 2048
local QUICK_SIZE = 512

local TAB_ITEMS = {
    { "Quick Diag", "Full Diag", "Loop Test" },
    { "Erase (Short)", "Erase (Long)", "Retension", "Unload" },
    {}
}
local TAB_HINTS = {
    { "Buffer + BOT test", "Full tape verify", "Repeat test N cycles" },
    { "Reset BOT markers", "Overwrite tape", "Rewind EOT and back", "Eject cartridge" },
    {}
}

local function Log(msg)
    table.insert(logLines, tostring(msg))
    while #logLines > 500 do table.remove(logLines, 1) end
    DbgPrint("SGTAPE21: " .. tostring(msg))
end

local function ResetStats()
    stats.soft = 0
    stats.hard = 0
    stats.tracking = 0
    totalWritten = 0
    totalRead = 0
end

local function GetDriver()
    return _G.Mm.NonPagedPool["\\Driver\\4mmDAT"]
end

local function ScanDrives()
    local prevName = drives[selectedIndex] and drives[selectedIndex].name
    drives = {}
    local drv = GetDriver()
    if drv and drv.tapes then
        for name, tape in pairs(drv.tapes) do
            table.insert(drives, {
                name = name,
                device = tape.device,
                generation = tape.generation,
                capacity = tape.capacity,
                address = tape.address
            })
        end
        table.sort(drives, function(a, b) return a.name < b.name end)
    end
    selectedIndex = 1
    if prevName then
        for i, d in ipairs(drives) do
            if d.name == prevName then selectedIndex = i; break end
        end
    end
    return #drives
end

local function GetSelected()
    return drives[selectedIndex]
end

local function FillRect(x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(color))
    gdi32.PatBlt(hdc, x, y, w, h, gdi32.PATCOPY)
end

local function DrawTextF(x, y, w, text, fg, bg)
    if w <= 0 then return end
    text = tostring(text or "")
    if #text > w then text = text:sub(1, w) end
    
    local background = bg or C_BG
    fg = fg or C_BLACK
    
    gdi32.SetTextColor(hdc, fg)
    gdi32.SetBkColor(hdc, background)
    gdi32.SetBkMode(hdc, 2)
    
    gdi32.TextOut(hdc, x, y, text)
end

local function DrawButton(x, y, w, text, active)
    local bg = active and C_TITLE or C_BTN
    local fg = active and C_WHITE or C_BLACK
    FillRect(x, y, w, 1, bg)
    DrawTextF(x + 1, y, w - 2, text, fg, bg)
end

local function DrawFrame(x, y, w, h, title, showClose)
    FillRect(x, y, w, h, C_BG)
    FillRect(x, y, w, 1, C_WHITE)
    FillRect(x, y, 1, h, C_WHITE)
    FillRect(x, y + h - 1, w, 1, C_DARK)
    FillRect(x + w - 1, y, 1, h, C_DARK)
    FillRect(x + 1, y + 1, w - 2, 1, C_TITLE)
    if title then DrawTextF(x + 2, y + 1, w - 6, title, C_WHITE, C_TITLE) end
    if showClose then DrawTextF(x + w - 4, y + 1, 3, "[X]", C_WHITE, C_TITLE) end
end

local winW, winH
if LDM then
    winW, winH = 60, 18
else
    winW, winH = 68, 20
end
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local layout = {}
layout.bodyY = winY + 2
layout.bodyH = LDM and 6 or 7
layout.driveW = LDM and 22 or 24
layout.infoX = winX + layout.driveW + 2
layout.infoW = winW - layout.driveW - 3
layout.sep1Y = layout.bodyY + layout.bodyH
layout.tabY = layout.sep1Y + 1
layout.sep2Y = layout.tabY + 2
layout.contentY = layout.sep2Y + 1
layout.statusY = winY + winH - 3
layout.sep3Y = layout.statusY - 1
layout.contentH = layout.sep3Y - layout.contentY

local function MakeChunk(offset, size)
    local t = {}
    for i = 0, size - 1 do
        t[#t+1] = string.char((offset + i) % 128)
    end
    return table.concat(t)
end

local function VerifyChunk(offset, data)
    for i = 1, #data do
        if string.byte(data, i) ~= ((offset + i - 1) % 128) then
            return false, offset + i - 1
        end
    end
    return true
end

local function DrawMainWindow()
    DrawFrame(winX, winY, winW, winH, " SGTAPE21 - 4mm DAT Diagnostic Tool", true)

    local bodyY = layout.bodyY
    local bodyH = layout.bodyH
    local driveW = layout.driveW
    local infoX = layout.infoX
    local infoW = layout.infoW

    DrawTextF(winX + 2, bodyY, driveW - 2, "Drives:", C_BLACK, C_BG)

    for i, d in ipairs(drives) do
        if i > bodyH - 2 then break end
        local y = bodyY + i
        local shortName = d.name:gsub("\\Device\\", "")
        local prefix = (i == selectedIndex) and "> " or "  "
        local line = prefix .. shortName
        if i == selectedIndex then
            FillRect(winX + 1, y, driveW, 1, C_TITLE)
            DrawTextF(winX + 2, y, driveW - 2, line, C_WHITE, C_TITLE)
        else
            DrawTextF(winX + 2, y, driveW - 2, line, C_BLACK, C_BG)
        end
    end

    if #drives == 0 then
        DrawTextF(winX + 2, bodyY + 1, driveW - 2, "(no drives)", C_GRAY, C_BG)
    end

    FillRect(infoX - 1, bodyY, 1, bodyH, C_DARK)

    local sel = GetSelected()
    DrawTextF(infoX + 1, bodyY, infoW - 1, "Drive Information:", C_BLACK, C_BG)

    if sel then
        local dev = sel.device
        local pos, sz, state, label = 0, 0, "N/A", ""
        pcall(function()
            pos = tonumber(dev.getPosition()) or 0
            sz = tonumber(dev.getSize()) or 0
            state = tostring(dev.getState() or "READY")
            label = tostring(dev.getLabel() or "")
        end)
        
        local info = {
            "Name: " .. sel.name:gsub("\\Device\\", ""),
            "Gen:  " .. tostring(sel.generation) .. " (Cap: " .. tostring(sel.capacity) .. "B)",
            "Pos:  " .. tostring(pos) .. " / " .. tostring(sz),
            "Lbl:  " .. (label ~= "" and label or "(none)"),
            "State:" .. state,
        }
        for i, line in ipairs(info) do
            if i > bodyH - 2 then break end
            DrawTextF(infoX + 1, bodyY + i, infoW - 1, line, C_BLACK, C_BG)
        end
    end

    FillRect(winX + 1, layout.sep1Y, winW - 2, 1, C_DARK)

    local tx = winX + 2
    for i, name in ipairs(TAB_NAMES) do
        local bw = #name + 4
        DrawButton(tx, layout.tabY, bw, " " .. name .. " ", i == currentTab)
        tx = tx + bw + 2
    end

    FillRect(winX + 1, layout.sep2Y, winW - 2, 1, C_DARK)

    local contentY = layout.contentY
    local contentH = layout.contentH

    if currentTab == 1 or currentTab == 2 then
        local items = TAB_ITEMS[currentTab]
        local hints = TAB_HINTS[currentTab]
        
        local col1W = 16
        local col2X = winX + col1W + 4
        local col2W = winW - col1W - 6

        for i, item in ipairs(items) do
            if i > contentH - (currentTab == 1 and 2 or 0) then break end
            local y = contentY + i - 1
            local isSel = (tabSelection[currentTab] == i)
            local bg = isSel and C_TITLE or C_BG
            local fg = isSel and C_WHITE or C_BLACK
            
            if isSel then FillRect(winX + 1, y, winW - 2, 1, bg) end
            
            local prefix = isSel and "> " or "  "
            DrawTextF(winX + 2, y, col1W, prefix .. item, fg, bg)
            DrawTextF(col2X, y, col2W, hints[i] or "", C_GRAY, bg)
        end

        if currentTab == 1 then
            local loopY = contentY + #items + 1
            if loopY < layout.sep3Y then
                FillRect(winX + 2, loopY, winW - 4, 1, C_BTN)
                DrawTextF(winX + 2, loopY, 16, "  Cycles:", C_BLACK, C_BTN)
                DrawTextF(winX + 18, loopY, 8, "[ " .. string.format("%2d", loopCycles) .. " ]", C_TITLE, C_BTN)
                DrawTextF(winX + 28, loopY, winW - 30, "(+/- to change)", C_GRAY, C_BTN)
            end
        end
    elseif currentTab == 3 then
        DrawTextF(winX + 2, contentY, winW - 4, "Report log (" .. #logLines .. " entries):", C_BLACK, C_BG)
        local maxShow = contentH - 1
        local start = math.max(1, #logLines - maxShow + 1)
        for i = start, #logLines do
            local y = contentY + 1 + (i - start)
            if y >= layout.sep3Y then break end
            DrawTextF(winX + 2, y, winW - 4, logLines[i], C_GRAY, C_BG)
        end
        if #logLines == 0 then
            DrawTextF(winX + 2, contentY + 2, winW - 4, "(no log entries)", C_GRAY, C_BG)
        end
    end

    FillRect(winX + 1, layout.sep3Y, winW - 2, 1, C_DARK)

    local exitBtnW = 8
    local rescanBtnW = 10
    local exitX = winX + winW - exitBtnW - 2
    local rescanX = exitX - rescanBtnW - 2
    
    DrawTextF(winX + 2, layout.statusY, rescanX - winX - 3, statusText, C_BLACK, C_BG)
    DrawButton(rescanX, layout.statusY, rescanBtnW, "[Rescan]")
    DrawButton(exitX, layout.statusY, exitBtnW, "[Exit]")
end

local function DrawProgress()
    local t = runningTest
    if not t then return nil end

    local pw, ph = 48, 18
    local px = math.floor((screenW - pw) / 2)
    local py = math.floor((screenH - ph) / 2)

    DrawFrame(px, py, pw, ph, " Diagnostic in progress", true)

    local y = py + 3
    DrawTextF(px + 2, y, pw - 4, "Test: " .. t.type, C_BLACK, C_BG); y = y + 1
    DrawTextF(px + 2, y, pw - 4, "Drive: " .. t.drive.name:gsub("\\Device\\", ""), C_BLACK, C_BG); y = y + 2

    local total = (t.type == "Quick Diagnostic") and QUICK_SIZE or t.totalSize
    local pct
    if t.phase == "read" then
        pct = math.min(100, math.floor(50 + (t.readDone / math.max(1, t.bytesDone)) * 50))
    elseif t.phase == "rewind" then
        pct = 50
    elseif t.phase == "done" then
        pct = 100
    else
        pct = math.min(50, math.floor((t.bytesDone / math.max(1, total)) * 50))
    end

    local barW = pw - 14
    local filled = math.floor(barW * pct / 100)
    local bar = "[" .. string.rep("#", filled) .. string.rep("-", barW - filled) .. "] " .. pct .. "%"
    DrawTextF(px + 2, y, pw - 4, bar, C_GREEN, C_BG); y = y + 1

    DrawTextF(px + 2, y, pw - 4, "Written: " .. t.bytesDone .. " / " .. total, C_BLACK, C_BG); y = y + 2

    DrawTextF(px + 2, y, pw - 4, "Error Counters:", C_BLACK, C_BG); y = y + 1
    local function errColor(n) return n > 0 and C_RED or C_GREEN end
    DrawTextF(px + 4, y, pw - 6, "Soft: " .. stats.soft, errColor(stats.soft), C_BG); y = y + 1
    DrawTextF(px + 4, y, pw - 6, "Hard: " .. stats.hard, errColor(stats.hard), C_BG); y = y + 1
    DrawTextF(px + 4, y, pw - 6, "Track: " .. stats.tracking, errColor(stats.tracking), C_BG); y = y + 2

    DrawTextF(px + 2, y, pw - 4, "Log:", C_BLACK, C_BG); y = y + 1
    local maxLog = py + ph - 3 - y
    for i = math.max(1, #logLines - maxLog + 1), #logLines do
        if y >= py + ph - 3 then break end
        DrawTextF(px + 2, y, pw - 4, logLines[i], C_GRAY, C_BG)
        y = y + 1
    end

    DrawButton(px + pw - 10, py + ph - 3, 9, "[Abort]")
    return px, py, pw, ph
end

local function StartTest(testType)
    local sel = GetSelected()
    if not sel or not sel.device then
        statusText = "No drive selected"
        return
    end
    local ready = false
    pcall(function() ready = sel.device.isReady() end)
    if not ready then
        statusText = "Drive not ready - insert tape"
        return
    end

    ResetStats()
    logLines = {}
    Log("=== " .. testType .. " ===")
    Log("Drive: " .. sel.name:gsub("\\Device\\", ""))
    Log("Gen: " .. tostring(sel.generation) .. "  Cap: " .. tostring(sel.capacity))

    local cap = tonumber(sel.capacity) or 0
    if cap <= 0 then cap = 1024 * 1024 end

    runningTest = {
        type = testType,
        drive = sel,
        phase = "init",
        totalSize = cap,
        bytesDone = 0,
        readDone = 0,
        loops = loopCycles,
        currentLoop = 1
    }
    statusText = "Running: " .. testType
end

local function AdvanceTest()
    local t = runningTest
    if not t then return end
    local dev = t.drive.device

    if t.phase == "init" then
        pcall(function() dev.stop() end)
        pcall(function() dev.seek(-dev.getSize()) end)
        pcall(function() dev.stop() end)
        
        t.phase = "write"
        t.bytesDone = 0
        Log("Loop " .. t.currentLoop .. "/" .. t.loops .. " - rewound to BOT")
        return
    end

    if t.phase == "write" then
        local limit = (t.type == "Quick Diagnostic") and QUICK_SIZE or t.totalSize
        local remaining = limit - t.bytesDone
        if remaining <= 0 then
            t.phase = "rewind"
            Log("Write done: " .. t.bytesDone .. " bytes")
            return
        end
        
        local chunk = math.min(CHUNK_SIZE, remaining)
        local pattern = MakeChunk(t.bytesDone, chunk)
        
        local success, errMsg = pcall(dev.write, pattern)
        
        if not success then
            stats.hard = stats.hard + 1
            Log("HARD ERROR write @" .. t.bytesDone .. " : " .. tostring(errMsg))
            t.phase = "done"
            return
        end
        
        t.bytesDone = t.bytesDone + chunk
        totalWritten = t.bytesDone
        return
    end

    if t.phase == "rewind" then
        pcall(function() dev.stop() end)
        pcall(function() dev.seek(-dev.getSize()) end)
        pcall(function() dev.stop() end)
        
        t.phase = "read"
        t.readDone = 0
        return
    end

    if t.phase == "read" then
        if t.readDone >= t.bytesDone then
            if t.type == "Loop Test" and t.currentLoop < t.loops then
                t.currentLoop = t.currentLoop + 1
                t.phase = "init"
                return
            end
            t.phase = "done"
            return
        end
        
        local chunk = math.min(CHUNK_SIZE, t.bytesDone - t.readDone)
        local success, data, err = pcall(dev.read, chunk)
        
        if not success or not data or #data == 0 then
            stats.hard = stats.hard + 1
            Log("HARD ERROR read @" .. t.readDone .. " : " .. tostring(err or "no data"))
            t.phase = "done"
            return
        end
        
        local match, errPos = VerifyChunk(t.readDone, data)
        if not match then
            stats.soft = stats.soft + 1
            if stats.soft <= 5 then Log("SOFT ERROR @" .. errPos) end
        end
        
        t.readDone = t.readDone + #data
        totalRead = t.readDone
        return
    end

    if t.phase == "done" then
        pcall(function() dev.stop() end)
        pcall(function() dev.seek(-dev.getSize()) end)
        
        Log("=== Complete ===")
        Log("Written: " .. totalWritten .. "  Read: " .. totalRead)
        Log("Soft: " .. stats.soft .. "  Hard: " .. stats.hard)
        statusText = (stats.hard > 0) and "FAILED" or "PASSED"
        runningTest = nil
    end
end

local function RunFunction(item)
    local sel = GetSelected()
    if not sel or not sel.device then
        statusText = "No drive selected"
        return
    end
    local dev = sel.device
    Log("Function: " .. item)

    if item == "Erase (Short)" then
        pcall(function()
            dev.stop()
            dev.seek(-dev.getSize())
            dev.write("\0")
        end)
        statusText = "Short erase done (BOT reset)"
    elseif item == "Erase (Long)" then
        pcall(function()
            dev.stop()
            dev.seek(-dev.getSize())
        end)
        Log("Note: full magnetic erase not exposed by component API")
        statusText = "Long erase: rewound to BOT"
    elseif item == "Retension" then
        pcall(function()
            dev.stop()
            local sz = dev.getSize() or 0
            dev.seek(sz)
            dev.seek(-sz)
        end)
        statusText = "Retension done"
    elseif item == "Unload" then
        pcall(function() dev.stop() end)
        statusText = "Unload requested"
    end
end

local function HandleMainInput(signal)
    local event = signal[1]

    if event == "key_down" then
        local char, code = signal[3], signal[4]

        if code == 1 then return false end

        if code == 200 then
            if selectedIndex > 1 then selectedIndex = selectedIndex - 1 end
        elseif code == 208 then
            if selectedIndex < #drives then selectedIndex = selectedIndex + 1 end
        elseif code == 203 then
            currentTab = math.max(1, currentTab - 1)
        elseif code == 205 then
            currentTab = math.min(#TAB_NAMES, currentTab + 1)
        elseif code == 28 then
            if currentTab == 1 then
                local names = { "Quick Diagnostic", "Full Diagnostic", "Loop Test" }
                StartTest(names[tabSelection[1]] or "Quick Diagnostic")
            elseif currentTab == 2 then
                RunFunction(TAB_ITEMS[2][tabSelection[2]])
            end
        elseif char then
            local c = string.char(char)
            if c == "r" or c == "R" then
                if currentTab == 1 then
                    local names = { "Quick Diagnostic", "Full Diagnostic", "Loop Test" }
                    StartTest(names[tabSelection[1]] or "Quick Diagnostic")
                elseif currentTab == 2 then
                    RunFunction(TAB_ITEMS[2][tabSelection[2]])
                end
            elseif c == "+" or c == "=" then
                loopCycles = math.min(99, loopCycles + 1)
            elseif c == "-" or c == "_" then
                loopCycles = math.max(1, loopCycles - 1)
            elseif c == "q" or c == "Q" then
                return false
            end
        end

    elseif event == "touch" then
        local tx, ty = signal[3], signal[4]

        if ty == winY + 1 and tx >= winX + winW - 4 then return false end

        if ty >= layout.bodyY and ty < layout.sep1Y then
            if tx >= winX + 1 and tx < winX + layout.driveW then
                local idx = ty - layout.bodyY
                if idx >= 1 and idx <= #drives then
                    selectedIndex = idx
                end
            end
        elseif ty == layout.tabY then
            local tx2 = winX + 2
            for i, name in ipairs(TAB_NAMES) do
                local bw = #name + 4
                if tx >= tx2 and tx < tx2 + bw then
                    currentTab = i
                    break
                end
                tx2 = tx2 + bw + 2
            end
        elseif ty >= layout.contentY and ty < layout.sep3Y then
            if currentTab == 1 or currentTab == 2 then
                local idx = ty - layout.contentY + 1
                if idx >= 1 and idx <= #TAB_ITEMS[currentTab] then
                    tabSelection[currentTab] = idx
                    if currentTab == 1 then
                        local names = { "Quick Diagnostic", "Full Diagnostic", "Loop Test" }
                        StartTest(names[idx])
                    else
                        RunFunction(TAB_ITEMS[2][idx])
                    end
                end
                if currentTab == 1 then
                    local loopY = layout.contentY + #TAB_ITEMS[1] + 1
                    if ty == loopY and tx >= winX + 18 and tx <= winX + 28 then
                        loopCycles = loopCycles >= 99 and 1 or loopCycles + 1
                    end
                end
            end
        elseif ty == layout.statusY then
            local exitBtnW = 8
            local rescanBtnW = 10
            local exitX = winX + winW - exitBtnW - 2
            local rescanX = exitX - rescanBtnW - 2
            if tx >= exitX and tx < exitX + exitBtnW then
                return false
            elseif tx >= rescanX and tx < rescanX + rescanBtnW then
                local n = ScanDrives()
                statusText = "Rescan: " .. n .. " drive(s)"
                Log("Rescan: " .. n .. " drive(s)")
            end
        end
    end
    return true
end

DbgPrint("SGTAPE21: Starting 4mm DAT diagnostic tool")
ScanDrives()
statusText = #drives .. " drive(s) found"
Log("SGTAPE21 ready. Drives: " .. #drives)

local running = true
while running do
    if needsRedraw then
        DrawMainWindow()
        if runningTest then DrawProgress() end
        needsRedraw = false
    end

    local timeout = runningTest and 0.05 or 0.2
    local signal = { computer.pullSignal(timeout) }
    
    if #signal > 0 then
        needsRedraw = true
        if runningTest then
            local event = signal[1]
            if event == "key_down" then
                local code = signal[4]
                if code == 1 then
                    Log("Test aborted by user")
                    runningTest = nil
                    statusText = "Aborted"
                end
            elseif event == "touch" then
                local pw, ph = 48, 18
                local px = math.floor((screenW - pw) / 2)
                local py = math.floor((screenH - ph) / 2)
                local tx, ty = signal[3], signal[4]
                if ty == py + ph - 3 and tx >= px + pw - 10 and tx < px + pw - 1 then
                    Log("Test aborted by user")
                    runningTest = nil
                    statusText = "Aborted"
                end
            end
        else
            if not HandleMainInput(signal) then
                running = false
            end
        end
    elseif runningTest then
        AdvanceTest()
        needsRedraw = true
    end
end

DbgPrint("SGTAPE21: Closed.")
return true