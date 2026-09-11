-- luazip.lua - ZIP Archiver для LuaNT
-- (C) RedstoneShell 2026
-- Підтримує Store (0) та Deflate (8, fixed Huffman)

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

-- ===== CRC-32 =====
local crc_table = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if c % 2 == 1 then
            c = math.floor(c / 2) ~ 0xEDB88320
        else
            c = math.floor(c / 2)
        end
    end
    crc_table[i] = c
end

local function crc32(data)
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        local byte = string.byte(data, i)
        crc = (crc >> 8) ~ crc_table[(crc ~ byte) % 256]
    end
    return (crc ~ 0xFFFFFFFF) % 4294967296
end

-- ===== DOS-час =====
local function dos_time()
    local t = os.date("*t")
    local dosTime = (t.hour * 2048) + (t.min * 32) + math.floor(t.sec / 2)
    local dosDate = ((t.year - 1980) * 512) + (t.month * 32) + t.day
    return dosTime, dosDate
end

-- ===== Little-endian =====
local function writeU16(v)
    return string.char(v % 256, math.floor(v / 256) % 256)
end

local function writeU32(v)
    v = v % 4294967296
    return string.char(
        v % 256,
        math.floor(v / 256) % 256,
        math.floor(v / 65536) % 256,
        math.floor(v / 16777216) % 256
    )
end

-- ===== Бітовий потік (LBS first) =====
local BitWriter = {}
BitWriter.__index = BitWriter

function BitWriter.new()
    return setmetatable({ bytes = {}, bitBuf = 0, bitCount = 0 }, BitWriter)
end

