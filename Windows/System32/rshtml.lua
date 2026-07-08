-- rshtml.lua - RedstoneShell HTML Parser
-- (C) RedstoneShell 2026

local rshtml = {}

local function replaceCI(str, tag, repl)
    str = str:gsub("<%s*" .. tag .. "[^>]->", repl)
    str = str:gsub("</%s*" .. tag .. "%s*>", repl)
    return str
end

function rshtml.DecodeEntities(text)
    local entities = {
        nbsp = " ",
        amp  = "&",
        lt   = "<",
        gt   = ">",
        quot = "\"",
        apos = "'",
        copy = "(c)",
        reg  = "(R)",
        trade = "(TM)",
        mdash = "—",
        ndash = "-",
        hellip = "...",
    }

    text = text:gsub("&#(%d+);", function(n)
        n = tonumber(n)
        if n and n >= 32 and n <= 255 then
            return string.char(n)
        end
        return ""
    end)

    text = text:gsub("&#x([0-9A-Fa-f]+);", function(h)
        local n = tonumber(h, 16)
        if n and n >= 32 and n <= 255 then
            return string.char(n)
        end
        return ""
    end)

    text = text:gsub("&([%w]+);", function(name)
        return entities[name] or ""
    end)

    return text
end

function rshtml.ToText(html)
    if not html then
        return ""
    end

    local text = html
    text = text:gsub("<!%-%-.-%-%->", "")
    text = text:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt].->.-</[Ss][Cc][Rr][Ii][Pp][Tt]>", "")
    text = text:gsub("<[Ss][Tt][Yy][Ll][Ee].->.-</[Ss][Tt][Yy][Ll][Ee]>", "")
    text = text:gsub("<[Hh][Ee][Aa][Dd].->.-</[Hh][Ee][Aa][Dd]>", "")
    text = text:gsub("<[Bb][Rr]%s*/?>", "\n")

    for i=1,6 do
        text = replaceCI(text, "[Hh]"..i, "\n\n")
    end
    local blockTags = {
        "[Pp]",
        "[Dd][Ii][Vv]",
        "[Ss][Ee][Cc][Tt][Ii][Oo][Nn]",
        "[Aa][Rr][Tt][Ii][Cc][Ll][Ee]",
        "[Hh][Rr]",
        "[Ff][Oo][Oo][Tt][Ee][Rr]",
        "[Hh][Ee][Aa][Dd][Ee][Rr]",
        "[Nn][Aa][Vv]",
        "[Aa][Ss][Ii][Dd][Ee]",
        "[Mm][Aa][Ii][Nn]",
        "[Ff][Oo][Rr][Mm]",
        "[Tt][Aa][Bb][Ll][Ee]",
        "[Tt][Rr]",
        "[Uu][Ll]",
        "[Oo][Ll]",
        "[Pp][Rr][Ee]",
        "[Bb][Ll][Oo][Cc][Kk][Qq][Uu][Oo][Tt][Ee]"
    }

    for _,tag in ipairs(blockTags) do
        text = replaceCI(text, tag, "\n")
    end

    text = text:gsub("<[Ll][Ii][^>]->", "\n • ")
    text = text:gsub("</[Tt][Dd]>", "\t")
    text = text:gsub("</[Tt][Hh]>", "\t")
    text = text:gsub("<[Aa][^>]-href%s*=%s*['\"]([^'\"]+)['\"][^>]->(.-)</[Aa]>", "%2 (%1)")
    text = text:gsub("<[Ii][Mm][Gg][^>]-alt%s*=%s*['\"]([^'\"]+)['\"][^>]->", "[Image: %1]")
    text = text:gsub("<[Ii][Mm][Gg][^>]->", "")
    text = text:gsub("<[Bb]>(.-)</[Bb]>", "%1")
    text = text:gsub("<[Ss][Tt][Rr][Oo][Nn][Gg]>(.-)</[Ss][Tt][Rr][Oo][Nn][Gg]>", "%1")
    text = text:gsub("<[Ii]>(.-)</[Ii]>", "%1")
    text = text:gsub("<[Ee][Mm]>(.-)</[Ee][Mm]>", "%1")
    text = text:gsub("<[Cc][Oo][Dd][Ee]>(.-)</[Cc][Oo][Dd][Ee]>", "%1")
    text = text:gsub("<[^>]->", "")
    text = rshtml.DecodeEntities(text)
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    text = text:gsub("[ \t]+", " ")
    text = text:gsub(" *\n *", "\n")
    text = text:gsub("\n\n\n+", "\n\n")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")

    return text
end

return rshtml