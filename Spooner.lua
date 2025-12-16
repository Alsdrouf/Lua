local pluginName = "Spooner"
local menuRootPath = FileMgr.GetMenuRootPath() .. "\\Lua\\" .. pluginName
local nativesPath = menuRootPath .. "\\Assets\\natives.lua"

FileMgr.CreateDir(menuRootPath)
FileMgr.CreateDir(menuRootPath .. "\\Assets")

--- Taken from constructor4lod credits Elfish-Beaker and WhiteWatermelon
local nativesURL = "https://raw.githubusercontent.com/Elfish-beaker/object-list/refs/heads/main/natives.lua"

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
        if not DownloadAndSaveLuaFile(nativesURL, path) then
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
--- End of credits

--- Credits to themilkman554
local M = {}

M.set_entity_as_networked = function(entity, timeout)
    local time <const> = Time.GetEpocheMs() + (timeout or 1500)
    while time > Time.GetEpocheMs() and not NETWORK.NETWORK_GET_ENTITY_IS_NETWORKED(entity) do
        NETWORK.NETWORK_REGISTER_ENTITY_AS_NETWORKED(entity)
        Script.Yield(0)
    end
    return NETWORK.NETWORK_GET_ENTITY_IS_NETWORKED(entity)
end

M.constantize_network_id = function(entity)
    M.set_entity_as_networked(entity, 25)
    local net_id <const> = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(entity)
    -- network.set_network_id_can_migrate(net_id, false) -- Caused players unable to drive vehicles
    NETWORK.SET_NETWORK_ID_EXISTS_ON_ALL_MACHINES(net_id, true)
    NETWORK.SET_NETWORK_ID_ALWAYS_EXISTS_FOR_PLAYER(net_id, PLAYER.PLAYER_ID(), true)
    return net_id
end

M.make_entity_networked = function(entity)
    if not DECORATOR.DECOR_EXIST_ON(entity, "PV_Slot") then
        ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, true, true)
    end
    ENTITY.SET_ENTITY_SHOULD_FREEZE_WAITING_ON_COLLISION(entity, false)
    M.constantize_network_id(entity)
    NETWORK.SET_NETWORK_ID_CAN_MIGRATE(NETWORK.OBJ_TO_NET(entity), false)
end
--- End of credits

---@class Keybinds
Keybinds = {}

---@param key number
function Keybinds.GetAsString(key)
    return PAD.GET_CONTROL_INSTRUCTIONAL_BUTTONS_STRING(0, key, true)
end

---@param key number
---@param func function
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

Keybinds.Grab = Keybinds.CreateKeybind(24, Keybinds.IsPressed) -- INPUT_ATTACK Right mouse button / LT
Keybinds.AddOrRemoveFromList = Keybinds.CreateKeybind(73, Keybinds.IsJustPressed) -- INPUT_COVER_IN_CAR X
Keybinds.MoveFaster = Keybinds.CreateKeybind(21, Keybinds.IsPressed) -- INPUT_SPRINT Shift
Keybinds.RotateLeft = Keybinds.CreateKeybind(44, Keybinds.IsPressed) -- INPUT_COVER Q
Keybinds.RotateRight = Keybinds.CreateKeybind(38, Keybinds.IsPressed) -- INPUT_PICKUP E
Keybinds.PushEntity = Keybinds.CreateKeybind(14, Keybinds.IsPressed) -- INPUT_WEAPON_WHEEL_NEXT
Keybinds.PullEntity = Keybinds.CreateKeybind(15, Keybinds.IsPressed) -- INPUT_WEAPON_WHEEL_PREV
Keybinds.MoveUp = Keybinds.CreateKeybind(22, Keybinds.GetControlNormal) -- INPUT_JUMP
Keybinds.MoveDown = Keybinds.CreateKeybind(36, Keybinds.GetControlNormal) -- INPUT_SNEAK
Keybinds.MoveForward = Keybinds.CreateKeybind(32, Keybinds.GetControlNormal) -- INPUT_MOVE_UP
Keybinds.MoveBackward = Keybinds.CreateKeybind(33, Keybinds.GetControlNormal) -- INPUT_MOVE_DOWN
Keybinds.MoveLeft = Keybinds.CreateKeybind(34, Keybinds.GetControlNormal) -- INPUT_MOVE_LEFT
Keybinds.MoveRight = Keybinds.CreateKeybind(35, Keybinds.GetControlNormal) -- INPUT_MOVE_RIGHT

