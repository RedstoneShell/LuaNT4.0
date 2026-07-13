-- pastebin.lua - Pastebin GUI for LuaNT 4.0
-- (C) RedstoneShell 2026
-- A GUI program to download and run scripts from pastebin.com

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local wininet = _G.LdrLoadDll("Windows/System32/wininet.lua")

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
        _G.DbgPrint("Pastebin: " .. tostring(text))
    end
end

local print = printToConsole

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 55, 15
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local clientX = winX + 1
local clientY = winY + 3
local clientW = winW - 2
local clientH = winH - 5

local pasteId = ""
local fileName = ""
local downloadPath = ""
local statusText = "Enter paste ID and name"
local downloadInProgress = false

local COLORS = {
    window_bg = 0xC0C0C0,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    selected = 0x000080,
    selected_text = 0xFFFFFF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF,
    input_bg = 0xFFFFFF
}

local function DownloadPaste(pasteId, filename)
    if not pasteId or pasteId == "" then
        return false, "No paste ID provided"
    end
    
    if not filename or filename == "" then
        return false, "No filename provided"
    end
    
    local url = "https://pastebin.com/raw/" .. pasteId
    print("Downloading from: " .. url)
    
    local ok, content = wininet.HttpGet(url)
    if not ok then
        return false, "HTTP request failed: " .. tostring(content)
    end
    
    if not content or content == "" then
        return false, "Empty response from pastebin"
    end
    
    local basePath = "Program Files/Pastebin/" .. filename
    local fs = component.proxy(computer.getBootAddress())
    
    local dirPath = "Program Files/Pastebin"
    if not fs.exists(dirPath) then
        pcall(function() fs.makeDirectory(dirPath) end)
    end
    
    local fullPath = dirPath .. "/" .. filename
    if not filename:match("%.lua$") then
        fullPath = fullPath .. ".lua"
    end
    
    local handle, err = fs.open(fullPath, "w")
    if not handle then
        return false, "Failed to open file for writing: " .. tostring(err)
    end
    
    fs.write(handle, content)
    fs.close(handle)
    
    print("Saved to: " .. fullPath)
    return true, fullPath
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
    gdi32.TextOut(hdc, winX + 2, winY + 1, "Pastebin Downloader")
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.window_bg)
    gdi32.TextOut(hdc, winX + 2, winY + 2, "Enter Pastebin ID:")
    gdi32.TextOut(hdc, winX + 2, winY + 3, "Program Name:")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.input_bg))
    gdi32.PatBlt(hdc, winX + 16, winY + 2, 20, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.input_bg)
    gdi32.TextOut(hdc, winX + 17, winY + 2, pasteId)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.input_bg))
    gdi32.PatBlt(hdc, winX + 14, winY + 3, 22, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.input_bg)
    gdi32.TextOut(hdc, winX + 15, winY + 3, fileName)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x00AA00))
    gdi32.PatBlt(hdc, winX + 2, winY + 5, 12, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x00AA00)
    gdi32.TextOut(hdc, winX + 3, winY + 5, "[ Get It ]")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xAA8800))
    gdi32.PatBlt(hdc, winX + 16, winY + 5, 10, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0xAA8800)
    gdi32.TextOut(hdc, winX + 17, winY + 5, "[ Run ]")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xAA0000))
    gdi32.PatBlt(hdc, winX + 28, winY + 5, 10, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0xAA0000)
    gdi32.TextOut(hdc, winX + 29, winY + 5, "[ Exit ]")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, winX + 2, winY + 7, winW - 4, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0x0000AA)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local status = statusText
    if #status > winW - 6 then
        status = status:sub(1, winW - 9) .. "..."
    end
    gdi32.TextOut(hdc, winX + 3, winY + 7, status)
    
    if downloadInProgress then
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x00AA00))
        gdi32.PatBlt(hdc, winX + 2, winY + 9, 20, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x00AA00)
        gdi32.TextOut(hdc, winX + 3, winY + 9, "Downloading...")
    end
end

local function RedrawWindow()
    DrawWindowFrame()
end

