local pluginName = "Spooner"
local menuRootPath = FileMgr.GetMenuRootPath() .. "\\Lua\\" .. pluginName
local nativesPath = menuRootPath .. "\\Assets\\natives.lua"
local configPath = menuRootPath .. "\\config.xml"
local libsPath = menuRootPath .. "\\libs\\"

FileMgr.CreateDir(menuRootPath)
FileMgr.CreateDir(menuRootPath .. "\\Assets")
FileMgr.CreateDir(menuRootPath .. "\\libs")

local propListPath = menuRootPath .. "\\Assets\\PropList.xml"
local vehicleListPath = menuRootPath .. "\\Assets\\VehicleList.xml"
local pedListPath = menuRootPath .. "\\Assets\\PedList.xml"

-- ============================================================================
-- Load Libraries
-- ============================================================================
local function LoadLib(name)
    local path = libsPath .. name .. ".lua"
    local status, result = pcall(dofile, path)
    if not status then
        Logger.Log(eLogColor.RED, pluginName, "Failed to load library " .. name .. ": " .. tostring(result))
        return nil
    end
    return result
end

local LoggerLib = LoadLib("Logger")
local XMLParser = LoadLib("XMLParser")
local EntityListsLib = LoadLib("EntityLists")
local NetworkUtilsLib = LoadLib("NetworkUtils")
local KeybindsLib = LoadLib("Keybinds")
local CameraUtilsLib = LoadLib("CameraUtils")
local MemoryUtilsLib = LoadLib("MemoryUtils")
local RaycastLib = LoadLib("Raycast")

-- ============================================================================
-- Constants
-- ============================================================================
local CONSTANTS = {
    NATIVES_URL = "https://raw.githubusercontent.com/Elfish-beaker/object-list/refs/heads/main/natives.lua",
    NETWORK_TIMEOUT = 1500,
    NETWORK_TIMEOUT_SHORT = 25,
    RAYCAST_MAX_DISTANCE = 1000.0,
    RAYCAST_INTERVAL = 3,
    RAYCAST_FLAGS = 30, -- vehicles + peds + objects + pickups
    MIN_GRAB_DISTANCE = 1.0,
    CAMERA_SPEED = 0.5,
    CAMERA_ROT_SPEED = 20.0,
    CAMERA_SPEED_BOOST = 3.0,
    ROTATION_SPEED = 2.0,
    ROTATION_SPEED_BOOST = 4.0,
    SCROLL_SPEED = 0.5,
    PITCH_CLAMP_MAX = 89.0,
    PITCH_CLAMP_MIN = -89.0,
    VELOCITY_MULTIPLIER = 30.0,
    CLIP_TO_GROUND_DISTANCE = 3, -- Distance from ground to trigger clip
    CLIP_TO_GROUND_RAYCAST_FLAGS = 33, -- Buildings, world geometry
    POSITION_STEP_DEFAULT = 1.0, -- Default step for position sliders
}

-- ============================================================================
-- Initialize Libraries (before natives)
-- ============================================================================
local CustomLogger = LoggerLib.New(pluginName)
local MemoryUtils = MemoryUtilsLib.New()

-- ============================================================================
-- Utilities
-- ============================================================================
local function DownloadAndSaveLuaFile(url, filePath)
    local curlObject = Curl.Easy()
    curlObject:Setopt(eCurlOption.CURLOPT_URL, url)
    curlObject:AddHeader("User-Agent: Lua-Curl-Client")
    curlObject:Perform()

    while not curlObject:GetFinished() do
    end

    local responseCode, responseString = curlObject:GetResponse()

    if responseCode ~= eCurlCode.CURLE_OK then
        Logger.LogError("Error downloading file. Response code: " .. responseCode)
        Logger.LogError("Response message: " .. responseString)
        return false
    end

    if responseString == "404: Not Found" then
        Logger.LogError("File not found on the internet!")
        return false
    end

    if not FileMgr.WriteFileContent(filePath, responseString) then
        Logger.LogError("Error saving file: " .. filePath)
        Logger.LogError("Content: " .. responseString)
        return false
    end

    Logger.LogInfo("Successfully downloaded and saved: " .. filePath)
    return true
end

local function LoadNatives(path)
    if not FileMgr.DoesFileExist(path) then
        Logger.LogInfo("natives.lua not found. Downloading...")
        if not DownloadAndSaveLuaFile(CONSTANTS.NATIVES_URL, path) then
            return false
        end
    end

    local status, err = pcall(dofile, path)
    if not status then
        Logger.LogError("Failed to load natives.lua: " .. err)
        return false
    end

    return true
end

LoadNatives(nativesPath)

-- ============================================================================
-- Initialize Libraries (after natives)
-- ============================================================================
local EntityLists = EntityListsLib.New(XMLParser, CustomLogger)
local NetworkUtils = NetworkUtilsLib.New(CONSTANTS)
local KeybindsInstance = KeybindsLib.New(PAD)
local Keybinds = KeybindsInstance.SetupDefaultBinds()
local CameraUtils = CameraUtilsLib.New(CONSTANTS)
local Raycast = RaycastLib.New("CameraHit", CONSTANTS, CustomLogger, MemoryUtils)
local RaycastForClipToGround = RaycastLib.New("ClipToGround", CONSTANTS, CustomLogger, MemoryUtils)

-- ============================================================================
-- Configuration Management
-- ============================================================================
local Config = {
    enableF9Key = false,
    throwableMode = false,
    clipToGround = false,
    lockMovementWhileMenuIsOpen = false,
    positionStep = CONSTANTS.POSITION_STEP_DEFAULT,
}

local function SaveConfig()
    local xmlContent = XMLParser.GenerateXML("SpoonerConfig", {
        enableF9Key = Config.enableF9Key,
        throwableMode = Config.throwableMode,
        clipToGround = Config.clipToGround,
        lockMovementWhileMenuIsOpen = Config.lockMovementWhileMenuIsOpen,
        positionStep = Config.positionStep
    })

    if FileMgr.WriteFileContent(configPath, xmlContent) then
        CustomLogger.Info("Configuration saved to XML")
        return true
    else
        CustomLogger.Error("Failed to save configuration")
        return false
    end
end

local function LoadConfig()
    if not FileMgr.DoesFileExist(configPath) then
        CustomLogger.Info("No config file found, using defaults")
        return
    end

    local configData = FileMgr.ReadFileContent(configPath)
    if not configData or configData == "" then
        CustomLogger.Warn("Config file is empty")
        return
    end

    local loadedConfig = XMLParser.ParseConfig(configData)

    if loadedConfig.enableF9Key ~= nil then
        Config.enableF9Key = loadedConfig.enableF9Key
    end
    if loadedConfig.throwableMode ~= nil then
        Config.throwableMode = loadedConfig.throwableMode
    end
    if loadedConfig.clipToGround ~= nil then
        Config.clipToGround = loadedConfig.clipToGround
    end
    if loadedConfig.positionStep ~= nil then
        Config.positionStep = loadedConfig.positionStep
    end

    CustomLogger.Info("Configuration loaded from XML")
end

-- ============================================================================
-- Spooner Core
-- ============================================================================
local Spooner = {}
Spooner.inSpoonerMode = false
Spooner.freecam = nil
Spooner.freecamBlip = nil
Spooner.camSpeed = CONSTANTS.CAMERA_SPEED
Spooner.camRotSpeed = CONSTANTS.CAMERA_ROT_SPEED
Spooner.crosshairColor = {r = 255, g = 255, b = 255, a = 255}
Spooner.crosshairSize = 0.01
Spooner.crosshairGap = 0
Spooner.crosshairThickness = 0.001
Spooner.crosshairColorGreen = {r = 0, g = 255, b = 0, a = 255}
Spooner.lastEntityPos = nil
Spooner.grabVelocity = {x = 0, y = 0, z = 0}
Spooner.targetedEntity = nil
Spooner.isEntityTargeted = false
Spooner.grabbedEntity = nil
Spooner.grabOffsets = nil
Spooner.grabbedEntityRotation = nil
Spooner.isGrabbing = false
Spooner.scaleform = nil
Spooner.managedEntities = {}
Spooner.selectedEntityIndex = 0
Spooner.makeMissionEntity = false
Spooner.throwableVelocityMultiplier = CONSTANTS.VELOCITY_MULTIPLIER
Spooner.throwableMode = false
Spooner.clipToGround = false
Spooner.lockMovementWhileMenuIsOpen = false
-- Preview spawn system
Spooner.previewEntity = nil
Spooner.previewModelHash = nil
Spooner.previewEntityType = nil  -- "prop", "vehicle", "ped"
Spooner.previewModelName = nil
Spooner.pendingPreviewDelete = nil  -- Entity handle pending deletion

