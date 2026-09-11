-- dhcpssvc.lua - DHCP Server Service for LuaNT (JET Blue Edition)
-- (C) RedstoneShell 2026
-- Всі дані зберігаються в dhcp.mdb через ESENT (JET Blue)

local dhcpssvc = {}
_G.DHCP_End=false
local esent = _G.LdrLoadDll("Windows/System32/esent.lua")

-- ===== Конфігурація =====
local config = {
    server_ip      = "192.168.1.1",
    subnet_mask    = "255.255.255.0",
    gateway        = "192.168.1.1",
    dns            = "192.168.1.1",
    pool_start     = 15,
    pool_end       = 100,
    lease_time     = 3600,
    server_port    = 67,
    client_port    = 68,
    subnet_prefix  = "192.168.1.",
    db_path        = "Windows\\System32\\dhcp\\dhcp.mdb",
    log_path       = "Windows\\System32\\dhcp\\j50.log",
    chk_path       = "Windows\\System32\\dhcp\\j50.chk"
}

-- ===== Глобальні структури =====
local leases = {}
local ip_to_uuid = {}
local next_ip = config.pool_start
local exclusions = {}
local scopes = {}

-- ===== Сесія JET =====
local sesid = nil

-- ===== Серіалізація (для мережі) =====
local function serialize(tbl)
    if type(tbl) ~= "table" then return tostring(tbl) end
    local parts = {}
    for k, v in pairs(tbl) do
        local vType = type(v)
        if vType == "string" then
            table.insert(parts, k .. "=S:" .. v)
        elseif vType == "number" then
            table.insert(parts, k .. "=N:" .. tostring(v))
        elseif vType == "boolean" then
            table.insert(parts, k .. "=B:" .. tostring(v))
        end
    end
    return table.concat(parts, ";")
end

local function deserialize(str)
    if type(str) ~= "string" then return nil end
    local tbl = {}
    for pair in str:gmatch("[^;]+") do
        local key, vType, value = pair:match("([^=]+)=([SNB]):(.+)")
        if key and vType and value then
            if vType == "S" then
                tbl[key] = value
            elseif vType == "N" then
                tbl[key] = tonumber(value) or 0
            elseif vType == "B" then
                tbl[key] = (value == "true")
            end
        end
    end
    return tbl
end

-- ===== JET Blue: Ініціалізація =====
local function InitJET()
    DbgPrint("DHCP: Initializing JET Blue (ESENT) engine...")

    -- Ініціалізуємо рушій
    local ok, result = pcall(function()
        return esent.JetInit()
    end)

    if not ok then
        DbgPrint("DHCP: ERROR - JetInit exception: " .. tostring(result))
        return false
    end

    if not result then
        DbgPrint("DHCP: ERROR - JetInit failed!")
        return false
    end

    DbgPrint("DHCP: ESENT engine initialized")

    -- Створюємо сесію
    local sessionOk, sessionResult = pcall(function()
        return esent.JetBeginSession()
    end)

    if not sessionOk then
        DbgPrint("DHCP: ERROR - JetBeginSession exception: " .. tostring(sessionResult))
        return false
    end

    sesid = sessionResult

    if not sesid then
        DbgPrint("DHCP: ERROR - JetBeginSession failed!")
        return false
    end

    DbgPrint("DHCP: ESENT session created: " .. tostring(sesid))

    -- Відкриваємо базу
    local dbOk, dbResult, dbErr = pcall(function()
        local a, b = esent.JetOpenDatabase(sesid, config.db_path)
        return a, b
    end)

    if not dbOk then
        DbgPrint("DHCP: ERROR - JetOpenDatabase exception: " .. tostring(dbResult))
        return false
    end

    if not dbResult then
        DbgPrint("DHCP: ERROR - JetOpenDatabase failed: " .. tostring(dbErr))
        return false
    end

    DbgPrint("DHCP: JET Blue initialized (Session ID: " .. tostring(sesid) .. ")")
    DbgPrint("DHCP: Database: " .. config.db_path)

    return true
end

local function LoadFromJET()
    DbgPrint("DHCP: Loading data from JET Blue...")

    leases = {}
    ip_to_uuid = {}

    local records = esent.QueryRecords("Leases")
    local count = 0

    for _, record in ipairs(records) do
        if record and #record > 0 then
            local ip       = record:match("IPAddress=([^;]*);")
            local uuid     = record:match("UniqueIdentifier=([^;]*);")
            local hostname = record:match("HostName=([^;]*);")
            local expires  = record:match("LeaseExpirationTime=([^;]*);")

            if ip and uuid and #ip > 0 and #uuid > 0 then
                count = count + 1
                leases[uuid] = {
                    ip       = ip,
                    expires  = tonumber(expires) or (computer.uptime() + config.lease_time),
                    hostname = hostname or "Unknown",  -- ← ТЕПЕР З БАЗИ!
                    uuid     = uuid
                }
                ip_to_uuid[ip] = uuid
            end
        end
    end

    DbgPrint("DHCP: Loaded " .. count .. " leases from JET Blue")
    return true
