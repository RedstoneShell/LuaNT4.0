local winlogon, gdi, HAL, csr, s32 = {}, nil, nil, nil, nil

local currentUser = "Administrator"
local enteredPassword = ""
local inputStage = "username" 
local winX, winY, winW, winH, hdc

function winlogon.RedrawLogonBox()
    local brush = gdi.CreateSolidBrush(0x000000)
    gdi.SelectObject(hdc, brush)
    gdi.PatBlt(hdc, winX+1, winY+1, winW, winH, 3160021)
    
    brush = gdi.CreateSolidBrush(0xCCCCCC)
    gdi.SelectObject(hdc, brush)
    gdi.PatBlt(hdc, winX, winY, winW, winH, 3160021)
    
    brush = gdi.CreateSolidBrush(0x000080) 
    gdi.SelectObject(hdc, brush)
    gdi.PatBlt(hdc, winX+1, winY+1, winW-2, 3, 3160021)
    
    gdi.SetTextColor(hdc, 0xFFFFFF)
    gdi.TextOut(hdc, winX+2, winY+2, "Logon Information")
    
    gdi.SetTextColor(hdc, 0x000000)
    gdi.TextOut(hdc, winX+4, winY+5, "Enter your credentials to log on.")
    
    local userCursor = (inputStage == "username") and "_" or ""
    local passCursor = (inputStage == "password") and "_" or ""
    
    local maskedPassword = string.rep("*", #enteredPassword)
    
    gdi.TextOut(hdc, winX+4, winY+7, "User:     " .. currentUser .. userCursor .. "      ")
    gdi.TextOut(hdc, winX+4, winY+9, "Password: " .. maskedPassword .. passCursor .. "      ")
    
    gdi.TextOut(hdc, winX+4, winY+11, "[Press Enter to confirm]")
end

function winlogon.Main(args)
    gdi = args.gdi
    HAL = args.halt
    csr = args.csr
    s32 = args.shell
    hdc = gdi.GetDC(0)
    
    winW, winH = 60, 13
    winX, winY = math.floor((HAL.w-winW)/2), math.floor((HAL.h-winH)/2)
    
    DbgPrint("WINLOGON: Switching to Winlogon desktop")
    
    winlogon.RedrawLogonBox()
    
    return winlogon
end

function winlogon.HandleKey(char, code)
    if code == 28 then -- ENTER
        if inputStage == "username" then
            if currentUser ~= "" then
                inputStage = "password"
                winlogon.RedrawLogonBox()
            end
        elseif inputStage == "password" then
            local reg = _G.regedit0
            local samRoot = "SAM\\Users\\" .. currentUser
            
            local correctPassword = reg.GetValueEx("HKEY_LOCAL_MACHINE\\SAM", samRoot, "Password")
            local userGroup = reg.GetValueEx("HKEY_LOCAL_MACHINE\\SAM", samRoot, "Group")
            local userHome = reg.GetValueEx("HKEY_LOCAL_MACHINE\\SAM", samRoot, "HomeDir")
            
            if correctPassword and enteredPassword == correctPassword then
                local userProfile = {
                    name = currentUser,
                    group = userGroup or "Users",
                    home = userHome or "C:\\Users\\" .. currentUser
                }
                return winlogon.AuthSuccess(userProfile)
            else
                _G.DbgPrint("WINLOGON: Logon failed for user " .. currentUser)
                
                if csr and csr.CsrDisplayErrorBox then
                    csr.CsrDisplayErrorBox("winlogon.exe", "Logon Error: Invalid username or password.")
                    KeDelayExecutionThread(5)
                    enteredPassword = ""
                    inputStage = "username"
                    winlogon.RedrawLogonBox()
                end
            end
        end
        
    elseif code == 14 then
        if inputStage == "username" then
            currentUser = currentUser:sub(1, -2)
        else
            enteredPassword = enteredPassword:sub(1, -2)
        end
        winlogon.RedrawLogonBox()
        
    elseif char >= 32 and char <= 126 then
        local keyChar = string.char(char)
        if inputStage == "username" then
            if #currentUser < 20 then currentUser = currentUser .. keyChar end
        else
            if #enteredPassword < 20 then enteredPassword = enteredPassword .. keyChar end
        end
        winlogon.RedrawLogonBox()
    end
    
    return nil
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
        local s, err = pcall(function () exp.Desktop(gdi, HAL, s32, userProfile) end)
        if not s then
            csr.CsrDisplayErrorBox("explorer.exe", err)
        end
        return exp
    else
        KeBugCheckEx("SHELL_NOT_FOUND", "explorer.lua missing", err)
    end
end

return winlogon