function Spooner.TakeControlOfEntity(entity)
    return NetworkUtils.MaintainNetworkControlV2(entity)
end

function Spooner.IsEntityRestricted(entity)
    if not ENTITY.DOES_ENTITY_EXIST(entity) then
        return true
    end

    if ENTITY.IS_ENTITY_A_PED(entity) and PED.IS_PED_A_PLAYER(entity) and entity ~= PLAYER.PLAYER_PED_ID() then
        return true
    end

    if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
        local driver = VEHICLE.GET_PED_IN_VEHICLE_SEAT(entity, -1)
        if driver ~= 0 and PED.IS_PED_A_PLAYER(driver) and driver ~= PLAYER.PLAYER_PED_ID() then
            return true
        end
    end

    return false
end

function Spooner.CalculateNewPosition(camPos, fwd, right, up, offsets)
    return {
        x = camPos.x + (right.x * offsets.x) + (fwd.x * offsets.y) + (up.x * offsets.z),
        y = camPos.y + (right.y * offsets.x) + (fwd.y * offsets.y) + (up.y * offsets.z),
        z = camPos.z + (right.z * offsets.x) + (fwd.z * offsets.y) + (up.z * offsets.z)
    }
end

function Spooner.CalculateGrabOffsets(camPos, entityPos, fwd, right, up)
    local vec = {
        x = entityPos.x - camPos.x,
        y = entityPos.y - camPos.y,
        z = entityPos.z - camPos.z
    }

    return {
        x = vec.x * right.x + vec.y * right.y + vec.z * right.z,
        y = vec.x * fwd.x + vec.y * fwd.y + vec.z * fwd.z,
        z = vec.x * up.x + vec.y * up.y + vec.z * up.z
    }
end

function Spooner.GetGroundZAtPosition(x, y, z)
    local isTargeted, entityTarget, rayHitCoords = RaycastForClipToGround.PerformCheck(x, y, z + 4, x, y, z - 100, CONSTANTS.CLIP_TO_GROUND_RAYCAST_FLAGS)

    return rayHitCoords.z
end

function Spooner.GetEntityDimensions(entity, memoryName)
    return Spooner.GetModelDimensions(ENTITY.GET_ENTITY_MODEL(entity), memoryName)
end

function Spooner.GetModelDimensions(modelHash, memoryName)
    local min = MemoryUtils.AllocV3(memoryName .. "Min")
    local max = MemoryUtils.AllocV3(memoryName .. "Max")
    MISC.GET_MODEL_DIMENSIONS(modelHash, min, max)
    local minV3 = MemoryUtils.ReadV3(min)
    local maxV3 = MemoryUtils.ReadV3(max)

    return minV3.x, minV3.y, minV3.z, maxV3.x, maxV3.y, maxV3.z
end

function Spooner.ClipEntityToGround(entity, newPos)
    if not Spooner.clipToGround then
        return newPos
    end

    -- Get ground Z at the entity's position
    local groundZ = Spooner.GetGroundZAtPosition(newPos.x, newPos.y, newPos.z)

    if groundZ then
        -- Get entity model dimensions
        local minX, minY, minZ, maxX, maxY, maxZ = Spooner.GetEntityDimensions(entity, "clip")

        -- Apply pending rotation first so GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS works correctly
        local rot = Spooner.grabbedEntityRotation or ENTITY.GET_ENTITY_ROTATION(entity, 2)
        ENTITY.SET_ENTITY_ROTATION(entity, rot.x, rot.y, rot.z, 2, true)

        -- Define the 8 corners of the bounding box (same as Draw3DBox)
        local corners = {
            {minX, minY, minZ}, {maxX, minY, minZ},
            {maxX, maxY, minZ}, {minX, maxY, minZ},
            {minX, minY, maxZ}, {maxX, minY, maxZ},
            {maxX, maxY, maxZ}, {minX, maxY, maxZ}
        }

        -- Find the lowest world Z using the game's transformation
        local lowestWorldZ = math.huge
        for _, corner in ipairs(corners) do
            local worldPos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(entity, corner[1], corner[2], corner[3])
            if worldPos.z < lowestWorldZ then
                lowestWorldZ = worldPos.z
            end
        end

        -- Calculate how far the lowest point is from the entity origin
        local entityZ = ENTITY.GET_ENTITY_COORDS(entity, true).z
        local lowestOffset = lowestWorldZ - entityZ

        -- Calculate distance from lowest point to ground
        local projectedLowestZ = newPos.z + lowestOffset
        local distanceToGround = projectedLowestZ - groundZ

        -- If close enough to ground (above or below), snap to it
        if math.abs(distanceToGround) < CONSTANTS.CLIP_TO_GROUND_DISTANCE then
            newPos.z = groundZ - lowestOffset
        end
    end

    return newPos
end

function Spooner.StartGrabbing()
    if Spooner.isGrabbing or not Spooner.isEntityTargeted or Spooner.targetedEntity == nil then
        return false
    end

    Spooner.isGrabbing = true
    Spooner.grabbedEntity = Spooner.targetedEntity

    local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
    local entityPos = ENTITY.GET_ENTITY_COORDS(Spooner.grabbedEntity, true)
    local fwd, right, up, camRot = CameraUtils.GetBasis(Spooner.freecam)

    Spooner.grabOffsets = Spooner.CalculateGrabOffsets(camPos, entityPos, fwd, right, up)
    Spooner.grabbedEntityRotation = ENTITY.GET_ENTITY_ROTATION(Spooner.grabbedEntity, 2)
    Spooner.TakeControlOfEntity(Spooner.grabbedEntity)

    return true
end

function Spooner.UpdateGrabbedEntity()
    if not Spooner.previewEntity and (not Spooner.isGrabbing or not Spooner.grabbedEntity) then
        return
    end

    local entity = Spooner.grabbedEntity or Spooner.previewEntity

    Spooner.isEntityTargeted = true

    if not ENTITY.DOES_ENTITY_EXIST(entity) then
        Spooner.ReleaseEntity()
        return
    end

    local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
    local fwd, right, up, camRot = CameraUtils.GetBasis(Spooner.freecam)

    local speedMultiplier = Keybinds.MoveFaster.IsPressed() and CONSTANTS.ROTATION_SPEED_BOOST or 1.0

    local scrollSpeed = CONSTANTS.SCROLL_SPEED * speedMultiplier
    if Keybinds.PushEntity.IsPressed() then
        Spooner.grabOffsets.y = math.max(Spooner.grabOffsets.y - scrollSpeed, CONSTANTS.MIN_GRAB_DISTANCE)
    elseif Keybinds.PullEntity.IsPressed() then
        Spooner.grabOffsets.y = Spooner.grabOffsets.y + scrollSpeed
    end

    local rotationSpeed = CONSTANTS.ROTATION_SPEED * speedMultiplier
    -- Yaw (Z axis) - Q/E keys
    if Keybinds.RotateRight.IsPressed() then
        Spooner.grabbedEntityRotation.z = Spooner.grabbedEntityRotation.z - rotationSpeed
    elseif Keybinds.RotateLeft.IsPressed() then
        Spooner.grabbedEntityRotation.z = Spooner.grabbedEntityRotation.z + rotationSpeed
    end
    -- Pitch (X axis) - Arrow Up/Down
    if Keybinds.PitchUp.IsPressed() then
        Spooner.grabbedEntityRotation.x = Spooner.grabbedEntityRotation.x - rotationSpeed
    elseif Keybinds.PitchDown.IsPressed() then
        Spooner.grabbedEntityRotation.x = Spooner.grabbedEntityRotation.x + rotationSpeed
    end
    -- Clamp pitch to avoid gimbal lock
    Spooner.grabbedEntityRotation.x = math.max(CONSTANTS.PITCH_CLAMP_MIN, math.min(Spooner.grabbedEntityRotation.x, CONSTANTS.PITCH_CLAMP_MAX))
    -- Roll (Y axis) - Arrow Left/Right
    if Keybinds.RollLeft.IsPressed() then
        Spooner.grabbedEntityRotation.y = Spooner.grabbedEntityRotation.y - rotationSpeed
    elseif Keybinds.RollRight.IsPressed() then
        Spooner.grabbedEntityRotation.y = Spooner.grabbedEntityRotation.y + rotationSpeed
    end

    local newPos = Spooner.CalculateNewPosition(camPos, fwd, right, up, Spooner.grabOffsets)

    -- Apply clip to ground if enabled
    newPos = Spooner.ClipEntityToGround(entity, newPos)

    ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, newPos.x, newPos.y, newPos.z, false, false, false)

    ENTITY.SET_ENTITY_ROTATION(
        entity,
        Spooner.grabbedEntityRotation.x,
        Spooner.grabbedEntityRotation.y,
        Spooner.grabbedEntityRotation.z,
        2,
        true
    )

    if Spooner.throwableMode then
        if Spooner.lastEntityPos then
            Spooner.grabVelocity = {
                x = (newPos.x - Spooner.lastEntityPos.x) * Spooner.throwableVelocityMultiplier,
                y = (newPos.y - Spooner.lastEntityPos.y) * Spooner.throwableVelocityMultiplier,
                z = (newPos.z - Spooner.lastEntityPos.z) * Spooner.throwableVelocityMultiplier
            }
        end
        Spooner.lastEntityPos = newPos
    end
