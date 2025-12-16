local pluginName = "Spooner"
local menuRootPath = FileMgr.GetMenuRootPath() .. "\\Lua\\" .. pluginName
local nativesPath = menuRootPath .. "\\Assets\\natives.lua"
local configPath = menuRootPath .. "\\config.txt"

FileMgr.CreateDir(menuRootPath)
FileMgr.CreateDir(menuRootPath .. "\\Assets")

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
}

-- ============================================================================
-- Custom Logger
-- ============================================================================
local CustomLogger = {}

function CustomLogger.Info(str)
    Logger.Log(eLogColor.WHITE, pluginName, str)
end

function CustomLogger.Warn(str)
    Logger.Log(eLogColor.YELLOW, pluginName, str)
end

function CustomLogger.Error(str)
    Logger.Log(eLogColor.RED, pluginName, str)
end

-- ============================================================================
-- Utilities
-- ============================================================================
local function DownloadAndSaveLuaFile(url, filePath)
    local curlObject = Curl.Easy()
    curlObject:Setopt(eCurlOption.CURLOPT_URL, url)
    curlObject:AddHeader("User-Agent: Lua-Curl-Client")
    curlObject:Perform()

    while not curlObject:GetFinished() do
        Script.Yield(0)
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
-- Network Utilities (Credits to themilkman554)
-- ============================================================================
local NetworkUtils = {}

function NetworkUtils.SetEntityAsNetworked(entity, timeout)
    local time = Time.GetEpocheMs() + (timeout or CONSTANTS.NETWORK_TIMEOUT)
    while time > Time.GetEpocheMs() and not NETWORK.NETWORK_GET_ENTITY_IS_NETWORKED(entity) do
        NETWORK.NETWORK_REGISTER_ENTITY_AS_NETWORKED(entity)
        Script.Yield(0)
    end
    return NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(entity)
end

function NetworkUtils.ConstantizeNetworkId(entity)
    local netId = NetworkUtils.SetEntityAsNetworked(entity, CONSTANTS.NETWORK_TIMEOUT_SHORT)
    NETWORK.SET_NETWORK_ID_EXISTS_ON_ALL_MACHINES(netId, true)
    NETWORK.SET_NETWORK_ID_ALWAYS_EXISTS_FOR_PLAYER(netId, PLAYER.PLAYER_ID(), true)
    return netId
end

function NetworkUtils.MakeEntityNetworked(entity)
    if not DECORATOR.DECOR_EXIST_ON(entity, "PV_Slot") then
        ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, false, true)
    end
    ENTITY.SET_ENTITY_SHOULD_FREEZE_WAITING_ON_COLLISION(entity, true)
    local netId = NetworkUtils.ConstantizeNetworkId(entity)
    NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netId, false)
    return netId
end

-- ============================================================================
-- Keybinds
-- ============================================================================
local Keybinds = {}

function Keybinds.GetAsString(key)
    return PAD.GET_CONTROL_INSTRUCTIONAL_BUTTONS_STRING(0, key, true)
end

function Keybinds.CreateKeybind(key, func)
    return {
        key = key,
        string = Keybinds.GetAsString(key),
        IsPressed = function()
            return func(key)
        end
    }
end

function Keybinds.IsPressed(key)
    return PAD.IS_DISABLED_CONTROL_PRESSED(0, key)
end

function Keybinds.IsJustPressed(key)
    return PAD.IS_DISABLED_CONTROL_JUST_PRESSED(0, key)
end

function Keybinds.GetControlNormal(key)
    return PAD.GET_DISABLED_CONTROL_NORMAL(0, key)
end