---@class CustomLogger
CustomLogger = {}

---@param str string
function CustomLogger.Info(str)
    Logger.Log(eLogColor.WHITE, pluginName, str)
end

---@param str string
function CustomLogger.Warn(str)
    Logger.Log(eLogColor.YELLOW, pluginName, str)
end

---@param str string
function CustomLogger.Error(str)
    Logger.Log(eLogColor.RED, pluginName, str)
end

---@class Spooner
Spooner = {}
Spooner.inSpoonerMode = false
Spooner.freecam = nil
Spooner.camSpeed = 0.5
Spooner.camRotSpeed = 20.0
Spooner.crosshairColor = {
    r = 255,
    g = 255,
    b = 255,
    a = 255
} -- White by default
Spooner.crosshairSize = 0.01 -- Size of the crosshair lines
Spooner.crosshairGap = 0 -- Gap from center
Spooner.lastEntityPos = nil -- for velocity calculation
Spooner.grabVelocity = {
    x = 0,
    y = 0,
    z = 0
} -- Store current grab velocity
Spooner.crosshairThickness = 0.001 -- Thickness of the crosshair lines
Spooner.crosshairColorGreen = {
    r = 0,
    g = 255,
    b = 0,
    a = 255
} -- Green when targeting entity
Spooner.targetedEntity = nil
Spooner.raycastHandle = nil
Spooner.raycastFrameCounter = 0
Spooner.isEntityTargeted = false
Spooner.grabbedEntity = nil
Spooner.grabDistance = 0
Spooner.isGrabbing = false
Spooner.scaleform = nil
Spooner.managedEntities = {}
Spooner.selectedEntityIndex = 0
Spooner.makeMissionEntity = false
Spooner.throwableVelocityMultiplier = 30.0
Spooner.throwableMode = false

function Spooner.TakeControlOfEntity(entity)
    -- Request network control of the entity
    if not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(entity) then
        NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(entity)

        local start = Time.GetEpocheMs()
        while not NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(entity) and (Time.GetEpocheMs() - start) < 1000 do
            Script.Yield(10)
        end
    end

    M.make_entity_networked(entity)
end

function Spooner.IsEntityRestricted(entity)
    if not ENTITY.DOES_ENTITY_EXIST(entity) then
        return true
    end

    -- Check if entity is a player
    if ENTITY.IS_ENTITY_A_PED(entity) and PED.IS_PED_A_PLAYER(entity) and entity ~= PLAYER.PLAYER_PED_ID() then
        return true
    end

    -- Check if entity is a vehicle driven by another player
    if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
        local driver = VEHICLE.GET_PED_IN_VEHICLE_SEAT(entity, -1)
        if driver ~= 0 and PED.IS_PED_A_PLAYER(driver) and driver ~= PLAYER.PLAYER_PED_ID() then
            return true
        end
    end

    return false
end

function Spooner.GetCamBasis(cam)
    local rot = CAM.GET_CAM_ROT(cam, 2)
    local radZ = math.rad(rot.z)
    local radX = math.rad(rot.x)

    -- Forward Vector
    local fwd = {
        x = -math.sin(radZ) * math.cos(radX),
        y = math.cos(radZ) * math.cos(radX),
        z = math.sin(radX)
    }

    -- Right Vector (assuming no roll and Z-up world)
    -- Cross(Forward, WorldUp) -> WorldUp is (0,0,1)
    -- This results in a horizontal right vector
    local right = {
        x = math.cos(radZ),
        y = math.sin(radZ),
        z = 0.0
    }

    -- Camera Up Vector
    -- Cross(Right, Forward)
    local up = {
        x = right.y * fwd.z - right.z * fwd.y, -- ry*fz - 0
        y = right.z * fwd.x - right.x * fwd.z, -- 0 - rx*fz
        z = right.x * fwd.y - right.y * fwd.x -- rx*fy - ry*fx
    }

    return fwd, right, up, rot
end

