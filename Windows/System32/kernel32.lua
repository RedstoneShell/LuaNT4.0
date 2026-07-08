local kernel32 = {}

function kernel32.GetCurrentProcessId()
    return 50
end

function kernel32.lstrlen(lpString)
    return #lpString
end

function kernel32.lstrcpy(lpString1, lpString2)
    local function unsafe_copy()
        if type(lpString1) ~= "table" then
            _G.DbgPrint("KERNEL32.StrCpy: Access Violation: lpString1 is not a buffer")
        end
        local src_str = tostring(lpString2 or "")
        for k in pairs(lpString1) do
            lpString1[k] = nil
        end
        for i = 1, #src_str do
            lpString1[i] = string.sub(src_str, i, i)
        end
        lpString1[#src_str + 1] = "\0"
        return lpString1
    end

    local success, result = pcall(unsafe_copy)
    
    if success then
        return result
    else
        return nil
    end
end

function kernel32.lstrcpyn(lpString1, lpString2, iMaxLength)
    local function unsafe_copy()
        if type(lpString1) ~= "table" then
            _G.DbgPrint("KERNEL32.StrCpyN: Access Violation: lpString1 is not a buffer")
            return nil
        end
        
        if type(iMaxLength) ~= "number" or iMaxLength <= 0 then
            return lpString1
        end

        local src_str = tostring(lpString2 or "")
        
        for k in pairs(lpString1) do
            lpString1[k] = nil
        end
        
        local max_chars_to_copy = iMaxLength - 1
        local actual_len = math.min(#src_str, max_chars_to_copy)
        
        for i = 1, actual_len do
            lpString1[i] = string.sub(src_str, i, i)
        end
        
        lpString1[actual_len + 1] = "\0"
        
        return lpString1
    end

    local success, result = pcall(unsafe_copy)
    
    if success then
        return result
    else
        return nil
    end
end

function kernel32.lstrcat(lpString1, lpString2)
    local function unsafe_copy()
        if type(lpString1) ~= "table" then
            _G.DbgPrint("KERNEL32.StrCat: Access Violation: lpString1 is not a buffer")
            return nil
        end
        
        local src_str = tostring(lpString2 or "")
        
        local start_index = 1
        for i = 1, #lpString1 do
            if lpString1[i] == "\0" then
                start_index = i
                break
            end
        end

        if start_index == 1 and lpString1[1] ~= "\0" then
            start_index = #lpString1 + 1
        end

        for i = 1, #src_str do
            local target_pos = start_index + i - 1
            lpString1[target_pos] = string.sub(src_str, i, i)
        end
        
        local final_null_pos = start_index + #src_str
        lpString1[final_null_pos] = "\0"
        
        local tail = final_null_pos + 1
        while lpString1[tail] ~= nil do
            lpString1[tail] = nil
            tail = tail + 1
        end
        
        return lpString1
    end

    local success, result = pcall(unsafe_copy)
    
    if success then
        return result
    else
        return nil
    end
end

return kernel32