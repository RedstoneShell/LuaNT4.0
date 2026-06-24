-- (C) RedstoneShell 2026

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local args = {}
if _G.RpcSs then
    local rpcOk, result = _G.RpcSs.RpcCliExecute("IConsoleManager", "GetProcessArgs")
    if rpcOk and result then
        args = result
    end
end

local function printToConsole(text)
    if _G.RpcSs then
        _G.RpcSs.RpcCliExecute("IConsoleManager", "WriteStdOut", tostring(text))
    else
        _G.DbgPrint("DevMgr: " .. tostring(text))
    end
end
local print = printToConsole

local function ParseArguments(args)
    local showHelp = false
    local deviceFilter = nil
    local showResources = false
    
    for _, arg in ipairs(args) do
        if arg == "/?" or arg == "-h" or arg == "--help" then
            showHelp = true
        elseif arg == "/r" or arg == "-r" or arg == "--resources" then
            showResources = true
        elseif arg:sub(1, 1) ~= "/" and arg:sub(1, 1) ~= "-" then
            deviceFilter = arg
        end
    end
    
    if showHelp then
        print("Device Manager - Hardware Management for LuaNT 4.0")
        print("")
        print("Usage: devmgr [filter] [/r] [/help]")
        print("")
        print("  filter       - Show only devices matching this type")
        print("  /r, /resources - Show resource allocation (IRQ, DMA)")
        print("  /?, /help    - Show this help message")
        print("")
        print("Commands in Device Manager:")
        print("  ENTER        - View device properties")
        print("  TAB          - Toggle Resource View")
        print("  R            - Refresh device list")
        print("  ESC          - Close Device Manager")
        print("")
        print("Examples:")
        print("  devmgr")
        print("  devmgr gpu")
        print("  devmgr /r")
        print("  devmgr filesystem /r")
        return nil, true
    end
    
    return deviceFilter, showResources, false
end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h
local winW, winH = 70, 24
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)
local clientX = winX + 1
local clientY = winY + 2
local clientW = winW - 2
local clientH = winH - 3
local devices = {}
local selectedIndex = 1
local scrollOffset = 0
local selectedDevice = nil
local viewMode = "list" -- "list" or "properties"
local showResources = false

local COLORS = {
    window_bg = 0xCCCCCC,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    selected = 0x000080,
    selected_text = 0xFFFFFF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF,
    good = 0x008000,
    warning = 0xFF8000,
    error = 0xFF0000,
    resource = 0x0066CC
}

local function GetDevicesFromPnP()
    local deviceList = {}
    
    local pnpManager = _G.PnPManager
    if pnpManager and pnpManager.DeviceTree then
        for addr, device in pairs(pnpManager.DeviceTree) do
            table.insert(deviceList, {
                address = addr,
                type = device.type or "Unknown",
                label = device.friendlyName or "No Label",
                slot = device.instance or 0,
                status = device.status or "Unknown",
                description = device.friendlyName or device.type,
                hardwareId = device.hardwareId,
                classGuid = device.classGuid,
                service = device.service,
                resources = device.resources or {},
                driver = device.driver and "Loaded" or "Not Loaded"
            })
        end
        
        table.sort(deviceList, function(a, b)
            if a.type == b.type then
                return a.slot < b.slot
            end
            return a.type < b.type
        end)
        
        return deviceList
    end
    
    print("PnP Manager not available. Scanning components directly...")
    for address in component.list() do
        local proxy = component.proxy(address)
        local devType = component.type(address)
        local label = proxy.getLabel and proxy.getLabel() or "No Label"
        local slot = component.slot(address) or 0
        
        table.insert(deviceList, {
            address = address,
            type = devType,
            label = label,
            slot = slot,
            status = "OK",
            description = devType .. " (" .. label .. ")",
            hardwareId = string.format("OC\\%s_%s", devType:upper(), address:sub(1,4):upper()),
            classGuid = "Unknown",
            service = nil,
            resources = {},
            driver = "Unknown"
        })
    end
    
    table.sort(deviceList, function(a, b)
        if a.type == b.type then
            return a.slot < b.slot
        end
        return a.type < b.type
    end)
    
    return deviceList
end

