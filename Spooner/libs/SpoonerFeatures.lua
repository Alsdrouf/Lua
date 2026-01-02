local SpoonerFeatures = {}

function SpoonerFeatures.New(deps)
    local Spooner = deps.Spooner
    local Config = deps.Config
    local SaveConfig = deps.SaveConfig
    local NetworkUtils = deps.NetworkUtils
    local CameraUtils = deps.CameraUtils
    local CustomLogger = deps.CustomLogger
    local CONSTANTS = deps.CONSTANTS

    local self = {}

    local isRunningFreeze = false
    local isRunningDynamic = false
    local isRunningGodMode = false
    local isRunningNetworked = false

    local dynamicEntityFeature
    local freezeEntityFeature
    local godModeEntityFeature
    local networkedEntityFeature

    -- Toggle Spooner Mode
    self.toggleSpoonerModeFeature = FeatureMgr.AddFeature(
        Utils.Joaat("ToggleSpoonerMode"),
        "Toggle Spooner Mode",
        eFeatureType.Toggle,
        "Toggle Spooner Mode",
        function(f)
            Script.QueueJob(function()
                Spooner.ToggleSpoonerMode(f:IsToggled())
            end)
        end
    )

    -- Remove Entity from Database
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_RemoveEntity"),
        "Remove from Database",
        eFeatureType.Button,
        "Remove selected entity from database",
        function(f)
            Script.QueueJob(function()
                local entity, isInDatabase = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) and isInDatabase then
                    for i, managed in ipairs(Spooner.managedEntities) do
                        if managed.entity == entity then
                            table.remove(Spooner.managedEntities, i)
                            Spooner.quickEditEntity = managed
                            Spooner.selectedEntityIndex = 0
                            break
                        end
                    end
                    Spooner.UpdateSelectedEntityBlip()
                    GUI.AddToast("Spooner", "Entity removed from database", 1500)
                else
                    GUI.AddToast("Spooner", "No valid entity in database selected", 2000)
                end
            end)
        end
    )

    -- Remove All
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_RemoveAll"),
        "Remove All",
        eFeatureType.Button,
        "Remove all entities from database (keeps entities in game)",
        function(f)
            Script.QueueJob(function()
                local count = #Spooner.managedEntities
                if count > 0 then
                    Spooner.managedEntities = {}
                    Spooner.quickEditEntity = nil
                    Spooner.selectedEntityIndex = 0
                    Spooner.UpdateSelectedEntityBlip()
                    GUI.AddToast("Spooner", "Removed " .. count .. " entities from database", 2000)
                else
                    GUI.AddToast("Spooner", "Database is empty", 1500)
                end
            end)
        end
    )

    -- Delete All
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_DeleteAll"),
        "Delete All",
        eFeatureType.Button,
        "Delete all entities from database and game",
        function(f)
            Script.QueueJob(function()
                local count = #Spooner.managedEntities
                if count > 0 then
                    for _, managed in ipairs(Spooner.managedEntities) do
                        if ENTITY.DOES_ENTITY_EXIST(managed.entity) then
                            Spooner.DeleteEntity(managed.entity)
                        end
                    end
                    Spooner.managedEntities = {}
                    Spooner.quickEditEntity = nil
                    Spooner.selectedEntityIndex = 0
                    Spooner.UpdateSelectedEntityBlip()
                    GUI.AddToast("Spooner", "Deleted " .. count .. " entities", 2000)
                else
                    GUI.AddToast("Spooner", "Database is empty", 1500)
                end
            end)
        end
    )

    -- Freeze Entity
    freezeEntityFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_FreezeSelectedEntity"),
        "Freeze Entity",
        eFeatureType.Toggle,
        "Freeze entity position",
        function(f)
            isRunningFreeze = true
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    Spooner.TakeControlOfEntity(entity)
                    local frozen = f:IsToggled()
                    ENTITY.FREEZE_ENTITY_POSITION(entity, frozen)

                    if not frozen then
                        ENTITY.SET_ENTITY_DYNAMIC(entity, true)
                        ENTITY.SET_ENTITY_HAS_GRAVITY(entity, true)
                        ENTITY.APPLY_FORCE_TO_ENTITY(entity, 1, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                    end

                    if not isRunningDynamic then
                        dynamicEntityFeature:Toggle(not frozen)
                    end

                    isRunningFreeze = false
                end
            end)
        end
    )

    -- Dynamic Entity
    dynamicEntityFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_DynamicEntity"),
        "Dynamic",
        eFeatureType.Toggle,
        "Toggle entity dynamic state",
        function(f)
            isRunningDynamic = true
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    Spooner.TakeControlOfEntity(entity)
                    local dynamic = f:IsToggled()
                    ENTITY.SET_ENTITY_DYNAMIC(entity, dynamic)

                    if not isRunningFreeze then
                        freezeEntityFeature:Toggle(not dynamic)
                    end

                    isRunningDynamic = false
                end
            end)
        end
    )

    -- God Mode Entity
    godModeEntityFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_GodModeEntity"),
        "God Mode",
        eFeatureType.Toggle,
        "Make entity invincible",
        function(f)
            isRunningGodMode = true
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    Spooner.TakeControlOfEntity(entity)
                    local godMode = f:IsToggled()
                    ENTITY.SET_ENTITY_INVINCIBLE(entity, godMode)
                    ENTITY.SET_ENTITY_CAN_BE_DAMAGED(entity, not godMode)
                    isRunningGodMode = false
                end
            end)
        end
    )

    -- Networked Entity
    networkedEntityFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_NetworkedEntity"),
        "Networked",
        eFeatureType.Toggle,
        "Toggle entity networking state",
        function(f)
            isRunningNetworked = true
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    local networkId = 0
                    if f:IsToggled() then
                        networkId = NetworkUtils.MakeEntityNetworked(entity)
                        networkId = NetworkUtils.MakeEntityNetworked(entity)
                    else
                        local cPhysical = GTA.HandleToPointer(entity)
                        NetworkObjectMgr.UnregisterNetworkObject(cPhysical.NetObject, 0, true, false)
                        ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, false, true)
                    end
                    for _, managed in ipairs(Spooner.managedEntities) do
                        if managed.entity == entity then
                            managed.networked = NetworkUtils.IsEntityNetworked(entity)
                            managed.networkId = networkId
                            break
                        end
                    end

                    if Spooner.quickEditEntity and Spooner.quickEditEntity.entity == entity then
                        Spooner.quickEditEntity.networked = NetworkUtils.IsEntityNetworked(entity)
                        Spooner.quickEditEntity.networkId = networkId
                    end

                    isRunningNetworked = false
                end
            end)
        end
    )

    -- Update toggle helpers
    function self.UpdateFreezeToggleForEntity(entity)
        if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
            local isFrozen = Spooner.isEntityFrozen(entity)
            local isToggled = freezeEntityFeature:IsToggled()
            if isFrozen ~= isToggled and not isRunningFreeze then
                freezeEntityFeature:Toggle(isFrozen)
            end
        end
    end

    function self.UpdateDynamicToggleForEntity(entity)
        if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
            local isDynamic = Spooner.isEntityDynamic(entity)
            local isToggled = dynamicEntityFeature:IsToggled()
            if isDynamic ~= isToggled and not isRunningDynamic then
                dynamicEntityFeature:Toggle(isDynamic)
            end
        end
    end

    function self.UpdateGodModeToggleForEntity(entity)
        if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
            local isInvincible = ENTITY.GET_ENTITY_CAN_BE_DAMAGED(entity) == false
            local isToggled = godModeEntityFeature:IsToggled()
            if isInvincible ~= isToggled and not isRunningGodMode then
                godModeEntityFeature:Toggle(isInvincible)
            end
        end
    end

    function self.UpdateNetworkedToggleForEntity(entity)
        if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
            local isNetworked = NetworkUtils.IsEntityNetworked(entity)
            local isToggled = networkedEntityFeature:IsToggled()
            if isNetworked ~= isToggled and not isRunningNetworked then
                networkedEntityFeature:Toggle(isNetworked)
            end
        end
    end

    -- Wire up Spooner toggle callbacks
    Spooner.UpdateFreezeToggle = self.UpdateFreezeToggleForEntity
    Spooner.UpdateDynamicToggle = self.UpdateDynamicToggleForEntity
    Spooner.UpdateGodModeToggle = self.UpdateGodModeToggleForEntity
    Spooner.UpdateNetworkedToggle = self.UpdateNetworkedToggleForEntity

    -- Delete Entity
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_DeleteEntity"),
        "Delete Entity",
        eFeatureType.Button,
        "Delete selected entity from the game",
        function(f)
            Script.QueueJob(function()
                local entity, isInDatabase = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    CustomLogger.Info("Deleting entity: " .. tostring(entity))

                    if Spooner.quickEditEntity and Spooner.quickEditEntity.entity == entity then
                        Spooner.quickEditEntity = nil
                    end
                    if isInDatabase then
                        for i, managed in ipairs(Spooner.managedEntities) do
                            if managed.entity == entity then
                                table.remove(Spooner.managedEntities, i)
                                break
                            end
                        end
                    end
                    Spooner.selectedEntityIndex = 0

                    Spooner.DeleteEntity(entity)

                    CustomLogger.Info("Deleted entity: " .. tostring(entity))
                    GUI.AddToast("Spooner", "Entity deleted", 1500)
                else
                    GUI.AddToast("Spooner", "No valid entity selected", 2000)
                end
            end)
        end
    )

    -- Save Database to XML
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_SaveDatabaseToXML"),
        "Save Database to XML",
        eFeatureType.Button,
        "Save all entities in database to XML file",
        function(f)
            Script.QueueJob(function()
                Spooner.SaveDatabaseToXML(Spooner.saveFileName)
            end)
        end
    )

    -- Teleport to Entity
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_TeleportToEntity"),
        "Teleport to Entity",
        eFeatureType.Button,
        "Teleport to the selected entity",
        function(f)
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    local entityPos = ENTITY.GET_ENTITY_COORDS(entity, true)
                    if Spooner.inSpoonerMode and Spooner.freecam then
                        CAM.SET_CAM_COORD(Spooner.freecam, entityPos.x, entityPos.y - 5.0, entityPos.z + 2.0)
                    else
                        local playerPed = PLAYER.PLAYER_PED_ID()
                        ENTITY.SET_ENTITY_COORDS_NO_OFFSET(playerPed, entityPos.x, entityPos.y, entityPos.z + 1.0, false, false, false)
                    end
                else
                    GUI.AddToast("Spooner", "No valid entity selected", 2000)
                end
            end)
        end
    )

    -- Teleport Entity Here
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_TeleportEntityHere"),
        "Teleport Entity Here",
        eFeatureType.Button,
        "Teleport the selected entity to camera/player position",
        function(f)
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    Spooner.TakeControlOfEntity(entity)
                    local targetPos
                    if Spooner.inSpoonerMode and Spooner.freecam then
                        local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
                        local fwd = CameraUtils.GetBasis(Spooner.freecam)
                        targetPos = {
                            x = camPos.x + fwd.x * 5.0,
                            y = camPos.y + fwd.y * 5.0,
                            z = camPos.z + fwd.z * 5.0
                        }
                    else
                        local playerPed = PLAYER.PLAYER_PED_ID()
                        local playerPos = ENTITY.GET_ENTITY_COORDS(playerPed, true)
                        local playerHeading = ENTITY.GET_ENTITY_HEADING(playerPed)
                        local rad = math.rad(playerHeading)
                        targetPos = {
                            x = playerPos.x - math.sin(rad) * 5.0,
                            y = playerPos.y + math.cos(rad) * 5.0,
                            z = playerPos.z
                        }
                    end
                    ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, targetPos.x, targetPos.y, targetPos.z, false, false, false)
                else
                    GUI.AddToast("Spooner", "No valid entity selected", 2000)
                end
            end)
        end
    )

    -- Add to Database
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_AddToDatabase"),
        "Add to Database",
        eFeatureType.Button,
        "Add the selected entity to the database",
        function(f)
            Script.QueueJob(function()
                local entity = Spooner.GetEditingEntity()
                if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
                    for _, managed in ipairs(Spooner.managedEntities) do
                        if managed.entity == entity then
                            GUI.AddToast("Spooner", "Entity already in database", 2000)
                            return
                        end
                    end
                    Spooner.ToggleEntityInManagedList(entity)
                    GUI.AddToast("Spooner", "Entity added to database", 1500)
                else
                    GUI.AddToast("Spooner", "No valid entity selected", 2000)
                end
            end)
        end
    )

    -- Load Selected XML
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_LoadSelectedXML"),
        "Load XML",
        eFeatureType.Button,
        "Load the selected XML file",
        function(f)
            if Spooner.selectedXMLFile then
                Script.QueueJob(function()
                    Spooner.LoadDatabaseFromXML(Spooner.selectedXMLFile)
                end)
            else
                GUI.AddToast("Spooner", "No XML file selected", 2000)
            end
        end
    )

    -- Delete Selected XML
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_DeleteSelectedXML"),
        "Delete XML",
        eFeatureType.Button,
        "Delete the selected XML file",
        function(f)
            if Spooner.selectedXMLFile then
                local selectedDisplayName = Spooner.selectedXMLFile:match("([^\\]+)%.xml$") or Spooner.selectedXMLFile
                Script.QueueJob(function()
                    if FileMgr.DeleteFile(Spooner.selectedXMLFile) then
                        GUI.AddToast("Spooner", "Deleted: " .. selectedDisplayName, 2000)
                        Spooner.selectedXMLFile = nil
                    else
                        GUI.AddToast("Spooner", "Failed to delete file", 2000)
                    end
                end)
            else
                GUI.AddToast("Spooner", "No XML file selected", 2000)
            end
        end
    )

    -- Refresh XML List
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_RefreshXMLList"),
        "Refresh",
        eFeatureType.Button,
        "Refresh the XML file list",
        function(f)
            GUI.AddToast("Spooner", "File list refreshed", 1000)
        end
    )

    -- Enable F9 Key
    self.enableF9KeyFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_EnableF9Key"),
        "Enable F9 Key",
        eFeatureType.Toggle,
        "Enable F9 key to toggle freecam",
        function(f)
            Config.enableF9Key = f:IsToggled()
            if Config.enableF9Key then
                self.toggleSpoonerModeFeature:AddHotKey(120)
            else
                self.toggleSpoonerModeFeature:RemoveHotkey(120, false)
            end
            SaveConfig()
        end
    )

    -- Enable Throwable Mode
    self.enableThrowableModeFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_EnableThrowableMode"),
        "Enable Throwable Mode",
        eFeatureType.Toggle,
        "Enable Throwable Mode",
        function(f)
            Config.throwableMode = f:IsToggled()
            Spooner.throwableMode = Config.throwableMode
            SaveConfig()
        end
    )

    -- Clip to Ground
    self.enableClipToGroundFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_EnableClipToGround"),
        "Clip to Ground",
        eFeatureType.Toggle,
        "Snap entities to ground when within " .. CONSTANTS.CLIP_TO_GROUND_DISTANCE .. "m",
        function(f)
            Config.clipToGround = f:IsToggled()
            Spooner.clipToGround = Config.clipToGround
            SaveConfig()
        end
    )

    -- Spawn Unnetworked
    self.spawnUnnetworkedFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_SpawnUnnetworked"),
        "Spawn Unnetworked",
        eFeatureType.Toggle,
        "Spawn entities as local (unnetworked) entities",
        function(f)
            Config.spawnUnnetworked = f:IsToggled()
            Spooner.spawnUnnetworked = Config.spawnUnnetworked
            SaveConfig()
        end
    )

    -- Lock Movement While Menu Is Open
    self.lockMovementWhileMenuIsOpenFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_LockMovementWhileMenuIsOpen"),
        "Lock Movement while menu is open",
        eFeatureType.Toggle,
        "Lock cam movement and entity grab while menu is open",
        function(f)
            Config.lockMovementWhileMenuIsOpen = f:IsToggled()
            Spooner.lockMovementWhileMenuIsOpen = Config.lockMovementWhileMenuIsOpen
            SaveConfig()
        end
    )

    -- Lock Movement While Menu Is Open Enhanced
    self.lockMovementWhileMenuIsOpenEnhancedFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_LockMovementWhileMenuIsOpenEnhanced"),
        "Lock Movement while menu is open and hovering over it",
        eFeatureType.Toggle,
        "Lock cam movement and entity grab while menu is open and hovering over the menu",
        function(f)
            Config.lockMovementWhileMenuIsOpenEnhanced = f:IsToggled()
            Spooner.lockMovementWhileMenuIsOpenEnhanced = Config.lockMovementWhileMenuIsOpenEnhanced
            SaveConfig()
        end
    )

    -- Position Step
    self.positionStepFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_PositionStep"),
        "Step",
        eFeatureType.SliderFloat,
        "Position adjustment step size",
        function(f)
            Config.positionStep = f:GetFloatValue()
            SaveConfig()
        end
    )
    self.positionStepFeature:SetMinValue(0.1)
    self.positionStepFeature:SetMaxValue(5.0)
    self.positionStepFeature:SetFloatValue(Config.positionStep)

    -- Enable At Player
    FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_EnableAtPlayer"),
        "Enable spooner at",
        eFeatureType.Button,
        "Enable spooner at the player",
        function(f)
            if self.toggleSpoonerModeFeature:IsToggled() == false then
                self.toggleSpoonerModeFeature:Toggle()
            end

            Script.QueueJob(function()
                local playerId = Utils.GetSelectedPlayer()
                local cPed = Players.GetCPed(playerId)
                CAM.SET_CAM_COORD(Spooner.freecam, cPed.Position.x, cPed.Position.y, cPed.Position.z)
            end)
        end
    )

    -- Follow Player
    self.followPlayerFeature = FeatureMgr.AddFeature(
        Utils.Joaat("Spooner_FollowPlayer"),
        "Follow player",
        eFeatureType.Toggle,
        "Follow the selected player with an offset. Camera moves when player moves, but you can still move freely.",
        function(f)
            Script.QueueJob(function()
                if f:IsToggled() then
                    if not Spooner.inSpoonerMode then
                        self.toggleSpoonerModeFeature:Toggle()
                    end
                    local playerId = Utils.GetSelectedPlayer()
                    if not Spooner.StartFollowingPlayer(playerId) then
                        f:Toggle()
                        GUI.AddToast("Spooner", "Failed to follow player", 2000)
                    else
                        GUI.AddToast("Spooner", "Following " .. Players.GetName(playerId), 2000)
                    end
                else
                    Spooner.StopFollowingPlayer()
                    GUI.AddToast("Spooner", "Stopped following player", 2000)
                end
            end)
        end
    )

    -- Apply loaded config
    function self.ApplyLoadedConfig(loadedConfig)
        if loadedConfig == nil then return end

        if loadedConfig.enableF9Key ~= nil and loadedConfig.enableF9Key then
            self.enableF9KeyFeature:Toggle(loadedConfig.enableF9Key)
        end
        if loadedConfig.clipToGround ~= nil and loadedConfig.clipToGround then
            self.enableClipToGroundFeature:Toggle(loadedConfig.clipToGround)
        end
        if loadedConfig.throwableMode ~= nil and loadedConfig.throwableMode then
            self.enableThrowableModeFeature:Toggle(loadedConfig.throwableMode)
        end
        if loadedConfig.lockMovementWhileMenuIsOpen ~= nil and loadedConfig.lockMovementWhileMenuIsOpen then
            self.lockMovementWhileMenuIsOpenFeature:Toggle(loadedConfig.lockMovementWhileMenuIsOpen)
        end
        if loadedConfig.lockMovementWhileMenuIsOpenEnhanced ~= nil and loadedConfig.lockMovementWhileMenuIsOpenEnhanced then
            self.lockMovementWhileMenuIsOpenEnhancedFeature:Toggle(loadedConfig.lockMovementWhileMenuIsOpenEnhanced)
        end
        if loadedConfig.positionStep ~= nil then
            self.positionStepFeature:SetFloatValue(loadedConfig.positionStep)
        end
        if loadedConfig.spawnUnnetworked ~= nil and loadedConfig.spawnUnnetworked then
            self.spawnUnnetworkedFeature:Toggle(loadedConfig.spawnUnnetworked)
        end
    end

    return self
end

return SpoonerFeatures
