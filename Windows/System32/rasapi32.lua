local rasapi32 = {
    ConnectionState="Disconnected",
    Device         ="Realtek PPP Adapter",
    TimeOut        =10,
    CHAP_Challenge =0
}

local LCP_Opts = {
    MRU=1500,
    Auth="CHAP",
    MagicNumber=0xDEADC0DE
}

local event = LdrLoadDll("/Windows/System32/etw.lua")
local recons = 0

function rasapi32.CreateNewTunnel()
    local link_card = component.proxy(component.list("tunnel")())
    if link_card then
        rasapi32.RemoteAddress=link_card.address
        link_card.setWakeMessage("0xFFFFFFFFFFFF")
        return true
    end
    return false
end

function rasapi32.LCP_Negotiate()
    if recons>=10 then return 2 end
    rasapi32.tunnel = component.proxy(rasapi32.RemoteAddress)
    if not rasapi32.tunnel then return 0 end

    rasapi32.ConnectionState="LCP Sent"
    rasapi32.tunnel.send("LCP_CONF_REQ "..LCP_Opts.MRU.." "..LCP_Opts.Auth)
    local _, a, b, c, d, payload = event.ReadData("modem_message")
    rasapi32.LCServer=b
    local cmd = payload:sub(1, 12)
    local val = payload:sub(11, 20)
    if cmd=="LCP_CONF_ACK" then
        rasapi32.ConnectionState="LCP Opened"
        rasapi32.CHAP_Challenge=val
        return 1
    elseif cmd=="LCP_CONF_NAK" then
        LCP_Opts.MRU=tonumber(val)
        recons=recons+1
        return rasapi32.LCP_Negotiate()
    elseif cmd=="LCP_CONF_REJ" then
        LCP_Opts.Auth="None"
        recons=recons+1
        return rasapi32.LCP_Negotiate()
    end
end

function rasapi32.IPCP_Negotiate()
    rasapi32.tunnel.send("IPCP_CONF_REQ 0.0.0.0")
    KeDelayExecutionThread(0.03)
    local _, _, _, _, _, pay = event.ReadData("modem_message")
    local cmd,ip=pay:match("(%S+)%s+(%S+)")
    ip=pay:sub(15,30)
    if cmd=="IPCP_CONF_NAK" then
        rasapi32.LocalIP=ip
        rasapi32.tunnel.send("IPCP_CONF_REQ "..ip)
        KeDelayExecutionThread(0.03)
        local _, _, _, _, _, ack_pay = event.ReadData("modem_message")
        if ack_pay:match("IPCP_CONF_ACK") then return true end
    end
    return false
end

function rasapi32.CHAPHandshake(password)
    local response, tunnel = password, component.proxy(rasapi32.RemoteAddress)
    tunnel.send("CHAP_RESP admin "..response)
    KeDelayExecutionThread(0.03)
    local _, a, b, c, d, pay = event.ReadData("modem_message")
    if pay=="AUTH_SUCCESS" then
        rasapi32.ConnectionState="Connected"
        return "SUCCESS"
    end
    return "AUTH_FAILED"
end

function rasapi32.GetLCConnServer()
    return rasapi32.LCServer
end

return rasapi32