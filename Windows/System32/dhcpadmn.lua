-- dhcpadmn.lua - DHCP Manager (окремий процес)
-- (C) RedstoneShell 2026
-- Керує dhcpssvc.lua через RPC

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

-- ===== Адаптивні розміри =====
local winW = math.min(math.max(90, screenW - 4), screenW)
local winH = math.min(28, screenH - 2)
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local clientX = winX + 1
local clientY = winY + 2
local clientW = winW - 2
local clientH = winH - 3

local treeW = 22
local contentW = clientW - treeW - 2
local contentX = clientX + treeW + 2

local activeTab = 1
local selectedItem = 1
local statusText = "Ready"

-- ===== Локальні копії даних =====
local scopes = {}
local leases = {}
local exclusions = {}
local config = {}

-- ===== Формати =====
local SCOPE_FMT = "%-18s %-15s %-15s %-15s %-8s"
local LEASE_FMT = "%-15s %-19s %-8s %-10s"
local EXCL_FMT  = "%-15s %-15s %-20s"

-- ===== RPC =====
local function RpcCall(method, ...)
    if not _G.RpcSs then
        return false, "RPC not available"
    end
    return _G.RpcSs.RpcCliExecute("IDhcpServer", method, ...)
end

local function RefreshData()
    local ok1, cfg = RpcCall("GetConfig")
    if ok1 and cfg then config = cfg end

    local ok2, sc = RpcCall("GetScopes")
    if ok2 and sc then scopes = sc end

    local ok3, l = RpcCall("GetLeases")
    if ok3 and l then leases = l end

    local ok4, ex = RpcCall("GetExclusions")
    if ok4 and ex then exclusions = ex end

    statusText = "Data refreshed"
    coroutine.yield()
end