local function RefreshDeviceList(filter)
    devices = GetDevicesFromPnP()
    
    if filter then
        local filtered = {}
        for _, dev in ipairs(devices) do
            if dev.type:find(filter, 1, true) or 
               dev.label:find(filter, 1, true) or
               (dev.hardwareId and dev.hardwareId:find(filter, 1, true)) then
                table.insert(filtered, dev)
            end
        end
        devices = filtered
    end
    
    if #devices == 0 then
        print("Device Manager: No devices found!")
        return false
    end
    
    selectedIndex = math.min(selectedIndex, #devices)
    if selectedIndex < 1 then selectedIndex = 1 end
    scrollOffset = 0
    
    return true
end

local function DrawWindowFrame()
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.window_bg))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
    gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.window_title))
    gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.window_title)
    
    local title = "Device Manager"
    if showResources then title = title .. " [Resources]" end
    if viewMode == "properties" and selectedDevice then
        title = "Properties - " .. (selectedDevice.label or selectedDevice.type)
    end
    gdi32.TextOut(hdc, winX + 2, winY + 1, title)
    
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
end

local function DrawList()
    local visibleItems = clientH - 2
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local header = "Type                Address        Status  Driver       Label"
    if showResources then
        header = "Type                Address        IRQ DMA Driver       Label"
    end
    gdi32.TextOut(hdc, clientX + 1, clientY, header)
    gdi32.TextOut(hdc, clientX + 1, clientY + 1, string.rep("─", clientW - 1))
    
    for i = scrollOffset + 1, math.min(scrollOffset + visibleItems, #devices) do
        local dev = devices[i]
        local yPos = clientY + 2 + (i - scrollOffset - 1)
        local isSelected = (i == selectedIndex)
        
        if isSelected then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.selected))
            gdi32.PatBlt(hdc, clientX, yPos, clientW, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, COLORS.selected_text)
        else
            gdi32.SetTextColor(hdc, COLORS.text)
        end
        gdi32.SetBkColor(hdc, isSelected and COLORS.selected or COLORS.client_bg)
        
        local statusChar = "OK"
        local statusColor = COLORS.good
        if dev.status == "Warning" or dev.status == "Warning" then
            statusChar = "!"
            statusColor = COLORS.warning
        elseif dev.status == "Error" or dev.status == "Stopped" then
            statusChar = "X"
            statusColor = COLORS.error
        end
        
        if isSelected then
            gdi32.SetTextColor(hdc, COLORS.selected_text)
        else
            gdi32.SetTextColor(hdc, statusColor)
        end
        gdi32.TextOut(hdc, clientX + 1, yPos, statusChar)
        
        if isSelected then
            gdi32.SetTextColor(hdc, COLORS.selected_text)
        else
            gdi32.SetTextColor(hdc, COLORS.text)
        end
        
        local typeStr = (dev.type or "Unknown"):sub(1, 18)
        local addrStr = (dev.address or ""):sub(1, 15)
        local driverStr = (dev.driver or "None"):sub(1, 10)
        local labelStr = (dev.label or ""):sub(1, 10)
        
        if showResources and dev.resources then
            local irqStr = tostring(dev.resources.irq or "-")
            local dmaStr = tostring(dev.resources.dma or "-")
            gdi32.TextOut(hdc, clientX + 3, yPos, 
                string.format("%-18s %-15s %3s %3s %-10s %s", 
                    typeStr, addrStr, irqStr, dmaStr, driverStr, labelStr))
        else
            local statusStr = dev.status:sub(1, 6)
            gdi32.TextOut(hdc, clientX + 3, yPos, 
                string.format("%-18s %-15s %-6s %-10s %s", 
                    typeStr, addrStr, statusStr, driverStr, labelStr))
        end
    end
    
    gdi32.SetTextColor(hdc, 0x888888)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local hint = "↑↓ Select  ENTER: Properties  TAB: Toggle Resources  R: Refresh  <: Exit"
    gdi32.TextOut(hdc, clientX + 2, clientY + clientH - 1, hint)
end

