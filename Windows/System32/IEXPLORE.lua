-- IEXPLORE.lua - Internet Explorer 2.0 for LuaNT 4.0
-- (C) RedstoneShell 2026
-- Simple web browser for OpenComputers

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local wininet = _G.LdrLoadDll("Windows/System32/wininet.lua")
local rshtml = _G.LdrLoadDll("Windows/System32/rshtml.lua")

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
        _G.DbgPrint("IE: " .. tostring(text))
    else
        _G.DbgPrint("IE: " .. tostring(text))
    end
end

local print = printToConsole

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

local winW, winH = 60, 20
local winX = math.floor((screenW - winW) / 2)
local winY = math.floor((screenH - winH) / 2)

local clientX = winX + 1
local clientY = winY + 4
local clientW = winW - 2
local clientH = winH - 6

local addressBar = ""
local pageContent = {}
local cursorPos = 1
local history = {}
local historyPos = 1

local COLORS = {
    window_bg = 0xC0C0C0,
    window_title = 0x000080,
    client_bg = 0xFFFFFF,
    text = 0x000000,
    address_bg = 0xFFFFFF,
    status_bg = 0x000080,
    status_text = 0xFFFFFF
}
local function FetchPage(url)
    if not url or url == "" then
        pageContent = {"<Empty page>"}
        return
    end

    if not url:match("^https?://") then
        url = "http://" .. url
    end

    print("Loading: " .. url)

    local ok, content = wininet.HttpGet(url)

    if not ok then
        pageContent = {tostring(content)}
        return
    end

    print("Downloaded " .. tostring(#content) .. " bytes")

    local MAX_SIZE = 80000
    if #content > MAX_SIZE then
        print("Page too large (" .. #content .. " bytes), truncating to " .. MAX_SIZE)
        content = content:sub(1, MAX_SIZE) .. "\n\n[Page truncated]"
    end

    print("Parsing HTML content...")
    local text = rshtml.ToText(content)

    pageContent = {}

    for line in text:gmatch("[^\n]+") do
        if #line > clientW - 2 then
            while #line > clientW - 2 do
                table.insert(pageContent, line:sub(1, clientW - 2))
                line = line:sub(clientW - 1)
                _G.KeDelayExecutionThread(0.7)
            end
        end

        if line ~= "" then
            table.insert(pageContent, line)
        end
    end

    if #pageContent == 0 then
        pageContent = {"(Empty page)"}
    end

    print("Loaded " .. tostring(#pageContent) .. " lines")
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
    
    local title = "Internet Explorer 2.0"
    if addressBar ~= "" then
        title = title .. " - " .. addressBar
    end
    gdi32.TextOut(hdc, winX + 2, winY + 1, title:sub(1, winW - 4))
    gdi32.SetTextColor(hdc, 0xFF0000)
    gdi32.TextOut(hdc, winX + winW - 3, winY + 1, "X")
    
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.address_bg))
    gdi32.PatBlt(hdc, clientX, winY + 2, clientW, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.address_bg)
    
    local displayUrl = addressBar
    if displayUrl == "" then
        displayUrl = "about:blank"
    end
    
    local maxUrlLen = clientW - 2
    if #displayUrl > maxUrlLen then
        displayUrl = "…" .. displayUrl:sub(#displayUrl - maxUrlLen + 2)
    end
    gdi32.TextOut(hdc, clientX + 1, winY + 2, displayUrl)

    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.client_bg))
    gdi32.PatBlt(hdc, clientX, clientY, clientW, clientH, gdi32.PATCOPY)
    
    gdi32.SetTextColor(hdc, COLORS.text)
    gdi32.SetBkColor(hdc, COLORS.client_bg)
    
    local maxLines = clientH - 2
    for i = 1, math.min(#pageContent, maxLines) do
        local line = pageContent[i] or ""
        if #line > clientW - 2 then
            line = line:sub(1, clientW - 5) .. "..."
        end
        gdi32.TextOut(hdc, clientX + 1, clientY + i - 1, line)
    end
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(COLORS.status_bg))
    gdi32.PatBlt(hdc, winX + 1, winY + winH - 2, winW - 2, 1, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, COLORS.status_text)
    gdi32.SetBkColor(hdc, COLORS.status_bg)
    gdi32.TextOut(hdc, winX + 2, winY + winH - 2, "Ready")
end

local function RedrawWindow()
    DrawWindowFrame()
end

local function HandleKey(char, code)
    if code == 211 then -- DEL
        return false
    elseif code == 28 then -- ENTER
        if addressBar ~= "" then
            table.insert(history, addressBar)
            historyPos = #history + 1
            FetchPage(addressBar)
            RedrawWindow()
        end
    elseif code == 14 then -- BACKSPACE
        addressBar = addressBar:sub(1, -2)
        RedrawWindow()
    elseif code == 203 then -- LEFT
        if historyPos > 1 then
            historyPos = historyPos - 1
            addressBar = history[historyPos]
            FetchPage(addressBar)
            RedrawWindow()
        end
    elseif code == 205 then -- RIGHT
        if historyPos < #history then
            historyPos = historyPos + 1
            addressBar = history[historyPos]
            FetchPage(addressBar)
            RedrawWindow()
        end
    elseif char >= 32 and char <= 126 then
        addressBar = addressBar .. string.char(char)
        RedrawWindow()
    end
    return true
end

local function IEMain()
    _G.DbgPrint("IE: Starting Internet Explorer 2.0...")
    
    addressBar = "about:blank"
    pageContent = {"Welcome to Internet Explorer 2.0!", "Enter a URL in the address bar.", "Press Enter to load."}
    table.insert(history, addressBar)
    historyPos = 1
    
    RedrawWindow()
    
    local ok, err = pcall(function()
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
                if y == winY + 1 and x >= winX + winW - 3 and x <= winX + winW - 1 then
                    break
                end
            end
        end
    end)

    if not ok then
        _G.DbgPrint("IE: Error occurred: " .. tostring(err))
    end
    
    _G.DbgPrint("IE: Exiting...")
    gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
    gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
    return false
end

local exitCode = IEMain()

if not exitCode then
    return true
else
    repeat
        coroutine.yield()
    until false
end

return true