end

function Spooner.ReleaseEntity()
    if not Spooner.isGrabbing or not Spooner.grabbedEntity then
        return
    end

    if ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) and Spooner.throwableMode then
        ENTITY.APPLY_FORCE_TO_ENTITY(
            Spooner.grabbedEntity,
            1,
            Spooner.grabVelocity.x,
            Spooner.grabVelocity.y,
            Spooner.grabVelocity.z,
            0.0, 0.0, 0.0,
            0,
            false,
            true,
            true,
            false,
            true
        )
    end

    Spooner.isGrabbing = false
    Spooner.grabbedEntity = nil
    Spooner.lastEntityPos = nil
    Spooner.grabVelocity = {x = 0, y = 0, z = 0}
end

function Spooner.HandleEntityGrabbing()
    if not Spooner.inSpoonerMode or not Spooner.freecam then
        return
    end

    local isRightClickPressed = Keybinds.Grab.IsPressed()

    if not Spooner.previewModelHash and (not GUI.IsOpen() or not Spooner.lockMovementWhileMenuIsOpen) then
        if isRightClickPressed and (Spooner.isGrabbing or (Spooner.isEntityTargeted and Spooner.targetedEntity)) then
            if not Spooner.isGrabbing then
                Spooner.StartGrabbing()
            end
        else
            Spooner.ReleaseEntity()
        end
    end
    Spooner.UpdateGrabbedEntity()
end

function Spooner.UpdateFreecam()
    if not Spooner.inSpoonerMode or not Spooner.freecam then
        return
    end

    PAD.DISABLE_ALL_CONTROL_ACTIONS(0)

    local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
    local camRot = CAM.GET_CAM_ROT(Spooner.freecam, 2)

    local rightAxisX = PAD.GET_DISABLED_CONTROL_NORMAL(0, 220)
    local rightAxisY = PAD.GET_DISABLED_CONTROL_NORMAL(0, 221)

    camRot.z = camRot.z - (rightAxisX * Spooner.camRotSpeed)
    camRot.x = CameraUtils.ClampPitch(camRot.x - (rightAxisY * Spooner.camRotSpeed))
    camRot.y = 0.0

    local radZ = math.rad(camRot.z)
    local radX = math.rad(camRot.x)

    local forwardX = -math.sin(radZ) * math.cos(radX)
    local forwardY = math.cos(radZ) * math.cos(radX)
    local forwardZ = math.sin(radX)
    local rightX = math.cos(radZ)
    local rightY = math.sin(radZ)

    local moveForward = Keybinds.MoveForward.IsPressed()
    local moveBackward = Keybinds.MoveBackward.IsPressed()
    local moveLeft = Keybinds.MoveLeft.IsPressed()
    local moveRight = Keybinds.MoveRight.IsPressed()
    local moveUp = Keybinds.MoveUp.IsPressed()
    local moveDown = Keybinds.MoveDown.IsPressed()

    local speed = Spooner.camSpeed
    if Keybinds.MoveFaster.IsPressed() then
        speed = speed * CONSTANTS.CAMERA_SPEED_BOOST
    end

    camPos.x = camPos.x + (forwardX * (moveForward - moveBackward) * speed)
    camPos.y = camPos.y + (forwardY * (moveForward - moveBackward) * speed)
    camPos.z = camPos.z + (forwardZ * (moveForward - moveBackward) * speed)
    camPos.x = camPos.x + (rightX * (moveRight - moveLeft) * speed)
    camPos.y = camPos.y + (rightY * (moveRight - moveLeft) * speed)
    camPos.z = camPos.z + ((moveUp - moveDown) * speed)

    if not GUI.IsOpen() or not Spooner.lockMovementWhileMenuIsOpen then
        CAM.SET_CAM_COORD(Spooner.freecam, camPos.x, camPos.y, camPos.z)
        CAM.SET_CAM_ROT(Spooner.freecam, camRot.x, camRot.y, camRot.z, 2)
    end

    STREAMING.SET_FOCUS_POS_AND_VEL(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)
    HUD.LOCK_MINIMAP_POSITION(camPos.x, camPos.y)

    -- Update blip position
    if Spooner.freecamBlip then
        HUD.SET_BLIP_COORDS(Spooner.freecamBlip, camPos.x, camPos.y, camPos.z)
    end
end

function Spooner.ToggleSpoonerMode(f)
    if Spooner.inSpoonerMode == f then
        return
    end

    Spooner.inSpoonerMode = f
    if Spooner.inSpoonerMode then
        local camPos = CAM.GET_GAMEPLAY_CAM_COORD()
        local camRot = CAM.GET_GAMEPLAY_CAM_ROT(2)

        Spooner.freecam = CAM.CREATE_CAM("DEFAULT_SCRIPTED_CAMERA", true)
        CAM.SET_CAM_COORD(Spooner.freecam, camPos.x, camPos.y, camPos.z)
        CAM.SET_CAM_ROT(Spooner.freecam, camRot.x, 0.0, camRot.z, 2)
        CAM.SET_CAM_ACTIVE(Spooner.freecam, true)
        CAM.RENDER_SCRIPT_CAMS(true, false, 0, true, false, 0)
        CAM.SET_CAM_CONTROLS_MINI_MAP_HEADING(Spooner.freecam, true)

        -- Create blip for camera position
        Spooner.freecamBlip = HUD.ADD_BLIP_FOR_COORD(camPos.x, camPos.y, camPos.z)
        HUD.SET_BLIP_SPRITE(Spooner.freecamBlip, 184)  -- Eye/viewing sprite
        HUD.SET_BLIP_COLOUR(Spooner.freecamBlip, 5)    -- Yellow
        HUD.SET_BLIP_SCALE(Spooner.freecamBlip, 0.8)

        CustomLogger.Info("Freecam enabled")
    else
        if Spooner.freecam then
            STREAMING.CLEAR_FOCUS()
            HUD.UNLOCK_MINIMAP_POSITION()
            HUD.UNLOCK_MINIMAP_ANGLE()
            CAM.RENDER_SCRIPT_CAMS(false, false, 0, true, false, 0)
            CAM.SET_CAM_ACTIVE(Spooner.freecam, false)
            CAM.DESTROY_CAM(Spooner.freecam, false)
            Spooner.freecam = nil

            -- Remove camera blip
            if Spooner.freecamBlip then
                local ptr = MemoryUtils.AllocInt("blipPtr")
                Memory.WriteInt(ptr, Spooner.freecamBlip)
                HUD.REMOVE_BLIP(ptr)
                Spooner.freecamBlip = nil
            end

            CustomLogger.Info("Freecam disabled")
        end
    end
end

function Spooner.ToggleEntityInManagedList(entity)
    if not entity then
        return
    end

    for i, e in ipairs(Spooner.managedEntities) do
        if e == entity then
            table.remove(Spooner.managedEntities, i)
            CustomLogger.Info("Removed entity from managed list: " .. tostring(entity))
            return
        end
    end

    NetworkUtils.MakeEntityNetworked(entity)
    Spooner.TakeControlOfEntity(entity)
    table.insert(Spooner.managedEntities, entity)
    CustomLogger.Info("Entity added to managed list: " .. tostring(entity))
end

