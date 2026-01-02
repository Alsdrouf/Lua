local SpoonerUI = {}

function SpoonerUI.New(deps)
    local Spooner = deps.Spooner
    local Spawner = deps.Spawner
    local DrawManager = deps.DrawManager
    local EntityLists = deps.EntityLists
    local SpoonerUtils = deps.SpoonerUtils
    local spoonerSavePath = deps.spoonerSavePath
    local pluginName = deps.pluginName
    local Config = deps.Config

    local self = {}

    function self.Init()
        ClickGUI.AddPlayerTab(pluginName, function()
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableAtPlayer"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_FollowPlayer"))
        end)

        ClickGUI.AddTab(pluginName, function()
            if ImGui.BeginTabBar("SpoonerMainTabs", 0) then
                -- Main subtab
                if ImGui.BeginTabItem("Main") then
                    if ClickGUI.BeginCustomChildWindow("Spooner") then
                        ClickGUI.RenderFeature(Utils.Joaat("ToggleSpoonerMode"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableF9Key"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableThrowableMode"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableClipToGround"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_SpawnUnnetworked"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_LockMovementWhileMenuIsOpen"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_LockMovementWhileMenuIsOpenEnhanced"))
                        ClickGUI.EndCustomChildWindow()
                    end
                    ImGui.EndTabItem()
                end

                -- Database subtab
                if ImGui.BeginTabItem("Database") then
                    if ClickGUI.BeginCustomChildWindow("Managed Entities") then
                        local vehicles = {}
                        local peds = {}
                        local props = {}

                        for i, managed in ipairs(Spooner.managedEntities) do
                            if ENTITY.DOES_ENTITY_EXIST(managed.entity) then
                                if ENTITY.IS_ENTITY_A_VEHICLE(managed.entity) then
                                    table.insert(vehicles, {index = i, entity = managed.entity, networkId = managed.networkId, networked = managed.networked})
                                elseif ENTITY.IS_ENTITY_A_PED(managed.entity) then
                                    table.insert(peds, {index = i, entity = managed.entity, networkId = managed.networkId, networked = managed.networked})
                                else
                                    table.insert(props, {index = i, entity = managed.entity, networkId = managed.networkId, networked = managed.networked})
                                end
                            end
                        end

                        if ImGui.BeginTabBar("DatabaseTabs", 0) then
                            -- Vehicles Tab
                            if ImGui.BeginTabItem("Vehicles (" .. #vehicles .. ")###VehiclesTab") then
                                if #vehicles == 0 then
                                    ImGui.Text("No vehicles in database")
                                else
                                    for _, item in ipairs(vehicles) do
                                        local label = DrawManager.GetEntityName(item.entity, item.networkId, item.networked)
                                        local isSelected = (item.index == Spooner.selectedEntityIndex)
                                        if ImGui.Selectable(label .. "##veh_" .. item.index, isSelected) then
                                            if (not Spooner.quickEditEntity or Spooner.quickEditEntity.entity ~= item.entity) and Spooner.selectedEntityIndex ~= item.index then
                                                Script.QueueJob(function()
                                                    Spooner.SelectEntityForQuickEdit(item.entity)
                                                end)
                                            end
                                        end
                                    end
                                end
                                ImGui.EndTabItem()
                            end

                            -- Peds Tab
                            if ImGui.BeginTabItem("Peds (" .. #peds .. ")###PedsTab") then
                                if #peds == 0 then
                                    ImGui.Text("No peds in database")
                                else
                                    for _, item in ipairs(peds) do
                                        local label = DrawManager.GetEntityName(item.entity, item.networkId, item.networked)
                                        local isSelected = (item.index == Spooner.selectedEntityIndex)
                                        if ImGui.Selectable(label .. "##ped_" .. item.index, isSelected) then
                                            if (not Spooner.quickEditEntity or Spooner.quickEditEntity.entity ~= item.entity) and Spooner.selectedEntityIndex ~= item.index then
                                                Script.QueueJob(function()
                                                    Spooner.SelectEntityForQuickEdit(item.entity)
                                                end)
                                            end
                                        end
                                    end
                                end
                                ImGui.EndTabItem()
                            end

                            -- Props Tab
                            if ImGui.BeginTabItem("Props (" .. #props .. ")###PropsTab") then
                                if #props == 0 then
                                    ImGui.Text("No props in database")
                                else
                                    for _, item in ipairs(props) do
                                        local label = DrawManager.GetEntityName(item.entity, item.networkId, item.networked)
                                        local isSelected = (item.index == Spooner.selectedEntityIndex)
                                        if ImGui.Selectable(label .. "##prop_" .. item.index, isSelected) then
                                            if (not Spooner.quickEditEntity or Spooner.quickEditEntity.entity ~= item.entity) and Spooner.selectedEntityIndex ~= item.index then
                                                Script.QueueJob(function()
                                                    Spooner.SelectEntityForQuickEdit(item.entity)
                                                end)
                                            end
                                        end
                                    end
                                end
                                ImGui.EndTabItem()
                            end

                            -- All Tab
                            local totalCount = #Spooner.managedEntities
                            if ImGui.BeginTabItem("All (" .. totalCount .. ")###AllTab") then
                                ImGui.Spacing()
                                ClickGUI.RenderFeature(Utils.Joaat("Spooner_RemoveAll"))
                                ClickGUI.RenderFeature(Utils.Joaat("Spooner_DeleteAll"))
                                ImGui.EndTabItem()
                            end

                            ImGui.EndTabBar()
                        end

                        ImGui.Separator()
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_RemoveEntity"))
                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_DeleteEntity"))

                        ImGui.Separator()
                        ImGui.Text("Save")
                        ImGui.Separator()

                        local newFileName, fileNameChanged = ImGui.InputText("File Name", Spooner.saveFileName, 256)
                        if fileNameChanged and type(newFileName) == "string" then
                            Spooner.saveFileName = newFileName
                        end

                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_SaveDatabaseToXML"))

                        ClickGUI.EndCustomChildWindow()
                    end

                    -- Entity Transform Section
                    if ClickGUI.BeginCustomChildWindow("Entity Transform") then
                        local entity, isInDatabase, networkId, networked = Spooner.GetEditingEntity()
                        if entity then
                            local pos = ENTITY.GET_ENTITY_COORDS(entity, true)
                            local rot = ENTITY.GET_ENTITY_ROTATION(entity, 2)

                            local entityName = DrawManager.GetEntityName(entity, networkId, networked)
                            ImGui.Text("Editing: " .. entityName)
                            if not isInDatabase then
                                ImGui.SameLine()
                                ImGui.TextColored(1.0, 0.7, 0.0, 1.0, "(Quick Edit)")
                            end
                            ImGui.Separator()

                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_FreezeSelectedEntity"))
                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_DynamicEntity"))
                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_GodModeEntity"))
                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_NetworkedEntity"))
                            ImGui.Spacing()

                            ImGui.Text("Position")
                            ImGui.Separator()

                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_PositionStep"))

                            local newX, changedX = ImGui.SliderFloat("X##pos", pos.x, pos.x - Config.positionStep, pos.x + Config.positionStep)
                            if changedX then
                                Script.QueueJob(function()
                                    Spooner.TakeControlOfEntity(entity)
                                    ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, newX, pos.y, pos.z, false, false, false)
                                end)
                            end

                            local newY, changedY = ImGui.SliderFloat("Y##pos", pos.y, pos.y - Config.positionStep, pos.y + Config.positionStep)
                            if changedY then
                                Script.QueueJob(function()
                                    Spooner.TakeControlOfEntity(entity)
                                    ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, pos.x, newY, pos.z, false, false, false)
                                end)
                            end

                            local newZ, changedZ = ImGui.SliderFloat("Z##pos", pos.z, pos.z - Config.positionStep, pos.z + Config.positionStep)
                            if changedZ then
                                Script.QueueJob(function()
                                    Spooner.TakeControlOfEntity(entity)
                                    ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, pos.x, pos.y, newZ, false, false, false)
                                end)
                            end

                            ImGui.Spacing()
                            ImGui.Text("Rotation")
                            ImGui.Separator()

                            local newPitch, changedPitch = ImGui.SliderFloat("Pitch##rot", rot.x, -89.0, 89.0)
                            if changedPitch then
                                Script.QueueJob(function()
                                    Spooner.TakeControlOfEntity(entity)
                                    ENTITY.SET_ENTITY_ROTATION(entity, newPitch, rot.y, rot.z, 2, true)
                                end)
                            end

                            local newRoll, changedRoll = ImGui.SliderFloat("Roll##rot", rot.y, -89.0, 89.0)
                            if changedRoll then
                                Script.QueueJob(function()
                                    Spooner.TakeControlOfEntity(entity)
                                    ENTITY.SET_ENTITY_ROTATION(entity, rot.x, newRoll, rot.z, 2, true)
                                end)
                            end

                            local newYaw, changedYaw = ImGui.SliderFloat("Yaw##rot", rot.z, -180.0, 180.0)
                            if changedYaw then
                                Script.QueueJob(function()
                                    Spooner.TakeControlOfEntity(entity)
                                    ENTITY.SET_ENTITY_ROTATION(entity, rot.x, rot.y, newYaw, 2, true)
                                end)
                            end

                            ImGui.Spacing()
                            ImGui.Separator()

                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_TeleportToEntity"))
                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_TeleportEntityHere"))

                            ImGui.Spacing()
                            ImGui.Separator()
                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_DeleteEntity"))

                            ImGui.Spacing()
                            if not isInDatabase then
                                ClickGUI.RenderFeature(Utils.Joaat("Spooner_AddToDatabase"))
                            else
                                ClickGUI.RenderFeature(Utils.Joaat("Spooner_RemoveEntity"))
                            end
                        else
                            ImGui.Text("No entity selected")
                            ImGui.Spacing()
                            ImGui.TextWrapped("Select an entity from the database above, or right-click an entity in Spooner mode to edit it.")
                        end

                        ClickGUI.EndCustomChildWindow()
                    end
                    ImGui.EndTabItem()
                end

                -- Spawner subtab
                if ImGui.BeginTabItem("Spawner") then
                    if ClickGUI.BeginCustomChildWindow("Entity Spawner") then
                        if ImGui.BeginTabBar("SpawnerTabs", 0) then
                            -- Props Tab
                            if ImGui.BeginTabItem("Props") then
                                local newPropFilter, propFilterChanged = ImGui.InputText("Prop Filter", EntityLists.PropFilter, 256)
                                if propFilterChanged and type(newPropFilter) == "string" then
                                    EntityLists.PropFilter = newPropFilter
                                end

                                local filterLower = (EntityLists.PropFilter or ""):lower()

                                local sortedCategories = {}
                                for categoryName, _ in pairs(EntityLists.Props) do
                                    table.insert(sortedCategories, categoryName)
                                end
                                table.sort(sortedCategories)

                                for _, categoryName in ipairs(sortedCategories) do
                                    local propsList = EntityLists.Props[categoryName]
                                    local filteredProps = {}
                                    for _, prop in ipairs(propsList) do
                                        if filterLower == "" or prop.name:lower():find(filterLower, 1, true) then
                                            table.insert(filteredProps, prop)
                                        end
                                    end

                                    if #filteredProps > 0 then
                                        local flags = (filterLower ~= "") and 32 or 0
                                        if ImGui.TreeNodeEx(categoryName .. "##Props", flags) then
                                            for _, prop in ipairs(filteredProps) do
                                                local displayName = prop.name
                                                if ImGui.Selectable(displayName .. "##prop_" .. prop.hash) then
                                                    Spawner.SpawnProp(prop.hash, prop.name)
                                                end
                                            end
                                            ImGui.TreePop()
                                        end
                                    end
                                end
                                ImGui.EndTabItem()
                            end

                            -- Vehicles Tab
                            if ImGui.BeginTabItem("Vehicles") then
                                local newVehFilter, vehFilterChanged = ImGui.InputText("Vehicle Filter", EntityLists.VehicleFilter, 256)
                                if vehFilterChanged and type(newVehFilter) == "string" then
                                    EntityLists.VehicleFilter = newVehFilter
                                end

                                local filterLower = (EntityLists.VehicleFilter or ""):lower()

                                local sortedCategories = {}
                                for categoryName, _ in pairs(EntityLists.Vehicles) do
                                    table.insert(sortedCategories, categoryName)
                                end
                                table.sort(sortedCategories)

                                for _, categoryName in ipairs(sortedCategories) do
                                    local vehiclesList = EntityLists.Vehicles[categoryName]
                                    local filteredVehicles = {}
                                    for _, vehicle in ipairs(vehiclesList) do
                                        local displayName = GTA.GetDisplayNameFromHash(Utils.Joaat(vehicle.name))
                                        if filterLower == "" or vehicle.name:lower():find(filterLower, 1, true) or displayName:lower():find(filterLower, 1, true) then
                                            table.insert(filteredVehicles, {vehicle = vehicle, displayName = displayName})
                                        end
                                    end

                                    if #filteredVehicles > 0 then
                                        local flags = (filterLower ~= "") and 32 or 0
                                        if ImGui.TreeNodeEx(categoryName .. "##Vehicles", flags) then
                                            for _, item in ipairs(filteredVehicles) do
                                                if ImGui.Selectable(item.displayName .. "##veh_" .. item.vehicle.name) then
                                                    Spawner.SpawnVehicle(item.vehicle.name)
                                                end
                                            end
                                            ImGui.TreePop()
                                        end
                                    end
                                end
                                ImGui.EndTabItem()
                            end

                            -- Peds Tab
                            if ImGui.BeginTabItem("Peds") then
                                local newPedFilter, pedFilterChanged = ImGui.InputText("Ped Filter", EntityLists.PedFilter, 256)
                                if pedFilterChanged and type(newPedFilter) == "string" then
                                    EntityLists.PedFilter = newPedFilter
                                end

                                local filterLower = (EntityLists.PedFilter or ""):lower()

                                local sortedCategories = {}
                                for categoryName, _ in pairs(EntityLists.Peds) do
                                    table.insert(sortedCategories, categoryName)
                                end
                                table.sort(sortedCategories)

                                for _, categoryName in ipairs(sortedCategories) do
                                    local pedsList = EntityLists.Peds[categoryName]
                                    local filteredPeds = {}
                                    for _, ped in ipairs(pedsList) do
                                        local displayName = ped.caption ~= "" and ped.caption or ped.name
                                        if filterLower == "" or ped.name:lower():find(filterLower, 1, true) or displayName:lower():find(filterLower, 1, true) then
                                            table.insert(filteredPeds, {ped = ped, displayName = displayName})
                                        end
                                    end

                                    if #filteredPeds > 0 then
                                        local flags = (filterLower ~= "") and 32 or 0
                                        if ImGui.TreeNodeEx(categoryName .. "##Peds", flags) then
                                            for _, item in ipairs(filteredPeds) do
                                                if ImGui.Selectable(item.displayName .. "##ped_" .. item.ped.name) then
                                                    Spawner.SpawnPed(item.ped.name)
                                                end
                                            end
                                            ImGui.TreePop()
                                        end
                                    end
                                end
                                ImGui.EndTabItem()
                            end

                            ImGui.EndTabBar()
                        end
                        ClickGUI.EndCustomChildWindow()
                    end
                    ImGui.EndTabItem()
                end

                -- Load XML subtab
                if ImGui.BeginTabItem("Load XML") then
                    if ClickGUI.BeginCustomChildWindow("XML File Browser") then
                        local xmlFiles = Spooner.GetAvailableXMLFiles()

                        if Spooner.selectedXMLFile then
                            local fileExists = false
                            for _, f in ipairs(xmlFiles) do
                                if f == Spooner.selectedXMLFile then
                                    fileExists = true
                                    break
                                end
                            end
                            if not fileExists then
                                Spooner.selectedXMLFile = nil
                            end
                        end

                        if #xmlFiles == 0 then
                            ImGui.Text("No XML files found")
                            ImGui.Text("Save some placements first!")
                        else
                            local fileTree = {}
                            for _, filename in ipairs(xmlFiles) do
                                local displayName = filename:gsub(spoonerSavePath .. "\\", ""):gsub(".xml$", "")
                                local parts = SpoonerUtils.SplitString(displayName, "\\")
                                if not parts or #parts == 0 then
                                    parts = {displayName}
                                end

                                local currentLevel = fileTree
                                for i, part in ipairs(parts) do
                                    if i == #parts then
                                        if not currentLevel._files then
                                            currentLevel._files = {}
                                        end
                                        table.insert(currentLevel._files, {name = part, fullPath = filename})
                                    else
                                        if not currentLevel[part] then
                                            currentLevel[part] = {}
                                        end
                                        currentLevel = currentLevel[part]
                                    end
                                end
                            end

                            local function renderXMLFileTree(tree, depth)
                                local folders = {}
                                for key, _ in pairs(tree) do
                                    if key ~= "_files" then
                                        table.insert(folders, key)
                                    end
                                end
                                table.sort(folders)

                                for _, folderName in ipairs(folders) do
                                    if ImGui.TreeNode(folderName .. "##xmlfolder" .. depth .. folderName) then
                                        renderXMLFileTree(tree[folderName], depth + 1)
                                        ImGui.TreePop()
                                    end
                                end

                                if tree._files then
                                    for _, fileInfo in ipairs(tree._files) do
                                        local isSelected = (Spooner.selectedXMLFile == fileInfo.fullPath)
                                        if ImGui.Selectable(fileInfo.name .. "##xml_" .. fileInfo.fullPath, isSelected) then
                                            Spooner.selectedXMLFile = fileInfo.fullPath
                                        end
                                    end
                                end
                            end

                            renderXMLFileTree(fileTree, 0)
                        end

                        ImGui.Separator()
                        ImGui.Spacing()

                        if Spooner.selectedXMLFile then
                            local selectedDisplayName = Spooner.selectedXMLFile:gsub(spoonerSavePath .. "\\", ""):gsub(".xml$", "")
                            ImGui.Text("Selected: " .. selectedDisplayName)

                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_LoadSelectedXML"))
                            ClickGUI.RenderFeature(Utils.Joaat("Spooner_DeleteSelectedXML"))
                        else
                            ImGui.Text("No file selected")
                        end

                        ImGui.Separator()
                        ImGui.Spacing()

                        ImGui.Text("XML Folder:")
                        ImGui.TextWrapped(spoonerSavePath)

                        ClickGUI.RenderFeature(Utils.Joaat("Spooner_RefreshXMLList"))

                        ClickGUI.EndCustomChildWindow()
                    end
                    ImGui.EndTabItem()
                end

                ImGui.EndTabBar()
            end
        end)
    end

    return self
end

return SpoonerUI
