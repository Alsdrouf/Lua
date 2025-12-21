local CustomLogger = {}

function CustomLogger.New(pluginName)
    local self = {}
    self.pluginName = pluginName

    function self.Info(str)
        Logger.Log(eLogColor.WHITE, self.pluginName, str)
    end

    function self.Warn(str)
        Logger.Log(eLogColor.YELLOW, self.pluginName, str)
    end

    function self.Error(str)
        Logger.Log(eLogColor.RED, self.pluginName, str)
    end

    return self
end

return CustomLogger
