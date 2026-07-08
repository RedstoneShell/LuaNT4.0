local shell32 = {}
local lCt, lCI = 0, ""

shell32.Icons = {
    MyPC = {
        "------",
        "| PC |",
        "--╗╔--",
        " ─╜╙─ ",
    },
    YesNetwork = {
        "▀     ",
        "░────┐",
        "│▄▄▄▄│",
        "├‗╗╔‗┘"
    },
    NoNetwork = {
        "▀      ",
        "░────┐ ",
        "│▄▄▄\\/",
        "├‗╗╔/\\"
    },
    RecycleBin = {
        "║    ║",
        "║ /\\║",
        "║ __ ║",
        "╙────╜"
    },
    Drive = {
        "   _____",
        "  /HDD /\\",
        "/-----\\ /",
        "\\-----/"
    },
    Drive_Error = {
        "   _____",
        "  /HDD /\\",
        "/-\\/--\\ /",
        "\\-/\\--/"
    },
    Floppy = {
        "|      |",
        "|      |",
        "||----||",
        "\\\\-█--//"
    },
    SetupMgr = {
        "|||| N",
        "\\--| T",
        "  \\/ O",
        "|||| S"
    },
    StartButton = {
        "______",
        "| NT |",
        "||||||",
        " Start"
    },
    Notepad = {
        "|-----|",
        "| TXT |",
        "|Type |",
        "|-----|"
    },
    Minesweeper = {
        " /-| ",
        " \\-| ",
        "   | ",
        "  ---"
    },
    IE = {
        "| +===",
        "| |___",
        "| |   ",
        "| +==="
    },
    AppCenter={
        "/----|",
        "| Lua|",
        "| SMS|",
        "+====+"
    }
}

shell32.DeskIcon = {}

function shell32.RegisterIcon(icon, x, y, w, h, callback)
    shell32.DeskIcon[icon] = {
        x=x,y=y,w=w,h=h,
        callback=callback
    }
end

function shell32.RegisterIcon(icon, x, yTable, w, h, callback)
    shell32.DeskIcon[icon] = {
        x=x,y=yTable,w=w,h=h,
        callback=callback
    }
end

function shell32.UnregIcon(icon, x, y)
    local srch = shell32.DeskIcon[icon]
    if srch==nil then return end
    if srch.x==x and srch.y==y then
        srch.callback=nil
    end
end

function shell32.DrawIcon(hdc, gdi, bkColor, x, y, iconName, label)
    local icon = shell32.Icons[iconName]
    if not icon then return false end
    
    for i, line in ipairs(icon) do
        gdi.SetTextColor(hdc, bkColor)
        gdi.TextOut(hdc, x, y + i - 1, line)
    end
    
    if label and #label>5 then
        local labelWidth = #label
        local iconWidth = 0
        for _, line in ipairs(icon) do
            if #line > iconWidth then iconWidth = #line end
        end
        
        local centerX = x + math.floor((iconWidth - labelWidth) / 2)
        if centerX < 0 then centerX = 0 end
        
        gdi.SetTextColor(hdc, bkColor)
        gdi.TextOut(hdc, centerX, y + #icon, label)
    else
        gdi.SetTextColor(bkColor)
        gdi.TextOut(hdc, x-1, y+#icon, label)
    end
    
    return true
end
function shell32.HandleClick(clickX, clickY, button)
    local cT = computer.uptime()
    for name, icon in pairs(shell32.DeskIcon) do
        if type(icon.y)=="table" then
            for i, y in ipairs(icon.y) do
                if clickX>=icon.x and clickX<=(icon.x+icon.w) and clickY>=y and clickY<=(y+icon.h) then
                    if cT-lCt<0.5 and lCI==name then
                        DbgPrint("SHELL32: Icon clicked: "..name)
                        icon.callback({ [1]="OPEN", [2]=i})
                    elseif button==1 then
                        icon.callback({ [1]="MENU", click={clickX, clickY}, [2]=i})
                    else
                        DbgPrint("SHELL32: Selected "..name)
                    end

                    lCt=cT
                    lCI=name
                    return true
                end
            end
        else
            if clickX>=icon.x and clickX<=(icon.x+icon.w) and clickY>=icon.y and clickY<=(icon.y+icon.h) then
                if cT-lCt<0.5 and lCI==name and icon.callback then
                    DbgPrint("SHELL32: Icon clicked: "..name)
                    icon.callback({ [1]="OPEN"})
                elseif button==1 and icon.callback then
                    icon.callback({ [1]="MENU", click={clickX, clickY}})
                else
                    DbgPrint("SHELL32: Selected "..name)
                end

                lCt=cT
                lCI=name
                return true
            end
        end
    end
    return false
end

return shell32