Keybinds.Grab = Keybinds.CreateKeybind(24, Keybinds.IsPressed)
Keybinds.AddOrRemoveFromList = Keybinds.CreateKeybind(73, Keybinds.IsJustPressed)
Keybinds.MoveFaster = Keybinds.CreateKeybind(21, Keybinds.IsPressed)
Keybinds.RotateLeft = Keybinds.CreateKeybind(44, Keybinds.IsPressed)
Keybinds.RotateRight = Keybinds.CreateKeybind(38, Keybinds.IsPressed)
Keybinds.PushEntity = Keybinds.CreateKeybind(14, Keybinds.IsPressed)
Keybinds.PullEntity = Keybinds.CreateKeybind(15, Keybinds.IsPressed)
Keybinds.MoveUp = Keybinds.CreateKeybind(22, Keybinds.GetControlNormal)
Keybinds.MoveDown = Keybinds.CreateKeybind(36, Keybinds.GetControlNormal)
Keybinds.MoveForward = Keybinds.CreateKeybind(32, Keybinds.GetControlNormal)
Keybinds.MoveBackward = Keybinds.CreateKeybind(33, Keybinds.GetControlNormal)
Keybinds.MoveLeft = Keybinds.CreateKeybind(34, Keybinds.GetControlNormal)
Keybinds.MoveRight = Keybinds.CreateKeybind(35, Keybinds.GetControlNormal)

-- ============================================================================
-- Configuration Management
-- ============================================================================
local Config = {
    enableF9Key = false,
    throwableMode = false,
    groundCollision = false
}

local function SaveConfig()
    -- Simple key=value format
    local configData = "enableF9Key=" .. tostring(Config.enableF9Key) .. "\n" ..
                       "throwableMode=" .. tostring(Config.throwableMode) .. "\n" ..
                       "groundCollision=" .. tostring(Config.groundCollision) .. "\n"

    if FileMgr.WriteFileContent(configPath, configData) then
        CustomLogger.Info("Configuration saved")
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

    -- Parse simple key=value format
    for line in configData:gmatch("[^\r\n]+") do
        local key, value = line:match("^(.-)=(.+)$")
        if key and value then
            if key == "enableF9Key" then
                Config.enableF9Key = (value == "true")
            elseif key == "throwableMode" then
                Config.throwableMode = (value == "true")
            elseif key == "groundCollision" then
                Config.groundCollision = (value == "true")
            end
        end
    end

    CustomLogger.Info("Configuration loaded")
end

-- ============================================================================
-- Camera Utilities
-- ============================================================================
local CameraUtils = {}

function CameraUtils.GetBasis(cam)
    local rot = CAM.GET_CAM_ROT(cam, 2)
    local radZ = math.rad(rot.z)
    local radX = math.rad(rot.x)

    local fwd = {
        x = -math.sin(radZ) * math.cos(radX),
        y = math.cos(radZ) * math.cos(radX),
        z = math.sin(radX)
    }

    local right = {
        x = math.cos(radZ),
        y = math.sin(radZ),
        z = 0.0
    }

    local up = {
        x = right.y * fwd.z - right.z * fwd.y,
        y = right.z * fwd.x - right.x * fwd.z,
        z = right.x * fwd.y - right.y * fwd.x
    }

    return fwd, right, up, rot
end

function CameraUtils.ClampPitch(pitch)
    if pitch > CONSTANTS.PITCH_CLAMP_MAX then
        return CONSTANTS.PITCH_CLAMP_MAX
    elseif pitch < CONSTANTS.PITCH_CLAMP_MIN then
        return CONSTANTS.PITCH_CLAMP_MIN
    end
    return pitch
end

-- ============================================================================
-- Memory Management Utilities
-- ============================================================================
local MemoryUtils = {}

function MemoryUtils.PerformRaycast(startX, startY, startZ, endX, endY, endZ, flags)
    local hit = Memory.AllocInt()
    local endCoords = Memory.Alloc(24)
    local surfaceNormal = Memory.Alloc(24)
    local entityHit = Memory.AllocInt()

    local handle = SHAPETEST.START_SHAPE_TEST_LOS_PROBE(
        startX, startY, startZ,
        endX, endY, endZ,
        flags,
        nil,
        7
    )

    local result = {
        handle = handle,
        hit = hit,
        endCoords = endCoords,
        surfaceNormal = surfaceNormal,
        entityHit = entityHit
    }

    return result
end