function Spooner.HandleEntityGrabbing()
    if not Spooner.inSpoonerMode or Spooner.freecam == nil then
        return
    end

    -- Check if right mouse button is pressed (attack control)
    local isRightClickPressed = Keybinds.Grab.IsPressed()

    -- Keep grabbing if already holding, or start grabbing if targeting entity
    if isRightClickPressed and (Spooner.isGrabbing or (Spooner.isEntityTargeted and Spooner.targetedEntity ~= nil)) then
        -- Start grabbing
        if not Spooner.isGrabbing then
            Spooner.isGrabbing = true
            Spooner.grabbedEntity = Spooner.targetedEntity

            local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
            local entityPos = ENTITY.GET_ENTITY_COORDS(Spooner.grabbedEntity, true)

            -- Get Camera Basis Vectors
            local fwd, right, up, camRot = Spooner.GetCamBasis(Spooner.freecam)

            -- Vector from Camera to Entity
            local vec = {
                x = entityPos.x - camPos.x,
                y = entityPos.y - camPos.y,
                z = entityPos.z - camPos.z
            }

            -- Project onto Basis Vectors to get relative offsets
            -- Dot Product
            Spooner.grabOffsets = {
                x = vec.x * right.x + vec.y * right.y + vec.z * right.z, -- Right offset
                y = vec.x * fwd.x + vec.y * fwd.y + vec.z * fwd.z, -- Forward offset (Distance)
                z = vec.x * up.x + vec.y * up.y + vec.z * up.z -- Up offset
            }

            -- Store current world rotation
            Spooner.grabbedEntityRotation = ENTITY.GET_ENTITY_ROTATION(Spooner.grabbedEntity, 2)

            Spooner.TakeControlOfEntity(Spooner.grabbedEntity)
        end

        -- Move the grabbed entity
        if Spooner.isGrabbing and Spooner.grabbedEntity ~= nil then
            -- Keep crosshair green while holding
            Spooner.isEntityTargeted = true

            if ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
                -- Ensure we have network control
                Spooner.TakeControlOfEntity(Spooner.grabbedEntity)

                local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
                local fwd, right, up, camRot = Spooner.GetCamBasis(Spooner.freecam)

                -- Check speed boost (Shift / A button)
                local speedMultiplier = 1.0
                if Keybinds.MoveFaster.IsPressed() then
                    speedMultiplier = 4.0
                end

                -- Check for scroll wheel to adjust distance (Offset Y)
                local scrollSpeed = 0.5 * speedMultiplier
                if Keybinds.PushEntity.IsPressed() then
                    Spooner.grabOffsets.y = Spooner.grabOffsets.y - scrollSpeed
                elseif Keybinds.PullEntity.IsPressed() then
                    Spooner.grabOffsets.y = Spooner.grabOffsets.y + scrollSpeed
                end

                if Spooner.grabOffsets.y < 1.0 then -- Min distance check
                    Spooner.grabOffsets.y = 1.0
                end

                -- Check if rotation keys are pressed (Q/E)
                local rotateRight = Keybinds.RotateRight.IsPressed()
                local rotateLeft = Keybinds.RotateLeft.IsPressed()
                local rotationSpeed = 2.0 * speedMultiplier -- degrees per frame

                if rotateRight then
                    Spooner.grabbedEntityRotation.z = Spooner.grabbedEntityRotation.z - rotationSpeed
                elseif rotateLeft then
                    Spooner.grabbedEntityRotation.z = Spooner.grabbedEntityRotation.z + rotationSpeed
                end

                -- Calculate New Position based on updated Camera + Offsets
                local newX = camPos.x + (right.x * Spooner.grabOffsets.x) + (fwd.x * Spooner.grabOffsets.y) +
                                 (up.x * Spooner.grabOffsets.z)
                local newY = camPos.y + (right.y * Spooner.grabOffsets.x) + (fwd.y * Spooner.grabOffsets.y) +
                                 (up.y * Spooner.grabOffsets.z)
                local newZ = camPos.z + (right.z * Spooner.grabOffsets.x) + (fwd.z * Spooner.grabOffsets.y) +
                                 (up.z * Spooner.grabOffsets.z)

                -- Move the entity
                ENTITY.SET_ENTITY_COORDS_NO_OFFSET(Spooner.grabbedEntity, newX, newY, newZ, false, false, false)

                -- Update Rotation (Absolute World Rotation - decoupled from cam)
                ENTITY.SET_ENTITY_ROTATION(Spooner.grabbedEntity, Spooner.grabbedEntityRotation.x,
                    Spooner.grabbedEntityRotation.y, Spooner.grabbedEntityRotation.z, 2, true)

                if Spooner.throwableMode then
                    -- Calculate and store velocity (displacement since last frame)
                    if Spooner.lastEntityPos then
                        -- Multiplier needs to be high because this is per-frame displacement (approx 1/60th of a second)
                        -- We want units per second roughly.
                        local velocityMult = Spooner.throwableVelocityMultiplier
                        Spooner.grabVelocity = {
                            x = (newX - Spooner.lastEntityPos.x) * velocityMult,
                            y = (newY - Spooner.lastEntityPos.y) * velocityMult,
                            z = (newZ - Spooner.lastEntityPos.z) * velocityMult
                        }
                    end

                    -- Store current pos for next frame velocity calc
                    Spooner.lastEntityPos = {
                        x = newX,
                        y = newY,
                        z = newZ
                    }
                end
            else
                -- Entity was deleted
                Spooner.isGrabbing = false
                Spooner.grabbedEntity = nil
                Spooner.lastEntityPos = nil
            end
        end
    else
        -- Release the entity
        if Spooner.isGrabbing and Spooner.grabbedEntity ~= nil then
            if ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
                -- Apply the velocity calculated during the grab as a force (Impulse)
                -- ForceType 1 (Strong Force / Impulse) seems best for throws
                if Spooner.throwableMode then
                    ENTITY.APPLY_FORCE_TO_ENTITY(Spooner.grabbedEntity, 1, Spooner.grabVelocity.x,
                        Spooner.grabVelocity.y, Spooner.grabVelocity.z, 0.0, 0.0, 0.0, -- Offset (center)
                        0, -- Bone index
                        false, -- isDirectionRel
                        true, -- ignoreUpVec
                        true, -- isForceRel
                        false, -- p12
                        true -- p13 (isMassRel)
                    )
                end
            end

            Spooner.isGrabbing = false
            Spooner.grabbedEntity = nil
            Spooner.lastEntityPos = nil
            Spooner.grabVelocity = {
                x = 0,
                y = 0,
                z = 0
            }
        end
    end
