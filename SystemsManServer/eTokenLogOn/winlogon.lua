local winlogon, gdi, HAL, csr, s32 = {}, nil, nil, nil, nil

local currentUser = "Administrator"
local enteredPassword = ""
local enteredPIN = ""
local inputStage = "token"
local winX, winY, winW, winH, hdc
local t2ButtonX, t2ButtonY = 1, 1
local t2ButtonW, t2ButtonH = 14, 1

local etoken = nil
local tokenLoaded = false
local tokenVerified = false

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
    for i = 1, #input do bytes[i] = string.byte(input, i) end
    local bit_len = #bytes * 8
    bytes[#bytes + 1] = 0x80
    while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
    for i = 0, 7 do bytes[#bytes + 1] = (bit_len >> (8 * i)) & 0xFF end
    local A, B, C, D = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476
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
            if j <= 16 then f, g = F(b, c, d), j - 1
            elseif j <= 32 then f, g = G(b, c, d), (5 * j - 4) % 16
            elseif j <= 48 then f, g = H(b, c, d), (3 * j + 2) % 16
            else f, g = I(b, c, d), (7 * j - 7) % 16 end
            local temp = d; d = c; c = b
            b = u32(b + rotl(u32(a + f + M[g + 1] + T[j]), S[j]))
            a = temp
        end
        A, B, C, D = u32(A + a), u32(B + b), u32(C + c), u32(D + d)
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

    return {
        id = data:sub(1, 16),
        pin_hash = data:sub(17, 32),
        private_key = data:sub(33, 64),
        public_key = data:sub(65, 80)
    }
end
local function SignChallenge(token, challenge)
    return rc4.crypt(token.private_key, challenge)
end

local function VerifySignature(token, challenge, signature)
    local expected = rc4.crypt(token.private_key, challenge)
    return signature == expected
end

local function VerifyPIN(token, pin)
    return md5.hash(pin) == token.pin_hash
end
local function IsTier2ModeEnabled()
    local fs = component.proxy(computer.getBootAddress())
    return fs.exists("/t2cm")
end

local function ToggleTier2Mode()
    local fs = component.proxy(computer.getBootAddress())

    if IsTier2ModeEnabled() then
        fs.remove("/t2cm")
        DbgPrint("WINLOGON: Tier 2 Mode DISABLED")
    else
        local f = fs.open("/t2cm", "w")
        if f then
            fs.write(f, "Tier2Mode=1\n")
            fs.close(f)
            DbgPrint("WINLOGON: Tier 2 Mode ENABLED")
        end
    end

    DbgPrint("WINLOGON: Rebooting in 1 second...")
    _G.KeDelayExecutionThread(1)
    computer.shutdown(true)
end

local function DrawTier2Button()
    local enabled = IsTier2ModeEnabled()
    local bgColor = enabled and 0x00AA00 or 0xAA0000

    gdi.SelectObject(hdc, gdi.CreateSolidBrush(bgColor))
    gdi.PatBlt(hdc, t2ButtonX, t2ButtonY, t2ButtonW, t2ButtonH, 3160021)

    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xFFFFFF))
    gdi.PatBlt(hdc, t2ButtonX, t2ButtonY, t2ButtonW, 1, 3160021)
    gdi.PatBlt(hdc, t2ButtonX, t2ButtonY, 1, t2ButtonH, 3160021)

    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x808080))
    gdi.PatBlt(hdc, t2ButtonX, t2ButtonY + t2ButtonH - 1, t2ButtonW, 1, 3160021)
    gdi.PatBlt(hdc, t2ButtonX + t2ButtonW - 1, t2ButtonY, 1, t2ButtonH, 3160021)

    gdi.SetTextColor(hdc, 0xFFFFFF)
    gdi.SetBkColor(hdc, bgColor)
    gdi.TextOut(hdc, t2ButtonX + 1, t2ButtonY, "T2 Mode: " .. (enabled and "ON " or "OFF"))