local function GetFileNameInput()
    local input = ""
    local maxLen = 30
    
    local dialogW = 40
    local dialogH = 6
    local dialogX = math.floor((screenW - dialogW) / 2)
    local dialogY = math.floor((screenH - dialogH) / 2)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
    gdi32.PatBlt(hdc, dialogX, dialogY, dialogW, dialogH, gdi32.PATCOPY)
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
    gdi32.PatBlt(hdc, dialogX, dialogY, dialogW, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.SetBkColor(hdc, 0x000080)
    gdi32.TextOut(hdc, dialogX + 2, dialogY, "Save As")
    
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.SetBkColor(hdc, 0xC0C0C0)
    gdi32.TextOut(hdc, dialogX + 2, dialogY + 2, "Enter file name (without .lua):")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
    gdi32.PatBlt(hdc, dialogX + 2, dialogY + 3, dialogW - 4, 1, gdi32.PATCOPY)
    
    while true do
        local signal = { computer.pullSignal(0.1) }
        if signal[1] == "key_down" then
            local char, code = signal[3], signal[4]
            if code == 28 then -- ENTER
                return input
            elseif code == 14 then -- BACKSPACE
                input = input:sub(1, -2)
            elseif code == 203 then -- <
                return nil
            elseif char >= 32 and char <= 126 and #input < maxLen then
                input = input .. string.char(char)
            end
            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
            gdi32.PatBlt(hdc, dialogX + 2, dialogY + 3, dialogW - 4, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, 0x000000)
            gdi32.SetBkColor(hdc, 0xFFFFFF)
            gdi32.TextOut(hdc, dialogX + 3, dialogY + 3, input)
        end
    end
end

local function HandleClick(x, y)
    if y == winY + 1 and x >= winX + winW - 3 and x <= winX + winW - 1 then
        return "close"
    end
    
    if y == winY + 5 and x >= winX + 2 and x <= winX + 14 then
        if downloadInProgress then
            statusText = "Download already in progress!"
            return
        end
        
        if pasteId == "" then
            statusText = "Please enter a paste ID!"
            return
        end
        
        local name = GetFileNameInput()
        if not name or name == "" then
            statusText = "Download cancelled"
            return
        end
        
        fileName = name
        statusText = "Downloading " .. fileName .. "..."
        downloadInProgress = true
        RedrawWindow()
        
        local ok, result = DownloadPaste(pasteId, fileName)
        downloadInProgress = false
        
        if ok then
            statusText = "Downloaded successfully to " .. result
            downloadPath = result
        else
            statusText = "Error: " .. tostring(result)
        end
        RedrawWindow()
        return
    end
    
    if y == winY + 5 and x >= winX + 16 and x <= winX + 26 then
        if downloadPath and downloadPath ~= "" then
            local fs = component.proxy(computer.getBootAddress())
            if fs.exists(downloadPath) then
                statusText = "Running " .. downloadPath
                RedrawWindow()
                _G.PsCreateSystemThread(downloadPath, "pastebin_run", 8, { name = "Administrator", group = "ADMINS" })
                statusText = "Started " .. downloadPath
            else
                statusText = "File not found: " .. downloadPath
            end
        else
            statusText = "No file downloaded yet!"
        end
        RedrawWindow()
        return
    end
    
    if y == winY + 5 and x >= winX + 28 and x <= winX + 38 then
        return "close"
    end
end

local function HandleKey(char, code)
    if code == 203 then -- <
        return false
    end
    
    if char >= 32 and char <= 126 then
        pasteId = pasteId .. string.char(char)
        RedrawWindow()
    elseif code == 14 then -- BACKSPACE
        pasteId = pasteId:sub(1, -2)
        RedrawWindow()
    elseif code == 28 then -- ENTER
        if pasteId ~= "" then
            local name = GetFileNameInput()
            if name and name ~= "" then
                fileName = name
                statusText = "Downloading " .. fileName .. "..."
                downloadInProgress = true
                RedrawWindow()
                
                local ok, result = DownloadPaste(pasteId, fileName)
                downloadInProgress = false
                
                if ok then
                    statusText = "Downloaded successfully to " .. result
                    downloadPath = result
                else
                    statusText = "Error: " .. tostring(result)
                end
                RedrawWindow()
            end
        end
    end
    
    return true
end

local function PastebinMain()
    _G.DbgPrint("Pastebin: Starting GUI...")
    
    statusText = "Enter paste ID and press Get It"
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
            if HandleClick(x, y) == "close" then
                break
            end
        end
    end
    
    _G.DbgPrint("Pastebin: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return false
end

local exitCode = PastebinMain()

if not exitCode then
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true