end

function Spooner.UpdateFreecam()
    if not Spooner.inSpoonerMode or Spooner.freecam == nil then
        return
    end

    PAD.DISABLE_ALL_CONTROL_ACTIONS(0)

    -- Get current camera position and rotation
    local camPos = CAM.GET_CAM_COORD(Spooner.freecam)
    local camRot = CAM.GET_CAM_ROT(Spooner.freecam, 2)

    -- Get input for camera rotation (mouse/right stick)
    local rightAxisX = PAD.GET_DISABLED_CONTROL_NORMAL(0, 220) -- Right stick X / Mouse X
    local rightAxisY = PAD.GET_DISABLED_CONTROL_NORMAL(0, 221) -- Right stick Y / Mouse Y

    -- Update rotation
    camRot.z = camRot.z - (rightAxisX * Spooner.camRotSpeed)
    camRot.x = camRot.x - (rightAxisY * Spooner.camRotSpeed)
    camRot.y = 0.0 -- Force horizontal

    -- Clamp pitch to prevent flipping
    if camRot.x > 89.0 then
        camRot.x = 89.0
    end
    if camRot.x < -89.0 then
        camRot.x = -89.0
    end

    -- Calculate forward/right vectors based on rotation
    local radZ = math.rad(camRot.z)
    local radX = math.rad(camRot.x)

    local forwardX = -math.sin(radZ) * math.cos(radX)
    local forwardY = math.cos(radZ) * math.cos(radX)
    local forwardZ = math.sin(radX)

    local rightX = math.cos(radZ)
    local rightY = math.sin(radZ)

    -- Get movement input (WASD / Left stick)
    local moveForward = Keybinds.MoveForward.IsPressed()
    local moveBackward = Keybinds.MoveBackward.IsPressed()
    local moveLeft = Keybinds.MoveLeft.IsPressed()
    local moveRight = Keybinds.MoveRight.IsPressed()
    local moveUp = Keybinds.MoveUp.IsPressed()
    local moveDown = Keybinds.MoveDown.IsPressed()

    -- Apply movement
    local speed = Spooner.camSpeed
    if Keybinds.MoveFaster.IsPressed() then
        speed = speed * 3.0
    end

    camPos.x = camPos.x + (forwardX * (moveForward - moveBackward) * speed)
    camPos.y = camPos.y + (forwardY * (moveForward - moveBackward) * speed)
    camPos.z = camPos.z + (forwardZ * (moveForward - moveBackward) * speed)

    camPos.x = camPos.x + (rightX * (moveRight - moveLeft) * speed)
    camPos.y = camPos.y + (rightY * (moveRight - moveLeft) * speed)

    camPos.z = camPos.z + ((moveUp - moveDown) * speed)

    -- Update camera
    CAM.SET_CAM_COORD(Spooner.freecam, camPos.x, camPos.y, camPos.z)
    CAM.SET_CAM_ROT(Spooner.freecam, camRot.x, camRot.y, camRot.z, 2)

    -- Focus streaming around camera to prevent LOD issues
    STREAMING.SET_FOCUS_POS_AND_VEL(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)

    -- Update minimap to follow camera
    HUD.LOCK_MINIMAP_POSITION(camPos.x, camPos.y)
