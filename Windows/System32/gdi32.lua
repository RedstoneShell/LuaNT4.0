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

local GDI_ObjectTable, last_handle = {}, 0

function GDI.GdiDllInitialize(gpu_proxy)
    local wi, he = gpu_proxy.getResolution()
    GDI_ObjectTable[0] = {
        type       = "OBJ_DC",
        gpu        = gpu_proxy,
        brushColor = 0x000000,
        penColor   = 0xFFFFFF,
        textColor  = 0xFFFFFF,
        bkColor    = 0x000000,
        bkMode     = 2,
        isSystem   = true,
        bounds     = {w=wi, h=he}
    }

    last_handle=0
    return true
end

function GDI.CreateDC(gpu_proxy)
    last_handle = last_handle+1
    local hdc_id = last_handle
    local hdc_str = {
        type       = "HDC",
        gpu        = gpu_proxy,
        brushColor = 0xAAAAAA,
        penColor   = 0xFFFFFF,
        textColor  = 0xFFFFFF,
        bkColor    = 0x000000,
        bkMode     = 2,
        bounds     = {x1=1,y1=1,z2=80,y2=25}
    }
    GDI_ObjectTable[hdc_id]=hdc_str
    return hdc_id
end

function GDI.GetDC(hwnd)
    if hwnd == nil or hwnd == 0 then
        return 0
    end

    return GDI_ObjectTable[hwnd]
end

local function ValidateHDC(hdc_handle)
    local hdc = GDI_ObjectTable[hdc_handle or 0]
    if not hdc then
        return GDI_ObjectTable[0]
    end
    return hdc
end

local function InvCrl(clr)
    return 0xFFFFFF - (clr or 0)
end

function GDI.PatBlt(hdc, x, y, w, h, dwRop)
    local hdc_h = ValidateHDC(hdc)
    local gpu   = hdc_h.gpu
    if dwRop == 3160021 then
        gpu.setBackground(hdc_h.brushColor or 0xAAAAAA)
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == 3000042 then
        gpu.setBackground(0x000000)
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == 3176062 then
        gpu.setBackground(0xFFFFFF)
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == 3550009 then
        gpu.setBackground(InvCrl(hdc_h.bkColor))
        gpu.fill(x, y, w, h, " ")
    elseif dwRop == 3600049 then
        gpu.setBackground(InvCrl(hdc_h.brushColor))
        gpu.fill(x, y, w, h, " ")
    end

    return true
end

function GDI.SetTextColor(hdc, color)
    local hdc_h = ValidateHDC(hdc)
    local oldClr = hdc_h.textColor
    hdc_h.textColor = color
    GDI_ObjectTable[hdc_h] = {
        type       = hdc_h.type,
        gpu        = hdc_h.gpu,
        brushColor = hdc_h.brushColor,
        penColor   = hdc_h.penColor,
        textColor  = hdc_h.textColor,
        bkColor    = hdc_h.bkColor,
        bkMode     = hdc_h.bkMode,
        bounds     = hdc_h.bounds
    }
    return oldClr
end

function GDI.CreateSolidBrush(clr)
    local hb = {
        type="BRUSH",
        color=clr
    }
    return hb
end

function GDI.SelectObject(hdc_, hObj)
    if not hObj then return nil end
    local oldB, hdc = 0, ValidateHDC(hdc_)
    if hObj.type == "BRUSH" then
        oldB = { type="BRUSH", color = hdc.brushColor }
        hdc.brushColor = hObj.color
        GDI_ObjectTable[hdc] = {
            type       = hdc.type,
            gpu        = hdc.gpu,
            brushColor = hdc.brushColor,
            penColor   = hdc.penColor,
            textColor  = hdc.textColor,
            bkColor    = hdc.bkColor,
            bkMode     = hdc.bkMode,
            bounds     = hdc.bounds
        }
    end
    return oldB
end

function GDI.SetBkMode(hdc, mode)
    local hdc_h = ValidateHDC(hdc)
    local oldM  = hdc_h.bkMode or 2
    if mode == 1 or mode == 2 then
        hdc_h.bkMode = mode
    end
    return oldM
end

function GDI.SetBkColor(hdc_, clr)
    local hdc = ValidateHDC(hdc_)
    if not hdc then return end
    local oldClr = hdc.bkColor
    GDI_ObjectTable[hdc] = {
        type       = hdc.type,
        gpu        = hdc.gpu,
        brushColor = hdc.brushColor,
        penColor   = hdc.penColor,
        textColor  = hdc.textColor,
        bkColor    = hdc.bkColor,
        bkMode     = hdc.bkMode,
        bounds     = hdc.bounds
    }
    return oldClr
end

function GDI.TextOut(hdc, x, y, text)
    if not text then return false end
    local hdc_h = ValidateHDC(hdc)
    local gpu   = hdc_h.gpu
    gpu.setForeground(hdc_h.textColor or 0xFFFFFF)
    if hdc_h.bkMode == 2 then gpu.setBackground(hdc_h.bkColor) end
    gpu.set(x, y, text)
    return true
end

return GDI