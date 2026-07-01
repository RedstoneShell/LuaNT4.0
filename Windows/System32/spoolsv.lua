local spoolsv = {}
local printQueue = {}
local nextJobId = 1

function spoolsv.AddJob(text, alignment, color)
    local job = {
        id = nextJobId,
        text = text,
        alignment = alignment or "left",
        color = color or 0x000000,
        status = "pending",
        timestamp = os.time(),
        retries = 0
    }
    
    table.insert(printQueue, job)
    nextJobId = nextJobId + 1
    
    DbgPrint(string.format("SPOOL: Job #%d added to queue", job.id))
    return job.id
end

function spoolsv.ProcessQueue()
    local processed = 0
    
    for _, job in ipairs(printQueue) do
        if job.status == "pending" then
            local winprint = _G.LdrLoadDll("Windows/System32/winprint.lua")
            local success = winprint.PrintText(job.text, job.alignment, job.color)
            
            if success then
                job.status = "printed"
                DbgPrint(string.format("SPOOL: Job #%d printed", job.id))
                processed = processed + 1
            else
                job.retries = job.retries + 1
                if job.retries >= 3 then
                    job.status = "error"
                    DbgPrint(string.format("SPOOL: Job #%d failed after %d retries", job.id, job.retries))
                end
            end
        end
    end
    
    return processed
end

function spoolsv.GetQueueStatus()
    local status = {}
    for _, job in ipairs(printQueue) do
        table.insert(status, {
            id = job.id,
            status = job.status,
            timestamp = job.timestamp
        })
    end
    return status
end

function spoolsv.ClearQueue()
    for _, job in ipairs(printQueue) do
        if job.status == "pending" then
            job.status = "cancelled"
        end
    end
    DbgPrint("SPOOL: Queue cleared")
    return true
end

if _G.RpcSs then
    local IPrintSpooler = {
        AddJob = function(text, alignment, color)
            return spoolsv.AddJob(text, alignment, color)
        end,
        GetQueueStatus = function()
            return spoolsv.GetQueueStatus()
        end,
        ClearQueue = function()
            return spoolsv.ClearQueue()
        end,
        ProcessNow = function()
            return spoolsv.ProcessQueue()
        end
    }
    _G.RpcSs.RpcServerRegisterIf("IPrintSpooler", IPrintSpooler)
    DbgPrint("SPOOL: RPC interface 'IPrintSpooler' registered")
end

while true do coroutine.yield() end

return spoolsv