end

function Spooner.ToggleSpoonerMode(f)
    if Spooner.inSpoonerMode == f then
        return
    end

    Spooner.inSpoonerMode = f
    if Spooner.inSpoonerMode then
        -- Enable freecam
        -- Get the current gameplay/ped camera position and rotation
        local camPos = CAM.GET_GAMEPLAY_CAM_COORD()
        local camRot = CAM.GET_GAMEPLAY_CAM_ROT(2)

        -- Create a render camera at the gameplay camera position
        Spooner.freecam = CAM.CREATE_CAM("DEFAULT_SCRIPTED_CAMERA", true)
        CAM.SET_CAM_COORD(Spooner.freecam, camPos.x, camPos.y, camPos.z)
        CAM.SET_CAM_ROT(Spooner.freecam, camRot.x, 0.0, camRot.z, 2)
        CAM.SET_CAM_ACTIVE(Spooner.freecam, true)
        CAM.RENDER_SCRIPT_CAMS(true, false, 0, true, false, 0)

        -- Sync minimap rotation with camera
        CAM.SET_CAM_CONTROLS_MINI_MAP_HEADING(Spooner.freecam, true)

        CustomLogger.Info("Freecam enabled")
    else
        -- Disable freecam
        if Spooner.freecam ~= nil then
            -- Restore streaming focus
            STREAMING.CLEAR_FOCUS()

            -- Unlock minimap
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

function Spooner.ManageEntities()
    if not Spooner.inSpoonerMode then
        return
    end

    -- Handle 'X' key press to add entity
    if Keybinds.AddOrRemoveFromList.IsPressed() then
        local entityToAdd = nil

        if Spooner.isGrabbing and Spooner.grabbedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
            entityToAdd = Spooner.grabbedEntity
        elseif Spooner.isEntityTargeted and Spooner.targetedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.targetedEntity) then
            entityToAdd = Spooner.targetedEntity
        end

        if entityToAdd then
            local alreadyAdded = false

            -- Check for duplicates
            for _, e in ipairs(Spooner.managedEntities) do
                if e == entityToAdd then
                    alreadyAdded = true
                    break
                end
            end

            if not alreadyAdded then
                -- Request network control
                Spooner.TakeControlOfEntity(entityToAdd)

                table.insert(Spooner.managedEntities, entityToAdd)
                CustomLogger.Info("Entity added to managed list: " .. tostring(entityToAdd))
            else
                for i, e in ipairs(Spooner.managedEntities) do
                    if e == entityToAdd then
                        table.remove(Spooner.managedEntities, i)
                        CustomLogger.Info("Removed entity from managed list: " .. tostring(entityToAdd))
                        break
                    end
                end
            end
        end
    end

    -- Cleanup invalid entities and maintain control
    for i = #Spooner.managedEntities, 1, -1 do
        local entity = Spooner.managedEntities[i]
        if ENTITY.DOES_ENTITY_EXIST(entity) then
            -- Maintain network control
            Spooner.TakeControlOfEntity(entity)
        else
            table.remove(Spooner.managedEntities, i)
            CustomLogger.Info("Removed invalid entity from list")
        end
    end
end

-- Drawing

--- @class DrawManager
DrawManager = {}

