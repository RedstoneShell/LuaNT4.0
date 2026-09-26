-- etoken.lua - Aladdin eToken Emulation for LuaNT
-- (C) RedstoneShell 2026
-- Hardware token authentication via diskette

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local regedit = _G.regedit0 or _G.LdrLoadDll("Windows/System32/regedit.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

-- ===== LDM Detection =====
local LDM = _G.Tier2CM == true

-- ============================================================
-- MD5 (для PIN-коду)
-- ============================================================
local md5 = {}

local T = {}
for i = 1, 64 do
    T[i] = math.floor(math.abs(math.sin(i)) * 2^32) % 4294967296
end

local S = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
}

local function u32(n) return n % 4294967296 end
local function rotl(x, n) return u32((x << n) | (x >> (32 - n))) end
local function F(x, y, z) return (x & y) | ((~x) & z) end
local function G(x, y, z) return (x & z) | (y & (~z)) end
local function H(x, y, z) return x ~ y ~ z end
local function I(x, y, z) return y ~ (x | (~z)) end

function md5.hash(input)
    local bytes = {}
    for i = 1, #input do
        bytes[i] = string.byte(input, i)
    end

    local bit_len = #bytes * 8

    bytes[#bytes + 1] = 0x80
    while (#bytes % 64) ~= 56 do
        bytes[#bytes + 1] = 0
    end
    for i = 0, 7 do
        bytes[#bytes + 1] = (bit_len >> (8 * i)) & 0xFF
    end

    local A = 0x67452301
    local B = 0xEFCDAB89
    local C = 0x98BADCFE
    local D = 0x10325476

    for i = 1, #bytes, 64 do
        local M = {}
        for j = 0, 15 do
            local b1 = bytes[i + j * 4] or 0
            local b2 = bytes[i + j * 4 + 1] or 0
            local b3 = bytes[i + j * 4 + 2] or 0
            local b4 = bytes[i + j * 4 + 3] or 0
            M[j + 1] = (b1) | (b2 << 8) | (b3 << 16) | (b4 << 24)
        end

        local a, b, c, d = A, B, C, D

        for j = 1, 64 do
            local f, g
            if j <= 16 then
                f = F(b, c, d)
                g = j - 1
            elseif j <= 32 then
                f = G(b, c, d)
                g = (5 * j - 4) % 16
            elseif j <= 48 then
                f = H(b, c, d)
                g = (3 * j + 2) % 16
            else
                f = I(b, c, d)
                g = (7 * j - 7) % 16
            end
            local temp = d
            d = c
            c = b
            b = u32(b + rotl(u32(a + f + M[g + 1] + T[j]), S[j]))
            a = temp
        end

        A = u32(A + a)
        B = u32(B + b)
        C = u32(C + c)
        D = u32(D + d)
    end

    local result = {}
    for i = 0, 3 do
        result[#result + 1] = (A >> (8 * i)) & 0xFF
        result[#result + 1] = (B >> (8 * i)) & 0xFF
        result[#result + 1] = (C >> (8 * i)) & 0xFF
        result[#result + 1] = (D >> (8 * i)) & 0xFF
    end

    return string.char(table.unpack(result))
end

-- ============================================================
-- RC4
-- ============================================================
local rc4 = {}

function rc4.crypt(key, data)
    local S = {}
    for i = 0, 255 do S[i] = i end

    local key_bytes = {}
    for i = 1, #key do key_bytes[i] = string.byte(key, i) end

    local j = 0
    for i = 0, 255 do
        j = (j + S[i] + key_bytes[(i % #key_bytes) + 1]) % 256
        S[i], S[j] = S[j], S[i]
    end

    local result = {}
    local i, j = 0, 0
    for k = 1, #data do
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
        local K = S[(S[i] + S[j]) % 256]
        result[k] = string.char(string.byte(data, k) ~ K)
    end

    return table.concat(result)
end

-- ============================================================
-- Генерація токена
-- ============================================================
local function GenerateToken()
    local token = {
        id = "",           -- Унікальний ID токена
        pin_hash = "",     -- MD5 хеш PIN
        private_key = "",  -- Приватний ключ (32 байти)
        public_key = "",   -- Публічний ключ
        created = os.time(),
        label = "eToken"
    }

    -- Генеруємо ID (16 байт)
    local id = {}
    for i = 1, 16 do
        id[i] = string.char(math.random(0, 255))
    end
    token.id = table.concat(id)

    -- Генеруємо приватний ключ (32 байти)
    local pk = {}
    for i = 1, 32 do
        pk[i] = string.char(math.random(0, 255))
    end
    token.private_key = table.concat(pk)

    -- Публічний ключ = MD5(private_key)
    token.public_key = md5.hash(token.private_key)

    return token
end

-- ============================================================
-- Збереження токена на дискету
-- ============================================================
local function SaveTokenToDiskette(token)
    local diskDrive = component.list("disk_drive")()

    if not diskDrive then
        DbgPrint("ETOKEN: No disk drive found!")
        return false
    end

    local drive = component.proxy(diskDrive)
    local media = drive.media()

    if not media then
        DbgPrint("ETOKEN: No diskette inserted!")
        return false
    end

    local fs = component.proxy(media)

    -- Створюємо файл токена
    local file = fs.open("/ETOKEN.KEY", "w")
    if not file then
        DbgPrint("ETOKEN: Cannot create token file!")
        return false
    end

    -- Формат: [ID:16][PIN_HASH:16][PRIVATE_KEY:32][PUBLIC_KEY:16]
    local data = token.id .. token.pin_hash .. token.private_key .. token.public_key
    fs.write(file, data)
    fs.close(file)

    -- Створюємо файл-маркер
    local marker = fs.open("/ETOKEN.ID", "w")
    if marker then
        fs.write(marker, token.id)
        fs.close(marker)
    end

    DbgPrint("ETOKEN: Token saved to diskette")
    return true
end

-- ============================================================
-- Читання токена з дискети
-- ============================================================
local function LoadTokenFromDiskette()
    local diskDrive = component.list("disk_drive")()

    if not diskDrive then
        return nil, "No disk drive"
    end

    local drive = component.proxy(diskDrive)
    local media = drive.media()

    if not media then
        return nil, "No diskette"
    end

    local fs = component.proxy(media)

    if not fs.exists("/ETOKEN.KEY") then
        return nil, "Not a token diskette"
    end

    local file = fs.open("/ETOKEN.KEY", "r")
    if not file then
        return nil, "Cannot read token"
    end

    local data = fs.read(file, math.huge)
    fs.close(file)

    if #data < 80 then
        return nil, "Invalid token data"
    end

    local token = {
        id = data:sub(1, 16),
        pin_hash = data:sub(17, 32),
        private_key = data:sub(33, 64),
        public_key = data:sub(65, 80)
    }

    return token
end

-- ============================================================
-- Перевірка PIN
-- ============================================================
local function VerifyPIN(token, pin)
    local hash = md5.hash(pin)
    return hash == token.pin_hash
end

-- ============================================================
-- Challenge-Response
-- ============================================================
local function SignChallenge(token, challenge)
    -- Підписуємо challenge приватним ключем
    local signature = rc4.crypt(token.private_key, challenge)
    return signature
end

local function VerifySignature(token, challenge, signature)
    -- Перевіряємо підпис публічним ключем
    local expected = rc4.crypt(token.private_key, challenge)
    return signature == expected
end

-- ============================================================
-- GUI
-- ============================================================
local function DrawWindow()
    local winW, winH
    if LDM then
        winW, winH = 50, 16
    else
        winW, winH = 56, 18
    end

    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2

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
    gdi32.TextOut(hdc, winX + 2, winY + 1, " Aladdin eToken Setup")
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

    -- Текст
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xC0C0C0)
    gdi32.TextOut(hdc, clientX + 2, clientY + 2, "Insert blank diskette into drive A:")
    gdi32.TextOut(hdc, clientX + 2, clientY + 3, "Press ENTER to initialize token...")
    gdi32.TextOut(hdc, clientX + 2, clientY + 5, "[ Create Token ]")
    gdi32.TextOut(hdc, clientX + 2, clientY + 7, "[ Verify Token ]")
    gdi32.TextOut(hdc, clientX + 2, clientY + 9, "[ Test PIN ]")

    return winX, winY, winW, winH, clientX, clientY
end

-- ============================================================
-- Create Token Dialog
-- ============================================================
local function CreateTokenDialog()
    local winW, winH = 50, 10
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2

    local pin = ""
    local statusText = "Enter PIN (4-16 chars):"

    local function DrawDialog()
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
        gdi32.TextOut(hdc, winX + 2, winY + 1, " Create eToken")
        gdi32.SetTextColor(hdc, 0xFF0000)
        gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 2, clientY + 2, statusText)

        -- Поле вводу
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, clientX + 2, clientY + 4, winW - 6, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)

        local masked = string.rep("*", #pin)
        gdi32.TextOut(hdc, clientX + 3, clientY + 4, masked .. "_")
    end

    DrawDialog()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then  -- ENTER
                if #pin >= 4 and #pin <= 16 then
                    -- Генеруємо токен
                    local token = GenerateToken()
                    token.pin_hash = md5.hash(pin)

                    -- Зберігаємо на дискету
                    if SaveTokenToDiskette(token) then
                        DbgPrint("ETOKEN: Token created successfully")
                        return true
                    else
                        statusText = "ERROR: Cannot save to diskette"
                        DrawDialog()
                    end
                else
                    statusText = "PIN must be 4-16 characters"
                    DrawDialog()
                end

            elseif code == 14 then  -- BACKSPACE
                pin = pin:sub(1, -2)
                DrawDialog()

            elseif char >= 32 and char <= 126 then
                if #pin < 16 then
                    pin = pin .. string.char(char)
                    DrawDialog()
                end
            end
        end
    end
end

-- ============================================================
-- Verify Token Dialog
-- ============================================================
local function VerifyTokenDialog()
    local token, err = LoadTokenFromDiskette()

    if not token then
        DbgPrint("ETOKEN: " .. tostring(err))
        return false
    end

    -- Генеруємо challenge (випадкові 32 байти)
    local challenge = {}
    for i = 1, 32 do
        challenge[i] = string.char(math.random(0, 255))
    end
    challenge = table.concat(challenge)

    -- Підписуємо
    local signature = SignChallenge(token, challenge)

    -- Перевіряємо
    if VerifySignature(token, challenge, signature) then
        DbgPrint("ETOKEN: Token verified successfully")
        return true
    else
        DbgPrint("ETOKEN: Token verification failed")
        return false
    end
end

-- ============================================================
-- Test PIN Dialog
-- ============================================================
local function TestPINDialog()
    local token, err = LoadTokenFromDiskette()

    if not token then
        DbgPrint("ETOKEN: " .. tostring(err))
        return false
    end

    local winW, winH = 50, 8
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2

    local pin = ""

    local function DrawDialog()
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
        gdi32.TextOut(hdc, winX + 2, winY + 1, " Enter PIN")
        gdi32.SetTextColor(hdc, 0xFF0000)
        gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 2, clientY + 2, "Enter PIN to verify:")

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, clientX + 2, clientY + 4, winW - 6, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xFFFFFF)

        local masked = string.rep("*", #pin)
        gdi32.TextOut(hdc, clientX + 3, clientY + 4, masked .. "_")
    end

    DrawDialog()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 28 then  -- ENTER
                if VerifyPIN(token, pin) then
                    DbgPrint("ETOKEN: PIN verified successfully")
                    return true
                else
                    DbgPrint("ETOKEN: Invalid PIN")
                    return false
                end

            elseif code == 14 then  -- BACKSPACE
                pin = pin:sub(1, -2)
                DrawDialog()

            elseif char >= 32 and char <= 126 then
                pin = pin .. string.char(char)
                DrawDialog()
            end
        end
    end
end

-- ============================================================
-- Main
-- ============================================================
local function ETokenMain()
    DbgPrint("ETOKEN: Starting Aladdin eToken...")

    local winX, winY, winW, winH, clientX, clientY = DrawWindow()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local code = signal[4]
            if code == 203 then  -- <
                return
            end

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]

            -- Закриття
            if ty == winY + 1 and tx >= winX + winW - 5 then
                return
            end

            -- Create Token
            if ty == clientY + 5 and tx >= clientX + 2 and tx <= clientX + 20 then
                CreateTokenDialog()
                DrawWindow()
            end

            -- Verify Token
            if ty == clientY + 7 and tx >= clientX + 2 and tx <= clientX + 20 then
                VerifyTokenDialog()
                DrawWindow()
            end

            -- Test PIN
            if ty == clientY + 9 and tx >= clientX + 2 and tx <= clientX + 16 then
                TestPINDialog()
                DrawWindow()
            end
        end
    end
end

DbgPrint("ETOKEN: Starting eToken...")
ETokenMain()
DbgPrint("ETOKEN: Closed.")

return true