end

-- ===== JET Blue: Збереження оренди =====
local function SaveLeaseToJET(uuid, ip, hostname, expires)
    esent.JetBeginTransaction(sesid)

    esent.JetPrepareUpdate(sesid, "Leases", "Insert")
    esent.JetSetColumn(sesid, "IPAddress", ip)
    esent.JetSetColumn(sesid, "UniqueIdentifier", uuid)
    esent.JetSetColumn(sesid, "HostName", hostname)
    esent.JetSetColumn(sesid, "LeaseExpirationTime", tostring(expires))
    esent.JetSetColumn(sesid, "ClientType", "DHCP")

    esent.JetUpdate(sesid)
    esent.JetCommitTransaction(sesid)

    DbgPrint("DHCP: Lease saved to JET Blue: " .. ip .. " -> " .. hostname)
    return true
end

-- ===== JET Blue: Збереження виключення =====
local function SaveExclusionToJET(start_ip, end_ip, reason)
    esent.JetBeginTransaction(sesid)

    esent.JetPrepareUpdate(sesid, "Exclusions", "Insert")
    esent.JetSetColumn(sesid, "StartIP", start_ip)
    esent.JetSetColumn(sesid, "EndIP", end_ip)
    esent.JetSetColumn(sesid, "Reason", reason)

    esent.JetUpdate(sesid)
    esent.JetCommitTransaction(sesid)

    DbgPrint("DHCP: Exclusion saved to JET Blue: " .. start_ip .. " - " .. end_ip)
    return true
end

-- ===== JET Blue: Збереження конфігу =====
local function SaveConfigToJET()
    esent.JetBeginTransaction(sesid)

    esent.JetPrepareUpdate(sesid, "Config", "Update")
    esent.JetSetColumn(sesid, "PoolStart", tostring(config.pool_start))
    esent.JetSetColumn(sesid, "PoolEnd", tostring(config.pool_end))
    esent.JetSetColumn(sesid, "LeaseTime", tostring(config.lease_time))
    esent.JetSetColumn(sesid, "Gateway", config.gateway)
    esent.JetSetColumn(sesid, "DNS", config.dns)
    esent.JetSetColumn(sesid, "SubnetMask", config.subnet_mask)

    esent.JetUpdate(sesid)
    esent.JetCommitTransaction(sesid)

    DbgPrint("DHCP: Config saved to JET Blue")
    return true
end

-- ===== IP-функції =====
local function ip_to_string(prefix, octet)
    return prefix .. tostring(octet)
end

local function is_ip_free(ip)
    if ip_to_uuid[ip] ~= nil then return false end
    for _, excl in ipairs(exclusions) do
        if ip >= excl.start_ip and ip <= excl.end_ip then
            return false
        end
    end
    return true
end

local function find_free_ip()
    for i = next_ip, config.pool_end do
        local ip = ip_to_string(config.subnet_prefix, i)
        if is_ip_free(ip) then return ip, i end
    end
    for i = config.pool_start, next_ip - 1 do
        local ip = ip_to_string(config.subnet_prefix, i)
        if is_ip_free(ip) then return ip, i end
    end
    return nil, nil
end

local function allocate_ip(uuid, hostname)
    if leases[uuid] then
        leases[uuid].expires = computer.uptime() + config.lease_time
        leases[uuid].hostname = hostname or leases[uuid].hostname

        -- Оновлюємо в JET
        SaveLeaseToJET(uuid, leases[uuid].ip, leases[uuid].hostname, leases[uuid].expires)

        DbgPrint("DHCP: Renewed lease for " .. tostring(hostname) ..
                 " (" .. leases[uuid].ip .. ")")
        return leases[uuid].ip
    end

    local ip, octet = find_free_ip()
    if not ip then
        DbgPrint("DHCP: ERROR - No free IPs in pool!")
        return nil
    end

    leases[uuid] = {
        ip       = ip,
        expires  = computer.uptime() + config.lease_time,
        hostname = hostname or "Unknown",
        uuid     = uuid
    }
    ip_to_uuid[ip] = uuid

    -- Зберігаємо в JET
    SaveLeaseToJET(uuid, ip, hostname or "Unknown", leases[uuid].expires)

    next_ip = octet + 1
    if next_ip > config.pool_end then
        next_ip = config.pool_start
    end

    DbgPrint("DHCP: Allocated " .. ip .. " for " .. tostring(hostname) ..
             " (UUID: " .. uuid:sub(1, 8) .. "...)")
    return ip
