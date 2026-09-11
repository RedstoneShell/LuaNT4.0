-- robocopy.lua - Robocopy для LuaNT
-- (C) RedstoneShell 2026
-- Копіювання, синхронізація та бекапи файлів

local gdi32 = _G.KRNL_GDI32 or _G.LdrLoadDll("Windows/System32/gdi32.lua")
local ntdll = _G.LdrLoadDll("Windows/System32/ntdll.lua")

local hdc = gdi32.GetDC(0)
local screenW, screenH = _G.HAL.w, _G.HAL.h

-- ===== Статистика =====
local stats = {
    copied = 0,
    skipped = 0,
    failed = 0,
    dirs = 0,
    bytes = 0
}

-- ===== Рекурсивне копіювання =====
local function CopyFile(fs, src, dst, options)
    local srcFile = fs.open(src, "rb")
    if not srcFile then
        stats.failed = stats.failed + 1
        return false, "Cannot open source"
    end

    -- Читаємо вміст
    local chunks = {}
    while true do
        local chunk = fs.read(srcFile, 4096)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    fs.close(srcFile)

    local content = table.concat(chunks)

    -- Створюємо цільову директорію
    local dstDir = dst:match("(.+)/[^/]+$")
    if dstDir and not fs.exists(dstDir) then
        fs.makeDirectory(dstDir)
    end

    -- Записуємо
    local dstFile = fs.open(dst, "wb")
    if not dstFile then
        stats.failed = stats.failed + 1
        return false, "Cannot create target"
    end

    fs.write(dstFile, content)
    fs.close(dstFile)

    stats.copied = stats.copied + 1
    stats.bytes = stats.bytes + #content

    if options.verbose then
        DbgPrint("ROBOCOPY: Copied " .. src .. " -> " .. dst)
    end

    return true
end

-- ===== Рекурсивний обхід =====
local function CopyTree(fs, src, dst, options, statusCallback)
    local items = fs.list(src)

    for _, item in ipairs(items) do
        local srcPath = src .. item
        local dstPath = dst .. item

        -- Перевірка виключень
        local skip = false
        for _, pattern in ipairs(options.exclude or {}) do
            if item:match(pattern) then
                skip = true
                break
            end
        end

        if not skip then
            if item:sub(-1) == "/" then
                -- Директорія
                stats.dirs = stats.dirs + 1
                if not fs.exists(dstPath) then
                    fs.makeDirectory(dstPath)
                end
                CopyTree(fs, srcPath, dstPath, options, statusCallback)
            else
                -- Файл
                local dstFile = dstPath

                -- Перевірка, чи файл вже існує (skip logic)
                if options.skipExisting and fs.exists(dstFile) then
                    local srcSize = fs.size(srcPath)
                    local dstSize = fs.size(dstFile)

                    if srcSize == dstSize then
                        stats.skipped = stats.skipped + 1
                        goto continue
                    end
                end

                -- Копіюємо
                if statusCallback then
                    statusCallback("Copying: " .. item)
                end

                CopyFile(fs, srcPath, dstFile, options)
                coroutine.yield()
            end
        end

        ::continue::
    end
end

-- ===== Видалення зайвих файлів (Mirror) =====
local function PurgeExtra(fs, src, dst, options)
    if not fs.exists(dst) then return end

    local dstItems = fs.list(dst)

    for _, item in ipairs(dstItems) do
        local srcPath = src .. item
        local dstPath = dst .. item

        if not fs.exists(srcPath) then
            if item:sub(-1) == "/" then
                -- Видаляємо директорію рекурсивно
                DbgPrint("ROBOCOPY: Purging directory " .. dstPath)
                local dirItems = fs.list(dstPath)
                for _, subItem in ipairs(dirItems) do
                    fs.remove(dstPath .. subItem)
                end
                -- OpenOS не має видалення директорій напряму
            else
                DbgPrint("ROBOCOPY: Purging file " .. dstPath)
                fs.remove(dstPath)
            end
        end
    end
end

-- ===== Основна функція =====
local function RunRobocopy(fs, src, dst, options, statusCallback)
    -- Скидаємо статистику
    stats = { copied = 0, skipped = 0, failed = 0, dirs = 0, bytes = 0 }

    -- Перевірка існування джерела
    if not fs.exists(src) then
        return false, "Source not found: " .. src
    end

    -- Створюємо цільову директорію
    if not fs.exists(dst) then
        fs.makeDirectory(dst)
    end

    if statusCallback then
        statusCallback("Starting copy...")
    end

    -- Копіюємо
    CopyTree(fs, src, dst, options, statusCallback)

    -- Mirror: видаляємо зайве
    if options.mirror then
        if statusCallback then
            statusCallback("Purging extra files...")
        end
        PurgeExtra(fs, src, dst, options)
    end

    return true, stats