function DrawManager.DrawCrosshair()
    if not Spooner.inSpoonerMode then
        return
    end

    local color = Spooner.crosshairColor
    local size = Spooner.crosshairSize
    local gap = Spooner.crosshairGap

    -- Get screen resolution to calculate aspect ratio
    local aspectRatio = GRAPHICS.GET_SCREEN_ASPECT_RATIO()

    -- Only perform raycast every 3 frames to reduce performance impact (and skip if already grabbing)
    if not Spooner.isGrabbing then
        Spooner.raycastFrameCounter = Spooner.raycastFrameCounter + 1
        if Spooner.raycastFrameCounter >= 3 then
            Spooner.raycastFrameCounter = 0

            -- Raycast from camera to detect entity at crosshair center
            local camCoord = CAM.GET_CAM_COORD(Spooner.freecam)
            local camRot = CAM.GET_CAM_ROT(Spooner.freecam, 2)

            -- Calculate forward direction from camera rotation
            local radZ = math.rad(camRot.z)
            local radX = math.rad(camRot.x)
            local forwardX = -math.sin(radZ) * math.cos(radX)
            local forwardY = math.cos(radZ) * math.cos(radX)
            local forwardZ = math.sin(radX)

            -- Raycast endpoint (1000 units forward)
            local endX = camCoord.x + forwardX * 1000.0
            local endY = camCoord.y + forwardY * 1000.0
            local endZ = camCoord.z + forwardZ * 1000.0

            -- Perform async raycast (non-blocking)
            -- Flags: 2 (vehicles) + 4 (peds) + 16 (objects) + 8 (pickups) = 30
            -- This excludes world geometry (buildings, terrain)
            local playerPed = PLAYER.PLAYER_PED_ID()
            Spooner.raycastHandle = SHAPETEST.START_SHAPE_TEST_LOS_PROBE(camCoord.x, camCoord.y, camCoord.z, endX, endY,
                endZ, 30, -- flags: vehicles + peds + objects + pickups (no world)
                nil, 7 -- shape test type
            )
        end
    end

    -- Check if raycast result is ready
    if Spooner.raycastHandle then
        local hit = Memory.AllocInt()
        local endCoords = Memory.Alloc(24)
        local surfaceNormal = Memory.Alloc(24)
        local entityHit = Memory.AllocInt()

        local resultReady = SHAPETEST.GET_SHAPE_TEST_RESULT(Spooner.raycastHandle, hit, endCoords, surfaceNormal,
            entityHit)

        -- Only process if result is ready (resultReady == 2 means complete)
        if resultReady == 2 then
            local hitValue = Memory.ReadInt(hit)
            local entityHitValue = Memory.ReadInt(entityHit)

            -- Change color to green if entity is hit and restricted checks pass
            if hitValue == 1 and entityHitValue ~= 0 and not Spooner.IsEntityRestricted(entityHitValue) then
                Spooner.isEntityTargeted = true
                Spooner.targetedEntity = entityHitValue
            else
                Spooner.isEntityTargeted = false
                Spooner.targetedEntity = nil
            end

            Spooner.raycastHandle = nil
        end

        Memory.Free(hit)
        Memory.Free(endCoords)
        Memory.Free(surfaceNormal)
        Memory.Free(entityHit)
    end

    -- Use cached result for color
    if Spooner.isEntityTargeted then
        color = Spooner.crosshairColorGreen
    end

    -- Adjust size for aspect ratio so lines appear same length
    local sizeX = size / aspectRatio -- Horizontal size (width)
    local sizeY = size -- Vertical size (height)

    -- Adjust thickness for aspect ratio so lines appear same thickness
    local thicknessX = Spooner.crosshairThickness
    local thicknessY = Spooner.crosshairThickness * aspectRatio

    -- Draw horizontal line (left)
    GRAPHICS.DRAW_RECT(0.5 - gap - sizeX / 2, 0.5, sizeX, thicknessY, color.r, color.g, color.b, color.a, false)
    -- Draw horizontal line (right)
    GRAPHICS.DRAW_RECT(0.5 + gap + sizeX / 2, 0.5, sizeX, thicknessY, color.r, color.g, color.b, color.a, false)
    -- Draw vertical line (top)
    GRAPHICS.DRAW_RECT(0.5, 0.5 - gap - sizeY / 2, thicknessX, sizeY, color.r, color.g, color.b, color.a, false)
    -- Draw vertical line (bottom)
    GRAPHICS.DRAW_RECT(0.5, 0.5 + gap + sizeY / 2, thicknessX, sizeY, color.r, color.g, color.b, color.a, false)
end

