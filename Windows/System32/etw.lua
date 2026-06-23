local evapi = {}

_G.KRNL_ETW = _G.KRNL_ETW or {}
_G.KRNL_ETW.signalQueue = _G.KRNL_ETW.signalQueue or {}

function _G.KRNL_ETW.PushSignal(...)
    table.insert(_G.KRNL_ETW.signalQueue, table.pack(...))
end

function evapi.PlFltr(name, ...)
    local filter = table.pack(...)
    if name==nil and filter.n == 0 then
        return nil
    end

    return function(...)
        local signal=table.pack(...)
        if name and not (type(signal[1])=="string" and signal[1]:match(name)) then
            return false
        end
        for i=1,filter.n do
            if filter[i]~=nil and filter[i]~=signal[i+1] then
                return false
            end
        end
        return true
    end
end

function evapi.ReadData(...)
    local args = table.pack(...)
    if type(args[1])=="string" then
        return evapi.ReadETWFiltered(evapi.PlFltr(...))
    else
        return evapi.ReadETWFiltered(args[1], evapi.PlFltr(select(2, ...)))
    end
end

function evapi.ReadETWFiltered(...)
    local args = table.pack(...)
    local seconds, filter = math.huge

    if type(args[1])=="function" then
        filter=args[1]
    else
        seconds=args[1]
        filter=args[2]
    end
    local timeout = computer.uptime()+(seconds or math.huge)
    repeat
        local waitTime=timeout-computer.uptime()
        if waitTime<0 then break end
        
        local signal = table.pack(computer.pullSignal(waitTime))
        if signal.n>0 then
            if not (seconds or filter) or filter==nil or filter(table.unpack(signal,1,signal.n)) then
                return table.unpack(signal,1,signal.n)
            end
        end
    until signal.n==0
end

function evapi.ReadETWFilteredEx(...)
    local args = table.pack(...)
    local seconds, filter = math.huge

    if type(args[1])=="function" then
        filter=args[1]
    else
        seconds=args[1]
        filter=args[2]
    end
    
    local timeout = computer.uptime() + (seconds or math.huge)
    
    repeat
        if #_G.KRNL_ETW.signalQueue > 0 then
            local signal = table.remove(_G.KRNL_ETW.signalQueue, 1)
            
            if not filter or filter(table.unpack(signal, 1, signal.n)) then
                return table.unpack(signal, 1, signal.n)
            end
        else
            coroutine.yield()
        end
        
        if computer.uptime() > timeout then
            break
        end
    until false
    return nil
end

function evapi.ReadDataEx(...)
    local args = table.pack(...)
    if type(args[1])=="string" then
        return evapi.ReadETWFilteredEx(evapi.PlFltr(...))
    else
        return evapi.ReadETWFilteredEx(args[1], evapi.PlFltr(select(2, ...)))
    end
end

return evapi