end

-- ===== GUI =====
local function RunGUI()
    local winW, winH = 64, 18
    local winX = math.floor((screenW - winW) / 2)
    local winY = math.floor((screenH - winH) / 2)

    local clientX = winX + 1
    local clientY = winY + 2
    local clientW = winW - 2
    local clientH = winH - 3

    local fields = {
        { label = "Source:", value = "Windows/System32/", max = 40 },
        { label = "Target:", value = "Windows/Backup/", max = 40 },
    }

    local options = {
        { label = "Mirror (delete extra)", value = false },
        { label = "Skip existing",        value = true },
        { label = "Verbose logging",      value = false },
    }

    -- ===== Фокус: 1..2 = поля, 3..5 = опції =====
    local focusIndex = 1
    local processing = false
    local statusText = "Ready"

    -- Координати опцій для кліку
    local optionY = clientY + 5
    local optionX = clientX + 2

    local function DrawWindow()
        -- Фон
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xC0C0C0))
        gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)

        -- 3D-рамка
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
        gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x808080))
        gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)

        -- Заголовок
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
        gdi32.PatBlt(hdc, winX + 1, winY + 1, winW - 2, 1, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0xFFFFFF)
        gdi32.SetBkColor(hdc, 0x000080)
        gdi32.TextOut(hdc, winX + 2, winY + 1, " Robocopy - File Replication")
        gdi32.SetTextColor(hdc, 0xFF0000)
        gdi32.TextOut(hdc, winX + winW - 4, winY + 1, "[X]")

        -- Поля
        for i, field in ipairs(fields) do
            gdi32.SetTextColor(hdc, 0x000000)
            gdi32.SetBkColor(hdc, 0xC0C0C0)
            gdi32.TextOut(hdc, clientX + 1, clientY + i, field.label)

            gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xFFFFFF))
            gdi32.PatBlt(hdc, clientX + 9, clientY + i, clientW - 10, 1, gdi32.PATCOPY)
            gdi32.SetTextColor(hdc, 0x000000)
            gdi32.SetBkColor(hdc, 0xFFFFFF)

            local display = field.value
            if i == focusIndex and not processing then display = display .. "_" end
            gdi32.TextOut(hdc, clientX + 10, clientY + i, display:sub(1, clientW - 12))
        end

        -- Опції
        gdi32.SetTextColor(hdc, 0x000080)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 1, clientY + 4, "Options:")

        for i, opt in ipairs(options) do
            local mark = opt.value and "[X]" or "[ ]"
            local focusMarker = (focusIndex == #fields + i) and ">" or " "

            -- Підсвітка вибраної опції
            if focusIndex == #fields + i then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x000080))
                gdi32.PatBlt(hdc, optionX - 1, optionY + i - 1, clientW - 4, 1, gdi32.PATCOPY)
                gdi32.SetTextColor(hdc, 0xFFFFFF)
            else
                gdi32.SetTextColor(hdc, 0x000000)
            end
            gdi32.SetBkColor(hdc, 0xC0C0C0)

            gdi32.TextOut(hdc, optionX, optionY + i - 1, focusMarker .. " " .. mark .. " " .. opt.label)
        end

        -- Підказка
        gdi32.SetTextColor(hdc, 0x808080)
        gdi32.SetBkColor(hdc, 0xC0C0C0)
        gdi32.TextOut(hdc, clientX + 1, clientY + 9, "[TAB] next  [SPACE] toggle  1/2/3 quick toggle")

        -- Статус
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.TextOut(hdc, clientX + 1, clientY + 10, "Status: " .. statusText:sub(1, clientW - 10))

        -- Статистика
        gdi32.TextOut(hdc, clientX + 1, clientY + 11,
            string.format("Copied: %d | Skipped: %d | Failed: %d | Dirs: %d",
            stats.copied, stats.skipped, stats.failed, stats.dirs))

        -- Кнопки
        local btnY = winY + winH - 3
        gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0xE0E0E0))
        gdi32.PatBlt(hdc, clientX + clientW - 20, btnY, 9, 2, gdi32.PATCOPY)
        gdi32.PatBlt(hdc, clientX + clientW - 10, btnY, 9, 2, gdi32.PATCOPY)
        gdi32.SetTextColor(hdc, 0x000000)
        gdi32.SetBkColor(hdc, 0xE0E0E0)
        gdi32.TextOut(hdc, clientX + clientW - 19, btnY, "[  OK  ]")
        gdi32.TextOut(hdc, clientX + clientW - 9, btnY, "[Cancel]")
    end

    -- ===== Перемикання опції =====
    local function ToggleOption(index)
        if options[index] then
            options[index].value = not options[index].value
            DbgPrint("ROBOCOPY: Option '" .. options[index].label .. "' = " .. tostring(options[index].value))
        end
    end

    -- ===== Обробка кліку =====
    local function HandleClick(tx, ty)
        -- Закриття
        if ty == winY + 1 and tx >= winX + winW - 5 then
            return "close"
        end

        -- Клік по полях
        for i = 1, #fields do
            if ty == clientY + i and tx >= clientX + 9 and tx <= clientX + clientW - 1 then
                focusIndex = i
                return
            end
        end

        -- Клік по опціях
        for i = 1, #options do
            local optRow = optionY + i - 1
            if ty == optRow and tx >= optionX and tx <= optionX + 40 then
                focusIndex = #fields + i
                ToggleOption(i)
                return
            end
        end

        -- Кнопки
        local btnY = winY + winH - 3
        if ty == btnY then
            if tx >= clientX + clientW - 20 and tx < clientX + clientW - 11 then
                return "ok"
            elseif tx >= clientX + clientW - 10 and tx < clientX + clientW - 1 then
                return "cancel"
            end
        end

        return nil
    end

    -- ===== Запуск копіювання =====
    local function StartCopy()
        processing = true
        statusText = "Starting..."
        DrawWindow()

        local fs = component.proxy(computer.getBootAddress())

        local opt = {
            mirror       = options[1].value,
            skipExisting = options[2].value,
            verbose      = options[3].value,
            exclude      = { "%.tmp$", "%.log$" }
        }

        local ok, _, result = pcall(RunRobocopy(fs,
            fields[1].value,
            fields[2].value,
            opt,
            function(msg)
                statusText = msg
                DrawWindow()
                coroutine.yield()
            end
        ))

        processing = false
        if ok and type(result) == "table" then
            statusText = string.format("Done! Copied: %d | Skipped: %d | Failed: %d",
                result.copied, result.skipped, result.failed)
        else
            statusText = "Error: " .. tostring(result)
        end
        DrawWindow()
    end

    DrawWindow()
    coroutine.yield()

    while true do
        local signal = { computer.pullSignal(0.2) }
        local event = signal[1]

        if event == "key_down" then
            local char, code = signal[3], signal[4]

            if code == 1 then
                return

            elseif code == 15 then -- TAB
                focusIndex = focusIndex + 1
                if focusIndex > #fields + #options then focusIndex = 1 end

            elseif code == 57 or char == 32 then -- SPACE
                if focusIndex > #fields then
                    ToggleOption(focusIndex - #fields)
                end

            elseif char == 49 then -- '1'
                ToggleOption(1)
            elseif char == 50 then -- '2'
                ToggleOption(2)
            elseif char == 51 then -- '3'
                ToggleOption(3)

            elseif code == 14 then -- BACKSPACE
                if focusIndex <= #fields and #fields[focusIndex].value > 0 then
                    fields[focusIndex].value = fields[focusIndex].value:sub(1, -2)
                end

            elseif code == 28 then -- ENTER
                if focusIndex > #fields then
                    ToggleOption(focusIndex - #fields)
                else
                    StartCopy()
                end

            elseif char >= 32 and char <= 126 then
                if focusIndex <= #fields and #fields[focusIndex].value < fields[focusIndex].max then
                    fields[focusIndex].value = fields[focusIndex].value .. string.char(char)
                end
            end

            DrawWindow()
            coroutine.yield()

        elseif event == "touch" then
            local result = HandleClick(signal[3], signal[4])
            if result == "close" or result == "cancel" then
                gdi32.SelectObject(hdc, gdi32.CreateSolidBrush(0x008080))
                gdi32.PatBlt(hdc, winX, winY, winW, 1, gdi32.PATCOPY)
                gdi32.PatBlt(hdc, winX, winY, 1, winH, gdi32.PATCOPY)
                gdi32.PatBlt(hdc, winX, winY + winH - 1, winW, 1, gdi32.PATCOPY)
                gdi32.PatBlt(hdc, winX + winW - 1, winY, 1, winH, gdi32.PATCOPY)
                gdi32.PatBlt(hdc, winX, winY, winW, winH, gdi32.PATCOPY)
                return
            elseif result == "ok" then
                StartCopy()
            end
            DrawWindow()
            coroutine.yield()
        end

        coroutine.yield()
    end
end

DbgPrint("ROBOCOPY: Starting Robocopy...")
RunGUI()
DbgPrint("ROBOCOPY: Closed.")

return true