end
function winlogon.RedrawLogonBox()
    DrawTier2Button()
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000000))
    gdi.PatBlt(hdc, winX + 1, winY + 1, winW, winH, 3160021)

    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0xCCCCCC))
    gdi.PatBlt(hdc, winX, winY, winW, winH, 3160021)
    gdi.SelectObject(hdc, gdi.CreateSolidBrush(0x000080))
    gdi.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 3, 3160021)

    gdi.SetTextColor(hdc, 0xFFFFFF)
    gdi.SetBkColor(hdc, 0x000080)

    if inputStage == "token" then
        gdi.TextOut(hdc, winX + 2, winY + 2, "Aladdin eToken", 0xA0A0A0)
    else
        gdi.TextOut(hdc, winX + 2, winY + 2, "Logon Information", 0xA0A0A0)
    end
    gdi.SetTextColor(hdc, 0x000000)
    gdi.SetBkColor(hdc, 0xCCCCCC)

    if inputStage == "token" then
        gdi.TextOut(hdc, winX + 4, winY + 5, "Insert eToken diskette into drive A:", 0xA0A0A0)
        gdi.TextOut(hdc, winX + 4, winY + 6, "and press ENTER to continue.", 0xA0A0A0)

        if tokenLoaded then
            gdi.SetTextColor(hdc, 0x008000)
            gdi.TextOut(hdc, winX + 4, winY + 8, "Token detected: " .. etoken.id:sub(1, 8) .. "...", 0xA0A0A0)
            gdi.SetTextColor(hdc, 0x000000)
        else
            gdi.SetTextColor(hdc, 0xAA0000)
            gdi.TextOut(hdc, winX + 4, winY + 8, "Waiting for token...", 0xA0A0A0)
            gdi.SetTextColor(hdc, 0x000000)
        end

        gdi.TextOut(hdc, winX + 4, winY + 10, "[Press ENTER to scan]", 0xA0A0A0)

    elseif inputStage == "pin" then
        gdi.TextOut(hdc, winX + 4, winY + 5, "Enter eToken PIN:")

        local maskedPIN = string.rep("*", #enteredPIN)
        gdi.TextOut(hdc, winX + 4, winY + 7, "PIN: " .. maskedPIN .. "_", 0xA0A0A0)

        if tokenVerified then
            gdi.SetTextColor(hdc, 0x008000)
            gdi.TextOut(hdc, winX + 4, winY + 9, "PIN verified successfully!", 0xA0A0A0)
            gdi.SetTextColor(hdc, 0x000000)
        else
            gdi.SetTextColor(hdc, 0xAA0000)
            gdi.TextOut(hdc, winX + 4, winY + 9, "Token: " .. etoken.id:sub(1, 8) .. "...", 0xA0A0A0)
            gdi.SetTextColor(hdc, 0x000000)
        end

        gdi.TextOut(hdc, winX + 4, winY + 11, "[Press Enter to confirm]", 0xA0A0A0)

    elseif inputStage == "password" then
        gdi.TextOut(hdc, winX + 4, winY + 5, "Enter your credentials to log on.", 0xA0A0A0)
        gdi.TextOut(hdc, winX + 4, winY + 6, "(Token: " .. etoken.id:sub(1, 8) .. "...)", 0xA0A0A0)

        local userCursor = (inputStage == "username") and "_" or ""
        local passCursor = (inputStage == "password") and "_" or ""
        local maskedPassword = string.rep("*", #enteredPassword)

        gdi.TextOut(hdc, winX + 4, winY + 8, "User:     " .. currentUser .. userCursor .. "      ", 0xA0A0A0)
        gdi.TextOut(hdc, winX + 4, winY + 10, "Password: " .. maskedPassword .. passCursor .. "      ", 0xA0A0A0)
        gdi.TextOut(hdc, winX + 4, winY + 12, "[Press Enter to confirm]", 0xA0A0A0)
    end
end

function winlogon.Main(args)
    gdi = args.gdi
    HAL = args.halt
    csr = args.csr
    s32 = args.shell
    hdc = gdi.GetDC(0)

    winW, winH = 60, 15
    winX, winY = math.floor((HAL.w - winW) / 2), math.floor((HAL.h - winH) / 2)

    t2ButtonX = 2
    t2ButtonY = 2

    DbgPrint("WINLOGON: Switching to Winlogon desktop")

    if IsTier2ModeEnabled() then
        _G.Tier2CM = true
        DbgPrint("WINLOGON: Tier 2 Mode is ENABLED")
    else
        _G.Tier2CM = false
        DbgPrint("WINLOGON: Tier 2 Mode is DISABLED")
    end

    local token, err = LoadTokenFromDiskette()
    if token then
        etoken = token
        tokenLoaded = true
        DbgPrint("WINLOGON: eToken detected: " .. etoken.id:sub(1, 8) .. "...")
    else
        DbgPrint("WINLOGON: No eToken found: " .. tostring(err))
    end

    winlogon.RedrawLogonBox()

    return winlogon
end
function winlogon.HandleKey(char, code)
    if code == 28 then
        if inputStage == "token" then
            local token, err = LoadTokenFromDiskette()
            if token then
                etoken = token
                tokenLoaded = true
                inputStage = "pin"
                DbgPrint("WINLOGON: Token loaded, waiting for PIN")
            else
                DbgPrint("WINLOGON: Token load failed: " .. tostring(err))
                if csr and csr.CsrDisplayErrorBox then
                    csr.CsrDisplayErrorBox("winlogon.exe", "Token Error: " .. tostring(err))
                end
            end
            winlogon.RedrawLogonBox()

        elseif inputStage == "pin" then
            if #enteredPIN >= 4 then
                if VerifyPIN(etoken, enteredPIN) then
                    tokenVerified = true
                    inputStage = "password"
                    DbgPrint("WINLOGON: PIN verified, switching to password")
                else
                    DbgPrint("WINLOGON: Invalid PIN")
                    if csr and csr.CsrDisplayErrorBox then
                        csr.CsrDisplayErrorBox("winlogon.exe", "Token Error: Invalid PIN.")
                    end
                    enteredPIN = ""
                end
            end
            winlogon.RedrawLogonBox()

        elseif inputStage == "password" then
            local reg = _G.regedit0
            local samRoot = "SAM\\Users\\" .. currentUser

            local correctPassword = reg.GetValueEx("HKEY_LOCAL_MACHINE\\SAM", samRoot, "Password")
            local userGroup = reg.GetValueEx("HKEY_LOCAL_MACHINE\\SAM", samRoot, "Group")
            local userHome = reg.GetValueEx("HKEY_LOCAL_MACHINE\\SAM", samRoot, "HomeDir")

            if correctPassword and enteredPassword == correctPassword then
                local challenge = {}
                for i = 1, 32 do
                    challenge[i] = string.char(math.random(0, 255))
                end
                challenge = table.concat(challenge)

                local signature = SignChallenge(etoken, challenge)

                if VerifySignature(etoken, challenge, signature) then
                    DbgPrint("WINLOGON: Token challenge verified")
                    local userProfile = {
                        name = currentUser,
                        group = userGroup or "Users",
                        home = userHome or "C:\\Users\\" .. currentUser,
                        token_id = etoken.id
                    }
                    return winlogon.AuthSuccess(userProfile)
                else
                    DbgPrint("WINLOGON: Token challenge failed")
                    if csr and csr.CsrDisplayErrorBox then
                        csr.CsrDisplayErrorBox("winlogon.exe", "Token Error: Challenge failed.")
                    end
                end
            else
                DbgPrint("WINLOGON: Logon failed for user " .. currentUser)
                if csr and csr.CsrDisplayErrorBox then
                    csr.CsrDisplayErrorBox("winlogon.exe", "Logon Error: Invalid username or password.")
                end
                enteredPassword = ""
                inputStage = "password"
            end
            winlogon.RedrawLogonBox()
        end
    elseif code == 14 then
        if inputStage == "pin" then
            enteredPIN = enteredPIN:sub(1, -2)
        elseif inputStage == "password" then
            if inputStage == "username" then
                currentUser = currentUser:sub(1, -2)
            else
                enteredPassword = enteredPassword:sub(1, -2)
            end
        end
        winlogon.RedrawLogonBox()
    elseif char >= 32 and char <= 126 then
        local keyChar = string.char(char)

        if inputStage == "pin" then
            if #enteredPIN < 16 then
                enteredPIN = enteredPIN .. keyChar
            end
        elseif inputStage == "password" then
            if inputStage == "username" then
                if #currentUser < 20 then currentUser = currentUser .. keyChar end
            else
                if #enteredPassword < 20 then enteredPassword = enteredPassword .. keyChar end
            end
        end
        winlogon.RedrawLogonBox()
    end

    return nil
end
function winlogon.HandleClick(x, y)
    if x >= t2ButtonX and x <= t2ButtonX + t2ButtonW and
       y >= t2ButtonY and y <= t2ButtonY + t2ButtonH then
        DbgPrint("WINLOGON: Tier 2 Mode button clicked")
        ToggleTier2Mode()
        return true
    end
    return false
end
function winlogon.AuthSuccess(userProfile)
    DbgPrint("WINLOGON: Auth success, initializing Desktop for user: " .. userProfile.name)

    _G.CurrentUserSession = userProfile

    if _G.RpcSs then
        local IScmInterface = {
            StartService = function(name) return _G.KRNL_SCM.StartService(name) end,
            StopService  = function(name) return _G.KRNL_SCM.StopService(name) end,
            QueryStatus  = function(name)
                if _G.KRNL_SCM.RunningServices[name] then
                    return true, _G.KRNL_SCM.RunningServices[name].pid
                end
                return false, nil
            end,
            EnumRunningServices = function()
                local list = {}
                for svcName, _ in pairs(_G.KRNL_SCM.RunningServices) do
                    table.insert(list, svcName)
                end
                return list
            end
        }
        _G.RpcSs.RpcServerRegisterIf("IServiceControlManager", IScmInterface)
    end

    local exp, err = _G.LdrLoadDll("/Windows/explorer.lua")
    if exp and exp.Desktop then
        local s, err = pcall(function() exp.Desktop(gdi, HAL, s32, userProfile) end)
        if not s then
            csr.CsrDisplayErrorBox("explorer.exe", err)
        end
        return exp
    else
        KeBugCheckEx("SHELL_NOT_FOUND", "explorer.lua missing", err)
    end
end

return winlogon