local function DrawProperties()
    if not selectedDevice then return end
    
    local dev = selectedDevice
    local line = 0
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local function propLine(label, value, color)
        if value then
            if color then gdi32.SetTextColor(hdc, color) end
            gdi32.TextOut(hdc, clientX + 2, clientY + line, 
                string.format("%-15s: %s", label, tostring(value)))
            if color then gdi32.SetTextColor(hdc, COLORS.text) end
            line = line + 1
        end
    end
    
    propLine("Type", dev.type)
    propLine("Address", dev.address)
    propLine("Slot", dev.slot)
    propLine("Label", dev.label)
    
    local statusColor = COLORS.good
    if dev.status == "Warning" then statusColor = COLORS.warning
    elseif dev.status == "Error" or dev.status == "Stopped" then statusColor = COLORS.error end
    propLine("Status", dev.status, statusColor)
    
    propLine("Description", dev.description)
    propLine("Hardware ID", dev.hardwareId)
    propLine("Class GUID", dev.classGuid)
    propLine("Service", dev.service or "None")
    propLine("Driver", dev.driver or "Not Loaded")
    
    if dev.resources and next(dev.resources) then
        line = line + 1
        gdi32.SetTextColor(hdc, COLORS.resource)
        gdi32.TextOut(hdc, clientX + 2, clientY + line, "Resources:")
        line = line + 1
        gdi32.SetTextColor(hdc, COLORS.text)
        
        if dev.resources.irq then
            propLine("  IRQ", dev.resources.irq)
        end
        if dev.resources.dma then
            propLine("  DMA", dev.resources.dma)
        end
        if dev.resources.port then
            propLine("  Port", dev.resources.port)
        end
        if dev.resources.memory then
            propLine("  Memory", dev.resources.memory)
        end
    end
    
    gdi32.SetTextColor(hdc, 0x888888)
    gdi32.TextOut(hdc, clientX + 2, clientY + line + 1, "[Press < to go back]")
end

local function RedrawWindow()
    DrawWindowFrame()
    
    if viewMode == "list" then
        DrawList()
    else
        DrawProperties()
    end
end

local function HandleKey(char, code)
    if viewMode == "list" then
        if code == 200 then -- UP
            if selectedIndex > 1 then
                selectedIndex = selectedIndex - 1
                if selectedIndex <= scrollOffset then
                    scrollOffset = selectedIndex - 1
                end
                RedrawWindow()
            end
        elseif code == 208 then -- DOWN
            if selectedIndex < #devices then
                selectedIndex = selectedIndex + 1
                if selectedIndex > scrollOffset + clientH - 4 then
                    scrollOffset = selectedIndex - clientH + 4
                end
                RedrawWindow()
            end
        elseif code == 28 then -- ENTER
            selectedDevice = devices[selectedIndex]
            viewMode = "properties"
            RedrawWindow()
        elseif code == 15 then -- TAB
            showResources = not showResources
            print("Device Manager: " .. (showResources and "Resource view enabled" or "Normal view enabled"))
            RedrawWindow()
        elseif char == 82 or char == 114 then -- R or r
            print("Refreshing device list...")
            RefreshDeviceList(currentFilter)
            RedrawWindow()
            print("Device Manager: " .. #devices .. " devices found")
        elseif code == 203 then -- <
            return false
        end
    else
        if code == 203 then -- <
            viewMode = "list"
            RedrawWindow()
        end
    end
    return true
end

local currentFilter = nil

local function DevMgrMain()
    _G.DbgPrint("DevMgr: Starting...")
    
    local filter, showResourcesFlag, showHelp = ParseArguments(args)
    currentFilter = filter
    showResources = showResourcesFlag
    
    if showHelp then
        return false
    end
    
    if not RefreshDeviceList(filter) then
        return false
    end
    
    print("Device Manager: Found " .. #devices .. " devices")
    if showResources then
        print("Resource view enabled (IRQ/DMA)")
    end
    print("Press < to exit, ENTER for properties, TAB to toggle resources, R to refresh")
    
    RedrawWindow()
    
    while true do
        local signal = { computer.pullSignal(0.1) }
        
        if signal[1] == "key_down" then
            local char = signal[3]
            local code = signal[4]
            
            if not HandleKey(char, code) then
                break
            end
            
        elseif signal[1] == "touch" then
            local x, y = signal[3], signal[4]
            if y == winY + 1 and x >= winX + winW - 3 and x <= winX + winW - 1 then
                break
            end
        end
    end
    
    _G.DbgPrint("DevMgr: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return false
end

local ahh=DevMgrMain()
if not ahh then
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true