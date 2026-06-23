local reg, gdi, mm = LdrLoadDll("/Windows/System32/regedit.lua"), _G.KRNL_GDI32, _G.Mm

local function benchmark()
    DbgPrint("WinSAT: Running formal assessments...")
    
    local s = computer.uptime()
    for i=1, 500000 do 
        local _ = math.sin(i) * math.cos(i)
    end
    local cpu_time = computer.uptime() - s
    local cpu_score = math.min(7.9, math.max(1.0, (0.5 / cpu_time)))
    
    local test_arr = {}
    s = computer.uptime()
    for i=1, 10000 do
        test_arr[i] = i * 3.14159
        local _ = test_arr[math.random(1, i)]
    end
    local ram_time = computer.uptime() - s
    local ram_score = math.min(7.9, math.max(1.0, (0.3 / ram_time)))
    
    s = computer.uptime()
    local dc = gdi.GetDC(0)
    for i=1, 1000 do
        gdi.PatBlt(dc, i % 100, i % 100, 10, 10, 0x0)
    end
    local gpu_time = computer.uptime() - s
    local gpu_score = math.min(7.9, math.max(1.0, (0.5 / gpu_time)))
    
    s = computer.uptime()
    local disk = component.proxy(computer.getBootAddress())
    local test_path = "/temp_winsat_test"
    local f = disk.open(test_path, "w")
    for i=1, 1000 do
        disk.write(f, string.rep("test_data_", 10))
    end
    disk.close(f)
    
    f = disk.open(test_path, "r")
    local data = disk.read(f, 4096)
    disk.close(f)
    disk.remove(test_path)
    
    local disk_time = computer.uptime() - s
    local disk_score = math.min(7.9, math.max(0.1, (0.2 / disk_time)))
    
    DbgPrint(string.format("Times - CPU:%.4f RAM:%.4f GPU:%.4f DISK:%.4f", 
             cpu_time, ram_time, gpu_time, disk_time))
    
    local path = "\\Software\\RedstoneShell\\Windows\\CurrentVersion\\WinSAT"
    reg.SetValue(path, "ProcessorScore", string.format("%.1f", cpu_score))
    reg.SetValue(path, "MemoryScore", string.format("%.1f", ram_score))
    reg.SetValue(path, "GraphicsScore", string.format("%.1f", gpu_score))
    reg.SetValue(path, "DiskScore", string.format("%.1f", disk_score))
    reg.Flush()
end

local WinSAT={}

function WinSAT.start()
    benchmark()
end

return WinSAT