function MemoryUtils.GetRaycastResult(raycastData)
    local resultReady = SHAPETEST.GET_SHAPE_TEST_RESULT(
        raycastData.handle,
        raycastData.hit,
        raycastData.endCoords,
        raycastData.surfaceNormal,
        raycastData.entityHit
    )

    if resultReady == 2 then
        local hitValue = Memory.ReadInt(raycastData.hit)
        local entityHitValue = Memory.ReadInt(raycastData.entityHit)
        return true, hitValue, entityHitValue
    end

    return false, nil, nil
end

function MemoryUtils.FreeRaycastData(raycastData)
    Memory.Free(raycastData.hit)
    Memory.Free(raycastData.endCoords)
    Memory.Free(raycastData.surfaceNormal)
    Memory.Free(raycastData.entityHit)
end

-- ============================================================================
-- Spooner Core
-- ============================================================================
local Spooner = {}
Spooner.inSpoonerMode = false
Spooner.freecam = nil
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
Spooner.raycastHandle = nil
Spooner.raycastData = nil
Spooner.raycastFrameCounter = 0
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

function Spooner.TakeControlOfEntity(entity)
    return NetworkUtils.MakeEntityNetworked(entity)
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
    if not Spooner.isGrabbing or not Spooner.grabbedEntity then
        return
    end

    Spooner.isEntityTargeted = true

    if not ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
        Spooner.ReleaseEntity()
        return
    end

    Spooner.TakeControlOfEntity(Spooner.grabbedEntity)

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
    if Keybinds.RotateRight.IsPressed() then
        Spooner.grabbedEntityRotation.z = Spooner.grabbedEntityRotation.z - rotationSpeed
    elseif Keybinds.RotateLeft.IsPressed() then
        Spooner.grabbedEntityRotation.z = Spooner.grabbedEntityRotation.z + rotationSpeed
    end

    local newPos = Spooner.CalculateNewPosition(camPos, fwd, right, up, Spooner.grabOffsets)

    -- Optional ground collision prevention
    if Config.groundCollision then
        local groundZPtr = Memory.Alloc(8)  -- Allocate 8 bytes for float/double
        Memory.WriteFloat(groundZPtr, 0.0)

        local foundGround = MISC.GET_GROUND_Z_FOR_3D_COORD(newPos.x, newPos.y, newPos.z + 100.0, groundZPtr, false, false)

        if foundGround then
            local groundZValue = Memory.ReadFloat(groundZPtr)

            -- Get entity dimensions to calculate where the bottom of the entity is
            local minPtr = Memory.Alloc(24)  -- 3 floats (x, y, z)
            local maxPtr = Memory.Alloc(24)
            MISC.GET_MODEL_DIMENSIONS(ENTITY.GET_ENTITY_MODEL(Spooner.grabbedEntity), minPtr, maxPtr)

            -- Read the minimum Z (bottom of the entity relative to its origin)
            local min = Memory.ReadV3(minPtr)
            local max = Memory.ReadV3(maxPtr)

            -- DEBUG: Log the values
            CustomLogger.Info(string.format("Ground Z: %.3f, Entity Pos Z: %.3f, MinZ: %.3f, MaxZ: %.3f",
                groundZValue, newPos.z, min.z, max.z))

            -- Calculate where the entity's origin needs to be so its bottom sits on the ground
            -- minZ is negative (e.g., -0.5 means bottom is 0.5 units below origin)
            -- So we subtract minZ from ground height to get the proper origin height
            local targetOriginZ = groundZValue - min.z

            CustomLogger.Info(string.format("Target Origin Z: %.3f (Ground: %.3f - MinZ: %.3f)",
                targetOriginZ, groundZValue, min.z))

            if newPos.z < targetOriginZ then
                CustomLogger.Info(string.format("Adjusting Z from %.3f to %.3f", newPos.z, targetOriginZ))
                newPos.z = targetOriginZ
            end

            Memory.Free(minPtr)
            Memory.Free(maxPtr)
        end

        Memory.Free(groundZPtr)
    end

    ENTITY.SET_ENTITY_COORDS_NO_OFFSET(Spooner.grabbedEntity, newPos.x, newPos.y, newPos.z, false, false, false)
    ENTITY.SET_ENTITY_ROTATION(
        Spooner.grabbedEntity,
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

    if isRightClickPressed and (Spooner.isGrabbing or (Spooner.isEntityTargeted and Spooner.targetedEntity)) then
        if not Spooner.isGrabbing then
            Spooner.StartGrabbing()
        end
        Spooner.UpdateGrabbedEntity()
    else
        Spooner.ReleaseEntity()
    end
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

    CAM.SET_CAM_COORD(Spooner.freecam, camPos.x, camPos.y, camPos.z)
    CAM.SET_CAM_ROT(Spooner.freecam, camRot.x, camRot.y, camRot.z, 2)

    STREAMING.SET_FOCUS_POS_AND_VEL(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)
    HUD.LOCK_MINIMAP_POSITION(camPos.x, camPos.y)
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

    Spooner.TakeControlOfEntity(entity)
    table.insert(Spooner.managedEntities, entity)
    CustomLogger.Info("Entity added to managed list: " .. tostring(entity))
end

function Spooner.ManageEntities()
    if not Spooner.inSpoonerMode then
        return
    end

    if Keybinds.AddOrRemoveFromList.IsPressed() then
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
            Spooner.TakeControlOfEntity(entity)
        else
            table.remove(Spooner.managedEntities, i)
            CustomLogger.Info("Removed invalid entity from list")
        end
    end
end

-- ============================================================================
-- Draw Manager
-- ============================================================================
local DrawManager = {}

function DrawManager.PerformRaycastCheck()
    if Spooner.raycastData then
        local ready, hitValue, entityHitValue = MemoryUtils.GetRaycastResult(Spooner.raycastData)

        if ready then
            if hitValue == 1 and entityHitValue ~= 0 and not Spooner.IsEntityRestricted(entityHitValue) then
                Spooner.isEntityTargeted = true
                Spooner.targetedEntity = entityHitValue
            else
                Spooner.isEntityTargeted = false
                Spooner.targetedEntity = nil
            end

            MemoryUtils.FreeRaycastData(Spooner.raycastData)
            Spooner.raycastData = nil
        end
    end

    if not Spooner.isGrabbing then
        Spooner.raycastFrameCounter = Spooner.raycastFrameCounter + 1
        if Spooner.raycastFrameCounter >= CONSTANTS.RAYCAST_INTERVAL then
            Spooner.raycastFrameCounter = 0

            local camCoord = CAM.GET_CAM_COORD(Spooner.freecam)
            local camRot = CAM.GET_CAM_ROT(Spooner.freecam, 2)

            local radZ = math.rad(camRot.z)
            local radX = math.rad(camRot.x)
            local forwardX = -math.sin(radZ) * math.cos(radX)
            local forwardY = math.cos(radZ) * math.cos(radX)
            local forwardZ = math.sin(radX)

            local endX = camCoord.x + forwardX * CONSTANTS.RAYCAST_MAX_DISTANCE
            local endY = camCoord.y + forwardY * CONSTANTS.RAYCAST_MAX_DISTANCE
            local endZ = camCoord.z + forwardZ * CONSTANTS.RAYCAST_MAX_DISTANCE

            Spooner.raycastData = MemoryUtils.PerformRaycast(
                camCoord.x, camCoord.y, camCoord.z,
                endX, endY, endZ,
                CONSTANTS.RAYCAST_FLAGS
            )
        end
    end
end

function DrawManager.DrawCrosshair()
    if not Spooner.inSpoonerMode then
        return
    end

    DrawManager.PerformRaycastCheck()

    local color = Spooner.isEntityTargeted and Spooner.crosshairColorGreen or Spooner.crosshairColor
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

    local grabLabel = Spooner.isGrabbing and "Release Entity" or "Grab Entity"
    DrawManager.AddInstructionalButton(buttonIndex, Keybinds.Grab.string, grabLabel)
    buttonIndex = buttonIndex + 1

    if Spooner.isGrabbing then
        DrawManager.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.RotateLeft.string, Keybinds.RotateRight.string},
            "Rotate Entity"
        )
        buttonIndex = buttonIndex + 1

        DrawManager.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.PushEntity.string, Keybinds.PullEntity.string},
            "Push / Pull Entity"
        )
        buttonIndex = buttonIndex + 1
    end

    local entityToCheck = Spooner.isGrabbing and Spooner.grabbedEntity or
                          (Spooner.isEntityTargeted and Spooner.targetedEntity or nil)

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
    local modelName = GTA.GetModelNameFromHash(modelHash)

    if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
        local plate = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(entity)
        return "Vehicle - " .. modelName .. " (" .. plate .. ")"
    elseif ENTITY.IS_ENTITY_A_PED(entity) then
        return "Ped - " .. modelName
    elseif ENTITY.IS_ENTITY_AN_OBJECT(entity) then
        return "Object - " .. modelName
    end

    return "Unknown - " .. modelName
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
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_EnableGroundCollision"))

            ImGui.Separator()
            ImGui.Text("Managed Entities Database")

            local previewValue = "None"
            if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
                local ent = Spooner.managedEntities[Spooner.selectedEntityIndex]
                previewValue = DrawManager.GetEntityName(ent)
            elseif #Spooner.managedEntities > 0 then
                Spooner.selectedEntityIndex = 1
                previewValue = DrawManager.GetEntityName(Spooner.managedEntities[1])
            end

            if ImGui.BeginCombo("Select Entity", previewValue) then
                if #Spooner.managedEntities == 0 then
                    ImGui.Selectable("None", false)
                else
                    for i, entity in ipairs(Spooner.managedEntities) do
                        local label = DrawManager.GetEntityName(entity)
                        local isSelected = (i == Spooner.selectedEntityIndex)
                        if ImGui.Selectable(label .. "##" .. i, isSelected) then
                            Spooner.selectedEntityIndex = i
                        end
                        if isSelected then
                            ImGui.SetItemDefaultFocus()
                        end
                    end
                end
                ImGui.EndCombo()
            end

            ClickGUI.RenderFeature(Utils.Joaat("Spooner_RemoveEntity"))
            ClickGUI.RenderFeature(Utils.Joaat("Spooner_DeleteEntity"))

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

                    local ptr = Memory.AllocInt()
                    Memory.WriteInt(ptr, entity)

                    NETWORK.SET_NETWORK_ID_EXISTS_ON_ALL_MACHINES(netId, false)
                    NETWORK.SET_NETWORK_ID_ALWAYS_EXISTS_FOR_PLAYER(netId, PLAYER.PLAYER_ID(), false)
                    NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netId, true)
                    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, false, true)
                    ENTITY.SET_ENTITY_SHOULD_FREEZE_WAITING_ON_COLLISION(entity, false)
                    ENTITY.DELETE_ENTITY(ptr)

                    CustomLogger.Info("Network ID: " .. tostring(netId))

                    Memory.Free(ptr)

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

local enableGroundCollisionFeature = FeatureMgr.AddFeature(
    Utils.Joaat("Spooner_EnableGroundCollision"),
    "Enable Ground Collision",
    eFeatureType.Toggle,
    "Prevent entities from going through the ground",
    function(f)
        Config.groundCollision = f:IsToggled()
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

-- Restore ground collision setting
if Config.groundCollision then
    enableGroundCollisionFeature:Toggle()
end

DrawManager.ClickGUIInit()

Script.RegisterLooped(function()
    Spooner.UpdateFreecam()
    DrawManager.DrawCrosshair()
    DrawManager.DrawInstructionalButtons()
    DrawManager.DrawSelectedEntityMarker()
end)

Script.RegisterLooped(function()
    if Spooner.inSpoonerMode then
        Script.QueueJob(function()
            Spooner.ManageEntities()
            Spooner.HandleEntityGrabbing()
        end)
    end
end)

EventMgr.RegisterHandler(eLuaEvent.ON_UNLOAD, function()
    if Spooner.inSpoonerMode then
        Script.QueueJob(function()
            toggleSpoonerModeFeature:Toggle()
        end)
    end
end)
