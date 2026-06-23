local reg = _G.regedit0
local tTable = {}

local EtwDpc = {}

function EtwDeferredRoutine(dpc, context, arg1, arg2)
    if _G.KRNL_ETW and _G.KRNL_ETW.PushSignal then
        _G.KRNL_ETW.PushSignal(table.unpack(context, 1, context.n))
    end
end

function _G.KiInterruptDispatch(sig, addr, arg1, arg2, arg3, arg4)
    local context = table.pack(sig, addr, arg1, arg2, arg3, arg4)
    _G.KeInitializeDpc(EtwDpc, EtwDeferredRoutine, context)
    _G.KeInsertQueueDpc(EtwDpc, arg1, arg2)
end

local function KiScanReadyQueues()
    for prio = 31, 1, -1 do
        if _G.PspActiveProcessList and #_G.PspActiveProcessList > 0 then
            for _, thread in ipairs(_G.PspActiveProcessList) do
                if thread.name ~= "System Idle Process" and thread.status == "READY" then
                    return true
                end
            end
        end
    end
    return false
end

while true do 
    if KiScanReadyQueues() then
        if _G.Prcb and #_G.Prcb.DpcQueue > 0 then
            _G.KiDispatchInterrupt()
        end
        coroutine.yield()
    else
        if _G.Prcb then _G.Prcb.IdleCount = _G.Prcb.IdleCount + 1 end
        local sig, addr, arg1, arg2, arg3, arg4 = computer.pullSignal(0.1)
        if sig then
            if _G.KiInterruptDispatch then
                _G.KiInterruptDispatch(sig, addr, arg1, arg2, arg3, arg4)
            end
            
            if _G.KiDispatchInterrupt then
                _G.KiDispatchInterrupt()
            end
            
            if sig == "key_down" or sig == "touch" then
                coroutine.yield()
            end
        end
        
        if _G.Prcb then _G.Prcb.CycleTime = _G.Prcb.CycleTime + 1 end
        
        if explorerTimeUpd and explorerTimeUpd.UpdateTime then
            _G.HAL.HalQueryRealTimeClock(tTable)
            explorerTimeUpd.UpdateTime(tTable)
        end
        
        local now = computer.uptime()
        if _G.LastRegSaveTime and now >= _G.LastRegSaveTime then 
            if reg and reg.Flush then 
                reg.Flush() 
            end
            _G.LastRegSaveTime = now + 30 
        end
    end
end