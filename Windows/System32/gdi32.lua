-- gdi32.lua - GDI32 для LuaNT
-- (C) RedstoneShell 2026
-- Підтримує screen.ini: 0=Monochrome, 1=16 colors, 2=256 colors

local GDI = {
    COLOR_BLUE      = 0x0000AA,
    COLOR_GRAY      = 0xAAAAAA,
    COLOR_WHITE     = 0xFFFFFF,
    COLOR_DARK_GRAY = 0x555555,
    COLOR_BLACK     = 0x000000
}

GDI.TRANSPARENT = 1
GDI.OPAQUE      = 2
GDI.PATCOPY     = 3160021
GDI.PATINVERT   = 3600049
GDI.DSTINVERT   = 3550009
GDI.BLACKNESS   = 3000042
GDI.WHITENESS   = 3176062

-- ===== Кольоровий режим =====
-- 0 = Monochrome (1-bit)
-- 1 = 16 colors (4-bit)
-- 2 = 256 colors (8-bit)
GDI.ColorMode = 2

-- ===== CGA 16-колірна палітра =====
local CGA_PALETTE = {
    0x000000, 0x0000AA, 0x00AA00, 0x00AAAA,
    0xAA0000, 0xAA00AA, 0xAA5500, 0xAAAAAA,
    0x555555, 0x5555FF, 0x55FF55, 0x55FFFF,
    0xFF5555, 0xFF55FF, 0xFFFF55, 0xFFFFFF
}

-- ===== Завантажити screen.ini =====
local function LoadScreenIni()
    local fs = component.proxy(computer.getBootAddress())
    local path = "Windows/System32/screen.ini"

    if not fs.exists(path) then
        GDI.ColorMode = 2  -- за замовчуванням 256 colors
        DbgPrint("GDI32: screen.ini not found, using default 256-color mode")
        return 2
    end

    local file = fs.open(path, "r")
    if not file then
        GDI.ColorMode = 2
        DbgPrint("GDI32: Could not open screen.ini, using default")
        return 2
    end

    local content = ""
    while true do
        local chunk = fs.read(file, 1024)
        if not chunk or #chunk == 0 then break end
        content = content .. chunk
    end
    fs.close(file)

    -- Парсимо screen=N
    local mode = content:match("screen=(%d+)")
    if mode then
        mode = tonumber(mode)
        if mode >= 0 and mode <= 2 then
            GDI.ColorMode = mode
            DbgPrint("GDI32: Loaded screen.ini - ColorMode = " .. mode)
            return mode
        end
    end

    GDI.ColorMode = 2
    DbgPrint("GDI32: Invalid screen.ini, using default 256-color mode")
    return 2
end

-- ===== Застосувати кольоровий режим (з захистом від nil) =====
local function ApplyColorMode(color)
    -- Захист від nil
    if color == nil then
        color = 0x000000
    end

    -- Захист від не-числа
    if type(color) ~= "number" then
        color = tonumber(color) or 0x000000
    end

    -- Обмежуємо діапазон 0x000000 - 0xFFFFFF
    color = math.floor(color) % 0x1000000
    if color < 0 then
        color = color + 0x1000000
    end

    if GDI.ColorMode == 0 then
        -- Monochrome: ч/б
        local r = math.floor(color / 65536) % 256
        local g = math.floor(color / 256) % 256
        local b = color % 256
        local gray = math.floor((r * 299 + g * 587 + b * 114) / 1000)
        if gray > 127 then
            return 0xFFFFFF
        else
            return 0x000000
        end

    elseif GDI.ColorMode == 1 then
        -- 16 colors: квантизація до CGA
        local best = CGA_PALETTE[1]
        local bestDist = math.huge
        local r1 = math.floor(color / 65536) % 256
        local g1 = math.floor(color / 256) % 256
        local b1 = color % 256

        for _, c in ipairs(CGA_PALETTE) do
            local r2 = math.floor(c / 65536) % 256
            local g2 = math.floor(c / 256) % 256
            local b2 = c % 256
            local dist = (r1 - r2)^2 + (g1 - g2)^2 + (b1 - b2)^2
            if dist < bestDist then
                bestDist = dist
                best = c
            end
        end
        return best
    end

    return color  -- 256 colors: без змін
end

-- ===== Експорт для інших модулів =====
GDI.ApplyColorMode = ApplyColorMode

-- ===== Object Table =====
local GDI_ObjectTable, last_handle = {}, 0

