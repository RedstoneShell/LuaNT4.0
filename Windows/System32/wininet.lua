-- Windows/System32/wininet.lua
-- WinINet for LuaNT 4.0
-- (C) RedstoneShell 2026

local component = component

local wininet = {}

local function GetInternet()
    local addr = component.list("internet")()
    if not addr then
        return nil, "No Internet Card found"
    end

    return component.proxy(addr)
end

function wininet.HttpGet(url)
    local internet, err = GetInternet()
    if not internet then
        return false, err
    end

    local ok, request = pcall(function()
        return internet.request(url)
    end)

    if not ok then
        return false, tostring(request)
    end

    if not request then
        return false, "internet.request returned nil"
    end

    local content = ""

    while true do
        local data, reason = request.read()

        if not data then
            if request.close then
                pcall(request.close)
            end

            if reason then
                return false, tostring(reason)
            end

            break
        end

        if #data > 0 then
            content = content .. data
        else
            if _G.KeDelayExecutionThread then
                _G.KeDelayExecutionThread(0)
            else
                coroutine.yield()
            end
        end
    end

    return true, content
end

return wininet