-- ===== Малювання =====
local function DrawWindow()
    -- Фон
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)

    -- 3D-рамка
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
    gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)

    -- Заголовок
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
    gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000080)
    gdi32.TextOut(hdc, winX + 2, winY + 1, " DHCP Manager - (Local Machine)")
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

    -- Дерево
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, clientX, clientY + 2, treeW, clientH - 4, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xFFFFFF)
    gdi32.TextOut(hdc, clientX + 1, clientY + 2, "DHCP Servers")
    gdi32.TextOut(hdc, clientX + 2, clientY + 4, "└─ Local Machine")
    gdi32.TextOut(hdc, clientX + 4, clientY + 5, "   ├─ Scopes")
    gdi32.TextOut(hdc, clientX + 4, clientY + 6, "   ├─ Leases")
    gdi32.TextOut(hdc, clientX + 4, clientY + 7, "   └─ Exclusions")

    -- Вкладки
    local tabX = contentX
    local tabW1, tabW2, tabW3 = 10, 10, 13
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
    gdi32.PatBlt(hdc, tabX, clientY + 2, tabW1, 2, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, tabX + tabW1, clientY + 2, tabW2, 2, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, tabX + tabW1 + tabW2, clientY + 2, tabW3, 2, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xE0E0E0)
    gdi32.TextOut(hdc, tabX + 1, clientY + 2, " Scopes ")
    gdi32.TextOut(hdc, tabX + tabW1 + 1, clientY + 2, " Leases ")
    gdi32.TextOut(hdc, tabX + tabW1 + tabW2 + 1, clientY + 2, " Exclusions ")

    -- Контент
    local contentY = clientY + 5
    local contentH = clientH - 8
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, contentX, contentY, contentW, contentH, gdi32.PATCOPY)

    if activeTab == 1 then
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)
        gdi32.TextOut(hdc, contentX + 1, contentY,
            string.format(SCOPE_FMT, "Name", "Start IP", "End IP", "Mask", "State"))
        gdi32.TextOut(hdc, contentX + 1, contentY + 1,
            string.rep("─", math.min(contentW - 2, 80)))

        for i, scope in ipairs(scopes) do
            local line = string.format(SCOPE_FMT,
                scope.name:sub(1, 18),
                scope.start_ip:sub(1, 15),
                scope.end_ip:sub(1, 15),
                scope.subnet_mask:sub(1, 15),
                scope.state)
            if i == selectedItem then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
                gdi32.PatBlt(hdc, contentX + 1, contentY + 1 + i, contentW - 2, 1, gdi32.PATCOPY)
                gdi32.SetTextColor(hdc, 0xFFFFFF)
            else
                gdi32.SetTextColor(hdc, 0x000000)
            end
            gdi32.TextOut(hdc, contentX + 1, contentY + 1 + i, line)
        end

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.TextOut(hdc, contentX + 1, contentY + contentH - 1,
            "[ Create Scope ]  [ Delete Scope ]  [ Properties ]")

    elseif activeTab == 2 then
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)
        gdi32.TextOut(hdc, contentX + 1, contentY,
            string.format(LEASE_FMT, "IP Address", "Hostname", "Type", "Expires"))
        gdi32.TextOut(hdc, contentX + 1, contentY + 1,
            string.rep("─", math.min(contentW - 2, 57)))

        local i = 0
        for uuid, lease in pairs(leases) do
            i = i + 1
            local remaining = math.max(0, lease.expires - computer.uptime())
            local line = string.format(LEASE_FMT,
                lease.ip:sub(1, 15),
                lease.hostname:sub(1, 19),
                "Dynamic",
                tostring(math.floor(remaining)) .. "s")
            if i == selectedItem then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
                gdi32.PatBlt(hdc, contentX + 1, contentY + 1 + i, contentW - 2, 1, gdi32.PATCOPY)
                gdi32.SetTextColor(hdc, 0xFFFFFF)
            else
                gdi32.SetTextColor(hdc, 0x000000)
            end
            gdi32.TextOut(hdc, contentX + 1, contentY + 1 + i, line)
            if i > contentH - 4 then break end
        end
        if i == 0 then
            gdi32.SetTextColor(hdc, 0x808080)
            gdi32.TextOut(hdc, contentX + 2, contentY + 3, "(No active leases)")
        end
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.TextOut(hdc, contentX + 1, contentY + contentH - 1,
            "[ Refresh ]  [ Release ]  [ Delete ]")

    else
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)
        gdi32.TextOut(hdc, contentX + 1, contentY,
            string.format(EXCL_FMT, "Start IP", "End IP", "Reason"))
        gdi32.TextOut(hdc, contentX + 1, contentY + 1,
            string.rep("─", math.min(contentW - 2, 52)))

        for i, excl in ipairs(exclusions) do
            local line = string.format(EXCL_FMT,
                excl.start_ip:sub(1, 15),
                excl.end_ip:sub(1, 15),
                excl.reason:sub(1, 20))
            if i == selectedItem then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
                gdi32.PatBlt(hdc, contentX + 1, contentY + 1 + i, contentW - 2, 1, gdi32.PATCOPY)
                gdi32.SetTextColor(hdc, 0xFFFFFF)
            else
                gdi32.SetTextColor(hdc, 0x000000)
            end
            gdi32.TextOut(hdc, contentX + 1, contentY + 1 + i, line)
        end
        if #exclusions == 0 then
            gdi32.SetTextColor(hdc, 0x808080)
            gdi32.TextOut(hdc, contentX + 2, contentY + 3, "(No exclusions)")
        end
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.TextOut(hdc, contentX + 1, contentY + contentH - 1,
            "[ Add Exclusion ]  [ Delete Exclusion ]")
    end

    -- Статус-бар
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
    gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xC0C0C0)
    gdi32.TextOut(hdc, winX + 2, winY + winH - 2, " " .. statusText)
end

local function DrawDialog(x, y, w, h, title, fields, activeField, buttons)
    -- Фон
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
    gdi32.PatBlt(hdc, x, y, w, h, gdi32.PATCOPY)

    -- 3D-рамка
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, x, y, w, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, x, y, 1, h, gdi32.PATCOPY)
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
    gdi32.PatBlt(hdc, x, y + h - 1, w, 1, gdi32.PATCOPY)
    gdi32.PatBlt(hdc, x + w - 1, y, 1, h, gdi32.PATCOPY)

    -- Заголовок
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
    gdi32.PatBlt(hdc, x + 1, y + 1, w - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000080)
    gdi32.TextOut(hdc, x + 2, y + 1, " " .. title)

    -- Поля
    for i, field in ipairs(fields) do
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, x + 2, y + 2 + i, field.label)

        -- Поле вводу
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, x + 14, y + 2 + i, w - 17, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)

        local display = field.value
        if i == activeField then display = display .. "_" end
        gdi32.TextOut(hdc, x + 15, y + 2 + i, display:sub(1, w - 19))
    end

    -- Кнопки
    local btnY = y + h - 2
    for _, btn in ipairs(buttons) do
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
        gdi32.PatBlt(hdc, btn.x, btnY, btn.w, 2, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xE0E0E0)
        gdi32.TextOut(hdc, btn.x + 1, btnY, btn.label)
    end