-- ===== Ініціалізація =====
function GDI.GdiDllInitialize(gpu_proxy)
    -- Читаємо screen.ini при старті
    LoadScreenIni()

    local wi, he = gpu_proxy.getResolution()
    GDI_ObjectTable[0] = {
        type       = "OBJ_DC",
        gpu        = gpu_proxy,
        brushColor = ApplyColorMode(0x000000),
        penColor   = ApplyColorMode(0xFFFFFF),
        textColor  = ApplyColorMode(0xFFFFFF),
        bkColor    = ApplyColorMode(0x000000),
        bkMode     = 2,
        isSystem   = true,
        bounds     = {w=wi, h=he}
    }

    last_handle = 0

    DbgPrint("GDI32: Initialized in mode " .. GDI.ColorMode ..
        " (" .. (GDI.ColorMode == 0 and "Monochrome" or
                 GDI.ColorMode == 1 and "16 colors" or "256 colors") .. ")")

    return true
end

-- ===== Створення DC =====
function GDI.CreateDC(gpu_proxy)
    last_handle = last_handle + 1
    local hdc_id = last_handle
    GDI_ObjectTable[hdc_id] = {
        type       = "HDC",
        gpu        = gpu_proxy,
        brushColor = ApplyColorMode(0xAAAAAA),
        penColor   = ApplyColorMode(0xFFFFFF),
        textColor  = ApplyColorMode(0xFFFFFF),
        bkColor    = ApplyColorMode(0x000000),
        bkMode     = 2,
        bounds     = {x1=1, y1=1, z2=80, y2=25}
    }
    return hdc_id
end

function GDI.GetDC(hwnd)
    if hwnd == nil or hwnd == 0 then return 0 end
    return GDI_ObjectTable[hwnd]
end

local function ValidateHDC(hdc_handle)
    local hdc = GDI_ObjectTable[hdc_handle or 0]
    if not hdc then return GDI_ObjectTable[0] end
    return hdc
end

local function InvCrl(clr)
    return 0xFFFFFF - (clr or 0)
end

-- ===== PatBlt =====
function GDI.PatBlt(hdc, x, y, w, h, dwRop)
    local hdc_h = ValidateHDC(hdc)
    local gpu   = hdc_h.gpu

    if dwRop == GDI.PATCOPY then
        gpu.setBackground(ApplyColorMode(hdc_h.brushColor or 0xAAAAAA))
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == GDI.BLACKNESS then
        gpu.setBackground(ApplyColorMode(0x000000))
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == GDI.WHITENESS then
        gpu.setBackground(ApplyColorMode(0xFFFFFF))
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == GDI.DSTINVERT then
        gpu.setBackground(ApplyColorMode(InvCrl(hdc_h.bkColor)))
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == GDI.PATINVERT then
        gpu.setBackground(ApplyColorMode(InvCrl(hdc_h.brushColor)))
        gpu.fill(x, y, w, h, " ")
    end

    return true
end

-- ===== SetTextColor =====
function GDI.SetTextColor(hdc, color)
    local hdc_h = ValidateHDC(hdc)
    local oldClr = hdc_h.textColor
    hdc_h.textColor = ApplyColorMode(color)
    return oldClr
end

-- ===== CreateSolidBrush =====
function GDI.CreateSolidBrush(clr)
    return {
        type = "BRUSH",
        color = ApplyColorMode(clr)
    }
end

-- ===== SelectObject =====
function GDI.SelectObject(hdc_, hObj)
    if not hObj then return nil end
    local oldB, hdc = 0, ValidateHDC(hdc_)
    if hObj.type == "BRUSH" then
        oldB = { type = "BRUSH", color = hdc.brushColor }
        hdc.brushColor = hObj.color
    end
    return oldB
end

-- ===== SetBkMode =====
function GDI.SetBkMode(hdc, mode)
    local hdc_h = ValidateHDC(hdc)
    local oldM = hdc_h.bkMode or 2
    if mode == 1 or mode == 2 then
        hdc_h.bkMode = mode
    end
    return oldM
end

-- ===== SetBkColor =====
function GDI.SetBkColor(hdc_, clr)
    local hdc = ValidateHDC(hdc_)
    if not hdc then return end
    local oldClr = hdc.bkColor
    hdc.bkColor = ApplyColorMode(clr)
    return oldClr
end

-- ===== TextOut =====
function GDI.TextOut(hdc, x, y, text)
    if not text then return false end
    local hdc_h = ValidateHDC(hdc)
    local gpu = hdc_h.gpu
    gpu.setForeground(ApplyColorMode(hdc_h.textColor or 0xFFFFFF))
    if hdc_h.bkMode == 2 then
        gpu.setBackground(ApplyColorMode(hdc_h.bkColor))
    end
    gpu.set(x, y, text)
    return true
end

return GDI