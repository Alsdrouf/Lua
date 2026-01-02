local SpoonerUtils = {}

function SpoonerUtils.New()
    local self = {}

    function self.SplitString(inputStr, separator)
        if separator == nil then
            separator = "%s"
        end
        local t = {}
        for str in string.gmatch(inputStr, "([^"..separator.."]+)") do
            table.insert(t, str)
        end
        return t
    end

    return self
end

return SpoonerUtils
