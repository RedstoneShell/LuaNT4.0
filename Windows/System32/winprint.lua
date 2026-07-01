local winprint = {}

local function GetPrinter()
    local addr = component.list("openprinter")()
    if not addr then
        DbgPrint("WINPRINT: No printer found")
        return nil
    end
    return component.proxy(addr)
end

local function CheckResources(printer)
    if printer.getPaperLevel() < 1 then
        DbgPrint("WINPRINT: No paper")
        return false, "No paper"
    end
    
    if printer.getBlackInkLevel() < 1 then
        DbgPrint("WINPRINT: No black ink")
        return false, "No black ink"
    end
    
    return true
end

function winprint.PrintText(text, alignment, color)
    alignment = alignment or "left"
    color = color or 0x000000
    
    local printer = GetPrinter()
    if not printer then
        return false, "No printer"
    end
    
    if not CheckResources(printer) then
        return false, "Insufficient resources"
    end
    
    printer.clear()
    
    local title = "LuaNT Document - " .. os.date("%Y-%m-%d %H:%M:%S")
    printer.setTitle(title)
    
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    for _, line in ipairs(lines) do
        printer.writeln(line, {color}, {alignment})
    end
    
    printer.print()
    
    DbgPrint(string.format("WINPRINT: Printed %d lines", #lines))
    return true
end

function winprint.PrintTag(text)
    local printer = GetPrinter()
    if not printer then
        return false, "No printer"
    end
    
    if not CheckResources(printer) then
        return false, "Insufficient resources"
    end
    
    printer.printTag(text)
    DbgPrint("WINPRINT: Printed tag: " .. text)
    return true
end

function winprint.ScanPage()
    local printer = GetPrinter()
    if not printer then
        return nil, "No printer"
    end
    
    local data = printer.scan()
    if data then
        DbgPrint("WINPRINT: Scanned page")
    end
    return data
end

return winprint