function DrawManager.DrawInstructionalButtons()
    if not Spooner.inSpoonerMode then
        return
    end

    -- Request scaleform if not loaded
    if not Spooner.scaleform then
        Spooner.scaleform = GRAPHICS.REQUEST_SCALEFORM_MOVIE("instructional_buttons")
    end

    if not GRAPHICS.HAS_SCALEFORM_MOVIE_LOADED(Spooner.scaleform) then
        return
    end

    -- Clear previous buttons
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "CLEAR_ALL")
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    -- Toggle mouse buttons off to prevent conflicts
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "TOGGLE_MOUSE_BUTTONS")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_BOOL(false)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_CLEAR_SPACE")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(200)
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    local buttonIndex = 0

    -- Right Click - Grab/Release
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.Grab.string)
    if Spooner.isGrabbing then
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Release Entity")
    else
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Grab Entity")
    end
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
    buttonIndex = buttonIndex + 1

    -- Rotation
    if Spooner.isGrabbing then
        GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.RotateLeft.string)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.RotateRight.string)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Rotate Entity")
        GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
        buttonIndex = buttonIndex + 1

        -- Push / Pull (Scroll)
        GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.PushEntity.string)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.PullEntity.string)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Push / Pull Entity")
        GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
        buttonIndex = buttonIndex + 1
    end

    -- Add to List (X) - When grabbing or targeting
    local entityToCheck = nil
    if Spooner.isGrabbing then
        entityToCheck = Spooner.grabbedEntity
    elseif Spooner.isEntityTargeted then
        entityToCheck = Spooner.targetedEntity
    end

    if entityToCheck and ENTITY.DOES_ENTITY_EXIST(entityToCheck) then
        local isManaged = false
        for _, e in ipairs(Spooner.managedEntities) do
            if e == entityToCheck then
                isManaged = true
                break
            end
        end

        GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.AddOrRemoveFromList.string)
        if isManaged then
            GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Remove from List")
        else
            GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Add to List")
        end
        GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
        buttonIndex = buttonIndex + 1
    end

    -- Speed
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveFaster.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Move Faster")
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
    buttonIndex = buttonIndex + 1

    -- Up/Down
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveUp.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveDown.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Up / Down")
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
    buttonIndex = buttonIndex + 1

    -- WASD - Move
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveRight.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveLeft.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveBackward.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.MoveForward.string)
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Move Camera")
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
    buttonIndex = buttonIndex + 1

    -- Enter - Spawn at Crosshair
    if SpawnMenu.selectedModel then
        GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(Keybinds.SpawnAtCrosshair.string)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING("Spawn: " .. SpawnMenu.selectedModelName)
        GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
        buttonIndex = buttonIndex + 1
    end

    -- Draw the buttons
    GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "DRAW_INSTRUCTIONAL_BUTTONS")
    GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(-1) -- Use -1 to force default layout
    GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

    -- Render the scaleform
    GRAPHICS.DRAW_SCALEFORM_MOVIE_FULLSCREEN(Spooner.scaleform, 255, 255, 255, 255, 0)
end

function DrawManager.GetEntityName(entity)
    if ENTITY.DOES_ENTITY_EXIST(entity) then
        local modelHash = ENTITY.GET_ENTITY_MODEL(entity)
        local modelName = GTA.GetModelNameFromHash(modelHash)
        if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
            return "Vehicle - " .. modelName .. " (" .. VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(entity) .. ")"
        elseif ENTITY.IS_ENTITY_A_PED(entity) then
            return "Ped - " .. modelName
        elseif ENTITY.IS_ENTITY_AN_OBJECT(entity) then
            return "Object - " .. modelName
        end
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
            -- Draw a red debug sphere on the entity to highlight it
            GRAPHICS.DRAW_MARKER(28, -- type: DebugSphere
            pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, -- dir
            0.0, 0.0, 0.0, -- rot
            0.3, 0.3, 0.3, -- scale
            255, 0, 0, 150, -- r, g, b, alpha
            false, false, 2, false, nil, nil, false)
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

            ImGui.Separator()
            ImGui.Text("Managed Entities Database")

            -- Entity Selection Dropdown
            local previewValue = "None"
            if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
                local ent = Spooner.managedEntities[Spooner.selectedEntityIndex]
                if ENTITY.DOES_ENTITY_EXIST(ent) then
                    previewValue = DrawManager.GetEntityName(ent)
                else
                    previewValue = "Invalid Entity"
                end
            else
                if #Spooner.managedEntities > 0 then
                    Spooner.selectedEntityIndex = 1 -- Auto-select first if we have entities but bad index
                    local ent = Spooner.managedEntities[1]
                    if ENTITY.DOES_ENTITY_EXIST(ent) then
                        previewValue = DrawManager.GetEntityName(ent)
                    end
                end
            end

            if ImGui.BeginCombo("Select Entity", previewValue) then
                if #Spooner.managedEntities == 0 then
                    ImGui.Selectable("None", false)
                else
                    for i, entity in ipairs(Spooner.managedEntities) do
                        local label = DrawManager.GetEntityName(entity)
                        -- Append hidden ID to ensure uniqueness for ImGui if names are identical
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

    -- Add Spawn Menu tab for ClickGUI
    ClickGUI.AddTab("Spawn Menu", function()
        if ClickGUI.BeginCustomChildWindow("SpawnMenu") then
            -- Render spawn categories
            for _, category in ipairs(SpawnMenu.objects) do
                if ImGui.CollapsingHeader(category.name) then
                    for _, item in ipairs(category.items) do
                        local itemHash = Utils.Joaat("SpawnMenu_" .. item.model)
                        ClickGUI.RenderFeature(itemHash)
                    end
                end
            end

            ClickGUI.EndCustomChildWindow()
        end
    end)
