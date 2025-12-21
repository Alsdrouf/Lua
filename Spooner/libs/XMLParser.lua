local XMLParser = {}

function XMLParser.ParseAttributes(tag)
    local attrs = {}
    for name, value in string.gmatch(tag, '(%w+)="([^"]*)"') do
        attrs[name] = value
    end
    return attrs
end

function XMLParser.Parse(xmlString)
    -- Remove XML declaration and comments
    xmlString = xmlString:gsub("<%?[^?]*%?>", "")
    xmlString = xmlString:gsub("<!%-%-.-%-%->" , "")

    local result = {}
    local stack = {result}
    local current = result

    for closing, tagName, attrs, selfClosing in string.gmatch(xmlString, "<(/?)([%w_]+)(.-)%s*(/?)>") do
        if closing == "/" then
            table.remove(stack)
            current = stack[#stack]
        else
            local node = {
                tag = tagName,
                attributes = XMLParser.ParseAttributes(attrs),
                children = {}
            }

            if not current.children then
                current.children = {}
            end
            table.insert(current.children, node)

            if selfClosing ~= "/" then
                table.insert(stack, node)
                current = node
            end
        end
    end

    return result.children or {}
end

function XMLParser.EscapeAttribute(str)
    if type(str) ~= "string" then
        str = tostring(str)
    end
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub('"', "&quot;")
    str = str:gsub("'", "&apos;")
    return str
end

function XMLParser.GenerateXML(rootTag, options)
    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(lines, '<' .. rootTag .. '>')

    for key, value in pairs(options) do
        local escapedValue = XMLParser.EscapeAttribute(value)
        table.insert(lines, '    <Option name="' .. key .. '" value="' .. escapedValue .. '" />')
    end

    table.insert(lines, '</' .. rootTag .. '>')
    return table.concat(lines, '\n')
end

function XMLParser.ParseConfig(xmlString)
    local config = {}
    local parsed = XMLParser.Parse(xmlString)

    for _, node in ipairs(parsed) do
        if node.tag == "SpoonerConfig" then
            for _, optionNode in ipairs(node.children or {}) do
                if optionNode.tag == "Option" then
                    local name = optionNode.attributes.name
                    local value = optionNode.attributes.value
                    if name and value then
                        -- Convert string values to appropriate types
                        if value == "true" then
                            config[name] = true
                        elseif value == "false" then
                            config[name] = false
                        elseif tonumber(value) then
                            config[name] = tonumber(value)
                        else
                            config[name] = value
                        end
                    end
                end
            end
        end
    end

    return config
end

return XMLParser