end

local function release_ip(uuid)
    if leases[uuid] then
        local ip = leases[uuid].ip
        ip_to_uuid[ip] = nil
        leases[uuid] = nil

        -- Видаляємо з JET
        esent.JetBeginTransaction(sesid)
        esent.JetPrepareUpdate(sesid, "Leases", "Delete")
        esent.JetSetColumn(sesid, "IPAddress", ip)
        esent.JetUpdate(sesid)
        esent.JetCommitTransaction(sesid)

        DbgPrint("DHCP: Released " .. ip .. " (UUID: " .. uuid:sub(1, 8) .. "...)")
        return true
    end
    return false
end

local function cleanup_leases()
    local now = computer.uptime()
    local count = 0
    for uuid, lease in pairs(leases) do
        if lease.expires < now then
            release_ip(uuid)
            count = count + 1
        end
    end
    if count > 0 then
        DbgPrint("DHCP: Cleaned up " .. count .. " expired leases")
    end
end

-- ===== Відправка OFFER =====
local function send_offer(modem, client_addr, uuid, hostname)
    local offered_ip = allocate_ip(uuid, hostname)
    if not offered_ip then
        DbgPrint("DHCP: Failed to allocate IP for " .. tostring(hostname))
        return
    end

    local offer_data = serialize({
        type        = "DHCP_OFFER",
        offered_ip  = offered_ip,
        server_ip   = config.server_ip,
        subnet_mask = config.subnet_mask,
        gateway     = config.gateway,
        dns         = config.dns,
        lease_time  = config.lease_time,
        uuid        = uuid
    })

    modem.send(client_addr, config.client_port, offer_data)
    DbgPrint("DHCP: Sent OFFER " .. offered_ip .. " to " .. tostring(hostname))
end

-- ===== Ініціалізація сервера =====
local modem = nil
local last_cleanup = 0

local function init_server()
    local modem_addr = component.list("modem")()
    if not modem_addr then
        DbgPrint("DHCP: ERROR - No modem found!")
        return false
    end

    modem = component.proxy(modem_addr)
    if not modem then
        DbgPrint("DHCP: ERROR - Failed to proxy modem!")
        return false
    end

    modem.open(config.server_port)
    DbgPrint("DHCP: Server started on " .. config.server_ip ..
             ":" .. config.server_port)
    DbgPrint("DHCP: Pool: " .. config.subnet_prefix .. config.pool_start ..
             " - " .. config.subnet_prefix .. config.pool_end)
    DbgPrint("DHCP: Listening on port " .. config.server_port)
    return true
end

-- ===== API =====
function dhcpssvc.GetConfig()
    return config
end

function dhcpssvc.SetConfig(newConfig)
    for k, v in pairs(newConfig) do
        if config[k] ~= nil then
            config[k] = v
        end
    end

    -- Зберігаємо в JET
    SaveConfigToJET()

    DbgPrint("DHCP: Configuration updated")
end

function dhcpssvc.GetLeases()
    return leases
end

function dhcpssvc.GetLeaseCount()
    local count = 0
    for _ in pairs(leases) do count = count + 1 end
    return count
end

function dhcpssvc.ReleaseLease(uuid)
    return release_ip(uuid)
end

function dhcpssvc.CleanupExpired()
    cleanup_leases()
end

-- ===== SCOPES =====
function dhcpssvc.GetScopes()
    return scopes
end

function dhcpssvc.CreateScope(name, start_ip, end_ip, subnet_mask)
    local start_octet = tonumber(start_ip:match("%.(%d+)$"))
    local end_octet   = tonumber(end_ip:match("%.(%d+)$"))

    if not start_octet or not end_octet then
        DbgPrint("DHCP: ERROR - Invalid IP format in CreateScope")
        return false
    end

    config.pool_start = start_octet
    config.pool_end   = end_octet
    config.subnet_mask = subnet_mask or config.subnet_mask

    -- Додаємо в scopes
    table.insert(scopes, {
        name        = name,
        start_ip    = start_ip,
        end_ip      = end_ip,
        subnet_mask = subnet_mask,
        state       = "Active"
    })

    -- Зберігаємо в JET
    SaveConfigToJET()

    DbgPrint("DHCP: Created scope '" .. name .. "' (" .. start_ip .. " - " .. end_ip .. ")")
    return true
end

function dhcpssvc.DeleteScope(name)
    for i, scope in ipairs(scopes) do
        if scope.name == name then
            table.remove(scopes, i)
            break
        end
    end

    config.pool_start = 15
    config.pool_end   = 100

    -- Зберігаємо в JET
    SaveConfigToJET()

    DbgPrint("DHCP: Deleted scope '" .. name .. "'")
    return true