end

-- Features
local toggleSpoonerModeFeature = FeatureMgr.AddFeature(Utils.Joaat("ToggleSpoonerMode"), "Toggle Spooner Mode",
    eFeatureType.Toggle, "Toggle Spooner Mode", function(f)
        Spooner.ToggleSpoonerMode(f:IsToggled())
    end)

local makeMissionEntityFeature = FeatureMgr.AddFeature(Utils.Joaat("Spooner_MakeMissionEntity"),
    "Set as Mission Entity", eFeatureType.Toggle, "Automatically set entities as mission entities (Better networking)",
    function(f)
        Spooner.makeMissionEntity = f:IsToggled()
    end)
makeMissionEntityFeature:Toggle()

FeatureMgr.AddFeature(Utils.Joaat("Spooner_RemoveEntity"), "Remove from List", eFeatureType.Button,
    "Remove selected entity from tracking", function(f)
        if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
            table.remove(Spooner.managedEntities, Spooner.selectedEntityIndex)
        else
            GUI.AddToast("Spooner", "No valid entity selected", 2000, eToastPos.BOTTOM_RIGHT)
        end
    end)

FeatureMgr.AddFeature(Utils.Joaat("Spooner_DeleteEntity"), "Delete Entity", eFeatureType.Button,
    "Delete selected entity from the game", function(f)
        if Spooner.selectedEntityIndex > 0 and Spooner.selectedEntityIndex <= #Spooner.managedEntities then
            local entity = Spooner.managedEntities[Spooner.selectedEntityIndex]

            CustomLogger.Info("Deleting entity: " .. tostring(entity))

            if ENTITY.DOES_ENTITY_EXIST(entity) then
                -- Move deletion to a job to allow for control request delays
                Script.QueueJob(function()
                    Spooner.TakeControlOfEntity(entity)

                    local ptr = Memory.AllocInt()
                    Memory.WriteInt(ptr, entity)

                    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, true, true)
                    ENTITY.DELETE_ENTITY(ptr)

                    Memory.Free(ptr)

                    CustomLogger.Info("Deleted entity: " .. tostring(entity))
                end)

                -- Remove from list immediately
                table.remove(Spooner.managedEntities, Spooner.selectedEntityIndex)
            end
        else
            GUI.AddToast("Spooner", "No valid entity selected", 2000, eToastPos.BOTTOM_RIGHT)
        end
    end)

FeatureMgr.AddFeature(Utils.Joaat("Spooner_EnableF9Key"), "Enable F9 Key", eFeatureType.Toggle,
    "Enable F9 key to toggle freecam", function(f)
        if f:IsToggled() then
            toggleSpoonerModeFeature:AddHotKey(120)
        else
            toggleSpoonerModeFeature:RemoveHotkey(120, false)
        end
    end)

FeatureMgr.AddFeature(Utils.Joaat("Spooner_EnableThrowableMode"), "Enable Throwable Mode", eFeatureType.Toggle,
    "Enable Throwable Mode", function(f)
        if f:IsToggled() then
            Spooner.throwableMode = true
        else
            Spooner.throwableMode = false
        end
    end)

-- Initialize ClickGUI
DrawManager.ClickGUIInit()

-- Update freecam every frame
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