function Spooner.ManageEntities()
    if not Spooner.inSpoonerMode then
        return
    end

    -- Block adding to database while in preview mode
    if not Spooner.previewModelHash and Keybinds.AddOrRemoveFromList.IsPressed() then
        local entityToAdd = nil

        if Spooner.isGrabbing and Spooner.grabbedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
            entityToAdd = Spooner.grabbedEntity
        elseif Spooner.isEntityTargeted and Spooner.targetedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.targetedEntity) then
            entityToAdd = Spooner.targetedEntity
        end

        if entityToAdd then
            Spooner.ToggleEntityInManagedList(entityToAdd)
        end
    end

    for i = #Spooner.managedEntities, 1, -1 do
        local entity = Spooner.managedEntities[i]
        if ENTITY.DOES_ENTITY_EXIST(entity) then
            -- Use lighter function to maintain control without resetting ped tasks
            Spooner.TakeControlOfEntity(entity)
        else
            table.remove(Spooner.managedEntities, i)
            CustomLogger.Info("Removed invalid entity from list")
        end
    end
end

-- ============================================================================
-- Spawner
-- ============================================================================
local Spawner = {}

function Spawner.LoadModel(modelHash, timeout)
    timeout = timeout or 5000
    local startTime = Time.GetEpocheMs()

    STREAMING.REQUEST_MODEL(modelHash)
    while not STREAMING.HAS_MODEL_LOADED(modelHash) do
        if Time.GetEpocheMs() - startTime > timeout then
            CustomLogger.Error("Failed to load model: " .. tostring(modelHash))
            return false
        end
        Script.Yield(0)
    end
    return true
end

function Spawner.GetModelSize(modelHash)
    -- Load model temporarily to get dimensions
    STREAMING.REQUEST_MODEL(modelHash)
    local timeout = Time.GetEpocheMs() + 1000
    while not STREAMING.HAS_MODEL_LOADED(modelHash) and Time.GetEpocheMs() < timeout do
        Script.Yield(0)
    end

    if not STREAMING.HAS_MODEL_LOADED(modelHash) then
        return 10.0  -- Default distance if model can't load
    end

    local minX, minY, minZ, maxX, maxY, maxZ = Spooner.GetModelDimensions(modelHash, "modelSize")

    -- Calculate the diagonal size of the bounding box
    local sizeX = maxX - minX
    local sizeY = maxY - minY
    local sizeZ = maxZ - minZ
    local diagonalSize = math.sqrt(sizeX * sizeX + sizeY * sizeY + sizeZ * sizeZ)

    return diagonalSize
end

function Spawner.SelectEntity(entityType, modelName, modelHash)
    if Spooner.previewModelHash == modelHash then
        return
    end

    -- Clear existing preview if any, but keep the rotation
    Spawner.ClearPreview(true, false)

    -- Calculate preview distance based on model size
    Script.QueueJob(function()
        local modelSize = Spawner.GetModelSize(modelHash)
        -- Set preview distance to 1.5x the model diagonal size, with min/max bounds
        local previewDistance = math.max(5.0, math.min(modelSize * 1.5, 50.0))
        Spooner.grabOffsets = {x = 0, y = previewDistance, z = 0}

        Spooner.previewEntityType = entityType
        Spooner.previewModelName = modelName
        Spooner.previewModelHash = modelHash
    end)

    CustomLogger.Info("Selected " .. entityType .. ": " .. modelName .. " - Press Enter to spawn, Backspace to cancel")
end

function Spawner.SpawnProp(hashString, propName)
    local hash = Utils.sJoaat(hashString)
    local name = propName or hashString
    Spawner.SelectEntity("prop", name, hash)
end

function Spawner.SpawnVehicle(modelName)
    local hash = Utils.sJoaat(modelName)
    Spawner.SelectEntity("vehicle", modelName, hash)
end

function Spawner.SpawnPed(modelName)
    local hash = Utils.sJoaat(modelName)
    Spawner.SelectEntity("ped", modelName, hash)
end

function Spawner.ClearPreview(keepRotation, keepOffset)
    -- Queue the current preview entity for deletion in the game thread
    if Spooner.previewEntity then
        Spooner.pendingPreviewDelete = Spooner.previewEntity
    end
    Spooner.previewEntity = nil
    Spooner.previewModelHash = nil
    Spooner.previewEntityType = nil
    Spooner.previewModelName = nil
    if not keepRotation or not Spooner.grabbedEntityRotation then
        Spooner.grabbedEntityRotation = {x = 0, y = 0, z = 0}
    end
    if not keepOffset then
        Spooner.grabOffsets = {x = 0, y = 10.0, z = 0}
    end
end

function Spawner.CreatePreviewEntity(modelHash, entityType, pos)
    local entity = nil

    if entityType == "prop" then
        entity = GTA.CreateWorldObject(modelHash, pos.x, pos.y, pos.z, false, false)
    elseif entityType == "vehicle" then
        entity = GTA.SpawnVehicle(modelHash, pos.x, pos.y, pos.z, 0.0, false, false)
    elseif entityType == "ped" then
        entity = GTA.CreatePed(modelHash, 26, pos.x, pos.y, pos.z, 0.0, false, false)
    end

    if entity and entity ~= 0 then
        -- Make it intangible
        ENTITY.SET_ENTITY_COLLISION(entity, false, false)
        ENTITY.SET_ENTITY_INVINCIBLE(entity, true)
        ENTITY.FREEZE_ENTITY_POSITION(entity, true)

        if entityType == "ped" then
            PED.SET_BLOCKING_OF_NON_TEMPORARY_EVENTS(entity, true)
            TASK.TASK_SET_BLOCKING_OF_NON_TEMPORARY_EVENTS(entity, true)
            TASK.TASK_STAND_STILL(entity, -1)
        end
    end

    return entity
end

function Spawner.GetCrosshairWorldPosition()
    if not Spooner.freecam then
        return nil, false
    end

    local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
    local camRot = CAM.GET_CAM_ROT(Spooner.freecam, 2)

    local radZ = math.rad(camRot.z)
    local radX = math.rad(camRot.x)

    local fwdX = -math.sin(radZ) * math.cos(radX)
    local fwdY = math.cos(radZ) * math.cos(radX)
    local fwdZ = math.sin(radX)

    local defaultSpawnDistance = 10.0
    local maxRaycastDistance = 100.0

    -- Default position: in front of camera at fixed distance
    local defaultPos = {
        x = camPos.x + fwdX * defaultSpawnDistance,
        y = camPos.y + fwdY * defaultSpawnDistance,
        z = camPos.z + fwdZ * defaultSpawnDistance
    }

    -- Raycast to find ground/surface
    local hit = MemoryUtils.AllocInt("crosshairHit")
    local endCoords = MemoryUtils.AllocV3("crosshairEndCoords")
    local surfaceNormal = MemoryUtils.AllocV3("crosshairSurfaceNormal")
    local entityHit = MemoryUtils.AllocInt("crosshairEntityHit")

    local rayHandle = SHAPETEST.START_EXPENSIVE_SYNCHRONOUS_SHAPE_TEST_LOS_PROBE(
        camPos.x, camPos.y, camPos.z,
        camPos.x + fwdX * maxRaycastDistance,
        camPos.y + fwdY * maxRaycastDistance,
        camPos.z + fwdZ * maxRaycastDistance,
        -1,
        Spooner.previewEntity or 0,
        7
    )

    local result = SHAPETEST.GET_SHAPE_TEST_RESULT(rayHandle, hit, endCoords, surfaceNormal, entityHit)

    local hitResult = Memory.ReadInt(hit)
    local finalPos = defaultPos
    local didHitGround = false

    if hitResult == 1 then
        local hitV3 = MemoryUtils.ReadV3(endCoords)

        -- Calculate distance to hit point
        local dx = hit.x - camPos.x
        local dy = hit.y - camPos.y
        local dz = hit.z - camPos.z
        local hitDistance = math.sqrt(dx*dx + dy*dy + dz*dz)

        -- If hit is within reasonable distance, use it; otherwise spawn in front
        if hitDistance < maxRaycastDistance then
            finalPos = hitV3
            didHitGround = true
        end
    end

    return finalPos, didHitGround
end