end

-- ===== ДІАЛОГ CREATE SCOPE =====
local function DialogCreateScope()
    local w, h = 50, 10
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    local fields = {
        { label = "Name:",        value = "New Scope",     max = 20 },
        { label = "Start IP:",    value = "192.168.1.20",  max = 15 },
        { label = "End IP:",      value = "192.168.1.50",  max = 15 },
        { label = "Subnet Mask:", value = "255.255.255.0", max = 15 },
    }
    local activeField = 1

    local buttons = {
        { x = x + w - 18, w = 7,  label = "[ OK ]" },
        { x = x + w - 9,  w = 8,  label = "[Cancel]" }
    }

    local function draw()
        DrawDialog(x, y, w, h, "Create Scope", fields, activeField, buttons)
    end

    draw()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then -- ENTER
                return {
                    name        = fields[1].value,
                    start_ip    = fields[2].value,
                    end_ip      = fields[3].value,
                    subnet_mask = fields[4].value
                }

            elseif code == 1 then -- ESC
                return nil

            elseif code == 15 then -- TAB
                activeField = activeField + 1
                if activeField > #fields then activeField = 1 end

            elseif code == 14 then -- BACKSPACE
                if #fields[activeField].value > 0 then
                    fields[activeField].value = fields[activeField].value:sub(1, -2)
                end

            elseif char >= 32 and char <= 126 then
                if #fields[activeField].value < fields[activeField].max then
                    fields[activeField].value = fields[activeField].value .. string.char(char)
                end
            end

            draw()
            coroutine.yield()

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = y + h - 2

            if ty == btnY and tx >= x + w - 18 and tx < x + w - 11 then
                return {
                    name        = fields[1].value,
                    start_ip    = fields[2].value,
                    end_ip      = fields[3].value,
                    subnet_mask = fields[4].value
                }
            elseif ty == btnY and tx >= x + w - 9 and tx < x + w - 1 then
                return nil
            end
        end

        coroutine.yield()
    end
end

-- ===== ДІАЛОГ ADD EXCLUSION =====
local function DialogAddExclusion()
    local w, h = 50, 8
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    local fields = {
        { label = "Start IP:", value = "192.168.1.1", max = 15 },
        { label = "End IP:",   value = "192.168.1.1", max = 15 },
        { label = "Reason:",   value = "Reserved",    max = 25 },
    }
    local activeField = 1

    local buttons = {
        { x = x + w - 18, w = 7,  label = "[ OK ]" },
        { x = x + w - 9,  w = 8,  label = "[Cancel]" }
    }

    local function draw()
        DrawDialog(x, y, w, h, "Add Exclusion", fields, activeField, buttons)
    end

    draw()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then
                return {
                    start_ip = fields[1].value,
                    end_ip   = fields[2].value,
                    reason   = fields[3].value
                }
            elseif code == 1 then
                return nil
            elseif code == 15 then
                activeField = activeField + 1
                if activeField > #fields then activeField = 1 end
            elseif code == 14 then
                if #fields[activeField].value > 0 then
                    fields[activeField].value = fields[activeField].value:sub(1, -2)
                end
            elseif char >= 32 and char <= 126 then
                if #fields[activeField].value < fields[activeField].max then
                    fields[activeField].value = fields[activeField].value .. string.char(char)
                end
            end

            draw()
            coroutine.yield()

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = y + h - 2

            if ty == btnY and tx >= x + w - 18 and tx < x + w - 11 then
                return {
                    start_ip = fields[1].value,
                    end_ip   = fields[2].value,
                    reason   = fields[3].value
                }
            elseif ty == btnY and tx >= x + w - 9 and tx < x + w - 1 then
                return nil
            end
        end

        coroutine.yield()
    end
end

