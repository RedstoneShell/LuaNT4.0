local csrss = {}
local screenW, screenH, gdi32 = 160, 50, nil

csrss.ProcessTable = {}
csrss.ApiPort      = {}
csrss.SharedSection= {}
csrss.WindowTable  = {}

function csrss.CsrServerInitialization(argc, argv)
    DbgPrint("CSRSS: Creating ApiPort...")
    csrss.ApiPort={
        Name="\\Windows\\ApiPort",
        ConnectQueue={},
        MessageQueue={}
    }
    gdi32 = argv.gdi
    local i=1
    while i<=argc do
        if argv[i]=="-scrRes" then
            screenW=tonumber(argv[i+1])or 160
            screenH=tonumber(argv[i+2])or 50
            i=i+2
        end
        i=i+1
    end
    DbgPrint("CSRSS: Creating root process object.")
    csrss.ProcessTable[440] = {
        name       = "csrss.exe",
        threads    = 1,
        priority   = "REALTIME",
        isCritical = true
    }
    KeDelayExecutionThread(1)
    local hdc = gdi32.GetDC(0)
    gdi32.PatBlt(hdc, 0, 0, screenW, screenH, gdi32.PATCOPY)

    return true
end

function csrss.CsrCreateWindow(pid, title, procExec, isCrit, x, y, w, h)
    local hwnd = #csrss.WindowTable+1
    csrss.WindowTable[hwnd] = {
        owner=pid,
        title=title,
        x=x, y=y, w=w, h=h,
        visible=true
    }
    csrss.ProcessTable[pid] = {
        name       = procExec,
        threads    = 1,
        priority   = "NORMAL",
        isCritical = isCrit
    }
    DbgPrint("CSRSS: Registered HWND "..hwnd.." for PID "..pid)
    return hwnd
end

function csrss.CsrExecuteProcess(path, pid, args)
    local pData = csrss.ProcessTable[pid]
    local succ, err = pcall(function()
        local app = LdrLoadDll(path)
        if app and app.Main then
            app.Main(args)
        else
            csrss.CsrDisplayErrorBox(path, "Entry point \"Main\" not found.")
        end
    end)

    if not succ then
        DbgPrint("CSRSS: Exception in "..path..": "..err)
        if pData and pData.isCritical then
            KeBugCheckEx("CRITICAL_PROCESS_TERMINATED", err, pid)
        else
            csrss.CsrDisplayErrorBox(path, err)
        end
    end
end

function csrss.CsrDisplayErrorBox(fN, errM)
    local hdc = gdi32.GetDC(0)
    local b = gdi32.CreateSolidBrush(0x000000)
    gdi32.SelectObject(hdc, b)
    gdi32.PatBlt(hdc, 32, 12, 100, 20, gdi32.PATCOPY)
    b = gdi32.CreateSolidBrush(0xCCCCCC)
    gdi32.SelectObject(hdc, b)
    gdi32.PatBlt(hdc, 30, 10, 100, 20, gdi32.PATCOPY)
    b = gdi32.CreateSolidBrush(0xAA0000)
    gdi32.SelectObject(hdc, b)
    gdi32.PatBlt(hdc, 30, 10, 100, 3, gdi32.PATCOPY)
    gdi32.SetTextColor(hdc, 0xFFFFFF)
    gdi32.TextOut(hdc, 32, 11, "Application Error")
    gdi32.SetTextColor(hdc, 0x000000)
    gdi32.TextOut(hdc, 32, 14, "File: "..fN)
    gdi32.TextOut(hdc, 32, 16, "Error: "..string.sub(errM, 1, 80))
    DbgPrint("CSRSS: Debug dialog displayed")
end

return csrss