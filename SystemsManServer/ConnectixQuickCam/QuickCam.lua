local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local fs_proxy = component.proxy(computer.getBootAddress())

local function DbgPrint(...)
    if _G.DbgPrint then _G.DbgPrint(...) end
end

if not _G.Mm then _G.Mm = { NonPagedPool = {} } end
if not _G.Mm.NonPagedPool then _G.Mm.NonPagedPool = {} end

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h
local LDM = _G.Tier2CM == true

local C_BG = 0xC0C0C0
local C_BTN = 0xE0E0E0
local C_WHITE = 0xFFFFFF
local C_BLACK = 0x000000
local C_TITLE = 0x000080
local C_DARK = 0x808080
local C_GRAY = 0x808080

local CONFIG_FILE = "QUICKCAM.INI"

local config = {
    resolution = 160,
    brightness = 50,
    saturation = 50,
    contrast = 50,
    whiteBalance = 50,
    fov = 60
}

local camera = nil
local isLive = false
local needsRedraw = true
local currentSlider = nil
local statusText = "Ready"

local asciiMap = " .:-=+*#%@"

-- Змінні для анти-миготіння
local lastFrame = {}        -- Кеш попереднього кадру
local lastFov = nil
local lastBrightness = nil
local lastContrast = nil
local forceRedraw = true

local function Log(msg)
    DbgPrint("QuickCam: " .. tostring(msg))
end

local function LoadConfig()
    local ok, file = pcall(fs_proxy.open, CONFIG_FILE, "r")
    if ok and file then
        local data = ""
        while true do
            local chunk = fs_proxy.read(file, 1024)
            if not chunk or #chunk == 0 then break end
            data = data .. chunk
        end
        fs_proxy.close(file)
        
        for key, value in data:gmatch("([^=]+)=([^\n]+)") do
            if config[key] ~= nil then
                local num = tonumber(value)
                if num then config[key] = num end
            end
        end
        Log("Config loaded")
    end
end

local function SaveConfig()
    local ok, file = pcall(fs_proxy.open, CONFIG_FILE, "w")
    if ok and file then
        local data = ""
        for k, v in pairs(config) do
            data = data .. k .. "=" .. tostring(v) .. "\n"
        end
        fs_proxy.write(file, data)
        fs_proxy.close(file)
        Log("Config saved")
    end
end

local function GetCamera()
    local drv = _G.Mm.NonPagedPool["\\Driver\\vc415"]
    if drv and drv.GetCameraCount() > 0 then
        return drv.GetCameraInfo(1).device
    end
    return nil
end

local function FillRect(x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(color))
    gdi32.PatBlt(hdc, x, y, w, h, gdi32.PATCOPY)
end

local function DrawTextF(x, y, w, text, fg, bg)
    if w <= 0 then return end
    text = tostring(text or "")
    if unicode and unicode.len then
        if unicode.len(text) > w then text = unicode.sub(text, 1, w) end
    else
        if #text > w then text = text:sub(1, w) end
    end
    
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
    winW, winH = 56, 18
else
    winW, winH = 64, 20
end
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local layout = {}
layout.videoX = winX + 2
layout.videoY = winY + 3
layout.videoW = 40
layout.videoH = 12
layout.sliderX = layout.videoX + layout.videoW + 2
layout.sliderW = winW - layout.videoW - 6
layout.sliderY = layout.videoY
layout.statusY = winY + winH - 3
layout.sepY = layout.statusY - 1

local function DrawSlider(x, y, w, value, label)
    DrawTextF(x, y, w, label .. ":", C_BLACK, C_BG)
    local barX = x
    local barY = y + 1
    local barW = w - 2
    FillRect(barX, barY, barW, 1, C_DARK)
    local thumbPos = barX + math.floor((value / 100) * (barW - 1))
    FillRect(thumbPos, barY - 1, 1, 3, C_TITLE)
    DrawTextF(x, y + 2, w, tostring(value) .. "%", C_GRAY, C_BG)
end