end

-- ===== EXCLUSIONS =====
function dhcpssvc.GetExclusions()
    return exclusions
end

function dhcpssvc.AddExclusion(start_ip, end_ip, reason)
    table.insert(exclusions, {
        start_ip = start_ip,
        end_ip   = end_ip,
        reason   = reason or "Reserved"
    })

    -- Зберігаємо в JET
    SaveExclusionToJET(start_ip, end_ip, reason)

    DbgPrint("DHCP: Added exclusion " .. start_ip .. " - " .. end_ip .. " (" .. reason .. ")")
    return true
end

function dhcpssvc.RemoveExclusion(index)
    if exclusions[index] then
        local removed = exclusions[index]

        -- Видаляємо з JET
        esent.JetBeginTransaction(sesid)
        esent.JetPrepareUpdate(sesid, "Exclusions", "Delete")
        esent.JetSetColumn(sesid, "StartIP", removed.start_ip)
        esent.JetUpdate(sesid)
        esent.JetCommitTransaction(sesid)

        table.remove(exclusions, index)
        DbgPrint("DHCP: Removed exclusion " .. removed.start_ip)
        return true
    end
    return false
end

-- ===== RPC =====
local IDhcpServer = {
    GetConfig = function() return dhcpssvc.GetConfig() end,
    SetConfig = function(newConfig)
        dhcpssvc.SetConfig(newConfig)
        return true
    end,
    GetLeases = function() return dhcpssvc.GetLeases() end,
    GetLeaseCount = function() return dhcpssvc.GetLeaseCount() end,
    ReleaseLease = function(uuid) return dhcpssvc.ReleaseLease(uuid) end,
    CleanupExpired = function() dhcpssvc.CleanupExpired() return true end,
    GetScopes = function() return dhcpssvc.GetScopes() end,
    CreateScope = function(name, start_ip, end_ip, subnet_mask)
        return dhcpssvc.CreateScope(name, start_ip, end_ip, subnet_mask)
    end,
    DeleteScope = function(name) return dhcpssvc.DeleteScope(name) end,
    GetExclusions = function() return dhcpssvc.GetExclusions() end,
    AddExclusion = function(start_ip, end_ip, reason)
        return dhcpssvc.AddExclusion(start_ip, end_ip, reason)
    end,
    RemoveExclusion = function(index)
        return dhcpssvc.RemoveExclusion(index)
    end
}

if _G.RpcSs then
    _G.RpcSs.RpcServerRegisterIf("IDhcpServer", IDhcpServer)
    DbgPrint("DHCP: RPC interface 'IDhcpServer' registered")
end

-- ===== Запуск =====
if not InitJET() then
    DbgPrint("DHCP: FATAL - JET Blue initialization failed!")
    return dhcpssvc
end

LoadFromJET()

if not init_server() then
    return dhcpssvc
end

-- ===== Головний цикл =====
while true do
    local event, localAddr, remoteAddr, port, distance, message = computer.pullSignal(0.5)

    if event == "modem_message" then
        DbgPrint("DHCP: Got message from " .. tostring(remoteAddr):sub(1, 8) .. " on port " .. tostring(port))
        local data = deserialize(message)

        if data then
            if data.type == "DHCP_DISCOVER" then
                local uuid = data.mac or remoteAddr
                local hostname = data.hostname or "Unknown"
                DbgPrint("DHCP: Received DISCOVER from " .. tostring(hostname))
                send_offer(modem, remoteAddr, uuid, hostname)

            elseif data.type == "DHCP_REQUEST" then
                local uuid = data.mac or remoteAddr
                DbgPrint("DHCP: Received REQUEST from " .. tostring(uuid):sub(1, 8))
                local ack_data = serialize({
                    type    = "DHCP_ACK",
                    mac     = uuid,
                    status  = "OK"
                })
                modem.send(remoteAddr, config.client_port, ack_data)

            elseif data.type == "DHCP_RELEASE" then
                local uuid = data.mac or remoteAddr
                if release_ip(uuid) then
                    DbgPrint("DHCP: RELEASE from " .. tostring(uuid):sub(1, 8))
                end
            end
        end
    end

    -- Періодичне очищення
    local now = computer.uptime()
    if now - last_cleanup > 60 then
        cleanup_leases()
        last_cleanup = now
    end

    if _G.DHCP_End then break end

    coroutine.yield()
end

-- ===== Завершення =====
esent.JetCloseDatabase(sesid, config.db_path)
esent.JetEndSession(sesid)
esent.JetTerm()

return dhcpssvc