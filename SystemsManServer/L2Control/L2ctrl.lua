local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
if not gdi32 then
    _G.DbgPrint("RELAY_CTRL: Failed to load GDI32.")
    return
end

local component = component
local computer = computer

local relay = component.proxy(component.list("relay")())
if not relay then
    local gpu = _G.HAL.gpu
    local hdc = gdi32.GetDC(0)
    local screenW, screenH = _G.HAL.w, _G.HAL.h
    local winW, winH = 50, 8
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)
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
    gdi32.TextOut(hdc, winX + 2, winY + 1, " Error")
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0xC0C0C0)
    gdi32.TextOut(hdc, winX + 2, winY + 4, "Relay not found! Please connect a switch.")
    gdi32.TextOut(hdc, winX + 2, winY + 6, "Press any key to exit...")
    computer.pullSignal(5)
    return
end

local gpu = _G.HAL.gpu
if not gpu then
    _G.DbgPrint("RELAY_CTRL: Error - GPU not found!")
    return
end

local hdc = gdi32.GetDC(0)
if not hdc then
    _G.DbgPrint("RELAY_CTRL: Failed to get GDI Device Context.")
    return
end

local currentStrength = relay.getStrength()
local isRepeater = relay.isRepeater()
local relayAddress = relay.address

local screenW, screenH = _G.HAL.w, _G.HAL.h
local winW, winH = 54, 20
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)
local clientX = winX + 1
local clientY = winY + 2

local statusText = "Ready"
local lossPercentText = ""
local buttons = {}

local function AddButton(x, y, w, h, label, action)
    table.insert(buttons, { x = x, y = y, w = w, h = h, label = label, action = action })
end