-- ===== ДІАЛОГ PROPERTIES =====
local function DialogProperties(cfg)
    local w, h = 50, 10
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    local fields = {
        { label = "Pool Start:", value = tostring(cfg.pool_start or 15),  max = 3 },
        { label = "Pool End:",   value = tostring(cfg.pool_end or 100),   max = 3 },
        { label = "Lease Time:", value = tostring(cfg.lease_time or 3600), max = 6 },
        { label = "Gateway:",    value = cfg.gateway or "192.168.1.1",    max = 15 },
        { label = "DNS:",        value = cfg.dns or "192.168.1.1",        max = 15 },
    }
    local activeField = 1

    local buttons = {
        { x = x + w - 18, w = 7,  label = "[ OK ]" },
        { x = x + w - 9,  w = 8,  label = "[Cancel]" }
    }

    local function draw()
        DrawDialog(x, y, w, h, "Scope Properties", fields, activeField, buttons)
    end

    draw()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then
                return {
                    pool_start = tonumber(fields[1].value),
                    pool_end   = tonumber(fields[2].value),
                    lease_time = tonumber(fields[3].value),
                    gateway    = fields[4].value,
                    dns        = fields[5].value
                }
            elseif code == 1 then
                return nil
            elseif code == 15 then
                activeField = activeField + 1
                if activeField > #fields then activeField = 1 end
            elseif code == 14 then
                if #fields[activeField].value > 0 then
                    fields[activeField].value = fields[activeField].value:sub(1, -2)
                end
            elseif char >= 32 and char <= 126 then
                if #fields[activeField].value < fields[activeField].max then
                    fields[activeField].value = fields[activeField].value .. string.char(char)
                end
            end

            draw()
            coroutine.yield()

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = y + h - 2

            if ty == btnY and tx >= x + w - 18 and tx < x + w - 11 then
                return {
                    pool_start = tonumber(fields[1].value),
                    pool_end   = tonumber(fields[2].value),
                    lease_time = tonumber(fields[3].value),
                    gateway    = fields[4].value,
                    dns        = fields[5].value
                }
            elseif ty == btnY and tx >= x + w - 9 and tx < x + w - 1 then
                return nil
            end
        end

        coroutine.yield()
    end
end

-- ===== ДІАЛОГ ПІДТВЕРДЖЕННЯ =====
local function DialogConfirm(title, message)
    local w, h = 40, 7
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    local buttons = {
        { x = x + w - 20, w = 8, label = "[ Yes ]" },
        { x = x + w - 10, w = 9, label = "[ No  ]" }
    }

    local function draw()
        -- Фон
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, x, y, w, h, gdi32.PATCOPY)

        -- 3D-рамка
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, x, y, w, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, x, y, 1, h, gdi32.PATCOPY)
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
        gdi32.PatBlt(hdc, x, y + h - 1, w, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, x + w - 1, y, 1, h, gdi32.PATCOPY)

        -- Заголовок
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, x + 1, y + 1, w - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)
        gdi32.TextOut(hdc, x + 2, y + 1, " " .. title)

        -- Текст
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, x + 2, y + 3, message)

        -- Кнопки
        local btnY = y + h - 2
        for _, btn in ipairs(buttons) do
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
            gdi32.PatBlt(hdc, btn.x, btnY, btn.w, 2, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, 0x000000)
            gdi32.SetBkColor(hdc, 0xE0E0E0)
            gdi32.TextOut(hdc, btn.x + 1, btnY, btn.label)
        end
    end

    draw()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local code = signal[4]
            if code == 28 then return true end
            if code == 1 then return false end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = y + h - 2

            if ty == btnY and tx >= x + w - 20 and tx < x + w - 12 then
                return true
            elseif ty == btnY and tx >= x + w - 10 and tx < x + w - 1 then
                return false
            end
        end

        coroutine.yield()
    end
end