function Spawner.UpdatePreview()
    -- Handle pending entity deletion (from UI thread selection)
    if Spooner.pendingPreviewDelete then
        if ENTITY.DOES_ENTITY_EXIST(Spooner.pendingPreviewDelete) then
            local ptr = MemoryUtils.AllocInt("previewDeletePtr")
            Memory.WriteInt(ptr, Spooner.pendingPreviewDelete)
            ENTITY.DELETE_ENTITY(ptr)
        end
        Spooner.pendingPreviewDelete = nil
    end

    if not Spooner.inSpoonerMode or not Spooner.previewModelHash then
        if Spooner.previewEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
            local ptr = MemoryUtils.AllocInt("previewEntityPtr")
            Memory.WriteInt(ptr, Spooner.previewEntity)
            ENTITY.DELETE_ENTITY(ptr)
            Spooner.previewEntity = nil
        end
        return
    end

    -- Create preview entity if needed
    if not Spooner.previewEntity or not ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
        Spooner.previewEntity = Spawner.CreatePreviewEntity(Spooner.previewModelHash, Spooner.previewEntityType, {x=0,y=0,z=0})
    end
end

function Spawner.ConfirmSpawn()
    if not Spooner.previewEntity or not ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
        return
    end

    -- Create actual entity
    Script.QueueJob(function()
        -- Remove status
        ENTITY.SET_ENTITY_COLLISION(Spooner.previewEntity, true, true)
        ENTITY.SET_ENTITY_INVINCIBLE(Spooner.previewEntity, false)
        if Spooner.previewEntityType ~= "prop" then
            ENTITY.FREEZE_ENTITY_POSITION(Spooner.previewEntity, false)
            ENTITY.SET_ENTITY_VELOCITY(Spooner.previewEntity, 0, 0 ,-1)
        end
        NetworkUtils.MakeEntityNetworked(Spooner.previewEntity)
        table.insert(Spooner.managedEntities, Spooner.previewEntity)
        CustomLogger.Info("Spawned " .. Spooner.previewEntityType .. ": " .. Spooner.previewModelName)
        Spooner.previewEntity = Spawner.CreatePreviewEntity(Spooner.previewModelHash, Spooner.previewEntityType, {x=0,y=0,z=0})
    end)
end

function Spawner.HandleInput()
    if not Spooner.inSpoonerMode or not Spooner.previewModelHash then
        return
    end

    -- Confirm spawn with Enter
    if Keybinds.ConfirmSpawn.IsPressed() then
        Spawner.ConfirmSpawn()
    end

    -- Cancel with Backspace
    if Keybinds.CancelSpawn.IsPressed() then
        Spawner.ClearPreview()
        CustomLogger.Info("Spawn cancelled")
    end
end

-- ============================================================================
-- Draw Manager
-- ============================================================================
local DrawManager = {}

function DrawManager.PerformRaycastCheck()
    if Spooner.isGrabbing then return end

    local isTargeted, targetedEntity = Raycast.PerformCheckForFreecam(
        Spooner.freecam
    )

    if isTargeted and not Spooner.IsEntityRestricted(targetedEntity) then
        Spooner.isEntityTargeted = true
        Spooner.targetedEntity = targetedEntity
    elseif Raycast.data == nil then
        -- Only reset when raycast completed (not while waiting)
        Spooner.isEntityTargeted = false
        Spooner.targetedEntity = nil
    end
end

function DrawManager.DrawCrosshair()
    if not Spooner.inSpoonerMode then
        return
    end

    -- Skip raycast check and entity targeting visuals while in preview mode
    if not Spooner.previewModelHash then
        DrawManager.PerformRaycastCheck()
    end

    -- In preview mode, always use white crosshair (no entity targeting)
    local isTargeting = not Spooner.previewModelHash and Spooner.isEntityTargeted
    local color = isTargeting and Spooner.crosshairColorGreen or Spooner.crosshairColor
    local size = Spooner.crosshairSize
    local gap = Spooner.crosshairGap
    local aspectRatio = GRAPHICS.GET_SCREEN_ASPECT_RATIO()

    local sizeX = size / aspectRatio
    local sizeY = size
    local thicknessX = Spooner.crosshairThickness
    local thicknessY = Spooner.crosshairThickness * aspectRatio

    GRAPHICS.DRAW_RECT(0.5 - gap - sizeX / 2, 0.5, sizeX, thicknessY, color.r, color.g, color.b, color.a, false)
    GRAPHICS.DRAW_RECT(0.5 + gap + sizeX / 2, 0.5, sizeX, thicknessY, color.r, color.g, color.b, color.a, false)
    GRAPHICS.DRAW_RECT(0.5, 0.5 - gap - sizeY / 2, thicknessX, sizeY, color.r, color.g, color.b, color.a, false)
    GRAPHICS.DRAW_RECT(0.5, 0.5 + gap + sizeY / 2, thicknessX, sizeY, color.r, color.g, color.b, color.a, false)
end

function DrawManager.AddInstructionalButton(buttonIndex, keyString, label)
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(keyString)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(label)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
end

function DrawManager.AddInstructionalButtonMulti(buttonIndex, keyStrings, label)
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
    for _, keyString in ipairs(keyStrings) do
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(keyString)
    end
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(label)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
end

function DrawManager.DrawInstructionalButtons()
    if not Spooner.inSpoonerMode then
        return
    end

    if not Spooner.scaleform then
        Spooner.scaleform = GRAPHICS.REQUEST_SCALEFORM_MOVIE("instructional_buttons")
    end

    if not GRAPHICS.HAS_SCALEFORM_MOVIE_LOADED(Spooner.scaleform) then
        return
    end

    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "CLEAR_ALL")
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "TOGGLE_MOUSE_BUTTONS")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_BOOL(false)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_CLEAR_SPACE")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(200)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    local buttonIndex = 0

    -- In preview mode
    if Spooner.previewModelHash then
        DrawManager.AddInstructionalButton(buttonIndex, Keybinds.ConfirmSpawn.string, "Spawn Entity")
        buttonIndex = buttonIndex + 1

        DrawManager.AddInstructionalButton(buttonIndex, Keybinds.CancelSpawn.string, "Cancel")
        buttonIndex = buttonIndex + 1
    end

    -- Normal mode keybinds
    if not Spooner.previewEntity then
        local grabLabel = Spooner.isGrabbing and "Release Entity" or "Grab Entity"
        DrawManager.AddInstructionalButton(buttonIndex, Keybinds.Grab.string, grabLabel)
        buttonIndex = buttonIndex + 1
    end

    if Spooner.isGrabbing or Spooner.previewEntity then
        DrawManager.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.RotateLeft.string, Keybinds.RotateRight.string},
            "Yaw"
        )
        buttonIndex = buttonIndex + 1

        DrawManager.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.PitchUp.string, Keybinds.PitchDown.string},
            "Pitch"
        )
        buttonIndex = buttonIndex + 1

        DrawManager.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.RollLeft.string, Keybinds.RollRight.string},
            "Roll"
        )
        buttonIndex = buttonIndex + 1

        DrawManager.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.PushEntity.string, Keybinds.PullEntity.string},
            "Push / Pull Entity"
        )
        buttonIndex = buttonIndex + 1
    end

    local entityToCheck = not Spooner.previewEntity and (Spooner.isGrabbing and Spooner.grabbedEntity or
                            (Spooner.isEntityTargeted and Spooner.targetedEntity or nil))

    if entityToCheck and ENTITY.DOES_ENTITY_EXIST(entityToCheck) then
        local isManaged = false
        for _, e in ipairs(Spooner.managedEntities) do
            if e == entityToCheck then
                isManaged = true
                break
            end
        end

        local listLabel = isManaged and "Remove from List" or "Add to List"
        DrawManager.AddInstructionalButton(buttonIndex, Keybinds.AddOrRemoveFromList.string, listLabel)
        buttonIndex = buttonIndex + 1
    end

    DrawManager.AddInstructionalButton(buttonIndex, Keybinds.MoveFaster.string, "Move Faster")
    buttonIndex = buttonIndex + 1

    DrawManager.AddInstructionalButtonMulti(
        buttonIndex,
        {Keybinds.MoveUp.string, Keybinds.MoveDown.string},
        "Up / Down"
    )
    buttonIndex = buttonIndex + 1

    DrawManager.AddInstructionalButtonMulti(
        buttonIndex,
        {Keybinds.MoveRight.string, Keybinds.MoveLeft.string, Keybinds.MoveBackward.string, Keybinds.MoveForward.string},
        "Move Camera"
    )
    buttonIndex = buttonIndex + 1

    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "DRAW_INSTRUCTIONAL_BUTTONS")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(-1)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    GRAPHICS.DRAW_SCALEFORM_MOVIE_FULLSCREEN(Spooner.scaleform, 255, 255, 255, 255, 0)
end