function BitWriter:WriteBits(value, count)
    for i = 0, count - 1 do
        local bit = (value >> i) & 1
        self.bitBuf = self.bitBuf | (bit << self.bitCount)
        self.bitCount = self.bitCount + 1

        if self.bitCount == 8 then
            self.bytes[#self.bytes + 1] = string.char(self.bitBuf)
            self.bitBuf = 0
            self.bitCount = 0
        end
    end
end

-- Huffman-коди пишуться у зворотному порядку (MSB first)
function BitWriter:WriteHuffCode(code, length)
    for i = length - 1, 0, -1 do
        local bit = (code >> i) & 1
        self.bitBuf = self.bitBuf | (bit << self.bitCount)
        self.bitCount = self.bitCount + 1

        if self.bitCount == 8 then
            self.bytes[#self.bytes + 1] = string.char(self.bitBuf)
            self.bitBuf = 0
            self.bitCount = 0
        end
    end
end

function BitWriter:Flush()
    if self.bitCount > 0 then
        self.bytes[#self.bytes + 1] = string.char(self.bitBuf)
        self.bitBuf = 0
        self.bitCount = 0
    end
    return table.concat(self.bytes)
end

-- ===== Deflate (fixed Huffman) =====
-- Фіксовані коди для літералів/довжин (RFC 1951, 3.2.6)
local function fixedLitCode(sym)
    if sym <= 143 then
        return 0x30 + sym, 8
    elseif sym <= 255 then
        return 0x190 + (sym - 144), 9
    elseif sym <= 279 then
        return sym - 256, 7
    else
        return 0xC0 + (sym - 280), 8
    end
end

-- Фіксовані коди для відстаней (5 біт)
local function fixedDistCode(dist)
    return dist, 5
end

-- Довжини та відстані для match (RFC 1951, 3.2.5)
local LENGTH_BASE = {
    3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258
}
local LENGTH_EXTRA = {
    0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0
}
local DIST_BASE = {
    1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577
}
local DIST_EXTRA = {
    0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13
}

local function FindLengthCode(length)
    for i = #LENGTH_BASE, 1, -1 do
        if length >= LENGTH_BASE[i] then
            return 257 + i - 1, length - LENGTH_BASE[i], LENGTH_EXTRA[i]
        end
    end
    return 257, 0, 0
end

local function FindDistCode(dist)
    for i = #DIST_BASE, 1, -1 do
        if dist >= DIST_BASE[i] then
            return i - 1, dist - DIST_BASE[i], DIST_EXTRA[i]
        end
    end
    return 0, 0, 0
end

-- ===== Deflate компресія (LZ77 + fixed Huffman) =====
local function Deflate(data)
    local writer = BitWriter.new()

    -- Заголовок блоку: BFINAL=1, BTYPE=01 (fixed Huffman)
    writer:WriteBits(1, 1)  -- BFINAL
    writer:WriteBits(1, 2)  -- BTYPE = 01 (fixed)

    local pos = 1
    local len = #data
    local windowSize = 32768
    local minMatch = 3
    local maxMatch = 258

    while pos <= len do
        local bestLen = 0
        local bestDist = 0

        -- LZ77: шукаємо найдовший match у вікні
        local searchStart = math.max(1, pos - windowSize)
        local searchEnd = pos - 1
        local maxLook = math.min(maxMatch, len - pos + 1)

        -- Швидкий пошук (тільки 4096 позицій назад для швидкості)
        local fastStart = math.max(searchStart, pos - 4096)

        for i = fastStart, searchEnd do
            local matchLen = 0
            while matchLen < maxLook and
                  data:sub(i + matchLen, i + matchLen) == data:sub(pos + matchLen, pos + matchLen) do
                matchLen = matchLen + 1
            end

            if matchLen > bestLen then
                bestLen = matchLen
                bestDist = pos - i
                if bestLen == maxLook then break end
            end
        end

        if bestLen >= minMatch then
            -- Match: пишемо length code + distance code
            local lengthSym, lengthExtra, lengthExtraBits = FindLengthCode(bestLen)
            local lenCode, lenBits = fixedLitCode(lengthSym)
            writer:WriteHuffCode(lenCode, lenBits)

            if lengthExtraBits > 0 then
                writer:WriteBits(lengthExtra, lengthExtraBits)
            end

            local distSym, distExtra, distExtraBits = FindDistCode(bestDist)
            local distCode, distBits = fixedDistCode(distSym)
            writer:WriteHuffCode(distCode, distBits)

            if distExtraBits > 0 then
                writer:WriteBits(distExtra, distExtraBits)
            end

            pos = pos + bestLen
        else
            -- Literal: пишемо байт
            local byte = string.byte(data, pos)
            local code, bits = fixedLitCode(byte)
            writer:WriteHuffCode(code, bits)
            pos = pos + 1
        end

        -- Даємо GC попрацювати
        if pos % 256 == 0 then coroutine.yield() end
    end

    -- End of block (символ 256)
    local endCode, endBits = fixedLitCode(256)
    writer:WriteHuffCode(endCode, endBits)

    return writer:Flush()
end

-- ===== Зібрати список файлів =====
local function collectFiles(fs, path, list)
    list = list or {}
    local items = fs.list(path)

    for _, item in ipairs(items) do
        local fullPath = path .. item
        if item:sub(-1) == "/" then
            table.insert(list, { path = fullPath, isDir = true })
            collectFiles(fs, fullPath, list)
        else
            table.insert(list, { path = fullPath, isDir = false })
        end
    end
    return list
end

-- ===== Прочитати файл =====
local function readFile(fs, path)
    local file = fs.open(path, "rb")
    if not file then return nil end

    local chunks = {}
    while true do
        local chunk = fs.read(file, 4096)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    fs.close(file)
    return table.concat(chunks)
end

-- ===== Створити ZIP =====
local function CreateZip(fs, sourcePath, targetPath, compressionLevel, statusCallback)
    local files = collectFiles(fs, sourcePath)
    local totalFiles = #files

    if totalFiles == 0 then
        return false, "No files found"
    end

    if statusCallback then
        statusCallback("Found " .. totalFiles .. " files")
    end

    local output = {}
    local centralDir = {}
    local offset = 0
    local processed = 0
    local totalCompressed = 0
    local totalUncompressed = 0

    for _, file in ipairs(files) do
        local name = file.path:sub(#sourcePath + 1)

        if file.isDir then
            name = name .. "/"
        end

        local content = ""
        local crc = 0
        local size = 0
        local compressed = ""
        local compSize = 0
        local method = 0

        if not file.isDir then
            content = readFile(fs, file.path) or ""
            crc = crc32(content)
            size = #content
            totalUncompressed = totalUncompressed + size

            if compressionLevel == 0 or size == 0 then
                compressed = content
                compSize = size
                method = 0
            else
                compressed = Deflate(content)
                compSize = #compressed
                method = 8

                -- Якщо Deflate не дав виграшу — пишемо Store
                if compSize >= size then
                    compressed = content
                    compSize = size
                    method = 0
                end
            end

            totalCompressed = totalCompressed + compSize
        end

        local dosTime, dosDate = dos_time()

        -- Local File Header
        local header = "PK\x03\x04"
        header = header .. writeU16(20)
        header = header .. writeU16(0)
        header = header .. writeU16(method)
        header = header .. writeU16(dosTime)
        header = header .. writeU16(dosDate)
        header = header .. writeU32(crc)
        header = header .. writeU32(compSize)
        header = header .. writeU32(size)
        header = header .. writeU16(#name)
        header = header .. writeU16(0)
        header = header .. name

        table.insert(output, header)
        table.insert(output, compressed)

        -- Central Directory
        local central = "PK\x01\x02"
        central = central .. writeU16(20)
        central = central .. writeU16(20)
        central = central .. writeU16(0)
        central = central .. writeU16(method)
        central = central .. writeU16(dosTime)
        central = central .. writeU16(dosDate)
        central = central .. writeU32(crc)
        central = central .. writeU32(compSize)
        central = central .. writeU32(size)
        central = central .. writeU16(#name)
        central = central .. writeU16(0)
        central = central .. writeU16(0)
        central = central .. writeU16(0)
        central = central .. writeU16(0)
        central = central .. writeU32(0)
        central = central .. writeU32(offset)
        central = central .. name

        table.insert(centralDir, central)

        offset = offset + #header + #compressed
        processed = processed + 1

        if statusCallback then
            local saved = size - compSize
            local pct = size > 0 and math.floor(compSize * 100 / size) or 100
            statusCallback(string.format("Packing: %s (%d/%d) %d%%",
                name, processed, totalFiles, pct))
        end
    end

    -- Central Directory
    local cdStart = offset
    local cdData = table.concat(centralDir)
    table.insert(output, cdData)

    -- EOCD
    local eocd = "PK\x05\x06"
    eocd = eocd .. writeU16(0)
    eocd = eocd .. writeU16(0)
    eocd = eocd .. writeU16(totalFiles)
    eocd = eocd .. writeU16(totalFiles)
    eocd = eocd .. writeU32(#cdData)
    eocd = eocd .. writeU32(cdStart)
    eocd = eocd .. writeU16(0)
    table.insert(output, eocd)

    if statusCallback then
        statusCallback("Writing ZIP file...")
    end

    local file = fs.open(targetPath, "wb")
    if not file then
        return false, "Could not create output file"
    end

    for _, chunk in ipairs(output) do
        fs.write(file, chunk)
    end
    fs.close(file)

    -- Повертаємо статистику
    return true, {
        files = totalFiles,
        uncompressed = totalUncompressed,
        compressed = totalCompressed
    }
end

-- ===== GUI =====
local function RunZip()
    local winW, winH = 64, 17
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2
    local clientW = winW - 2
    local clientH = winH - 3

    local fields = {
        { label = "Source:", value = "Windows/System32/", max = 40 },
        { label = "Target:", value = "Windows/System32/archive.zip", max = 40 },
        { label = "Level:",  value = "8", max = 1 },
    }
    local activeField = 1
    local statusText = "Ready"
    local processing = false

    local function DrawWindow()
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
        gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)

        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)
        gdi32.TextOut(hdc, winX + 2, winY + 1, " LuaZip - Compress Files")
        gdi32.SetTextColor(hdc, 0xFF0000)
        gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        for i, field in ipairs(fields) do
            gdi32.SetTextColor(hdc, 0x000000)
            gdi32.SetBkColor(hdc, 0xC0C0C0)
            gdi32.TextOut(hdc, clientX + 1, clientY + i, field.label)

            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
            gdi32.PatBlt(hdc, clientX + 9, clientY + i, clientW - 10, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, 0x000000)
            gdi32.SetBkColor(hdc, 0xFFFFFF)

            local display = field.value
            if i == activeField and not processing then display = display .. "_" end
            gdi32.TextOut(hdc, clientX + 10, clientY + i, display:sub(1, clientW - 12))
        end

        gdi32.SetTextColor(hdc, 0x000080)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 1, clientY + 5, "Compression:")
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.TextOut(hdc, clientX + 1, clientY + 6, "  0 = Store (no compression)")
        gdi32.TextOut(hdc, clientX + 1, clientY + 7, "  8 = Deflate (LZ77 + Huffman)")

        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 1, clientY + 9, "Status: " .. statusText:sub(1, clientW - 10))

        local btnY = winY + winH - 3
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
        gdi32.PatBlt(hdc, clientX + clientW - 20, btnY, 9, 2, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, clientX + clientW - 10, btnY, 9, 2, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xE0E0E0)
        gdi32.TextOut(hdc, clientX + clientW - 19, btnY, "[  OK  ]")
        gdi32.TextOut(hdc, clientX + clientW - 9, btnY, "[Cancel]")
    end

    DrawWindow()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 1 then return end
            if code == 15 then
                activeField = activeField + 1
                if activeField > #fields then activeField = 1 end
            elseif code == 14 then
                if #fields[activeField].value > 0 then
                    fields[activeField].value = fields[activeField].value:sub(1, -2)
                end
            elseif code == 28 then
                processing = true
                statusText = "Starting..."
                DrawWindow()

                local fs = component.proxy(computer.getBootAddress())
                local level = tonumber(fields[3].value) or 8

                local ok, result = pcall(CreateZip, fs,
                    fields[1].value,
                    fields[2].value,
                    level,
                    function(msg)
                        statusText = msg
                        DrawWindow()
                    end
                )

                processing = false
                if ok and type(result) == "table" then
                    local ratio = result.uncompressed > 0 and
                        math.floor(result.compressed * 100 / result.uncompressed) or 100
                    statusText = string.format("Done! %d files, %d%% ratio",
                        result.files, ratio)
                else
                    statusText = "Error: " .. tostring(result)
                end
                DrawWindow()

            elseif char >= 32 and char <= 126 then
                if #fields[activeField].value < fields[activeField].max then
                    fields[activeField].value = fields[activeField].value .. string.char(char)
                end
            end

            DrawWindow()

        elseif event == "touch" then
            local tx, ty = signal[3], signal[4]
            local btnY = winY + winH - 3

            if ty == winY + 1 and tx >= winX + winW - 5 then
                return
            end

            if ty == btnY and tx >= clientX + clientW - 20 and tx < clientX + clientW - 11 then
                processing = true
                statusText = "Starting..."
                DrawWindow()

                local fs = component.proxy(computer.getBootAddress())
                local level = tonumber(fields[3].value) or 8

                local ok, result = pcall(CreateZip, fs,
                    fields[1].value,
                    fields[2].value,
                    level,
                    function(msg)
                        statusText = msg
                        DrawWindow()
                    end
                )

                processing = false
                if ok and type(result) == "table" then
                    local ratio = result.uncompressed > 0 and
                        math.floor(result.compressed * 100 / result.uncompressed) or 100
                    statusText = string.format("Done! %d files, %d%% ratio",
                        result.files, ratio)
                else
                    statusText = "Error: " .. tostring(result)
                end
                DrawWindow()

            elseif ty == btnY and tx >= clientX + clientW - 10 and tx < clientX + clientW - 1 then
                return
            end
        end
    end
end

DbgPrint("LUAZIP: Starting LuaZip archiver...")
RunZip()
DbgPrint("LUAZIP: Closed.")

return true