local function HandleClick(x, y)
    if y == winY + 1 and x >= winX + winW - 5 and x <= winX + winW - 2 then
        _G.DHCP_End=true
        return "close"
    end

    local tabX = contentX
    if y == clientY + 2 then
        if x >= tabX and x < tabX + 10 then activeTab = 1 selectedItem = 1
        elseif x >= tabX + 10 and x < tabX + 20 then activeTab = 2 selectedItem = 1
        elseif x >= tabX + 20 and x < tabX + 33 then activeTab = 3 selectedItem = 1 end
    end

    if x >= clientX + 1 and x <= clientX + treeW then
        if y == clientY + 5 then activeTab = 1 selectedItem = 1 end
        if y == clientY + 6 then activeTab = 2 selectedItem = 1 end
        if y == clientY + 7 then activeTab = 3 selectedItem = 1 end
    end

    local btnY = clientY + 5 + (clientH - 8) - 1

    -- ===== SCOPES =====
    if activeTab == 1 and y == btnY then
        -- [ Create Scope ]
        if x >= contentX + 1 and x < contentX + 18 then
            local result = DialogCreateScope()
            if result then
                local ok, err = RpcCall("CreateScope",
                    result.name, result.start_ip, result.end_ip, result.subnet_mask)
                if ok then
                    RefreshData()
                    statusText = "Created scope: " .. result.name
                else
                    statusText = "Failed: " .. tostring(err)
                end
            else
                statusText = "Create Scope cancelled"
            end
            DrawWindow()

        -- [ Delete Scope ]
        elseif x >= contentX + 19 and x < contentX + 36 then
            if DialogConfirm("Delete Scope", "Delete 'Default Scope'?") then
                local ok = RpcCall("DeleteScope", "Default Scope")
                if ok then
                    RefreshData()
                    statusText = "Scope deleted"
                end
            else
                statusText = "Delete cancelled"
            end
            DrawWindow()

        -- [ Properties ]
        elseif x >= contentX + 37 and x < contentX + 52 then
            local result = DialogProperties(config)
            if result then
                local ok = RpcCall("SetConfig", result)
                if ok then
                    RefreshData()
                    statusText = "Properties updated"
                end
            else
                statusText = "Properties cancelled"
            end
            DrawWindow()
        end
    end

    -- ===== LEASES =====
    if activeTab == 2 and y == btnY then
        -- [ Refresh ]
        if x >= contentX + 1 and x < contentX + 13 then
            RefreshData()
            statusText = "Refreshed: " .. tostring(#leases) .. " leases"
            DrawWindow()

        -- [ Release ]
        elseif x >= contentX + 14 and x < contentX + 26 then
            local uuidToRelease = nil
            local i = 0
            for uuid, _ in pairs(leases) do
                i = i + 1
                if i == selectedItem then uuidToRelease = uuid break end
            end
            if uuidToRelease then
                if DialogConfirm("Release Lease", "Release lease #" .. selectedItem .. "?") then
                    RpcCall("ReleaseLease", uuidToRelease)
                    RefreshData()
                    statusText = "Released lease"
                else
                    statusText = "Release cancelled"
                end
            else
                statusText = "No lease selected"
            end
            DrawWindow()

        -- [ Delete ]
        elseif x >= contentX + 27 and x < contentX + 39 then
            statusText = "Use Release instead"
            DrawWindow()
        end
    end

    -- ===== EXCLUSIONS =====
    if activeTab == 3 and y == btnY then
        -- [ Add Exclusion ]
        if x >= contentX + 1 and x < contentX + 20 then
            local result = DialogAddExclusion()
            if result then
                local ok = RpcCall("AddExclusion",
                    result.start_ip, result.end_ip, result.reason)
                if ok then
                    RefreshData()
                    statusText = "Added exclusion: " .. result.start_ip
                else
                    statusText = "Failed to add exclusion"
                end
            else
                statusText = "Add Exclusion cancelled"
            end
            DrawWindow()

        -- [ Delete Exclusion ]
        elseif x >= contentX + 21 and x < contentX + 42 then
            if #exclusions > 0 and selectedItem <= #exclusions then
                if DialogConfirm("Delete Exclusion",
                    "Delete exclusion #" .. selectedItem .. "?") then
                    RpcCall("RemoveExclusion", selectedItem)
                    RefreshData()
                    statusText = "Exclusion removed"
                else
                    statusText = "Delete cancelled"
                end
            else
                statusText = "No exclusion selected"
            end
            DrawWindow()
        end
    end

    -- Вибір рядка
    local contentY = clientY + 5
    if y > contentY + 1 and y < btnY then
        selectedItem = y - contentY - 1
        statusText = "Selected item #" .. tostring(selectedItem)
    end

    coroutine.yield()
    return nil
end

-- ===== Головний цикл =====
RefreshData()
DrawWindow()

while true do
    local signal = { computer.pullSignal(0.5) }
    local event = signal[1]

    if event == "touch" then
        local result = HandleClick(signal[3], signal[4])
        if result == "close" then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
            gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
            break
        end
        DrawWindow()
        coroutine.yield()

    elseif event == "key_down" then
        local code = signal[4]
        if code == 1 then
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
            gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
            break
        elseif code == 15 then
            activeTab = activeTab + 1
            if activeTab > 3 then activeTab = 1 end
            DrawWindow()
            coroutine.yield()
        elseif code == 116 then -- F5
            RefreshData()
            DrawWindow()
            coroutine.yield()
        end

    elseif event == "modem_message" then
        RefreshData()
        DrawWindow()
        coroutine.yield()
    end

    coroutine.yield()
end

return true