function DrawManager.GetEntityName(entity)
    if not ENTITY.DOES_ENTITY_EXIST(entity) then
        return "Invalid Entity"
    end

    local modelHash = ENTITY.GET_ENTITY_MODEL(entity)

    if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
        -- Get the display name (like "Adder" instead of "adder")
        local displayName = GTA.GetDisplayNameFromHash(modelHash)
        local plate = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(entity)
        if displayName and displayName ~= "" and displayName ~= "NULL" then
            return displayName .. " [" .. plate .. "]"
        end
        return GTA.GetModelNameFromHash(modelHash) .. " [" .. plate .. "]"
    end

    -- Check cache first for peds and props
    local cachedName = EntityLists.NameCache[modelHash]
    if cachedName then
        return cachedName
    end

    -- Fallback to model name
    return GTA.GetModelNameFromHash(modelHash)
end

function DrawManager.Draw3DBox(entity)
    if not ENTITY.DOES_ENTITY_EXIST(entity) then
        return
    end

    -- Get entity bounding box
    local minX, minY, minZ, maxX, maxY, maxZ = Spooner.GetEntityDimensions(entity, "3DBox")

    -- Calculate the 8 corners of the bounding box
    local corners = {
        {minX, minY, minZ}, -- bottom front left
        {maxX, minY, minZ}, -- bottom front right
        {maxX, maxY, minZ}, -- bottom back right
        {minX, maxY, minZ}, -- bottom back left
        {minX, minY, maxZ}, -- top front left
        {maxX, minY, maxZ}, -- top front right
        {maxX, maxY, maxZ}, -- top back right
        {minX, maxY, maxZ}  -- top back left
    }

    -- Transform corners to world space
    local worldCorners = {}
    for _, corner in ipairs(corners) do
        local worldPos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(entity, corner[1], corner[2], corner[3])
        table.insert(worldCorners, worldPos)
    end

    -- Draw bottom edges (RED)
    GRAPHICS.DRAW_LINE(worldCorners[1].x, worldCorners[1].y, worldCorners[1].z,
                       worldCorners[2].x, worldCorners[2].y, worldCorners[2].z, 255, 0, 0, 255)
    GRAPHICS.DRAW_LINE(worldCorners[2].x, worldCorners[2].y, worldCorners[2].z,
                       worldCorners[3].x, worldCorners[3].y, worldCorners[3].z, 255, 0, 0, 255)
    GRAPHICS.DRAW_LINE(worldCorners[3].x, worldCorners[3].y, worldCorners[3].z,
                       worldCorners[4].x, worldCorners[4].y, worldCorners[4].z, 255, 0, 0, 255)
    GRAPHICS.DRAW_LINE(worldCorners[4].x, worldCorners[4].y, worldCorners[4].z,
                       worldCorners[1].x, worldCorners[1].y, worldCorners[1].z, 255, 0, 0, 255)

    -- Draw top edges (BLUE)
    GRAPHICS.DRAW_LINE(worldCorners[5].x, worldCorners[5].y, worldCorners[5].z,
                       worldCorners[6].x, worldCorners[6].y, worldCorners[6].z, 0, 0, 255, 255)
    GRAPHICS.DRAW_LINE(worldCorners[6].x, worldCorners[6].y, worldCorners[6].z,
                       worldCorners[7].x, worldCorners[7].y, worldCorners[7].z, 0, 0, 255, 255)
    GRAPHICS.DRAW_LINE(worldCorners[7].x, worldCorners[7].y, worldCorners[7].z,
                       worldCorners[8].x, worldCorners[8].y, worldCorners[8].z, 0, 0, 255, 255)
    GRAPHICS.DRAW_LINE(worldCorners[8].x, worldCorners[8].y, worldCorners[8].z,
                       worldCorners[5].x, worldCorners[5].y, worldCorners[5].z, 0, 0, 255, 255)

    -- Draw vertical edges connecting bottom to top (GREEN)
    GRAPHICS.DRAW_LINE(worldCorners[1].x, worldCorners[1].y, worldCorners[1].z,
                       worldCorners[5].x, worldCorners[5].y, worldCorners[5].z, 0, 255, 0, 255)
    GRAPHICS.DRAW_LINE(worldCorners[2].x, worldCorners[2].y, worldCorners[2].z,
                       worldCorners[6].x, worldCorners[6].y, worldCorners[6].z, 0, 255, 0, 255)
    GRAPHICS.DRAW_LINE(worldCorners[3].x, worldCorners[3].y, worldCorners[3].z,
                       worldCorners[7].x, worldCorners[7].y, worldCorners[7].z, 0, 255, 0, 255)
    GRAPHICS.DRAW_LINE(worldCorners[4].x, worldCorners[4].y, worldCorners[4].z,
                       worldCorners[8].x, worldCorners[8].y, worldCorners[8].z, 0, 255, 0, 255)
end

function DrawManager.DrawTargetedEntityBox()
    if not Spooner.inSpoonerMode then
        return
    end

    -- In preview mode, only draw box on preview entity
    if Spooner.previewModelHash then
        if Spooner.previewEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
            DrawManager.Draw3DBox(Spooner.previewEntity)
        end
        return
    end

    -- Draw box on targeted entity
    if Spooner.isEntityTargeted and Spooner.targetedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.targetedEntity) then
        DrawManager.Draw3DBox(Spooner.targetedEntity)
    end

    -- Draw box on grabbed entity
    if Spooner.isGrabbing and Spooner.grabbedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
        DrawManager.Draw3DBox(Spooner.grabbedEntity)
    end
end

function DrawManager.DrawSelectedEntityMarker()
    if not Spooner.inSpoonerMode then
        return
    end

    if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
        local entity = Spooner.managedEntities[Spooner.selectedEntityIndex]
        if ENTITY.DOES_ENTITY_EXIST(entity) then
            local pos = ENTITY.GET_ENTITY_COORDS(entity, true)
            GRAPHICS.DRAW_MARKER(
                28,
                pos.x, pos.y, pos.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                0.3, 0.3, 0.3,
                255, 0, 0, 150,
                false, false, 2, false, nil, nil, false
            )
        end
    end
end

