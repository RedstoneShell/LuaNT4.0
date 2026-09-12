local basic = {}
local program = {}
local line_numbers = {}
local variables = {}

local gpu = _G.HAL and _G.HAL.gpu or component.proxy(component.list("gpu")())
local keyboard_address = component.list("keyboard")()

local function check_scroll()
    if _G.HAL and _G.HAL.CursorY then
        local w, h = gpu.getResolution()
        if _G.HAL.CursorY > h then
            gpu.copy(1, 2, w, h - 1, 0, -1)
            gpu.fill(1, h, w, 1, " ")
            _G.HAL.CursorY = h
        end
    end
end

local function ShellPrint(text)
    if _G.HAL and _G.HAL.CursorY then
        local w, h = gpu.getResolution()
        check_scroll()
        gpu.set(1, _G.HAL.CursorY, tostring(text))
        _G.HAL.CursorY = _G.HAL.CursorY + 1
        check_scroll()
    else
        DbgPrint(text)
    end
end

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function evaluate(expr)
    expr = trim(expr)
    if expr == "" then return 0 end

    local func, f_arg = expr:match("^([%a_][%w_]*)%s*%((.*)%)$")
    if func then
        local fn = func:upper()
        if fn == "SIN" or fn == "COS" or fn == "SQRT" or fn == "ABS" then
            local arg_val = evaluate(f_arg)
            if fn == "SIN"  then return math.sin(arg_val) end
            if fn == "COS"  then return math.cos(arg_val) end
            if fn == "SQRT" then return math.sqrt(arg_val) end
            if fn == "ABS"  then return math.abs(arg_val) end
        end
    end

    local sub_expr = expr:match("%(([^()]+)%)")
    if sub_expr then
        local val = evaluate(sub_expr)
        local safe_val = tostring(val):gsub("%%", "%%%%")
        local escaped = sub_expr:gsub("([%^%$%%%.%*%+%-%?%[%]%(%)])", "%%%1")
        local new_expr = expr:gsub("%(" .. escaped .. "%)", safe_val, 1)
        return evaluate(new_expr)
    end

    for _, op in ipairs({"<=", ">=", "<>", "=", "<", ">"}) do
        local p = expr:find(op, 1, true)
        if p then
            local left  = evaluate(expr:sub(1, p - 1))
            local right = evaluate(expr:sub(p + #op))
            if op == "="  then return left == right and 1 or 0 end
            if op == "<"  then return left <  right and 1 or 0 end
            if op == ">"  then return left >  right and 1 or 0 end
            if op == "<=" then return left <= right and 1 or 0 end
            if op == ">=" then return left >= right and 1 or 0 end
            if op == "<>" then return left ~= right and 1 or 0 end
        end
    end

    local depth = 0
    for i = 1, #expr do
        local c = expr:sub(i, i)
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
        elseif depth == 0 and (c == "+" or c == "-") and i > 1 then
            local prev = expr:sub(i - 1, i - 1)
            if not prev:match("[%*%/%+%-%^%(]") then
                local left  = evaluate(expr:sub(1, i - 1))
                local right = evaluate(expr:sub(i + 1))
                return c == "+" and left + right or left - right
            end
        end
    end

    depth = 0
    for i = 1, #expr do
        local c = expr:sub(i, i)
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
        elseif depth == 0 and (c == "*" or c == "/") and i > 1 then
            local left  = evaluate(expr:sub(1, i - 1))
            local right = evaluate(expr:sub(i + 1))
            if c == "/" then
                if right == 0 then
                    ShellPrint("MATH ERROR: DIVISION BY ZERO")
                    return 0
                end
                return left / right
            end
            return left * right
        end
    end

    local unary = expr:match("^%-(.+)$")
    if unary then
        return -evaluate(unary)
    end

    local num = expr:match("^%-?%d+%.?%d*$")
    if num then
        return tonumber(num) or 0
    end

    local var = expr:upper()
    return variables[var] or 0
end

local function execute_statement(statement)
    statement = trim(statement)
    if statement == "" then return nil end

    local upper = statement:upper()

    if upper:sub(1, 5) == "PRINT" then
        local args = trim(statement:sub(6))
        local str = args:match('^"(.-)"$')
        if str then
            ShellPrint(str)
        else
            ShellPrint(tostring(evaluate(args)))
        end
        return nil
    end

    if upper:sub(1, 2) == "IF" then
        local then_pos = upper:find("THEN", 3, true)
        if then_pos then
            local cond = statement:sub(3, then_pos - 1)
            local action = trim(statement:sub(then_pos + 4))
            if evaluate(cond) ~= 0 then
                if tonumber(action) then return tonumber(action) end
                return execute_statement(action)
            end
        else
            ShellPrint("SYNTAX ERROR: MISSING THEN")
        end
        return nil
    end

    if upper:sub(1, 4) == "GOTO" then
        return tonumber(trim(statement:sub(5)))
    end

    local eq_pos = statement:find("=", 1, true)
    if eq_pos then
        local var = trim(statement:sub(1, eq_pos - 1)):upper()
        local val = statement:sub(eq_pos + 1)
        if var:match("^[A-Z_][%w_]*$") then
            variables[var] = evaluate(val)
        else
            ShellPrint("SYNTAX ERROR: INVALID VARIABLE NAME")
        end
        return nil
    end

    ShellPrint("SYNTAX ERROR: " .. statement)
    return nil
end

local function refresh_line_numbers()
    line_numbers = {}
    for num in pairs(program) do
        table.insert(line_numbers, num)
    end
    table.sort(line_numbers)
end

local function run_program()
    refresh_line_numbers()
    local pc = 1
    while pc <= #line_numbers do
        local line = line_numbers[pc]
        local jump = execute_statement(program[line])
        if jump then
            local found = false
            for idx, num in ipairs(line_numbers) do
                if num == jump then
                    pc = idx
                    found = true
                    break
                end
            end
            if not found then
                ShellPrint("LINE " .. line .. ": GOTO TARGET " .. jump .. " NOT FOUND")
                break
            end
        else
            pc = pc + 1
        end
    end
end

local function read_line()
    check_scroll()
    local current_y = _G.HAL and _G.HAL.CursorY or 1
    gpu.set(1, current_y, "> ")
    local input_str = ""
    local cursor_idx = 1
    local start_x = 3

    while true do
        current_y = _G.HAL and _G.HAL.CursorY or 1
        local total_len = unicode.len(input_str)
        local display_str = input_str .. " "
        gpu.set(start_x, current_y, display_str)
        gpu.set(start_x + cursor_idx - 1, current_y, "_")

        local event, addr, char, code = computer.pullSignal()
        if event == "key_down" then
            local old_char = unicode.sub(display_str, cursor_idx, cursor_idx)
            if old_char == "" then old_char = " " end
            gpu.set(start_x + cursor_idx - 1, current_y, old_char)

            if char == 13 then
                gpu.set(start_x, current_y, input_str .. " ")
                if _G.HAL and _G.HAL.CursorY then
                    _G.HAL.CursorY = _G.HAL.CursorY + 1
                    check_scroll()
                end
                return input_str
            else
                if char == 8 then
                    if cursor_idx > 1 then
                        local left_part = unicode.sub(input_str, 1, cursor_idx - 2)
                        local right_part = unicode.sub(input_str, cursor_idx, total_len)
                        input_str = left_part .. right_part
                        cursor_idx = cursor_idx - 1
                        gpu.set(start_x, current_y, input_str .. "  ")
                    end
                elseif code == 203 then
                    if cursor_idx > 1 then
                        cursor_idx = cursor_idx - 1
                    end
                elseif code == 205 then
                    if cursor_idx <= total_len then
                        cursor_idx = cursor_idx + 1
                    end
                elseif char > 0 then
                    local left_part = unicode.sub(input_str, 1, cursor_idx - 1)
                    local right_part = unicode.sub(input_str, cursor_idx, total_len)
                    input_str = left_part .. unicode.char(char) .. right_part
                    cursor_idx = cursor_idx + 1
                end
            end
        end
    end
end

function basic.DriverEntry()
    DbgPrint("BASIC: Initializing BASIC shell, before loading shell 5s...")
    _G.KeDelayExecutionThread(5)

    local w, h = gpu.getResolution()
    gpu.fill(1, 1, w, h, " ")
    if _G.HAL then _G.HAL.CursorY = 1 end
    _G.DbgPrintToFile = false

    ShellPrint("RedstoneShell BASIC v1.5 (Fixed Scrolling)")
    ShellPrint(computer.freeMemory() .. " BYTES FREE")
    ShellPrint("")
    ShellPrint("READY.")

    while true do
        local input = trim(read_line())
        if input ~= "" then
            local line_num_str = input:match("^(%d+)")
            if line_num_str then
                local num = tonumber(line_num_str)
                local stmt = trim(input:sub(#line_num_str + 1))
                program[num] = (stmt == "") and nil or stmt
            else
                local cmd = input:upper()
                if cmd == "RUN" then
                    run_program()
                    ShellPrint("READY.")
                elseif cmd == "LIST" then
                    refresh_line_numbers()
                    for _, num in ipairs(line_numbers) do
                        ShellPrint(num .. " " .. program[num])
                    end
                    ShellPrint("READY.")
                elseif cmd == "NEW" then
                    program, variables, line_numbers = {}, {}, {}
                    ShellPrint("READY.")
                elseif cmd == "EXIT" then
                    ShellPrint("Exiting BASIC...")
                    break
                else
                    execute_statement(input)
                end
            end
        end
        _G.KeDelayExecutionThread(0.1)
    end
end

return basic.DriverEntry()