local function DrawButton(btn, pressed)
    local bgColor = pressed and 0x808080 or 0xE0E0E0
    local lightColor = pressed and 0x808080 or 0xFFFFFF
    local darkColor  = pressed and 0xFFFFFF or 0x808080
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(bgColor))
    gdi32.PatBlt(hdc, btn.x, btn.y, btn.w, btn.h, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(lightColor))
    gdi32.PatBlt(hdc, btn.x, btn.y, btn.w, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, btn.x, btn.y, 1, btn.h, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(darkColor))
    gdi32.PatBlt(hdc, btn.x, btn.y + btn.h - 1, btn.w, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, btn.x + btn.w - 1, btn.y, 1, btn.h, gdi32.PATCOPY)
    local labelX = btn.x + math.floor((btn.w - #btn.label) / 2)
    if labelX < btn.x + 1 then labelX = btn.x + 1 end
    local labelY = btn.y + math.floor(btn.h / 2)
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, bgColor)
    gdi32.TextOut(hdc, labelX, labelY, btn.label)
end

local function DrawWindow()
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
    gdi32.TextOut(hdc, winX + 2, winY + 1, " Relay Control Panel")
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")
    
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0xC0C0C0)
    gdi32.TextOut(hdc, clientX + 2, clientY + 1, "Address: " .. tostring(relayAddress):sub(1, 36))
    
    local repStatus = isRepeater and "ENABLED" or "DISABLED"
    local repColor = isRepeater and 0x00FF00 or 0xFF0000
    gdi32.SetTextColor(hdc, repColor)
    gdi32.TextOut(hdc, clientX + 2, clientY + 3, "Repeater Mode: " .. repStatus)
    
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.TextOut(hdc, clientX + 2, clientY + 5, "Signal Strength: " .. tostring(currentStrength))
    gdi32.TextOut(hdc, clientX + 2, clientY + 7, "Status: " .. statusText:sub(1, winW - 12))
    if lossPercentText ~= "" then
        gdi32.SetTextColor(hdc, 0xFFFF00)
        gdi32.TextOut(hdc, clientX + 2, clientY + 8, lossPercentText:sub(1, winW - 12))
    end

    buttons = {}
    local btnW, btnH = 16, 3
    local btnY1 = clientY + 10
    local spacing = 2

    AddButton(clientX + 2, btnY1, btnW, btnH, "Toggle Repeater", function()
        isRepeater = not isRepeater
        relay.setRepeater(isRepeater)
        statusText = "Repeater " .. (isRepeater and "enabled" or "disabled")
        _G.DbgPrint("RELAY_CTRL: Repeater mode = " .. tostring(isRepeater))
    end)

    AddButton(clientX + 2 + btnW + spacing, btnY1, btnW, btnH, "Strength +", function()
        if currentStrength < 100 then
            currentStrength = currentStrength + 10
            relay.setStrength(currentStrength)
            statusText = "Strength = " .. tostring(currentStrength)
        else
            statusText = "Max strength reached"
        end
        _G.DbgPrint("RELAY_CTRL: Strength = " .. tostring(currentStrength))
    end)

    AddButton(clientX + 2 + (btnW + spacing) * 2, btnY1, btnW, btnH, "Strength -", function()
        if currentStrength > 0 then
            currentStrength = currentStrength - 10
            relay.setStrength(currentStrength)
            statusText = "Strength = " .. tostring(currentStrength)
        else
            statusText = "Min strength reached"
        end
        _G.DbgPrint("RELAY_CTRL: Strength = " .. tostring(currentStrength))
    end)

    local btnY2 = clientY + 14
    local modemAddr = component.list("modem")()
    local modem = modemAddr and component.proxy(modemAddr) or nil
    if modem then
        AddButton(clientX + 2, btnY2, btnW, btnH, "Lossmeter", function()
            local PORT = 1234
            local PACKET_COUNT = 500
            local INTERVAL = 0.001

            modem.open(PORT)

            local sent = 0
            local received = 0
            local receivedSet = {}

            statusText = "Broadcasting " .. PACKET_COUNT .. " packets..."
            lossPercentText = ""
            DrawWindow()
            _G.DbgPrint("RELAY_CTRL: Lossmeter started. Broadcasting " .. PACKET_COUNT .. " packets.")

            for i = 1, PACKET_COUNT do
                modem.broadcast(PORT, i)
                sent = i
                if i % 100 == 0 then
                    statusText = "Sent " .. i .. " / " .. PACKET_COUNT
                    DrawWindow()
                end
                _G.KeDelayExecutionThread(INTERVAL)
            end

            statusText = "Sending GO!..."
            DrawWindow()
            modem.broadcast(PORT, "GO!")
            _G.DbgPrint("RELAY_CTRL: Sent GO! signal.")

            statusText = "Waiting for responses..."
            DrawWindow()

            local timeout = computer.uptime() + 20
            while computer.uptime() < timeout do
                local sig, _, remoteAddress, port, _, seq = computer.pullSignal(0.1)
                if sig == "modem_message" and port == PORT and seq then
                    if type(seq) == "number" and not receivedSet[seq] then
                        receivedSet[seq] = true
                        received = received + 1
                    end
                end
            end

            local lost = PACKET_COUNT - received
            local lossPercent = (lost / PACKET_COUNT) * 100
            statusText = string.format("Sent: %d  Recv: %d  Lost: %d", sent, received, lost)
            lossPercentText = string.format("Packet Loss: %.2f%%", lossPercent)
            _G.DbgPrint("RELAY_CTRL: Lossmeter finished. Sent=" .. sent ..
                ", Received=" .. received .. ", Lost=" .. lost ..
                ", Loss%=" .. string.format("%.2f", lossPercent))
        end)
    else
        AddButton(clientX + 2, btnY2, btnW, btnH, "No Modem", function()
            statusText = "Modem not found!"
            _G.DbgPrint("RELAY_CTRL: Lossmeter failed - no modem.")
        end)
    end

    local btnY3 = winY + winH - 3
    local smallW = 8
    AddButton(clientX + winW - (smallW * 2) - 4, btnY3, smallW, btnH, "[ OK ]", function()
        statusText = "Settings saved"
        _G.DbgPrint("RELAY_CTRL: Settings saved (repeater=" .. tostring(isRepeater) ..
            ", strength=" .. tostring(currentStrength) .. ")")
    end)

    AddButton(clientX + winW - smallW - 2, btnY3, smallW, btnH, "[Close]", function()
        return "EXIT"
    end)

    for _, btn in ipairs(buttons) do
        DrawButton(btn, false)
    end
end

DrawWindow()
_G.DbgPrint("RELAY_CTRL: Program started. Click buttons to control the relay.")

local function HitTest(btn, tx, ty)
    return tx >= btn.x and tx < btn.x + btn.w and
           ty >= btn.y and ty < btn.y + btn.h
end

while true do
    local signal = { computer.pullSignal(0.2) }
    local eventName = signal[1]
    if eventName == "touch" then
        local tx, ty = signal[3], signal[4]
        if ty == winY + 1 and tx >= winX + winW - 5 then
            _G.DbgPrint("RELAY_CTRL: Closed via title bar [X].")
            break
        end
        local redraw = false
        for _, btn in ipairs(buttons) do
            if HitTest(btn, tx, ty) then
                DrawButton(btn, true)
                computer.pullSignal(0.1)
                local result = btn.action()
                if result == "EXIT" then
                    _G.DbgPrint("RELAY_CTRL: Closed via [Close] button.")
                    goto exit_loop
                end
                redraw = true
                break
            end
        end
        if redraw then
            DrawWindow()
        end
    end
end

::exit_loop::
gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
_G.DbgPrint("RELAY_CTRL: Program terminated. Window cleared with 0x008080.")