function DrawManager.ClickGUIInit()
    ClickGUI.AddTab(pluginName, function()
        if ClickGUI.BeginCustomChildWindow("Spooner") then
            ClickGUI.RenderFeature(Utils.Joaat("ToggleSpoonerMode"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_MakeMissionEntity"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableF9Key"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableThrowableMode"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableClipToGround"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_LockMovementWhileMenuIsOpen"))

            ClickGUI.EndCustomChildWindow()
        end

        -- Managed Entities Database Section
        if ClickGUI.BeginCustomChildWindow("Managed Entities Database") then
            -- Categorize entities by type
            local vehicles = {}
            local peds = {}
            local props = {}

            for i, entity in ipairs(Spooner.managedEntities) do
                if ENTITY.DOES_ENTITY_EXIST(entity) then
                    if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
                        table.insert(vehicles, {index = i, entity = entity})
                    elseif ENTITY.IS_ENTITY_A_PED(entity) then
                        table.insert(peds, {index = i, entity = entity})
                    else
                        table.insert(props, {index = i, entity = entity})
                    end
                end
            end

            if ImGui.BeginTabBar("DatabaseTabs", 0) then
                -- Vehicles Tab
                if ImGui.BeginTabItem("Vehicles (" .. #vehicles .. ")") then
                    if #vehicles == 0 then
                        ImGui.Text("No vehicles in database")
                    else
                        for _, item in ipairs(vehicles) do
                            local label = DrawManager.GetEntityName(item.entity)
                            local isSelected = (item.index == Spooner.selectedEntityIndex)
                            if ImGui.Selectable(label .. "##veh_" .. item.index, isSelected) then
                                Spooner.selectedEntityIndex = item.index
                                Spooner.UpdateFreezeToggleForEntity(item.entity)
                            end
                        end
                    end
                    ImGui.EndTabItem()
                end

                -- Peds Tab
                if ImGui.BeginTabItem("Peds (" .. #peds .. ")") then
                    if #peds == 0 then
                        ImGui.Text("No peds in database")
                    else
                        for _, item in ipairs(peds) do
                            local label = DrawManager.GetEntityName(item.entity)
                            local isSelected = (item.index == Spooner.selectedEntityIndex)
                            if ImGui.Selectable(label .. "##ped_" .. item.index, isSelected) then
                                Spooner.selectedEntityIndex = item.index
                                Spooner.UpdateFreezeToggleForEntity(item.entity)
                            end
                        end
                    end
                    ImGui.EndTabItem()
                end

                -- Props Tab
                if ImGui.BeginTabItem("Props (" .. #props .. ")") then
                    if #props == 0 then
                        ImGui.Text("No props in database")
                    else
                        for _, item in ipairs(props) do
                            local label = DrawManager.GetEntityName(item.entity)
                            local isSelected = (item.index == Spooner.selectedEntityIndex)
                            if ImGui.Selectable(label .. "##prop_" .. item.index, isSelected) then
                                Spooner.selectedEntityIndex = item.index
                                Spooner.UpdateFreezeToggleForEntity(item.entity)
                            end
                        end
                    end
                    ImGui.EndTabItem()
                end

                ImGui.EndTabBar()
            end

            ImGui.Separator()
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_RemoveEntity"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_DeleteEntity"))

            ClickGUI.EndCustomChildWindow()
        end

        -- Manual Position/Rotation Control Section
        if ClickGUI.BeginCustomChildWindow("Entity Transform") then
            if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
                local entity = Spooner.managedEntities[Spooner.selectedEntityIndex]
                if ENTITY.DOES_ENTITY_EXIST(entity) then
                    local pos = ENTITY.GET_ENTITY_COORDS(entity, true)
                    local rot = ENTITY.GET_ENTITY_ROTATION(entity, 2)

                    -- Freeze toggle to prevent physics interference during rotation
                    ClickGUI.RenderFeature(Utils.Joaat("Spooner_FreezeSelectedEntity"))
                    ImGui.Spacing()

                    ImGui.Text("Position")
                    ImGui.Separator()

                    -- Position step slider
                    local newStep, changedStep = ImGui.SliderFloat("Step##pos", Config.positionStep, 0.1, 5.0)
                    if changedStep then
                        Config.positionStep = newStep
                        SaveConfig()
                    end

                    -- X Position slider
                    local newX, changedX = ImGui.SliderFloat("X##pos", pos.x, pos.x - Config.positionStep, pos.x + Config.positionStep)
                    if changedX then
                        Script.QueueJob(function()
                            Spooner.TakeControlOfEntity(entity)
                            ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, newX, pos.y, pos.z, false, false, false)
                        end)
                    end

                    -- Y Position slider
                    local newY, changedY = ImGui.SliderFloat("Y##pos", pos.y, pos.y - Config.positionStep, pos.y + Config.positionStep)
                    if changedY then
                        Script.QueueJob(function()
                            Spooner.TakeControlOfEntity(entity)
                            ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, pos.x, newY, pos.z, false, false, false)
                        end)
                    end

                    -- Z Position slider
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

                    -- Pitch (X rotation) slider - clamped to +/-89 to avoid gimbal lock flip
                    local newPitch, changedPitch = ImGui.SliderFloat("Pitch##rot", rot.x, -89.0, 89.0)
                    if changedPitch then
                        Script.QueueJob(function()
                            Spooner.TakeControlOfEntity(entity)
                            ENTITY.SET_ENTITY_ROTATION(entity, newPitch, rot.y, rot.z, 2, true)
                        end)
                    end

                    -- Roll (Y rotation) slider - clamped to +/-89 to avoid gimbal lock flip
                    local newRoll, changedRoll = ImGui.SliderFloat("Roll##rot", rot.y, -89.0, 89.0)
                    if changedRoll then
                        Script.QueueJob(function()
                            Spooner.TakeControlOfEntity(entity)
                            ENTITY.SET_ENTITY_ROTATION(entity, rot.x, newRoll, rot.z, 2, true)
                        end)
                    end

                    -- Yaw (Z rotation) slider
                    local newYaw, changedYaw = ImGui.SliderFloat("Yaw##rot", rot.z, -180.0, 180.0)
                    if changedYaw then
                        Script.QueueJob(function()
                            Spooner.TakeControlOfEntity(entity)
                            ENTITY.SET_ENTITY_ROTATION(entity, rot.x, rot.y, newYaw, 2, true)
                        end)
                    end

                    ImGui.Spacing()
                    ImGui.Separator()

                    -- Teleport to entity button
                    if ImGui.Button("Teleport to Entity") then
                        Script.QueueJob(function()
                            local entityPos = ENTITY.GET_ENTITY_COORDS(entity, true)
                            if Spooner.inSpoonerMode and Spooner.freecam then
                                CAM.SET_CAM_COORD(Spooner.freecam, entityPos.x, entityPos.y - 5.0, entityPos.z + 2.0)
                            else
                                local playerPed = PLAYER.PLAYER_PED_ID()
                                ENTITY.SET_ENTITY_COORDS_NO_OFFSET(playerPed, entityPos.x, entityPos.y, entityPos.z + 1.0, false, false, false)
                            end
                        end)
                    end

                    ImGui.SameLine()

                    -- Teleport entity to camera/player button
                    if ImGui.Button("Teleport Entity Here") then
                        Script.QueueJob(function()
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
                        end)
                    end
                else
                    ImGui.Text("Selected entity no longer exists")
                end
            else
                ImGui.Text("Select an entity from the database above")
            end
            ClickGUI.EndCustomChildWindow()
        end

        -- Entity Spawner Section
        if ClickGUI.BeginCustomChildWindow("Entity Spawner") then
            if ImGui.BeginTabBar("SpawnerTabs", 0) then
                -- Props Tab
                if ImGui.BeginTabItem("Props") then
                    -- Filter input (InputText returns: newValue, changed)
                    local newPropFilter, propFilterChanged = ImGui.InputText("Prop Filter", EntityLists.PropFilter, 256)
                    if propFilterChanged and type(newPropFilter) == "string" then
                        EntityLists.PropFilter = newPropFilter
                    end

                    local filterLower = (EntityLists.PropFilter or ""):lower()

                    -- Sort categories alphabetically
                    local sortedCategories = {}
                    for categoryName, _ in pairs(EntityLists.Props) do
                        table.insert(sortedCategories, categoryName)
                    end
                    table.sort(sortedCategories)

                    for _, categoryName in ipairs(sortedCategories) do
                        local props = EntityLists.Props[categoryName]
                        -- Filter items within category
                        local filteredProps = {}
                        for _, prop in ipairs(props) do
                            if filterLower == "" or prop.name:lower():find(filterLower, 1, true) then
                                table.insert(filteredProps, prop)
                            end
                        end

                        -- Only show category if it has matching items or filter is empty
                        if #filteredProps > 0 then
                            -- Auto-expand when filtering (32 = TreeNodeFlags_DefaultOpen)
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
                    -- Filter input (InputText returns: newValue, changed)
                    local newVehFilter, vehFilterChanged = ImGui.InputText("Vehicle Filter", EntityLists.VehicleFilter, 256)
                    if vehFilterChanged and type(newVehFilter) == "string" then
                        EntityLists.VehicleFilter = newVehFilter
                    end

                    local filterLower = (EntityLists.VehicleFilter or ""):lower()

                    -- Sort categories alphabetically
                    local sortedCategories = {}
                    for categoryName, _ in pairs(EntityLists.Vehicles) do
                        table.insert(sortedCategories, categoryName)
                    end
                    table.sort(sortedCategories)

                    for _, categoryName in ipairs(sortedCategories) do
                        local vehicles = EntityLists.Vehicles[categoryName]
                        -- Filter items within category
                        local filteredVehicles = {}
                        for _, vehicle in ipairs(vehicles) do
                            local displayName = GTA.GetDisplayNameFromHash(Utils.Joaat(vehicle.name))
                            if filterLower == "" or vehicle.name:lower():find(filterLower, 1, true) or displayName:lower():find(filterLower, 1, true) then
                                table.insert(filteredVehicles, {vehicle = vehicle, displayName = displayName})
                            end
                        end

                        -- Only show category if it has matching items
                        if #filteredVehicles > 0 then
                            -- Auto-expand when filtering (32 = TreeNodeFlags_DefaultOpen)
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
                    -- Filter input (InputText returns: newValue, changed)
                    local newPedFilter, pedFilterChanged = ImGui.InputText("Ped Filter", EntityLists.PedFilter, 256)
                    if pedFilterChanged and type(newPedFilter) == "string" then
                        EntityLists.PedFilter = newPedFilter
                    end

                    local filterLower = (EntityLists.PedFilter or ""):lower()

                    -- Sort categories alphabetically
                    local sortedCategories = {}
                    for categoryName, _ in pairs(EntityLists.Peds) do
                        table.insert(sortedCategories, categoryName)
                    end
                    table.sort(sortedCategories)

                    for _, categoryName in ipairs(sortedCategories) do
                        local peds = EntityLists.Peds[categoryName]
                        -- Filter items within category
                        local filteredPeds = {}
                        for _, ped in ipairs(peds) do
                            local displayName = ped.caption ~= "" and ped.caption or ped.name
                            if filterLower == "" or ped.name:lower():find(filterLower, 1, true) or displayName:lower():find(filterLower, 1, true) then
                                table.insert(filteredPeds, {ped = ped, displayName = displayName})
                            end
                        end

                        -- Only show category if it has matching items
                        if #filteredPeds > 0 then
                            -- Auto-expand when filtering (32 = TreeNodeFlags_DefaultOpen)
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
    end)
end

-- ============================================================================
-- Features
-- ============================================================================
local toggleSpoonerModeFeature = FeatureMgr.AddFeature(
    Utils.Joaat("ToggleSpoonerMode"),
    "Toggle Spooner Mode",
    eFeatureType.Toggle,
    "Toggle Spooner Mode",
    function(f)
        Spooner.ToggleSpoonerMode(f:IsToggled())
    end
)

local makeMissionEntityFeature = FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_MakeMissionEntity"),
    "Set as Mission Entity",
    eFeatureType.Toggle,
    "Automatically set entities as mission entities (Better networking)",
    function(f)
        Spooner.makeMissionEntity = f:IsToggled()
    end
)
makeMissionEntityFeature:Toggle()

FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_RemoveEntity"),
    "Remove from List",
    eFeatureType.Button,
    "Remove selected entity from tracking",
    function(f)
        if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
            table.remove(Spooner.managedEntities, Spooner.selectedEntityIndex)
        else
            GUI.AddToast("Spooner", "No valid entity selected", 2000, eToastPos.BOTTOM_RIGHT)
        end
    end
)

local isRunningFreeze = false

local freezeEntityFeature = FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_FreezeSelectedEntity"),
    "Freeze Entity",
    eFeatureType.Toggle,
    "Freeze entity position",
    function(f)
        isRunningFreeze = true
        if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
            local entity = Spooner.managedEntities[Spooner.selectedEntityIndex]
            if ENTITY.DOES_ENTITY_EXIST(entity) then
                Script.QueueJob(function()
                    Spooner.TakeControlOfEntity(entity)
                    local frozen = f:IsToggled()
                    ENTITY.FREEZE_ENTITY_POSITION(entity, frozen)

                    -- When unfreezing, activate physics so entity responds to gravity
                    if not frozen then
                        ENTITY.SET_ENTITY_DYNAMIC(entity, true)
                        ENTITY.SET_ENTITY_HAS_GRAVITY(entity, true)
                        -- Apply small downward force to kickstart physics
                        ENTITY.APPLY_FORCE_TO_ENTITY(entity, 1, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                    end

                    isRunningFreeze = false
                end)
            end
        end
    end
)

-- Helper function to update freeze toggle when selecting a new entity
function Spooner.UpdateFreezeToggleForEntity(entity)
    if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
        -- Check frozen state via memory (offset 0x2E, bit 1)
        local isFrozen = false
        local pEntity = GTA.HandleToPointer(entity)
        if pEntity then
            local address = pEntity:GetAddress()
            local frozenByte = Memory.ReadByte(address + 0x2E)
            isFrozen = (frozenByte & (1 << 1)) ~= 0
        end
        local isToggled = freezeEntityFeature:IsToggled()
        if isFrozen ~= isToggled and not isRunningFreeze then
            freezeEntityFeature:Toggle(isFrozen)
        end
    end
end

FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_DeleteEntity"),
    "Delete Entity",
    eFeatureType.Button,
    "Delete selected entity from the game",
    function(f)
        if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
            local entity = Spooner.managedEntities[Spooner.selectedEntityIndex]

            CustomLogger.Info("Deleting entity: " .. tostring(entity))

            if ENTITY.DOES_ENTITY_EXIST(entity) then
                Script.QueueJob(function()
                    local netId = Spooner.TakeControlOfEntity(entity)

                    local ptr = MemoryUtils.AllocInt("deleteEntityPtr")
                    Memory.WriteInt(ptr, entity)

                    NETWORK.SET_NETWORK_ID_EXISTS_ON_ALL_MACHINES(netId, false)
                    NETWORK.SET_NETWORK_ID_ALWAYS_EXISTS_FOR_PLAYER(netId, PLAYER.PLAYER_ID(), false)
                    NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netId, true)
                    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, false, true)
                    ENTITY.DELETE_ENTITY(ptr)

                    CustomLogger.Info("Network ID: " .. tostring(netId))

                    if ENTITY.DOES_ENTITY_EXIST(entity) then
                        ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, 0, 0, 0, false, false, false)
                    end

                    CustomLogger.Info("Deleted entity: " .. tostring(entity))
                end)

                table.remove(Spooner.managedEntities, Spooner.selectedEntityIndex)
            end
        else
            GUI.AddToast("Spooner", "No valid entity selected", 2000, eToastPos.BOTTOM_RIGHT)
        end
    end
)

local enableF9KeyFeature = FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_EnableF9Key"),
    "Enable F9 Key",
    eFeatureType.Toggle,
    "Enable F9 key to toggle freecam",
    function(f)
        Config.enableF9Key = f:IsToggled()
        if Config.enableF9Key then
            toggleSpoonerModeFeature:AddHotKey(120)
        else
            toggleSpoonerModeFeature:RemoveHotkey(120, false)
        end
        SaveConfig()
    end
)

local enableThrowableModeFeature = FeatureMgr.AddFeature(
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

local enableClipToGroundFeature = FeatureMgr.AddFeature(
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

local lockMovementWhileMenuIsOpenFeature = FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_LockMovementWhileMenuIsOpen"),
    "Lock Movement while menu is open",
    eFeatureType.Toggle,
    "Lock cam movement and entity grab while menu is open",
    function (f)
        Config.lockMovementWhileMenuIsOpen = f:IsToggled()
        Spooner.lockMovementWhileMenuIsOpen = Config.lockMovementWhileMenuIsOpen
        SaveConfig()
    end
)

-- ============================================================================
-- Initialization
-- ============================================================================
-- Load configuration and restore settings
LoadConfig()

-- Restore F9 key setting
if Config.enableF9Key then
    enableF9KeyFeature:Toggle()
end

-- Restore throwable mode setting
if Config.throwableMode then
    enableThrowableModeFeature:Toggle()
end

-- Restore clip to ground setting
if Config.clipToGround then
    enableClipToGroundFeature:Toggle()
end

-- Restore lock movement while menu is open setting
if Config.lockMovementWhileMenuIsOpen then
    lockMovementWhileMenuIsOpenFeature:Toggle()
end

-- Load entities
EntityLists.LoadAll(propListPath, vehicleListPath, pedListPath)

DrawManager.ClickGUIInit()

-- Thread for movement and action
Script.RegisterLooped(function()
    Script.QueueJob(function()
        Spooner.UpdateFreecam()
        Spawner.HandleInput()
        Spawner.UpdatePreview()
    end)
end)

-- Thread for on screen display
Script.RegisterLooped(function()
    Script.QueueJob(function()
        DrawManager.DrawCrosshair()
        DrawManager.DrawInstructionalButtons()
        DrawManager.DrawSelectedEntityMarker()
    end)
end)

Script.RegisterLooped(function()
    if Spooner.inSpoonerMode then
        Script.QueueJob(function()
            Spooner.HandleEntityGrabbing()
            DrawManager.DrawTargetedEntityBox()
        end)
    end
end)

Script.RegisterLooped(function()
    if Spooner.grabbedEntity then
        Script.QueueJob(function() 
            Spooner.TakeControlOfEntity(Spooner.targetedEntity)
        end)
    elseif Spooner.targetedEntity then
        Script.QueueJob(function() 
            Spooner.TakeControlOfEntity(Spooner.targetedEntity)
        end)
    end
end)

Script.RegisterLooped(function()
    Script.QueueJob(function()
        Spooner.ManageEntities()
    end)
end)

EventMgr.RegisterHandler(eLuaEvent.ON_UNLOAD, function()
    if Spooner.inSpoonerMode then
        Script.QueueJob(function()
            toggleSpoonerModeFeature:Toggle()
        end)
    end
    -- Free all cached memory allocations
    MemoryUtils.FreeAll()
end)
