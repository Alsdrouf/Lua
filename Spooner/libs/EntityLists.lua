local EntityLists = {}

function EntityLists.New(XMLParser, Logger)
    local self = {
        Props = {},      -- { [categoryName] = { {name, hash}, ... } }
        Vehicles = {},   -- { [categoryName] = { {name}, ... } }
        Peds = {},       -- { [categoryName] = { {name, caption}, ... } }
        -- Filter states for each tab
        PropFilter = "",
        VehicleFilter = "",
        PedFilter = "",
        -- Cache for model hash to name lookups
        NameCache = {}   -- { [modelHash] = displayName }
    }

    function self.LoadPropList(filePath)
        if not FileMgr.DoesFileExist(filePath) then
            Logger.Warn("PropList.xml not found at: " .. filePath)
            return false
        end

        local content = FileMgr.ReadFileContent(filePath)
        if not content or content == "" then
            Logger.Error("Failed to read PropList.xml")
            return false
        end

        self.Props = {}
        local parsed = XMLParser.Parse(content)

        for _, node in ipairs(parsed) do
            if node.tag == "PropList" then
                for _, categoryNode in ipairs(node.children or {}) do
                    if categoryNode.tag == "Category" then
                        local categoryName = categoryNode.attributes.name or "Unknown"
                        self.Props[categoryName] = {}

                        for _, propNode in ipairs(categoryNode.children or {}) do
                            if propNode.tag == "Prop" then
                                table.insert(self.Props[categoryName], {
                                    name = propNode.attributes.name or "",
                                    hash = propNode.attributes.hash or ""
                                })
                            end
                        end
                    end
                end
            end
        end

        local categoryCount = 0
        local propCount = 0
        for _, props in pairs(self.Props) do
            categoryCount = categoryCount + 1
            propCount = propCount + #props
        end

        Logger.Info("Loaded PropList: " .. categoryCount .. " categories, " .. propCount .. " props")
        return true
    end

    function self.LoadVehicleList(filePath)
        if not FileMgr.DoesFileExist(filePath) then
            Logger.Warn("VehicleList.xml not found at: " .. filePath)
            return false
        end

        local content = FileMgr.ReadFileContent(filePath)
        if not content or content == "" then
            Logger.Error("Failed to read VehicleList.xml")
            return false
        end

        self.Vehicles = {}
        local parsed = XMLParser.Parse(content)

        for _, node in ipairs(parsed) do
            if node.tag == "VehicleList" then
                for _, categoryNode in ipairs(node.children or {}) do
                    if categoryNode.tag == "Category" then
                        local categoryName = categoryNode.attributes.name or "Unknown"
                        self.Vehicles[categoryName] = {}

                        for _, vehicleNode in ipairs(categoryNode.children or {}) do
                            if vehicleNode.tag == "Vehicle" then
                                table.insert(self.Vehicles[categoryName], {
                                    name = vehicleNode.attributes.name or ""
                                })
                            end
                        end
                    end
                end
            end
        end

        local categoryCount = 0
        local vehicleCount = 0
        for _, vehicles in pairs(self.Vehicles) do
            categoryCount = categoryCount + 1
            vehicleCount = vehicleCount + #vehicles
        end

        Logger.Info("Loaded VehicleList: " .. categoryCount .. " categories, " .. vehicleCount .. " vehicles")
        return true
    end

    function self.LoadPedList(filePath)
        if not FileMgr.DoesFileExist(filePath) then
            Logger.Warn("PedList.xml not found at: " .. filePath)
            return false
        end

        local content = FileMgr.ReadFileContent(filePath)
        if not content or content == "" then
            Logger.Error("Failed to read PedList.xml")
            return false
        end

        self.Peds = {}
        local parsed = XMLParser.Parse(content)

        for _, node in ipairs(parsed) do
            if node.tag == "PedList" then
                for _, categoryNode in ipairs(node.children or {}) do
                    if categoryNode.tag == "Category" then
                        local categoryName = categoryNode.attributes.name or "Unknown"
                        self.Peds[categoryName] = {}

                        for _, pedNode in ipairs(categoryNode.children or {}) do
                            if pedNode.tag == "Ped" then
                                table.insert(self.Peds[categoryName], {
                                    name = pedNode.attributes.name or "",
                                    caption = pedNode.attributes.caption or ""
                                })
                            end
                        end
                    end
                end
            end
        end

        local categoryCount = 0
        local pedCount = 0
        for _, peds in pairs(self.Peds) do
            categoryCount = categoryCount + 1
            pedCount = pedCount + #peds
        end

        Logger.Info("Loaded PedList: " .. categoryCount .. " categories, " .. pedCount .. " peds")
        return true
    end

    function self.BuildNameCache()
        self.NameCache = {}

        -- Cache prop names by hash (use sJoaat for signed hash to match ENTITY.GET_ENTITY_MODEL)
        for _, props in pairs(self.Props) do
            for _, prop in ipairs(props) do
                local hash = Utils.sJoaat(prop.hash)
                self.NameCache[hash] = prop.name
            end
        end

        -- Cache ped names by hash (use sJoaat for signed hash to match ENTITY.GET_ENTITY_MODEL)
        for _, peds in pairs(self.Peds) do
            for _, ped in ipairs(peds) do
                local hash = Utils.sJoaat(ped.name)
                local displayName = (ped.caption and ped.caption ~= "") and ped.caption or ped.name
                self.NameCache[hash] = displayName
            end
        end

        Logger.Info("Built name cache with " .. tostring(#self.NameCache) .. " entries")
    end

    function self.LoadAll(propListPath, vehicleListPath, pedListPath)
        self.LoadPropList(propListPath)
        self.LoadVehicleList(vehicleListPath)
        self.LoadPedList(pedListPath)
        self.BuildNameCache()
    end

    return self
end

return EntityLists