-- Малює лише ті пікселі відео, які змінилися
local function DrawVideoFrame()
    local vx, vy, vw, vh = layout.videoX, layout.videoY, layout.videoW, layout.videoH
    local cam = GetCamera()
    
    if not (cam and isLive) then
        local msg = cam and "STANDBY" or "NO CAMERA"
        FillRect(vx, vy, vw, vh, C_BLACK)
        DrawTextF(vx + math.floor(vw / 2) - math.floor(#msg / 2), vy + math.floor(vh / 2), vw, msg, C_GRAY, C_BLACK)
        lastFrame = {}
        return
    end

    -- Перевіряємо, чи змінилися налаштування, що впливають на картинку
    if forceRedraw or lastFov ~= config.fov or lastBrightness ~= config.brightness or lastContrast ~= config.contrast then
        FillRect(vx, vy, vw, vh, C_BLACK)
        lastFrame = {}
        lastFov = config.fov
        lastBrightness = config.brightness
        lastContrast = config.contrast
        forceRedraw = false
    end

    local frame = cam.renderFrame(vw, vh, config.fov)
    if not frame then return end

    for py = 1, vh do
        for px = 1, vw do
            local val = frame[py][px]
            
            -- Перевіряємо, чи цей піксель змінився
            local oldVal = lastFrame[py] and lastFrame[py][px]
            if oldVal == val then
                -- Піксель не змінився, пропускаємо малювання (економія ресурсів)
            else
                local charIdx = math.floor(val * (#asciiMap - 1)) + 1
                local char = asciiMap:sub(charIdx, charIdx)
                
                local fg = C_BLACK
                if val > 0.8 then fg = C_WHITE
                elseif val > 0.6 then fg = 0xCCCCCC
                elseif val > 0.4 then fg = 0x999999
                elseif val > 0.2 then fg = 0x666666
                else fg = 0x333333 end
                
                DrawTextF(vx + px - 1, vy + py - 1, 1, char, fg, C_BLACK)
                
                if not lastFrame[py] then lastFrame[py] = {} end
                lastFrame[py][px] = val
            end
        end
    end
end

local function DrawMainWindow()
    DrawFrame(winX, winY, winW, winH, " QuickCam - B&W Camera", true)

    local sx = layout.sliderX
    local sy = layout.sliderY
    local sw = layout.sliderW
    
    DrawTextF(sx, sy, sw, "Resolution:", C_BLACK, C_BG)
    local resY = sy + 1
    DrawButton(sx, resY, 6, "160p", config.resolution == 160)
    DrawButton(sx + 7, resY, 6, "240p", config.resolution == 240)
    DrawButton(sx + 14, resY, 6, "320p", config.resolution == 320)

    DrawSlider(sx, resY + 2, sw, config.brightness, "Brightness")
    DrawSlider(sx, resY + 6, sw, config.contrast, "Contrast")
    DrawSlider(sx, resY + 10, sw, config.fov, "FOV")

    local toggleY = layout.sepY - 1
    DrawButton(winX + 2, toggleY, 12, isLive and "[Stop]" or "[Start Live]", false)

    FillRect(winX + 1, layout.sepY, winW - 2, 1, C_DARK)

    local exitBtnW = 8
    local saveBtnW = 10
    local exitX = winX + winW - exitBtnW - 2
    local saveX = exitX - saveBtnW - 2

    DrawTextF(winX + 2, layout.statusY, saveX - winX - 3, statusText, C_BLACK, C_BG)
    DrawButton(saveX, layout.statusY, saveBtnW, "[Save]")
    DrawButton(exitX, layout.statusY, exitBtnW, "[Exit]")
end

local function HandleMainInput(signal)
    local eventType = signal[1]

    if eventType == "key_down" then
        local code = signal[4]
        if code == 1 then return false end
        
        if currentSlider then
            if code == 200 then
                config[currentSlider] = math.min(100, config[currentSlider] + 5)
                statusText = "Adjusted " .. currentSlider
                forceRedraw = true
            elseif code == 208 then
                config[currentSlider] = math.max(0, config[currentSlider] - 5)
                statusText = "Adjusted " .. currentSlider
                forceRedraw = true
            elseif code == 28 then
                currentSlider = nil
                statusText = "Ready"
            end
            needsRedraw = true
            return true
        end

    elseif eventType == "touch" then
        local tx, ty = signal[3], signal[4]

        if ty == winY + 1 and tx >= winX + winW - 4 then return false end

        local toggleY = layout.sepY - 1
        if ty == toggleY and tx >= winX + 2 and tx < winX + 14 then
            if GetCamera() then
                isLive = not isLive
                statusText = isLive and "Live feed started" or "Live feed stopped"
                forceRedraw = true
            else
                statusText = "Camera not found!"
            end
            needsRedraw = true
            return true
        end

        local sx = layout.sliderX
        local sy = layout.sliderY
        local sw = layout.sliderW
        local resY = sy + 1
        
        if ty == resY then
            if tx >= sx and tx < sx + 6 then config.resolution = 160
            elseif tx >= sx + 7 and tx < sx + 13 then config.resolution = 240
            elseif tx >= sx + 14 and tx < sx + 20 then config.resolution = 320
            end
            needsRedraw = true
            forceRedraw = true
            return true
        end

        local sliders = {
            { name = "brightness", y = resY + 2 },
            { name = "contrast", y = resY + 6 },
            { name = "fov", y = resY + 10 }
        }
        for _, sl in ipairs(sliders) do
            if ty == sl.y + 1 then
                if tx >= sx and tx <= sx + sw - 2 then
                    local ratio = (tx - sx) / (sw - 2)
                    config[sl.name] = math.floor(ratio * 100)
                    statusText = "Set " .. sl.name
                    forceRedraw = true
                end
                currentSlider = sl.name
                needsRedraw = true
                return true
            end
        end

        if ty == layout.statusY then
            local exitBtnW = 8
            local saveBtnW = 10
            local exitX = winX + winW - exitBtnW - 2
            local saveX = exitX - saveBtnW - 2
            if tx >= exitX and tx < exitX + exitBtnW then
                return false
            elseif tx >= saveX and tx < saveX + saveBtnW then
                SaveConfig()
                statusText = "Config saved to " .. CONFIG_FILE
                needsRedraw = true
            end
        end
    end
    return true
end

Log("Starting QuickCam")
LoadConfig()
local cam = GetCamera()
if cam then
    statusText = "Camera found, ready"
else
    statusText = "No camera detected"
end

local running = true
local lastFrameTime = 0

-- Повне перемальовування вікна лише один раз при старті
DrawMainWindow()
DrawVideoFrame()

while running do
    local now = computer.uptime()
    
    -- Якщо увімкнено Live і минуло достатньо часу, оновлюємо ВІДЕО
    if isLive and (now - lastFrameTime > 0.1) then
        DrawVideoFrame()
        lastFrameTime = now
    end

    -- Повне перемальовування вікна (кнопки, слайдери) лише за потреби
    if needsRedraw then
        DrawMainWindow()
        if isLive then
            DrawVideoFrame()
        end
        needsRedraw = false
    end

    local signal = { computer.pullSignal(isLive and 0.05 or 0.2) }
    
    if #signal > 0 then
        needsRedraw = true
        if not HandleMainInput(signal) then
            running = false
        end
    end
end

SaveConfig()
Log("QuickCam closed")
return true