local SpoonerCore = {}

function SpoonerCore.New(deps)
    local CONSTANTS = deps.CONSTANTS
    local NetworkUtils = deps.NetworkUtils
    local CameraUtils = deps.CameraUtils
    local MemoryUtils = deps.MemoryUtils
    local Raycast = deps.Raycast
    local RaycastForClipToGround = deps.RaycastForClipToGround
    local XMLParser = deps.XMLParser
    local Keybinds = deps.Keybinds
    local CustomLogger = deps.CustomLogger
    local spoonerSavePath = deps.spoonerSavePath
    local SpoonerUtils = deps.SpoonerUtils
    local RotationUtils = deps.RotationUtils

    local self = {}

    -- State
    self.inSpoonerMode = false
    self.freecam = nil
    self.freecamBlip = nil
    self.camSpeed = CONSTANTS.CAMERA_SPEED
    self.camRotSpeed = CONSTANTS.CAMERA_ROT_SPEED
    self.crosshairColor = {r = 255, g = 255, b = 255, a = 255}
    self.crosshairSize = 0.01
    self.crosshairGap = 0
    self.crosshairThickness = 0.001
    self.crosshairColorGreen = {r = 0, g = 255, b = 0, a = 255}
    self.lastEntityPos = nil
    self.grabVelocity = {x = 0, y = 0, z = 0}
    self.targetedEntity = nil
    self.isEntityTargeted = false
    self.grabbedEntity = nil
    self.grabOffsets = nil
    self.grabbedEntityRotation = nil
    self.isGrabbing = false
    self.scaleform = nil
    ---@type ManagedEntity[]
    self.managedEntities = {}
    self.selectedEntityIndex = 0
    self.selectedEntityBlip = nil
    self.throwableVelocityMultiplier = CONSTANTS.VELOCITY_MULTIPLIER
    self.throwableMode = false
    self.clipToGround = false
    self.lockMovementWhileMenuIsOpen = false
    self.lockMovementWhileMenuIsOpenEnhanced = false
    self.spawnUnnetworked = false
    -- Preview spawn system
    self.previewEntity = nil
    self.previewModelHash = nil
    self.previewEntityType = nil
    self.previewModelName = nil
    self.pendingPreviewDelete = nil
    self.saveFileName = "MyPlacements"
    self.selectedXMLFile = nil
    ---@type QuickEditEntity
    self.quickEditEntity = nil
    -- Follow player mode
    self.followPlayerEnabled = false
    self.followPlayerId = nil
    self.followOffset = nil
    self.lastFollowPlayerPos = nil
    -- Player frozen state tracking
    self.playerWasFrozen = false

    function self.TakeControlOfEntity(entity)
        return NetworkUtils.MaintainNetworkControlV2(entity)
    end

    function self.IsEntityRestricted(entity)
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

    function self.CalculateNewPosition(camPos, fwd, right, up, offsets)
        return {
            x = camPos.x + (right.x * offsets.x) + (fwd.x * offsets.y) + (up.x * offsets.z),
            y = camPos.y + (right.y * offsets.x) + (fwd.y * offsets.y) + (up.y * offsets.z),
            z = camPos.z + (right.z * offsets.x) + (fwd.z * offsets.y) + (up.z * offsets.z)
        }
    end

    function self.CalculateGrabOffsets(camPos, entityPos, fwd, right, up)
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

    function self.ShouldLockMovement()
        return GUI.IsOpen() and (self.lockMovementWhileMenuIsOpen or (self.lockMovementWhileMenuIsOpenEnhanced and (ImGui.IsWindowHovered(ImGuiHoveredFlags.AnyWindow) or ImGui.IsAnyItemHovered() or ImGui.IsAnyItemActive())))
    end

    function self.StartFollowingPlayer(playerId)
        if not self.freecam then
            return false
        end

        local cPed = Players.GetCPed(playerId)
        if not cPed then
            return false
        end

        local camPos = CAM.GET_CAM_COORD(self.freecam)
        local playerPos = cPed.Position

        self.followOffset = {
            x = camPos.x - playerPos.x,
            y = camPos.y - playerPos.y,
            z = camPos.z - playerPos.z
        }
        self.lastFollowPlayerPos = {
            x = playerPos.x,
            y = playerPos.y,
            z = playerPos.z
        }
        self.followPlayerId = playerId
        self.followPlayerEnabled = true

        CustomLogger.Info("Now following player: " .. Players.GetName(playerId))
        return true
    end

    function self.StopFollowingPlayer()
        self.followPlayerEnabled = false
        self.followPlayerId = nil
        self.followOffset = nil
        self.lastFollowPlayerPos = nil
        CustomLogger.Info("Stopped following player")
    end

    function self.GetFollowPlayerDelta()
        if not self.followPlayerEnabled or not self.followPlayerId then
            return nil
        end

        local cPed = Players.GetCPed(self.followPlayerId)
        if not cPed then
            self.StopFollowingPlayer()
            return nil
        end

        local playerPos = cPed.Position

        local delta = {
            x = playerPos.x - self.lastFollowPlayerPos.x,
            y = playerPos.y - self.lastFollowPlayerPos.y,
            z = playerPos.z - self.lastFollowPlayerPos.z
        }

        self.lastFollowPlayerPos = {
            x = playerPos.x,
            y = playerPos.y,
            z = playerPos.z
        }

        return delta
    end

    function self.GetGroundZAtPosition(x, y, z, ignoreEntity)
        local isTargeted, entityTarget, rayHitCoords = RaycastForClipToGround.PerformCheck(x, y, z + 4, x, y, z - 100, CONSTANTS.CLIP_TO_GROUND_RAYCAST_FLAGS, ignoreEntity)
        return rayHitCoords.z
    end

    function self.GetEntityDimensions(entity, memoryName)
        return self.GetModelDimensions(ENTITY.GET_ENTITY_MODEL(entity), memoryName)
    end

    function self.GetModelDimensions(modelHash, memoryName)
        local min = MemoryUtils.AllocV3(memoryName .. "Min")
        local max = MemoryUtils.AllocV3(memoryName .. "Max")
        MISC.GET_MODEL_DIMENSIONS(modelHash, min, max)
        local minV3 = MemoryUtils.ReadV3(min)
        local maxV3 = MemoryUtils.ReadV3(max)

        return minV3.x, minV3.y, minV3.z, maxV3.x, maxV3.y, maxV3.z
    end

    function self.ClipEntityToGround(entity, newPos)
        if not self.clipToGround then
            return newPos
        end

        local groundZ = self.GetGroundZAtPosition(newPos.x, newPos.y, newPos.z, entity)

        if groundZ then
            local minX, minY, minZ, maxX, maxY, maxZ = self.GetEntityDimensions(entity, "clip")

            local rot = self.grabbedEntityRotation or ENTITY.GET_ENTITY_ROTATION(entity, 2)
            ENTITY.SET_ENTITY_ROTATION(entity, rot.x, rot.y, rot.z, 2, true)

            local corners = {
                {minX, minY, minZ}, {maxX, minY, minZ},
                {maxX, maxY, minZ}, {minX, maxY, minZ},
                {minX, minY, maxZ}, {maxX, minY, maxZ},
                {maxX, maxY, maxZ}, {minX, maxY, maxZ}
            }

            local lowestWorldZ = math.huge
            for _, corner in ipairs(corners) do
                local worldPos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(entity, corner[1], corner[2], corner[3])
                if worldPos.z < lowestWorldZ then
                    lowestWorldZ = worldPos.z
                end
            end

            local entityZ = ENTITY.GET_ENTITY_COORDS(entity, true).z
            local lowestOffset = lowestWorldZ - entityZ

            local projectedLowestZ = newPos.z + lowestOffset
            local distanceToGround = projectedLowestZ - groundZ

            if math.abs(distanceToGround) < CONSTANTS.CLIP_TO_GROUND_DISTANCE then
                newPos.z = groundZ - lowestOffset
            end
        end

        return newPos
    end

    function self.DeleteEntity(entity)
        self.UpdateSelectedEntityBlip()

        local netId = self.TakeControlOfEntity(entity)

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
    end

    function self.StartGrabbing()
        if self.isGrabbing or not self.isEntityTargeted or self.targetedEntity == nil then
            return false
        end

        self.isGrabbing = true
        self.grabbedEntity = self.targetedEntity

        local camPos = CAM.GET_CAM_COORD(self.freecam)
        local entityPos = ENTITY.GET_ENTITY_COORDS(self.grabbedEntity, true)
        local fwd, right, up, camRot = CameraUtils.GetBasis(self.freecam)

        self.grabOffsets = self.CalculateGrabOffsets(camPos, entityPos, fwd, right, up)
        self.grabbedEntityRotation = ENTITY.GET_ENTITY_ROTATION(self.grabbedEntity, 2)
        self.TakeControlOfEntity(self.grabbedEntity)

        return true
    end

    function self.UpdateGrabbedEntity()
        if not self.previewEntity and (not self.isGrabbing or not self.grabbedEntity) then
            return
        end

        local entity = self.grabbedEntity or self.previewEntity

        self.isEntityTargeted = true

        if not ENTITY.DOES_ENTITY_EXIST(entity) then
            self.ReleaseEntity()
            return
        end

        local camPos = CAM.GET_CAM_COORD(self.freecam)
        local fwd, right, up, camRot = CameraUtils.GetBasis(self.freecam)

        local speedMultiplier = Keybinds.MoveFaster.IsPressed() and CONSTANTS.ROTATION_SPEED_BOOST or 1.0

        if not self.ShouldLockMovement() then
            local scrollSpeed = CONSTANTS.SCROLL_SPEED * speedMultiplier
            if Keybinds.PushEntity.IsPressed() then
                self.grabOffsets.y = math.max(self.grabOffsets.y - scrollSpeed, CONSTANTS.MIN_GRAB_DISTANCE)
            elseif Keybinds.PullEntity.IsPressed() then
                self.grabOffsets.y = self.grabOffsets.y + scrollSpeed
            end
        end

        local rotationSpeed = CONSTANTS.ROTATION_SPEED * speedMultiplier

        -- Camera-based rotation: rotate around camera's basis vectors
        if Keybinds.RotateRight.IsPressed() then
            self.grabbedEntityRotation.z = self.grabbedEntityRotation.z - rotationSpeed
        elseif Keybinds.RotateLeft.IsPressed() then
            self.grabbedEntityRotation.z = self.grabbedEntityRotation.z + rotationSpeed
        end

        if Keybinds.PitchUp.IsPressed() then
            local newPitch, newRoll, newYaw = RotationUtils.ApplyCameraRelativeRotation(
                right, -rotationSpeed,
                self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z
            )
            self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z = newPitch, newRoll, newYaw
        elseif Keybinds.PitchDown.IsPressed() then
            local newPitch, newRoll, newYaw = RotationUtils.ApplyCameraRelativeRotation(
                right, rotationSpeed,
                self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z
            )
            self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z = newPitch, newRoll, newYaw
        end

        if Keybinds.RollLeft.IsPressed() then
            local newPitch, newRoll, newYaw = RotationUtils.ApplyCameraRelativeRotation(
                fwd, -rotationSpeed,
                self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z
            )
            self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z = newPitch, newRoll, newYaw
        elseif Keybinds.RollRight.IsPressed() then
            local newPitch, newRoll, newYaw = RotationUtils.ApplyCameraRelativeRotation(
                fwd, rotationSpeed,
                self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z
            )
            self.grabbedEntityRotation.x, self.grabbedEntityRotation.y, self.grabbedEntityRotation.z = newPitch, newRoll, newYaw
        end

        local newPos = self.CalculateNewPosition(camPos, fwd, right, up, self.grabOffsets)

        newPos = self.ClipEntityToGround(entity, newPos)

        ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, newPos.x, newPos.y, newPos.z, false, false, false)

        ENTITY.SET_ENTITY_ROTATION(
            entity,
            self.grabbedEntityRotation.x,
            self.grabbedEntityRotation.y,
            self.grabbedEntityRotation.z,
            2,
            true
        )

        if self.throwableMode then
            if self.lastEntityPos then
                self.grabVelocity = {
                    x = (newPos.x - self.lastEntityPos.x) * self.throwableVelocityMultiplier,
                    y = (newPos.y - self.lastEntityPos.y) * self.throwableVelocityMultiplier,
                    z = (newPos.z - self.lastEntityPos.z) * self.throwableVelocityMultiplier
                }
            end
            self.lastEntityPos = newPos
        end
    end

    function self.ReleaseEntity()
        if not self.isGrabbing or not self.grabbedEntity then
            return
        end

        if ENTITY.DOES_ENTITY_EXIST(self.grabbedEntity) and self.throwableMode then
            ENTITY.APPLY_FORCE_TO_ENTITY(
                self.grabbedEntity,
                1,
                self.grabVelocity.x,
                self.grabVelocity.y,
                self.grabVelocity.z,
                0.0, 0.0, 0.0,
                0,
                false,
                true,
                true,
                false,
                true
            )
        end

        self.isGrabbing = false
        self.grabbedEntity = nil
        self.lastEntityPos = nil
        self.grabVelocity = {x = 0, y = 0, z = 0}
    end

    function self.HandleEntityGrabbing()
        if not self.inSpoonerMode or not self.freecam then
            return
        end

        local isRightClickPressed = Keybinds.Grab.IsPressed()

        if not self.previewModelHash and not self.ShouldLockMovement() then
            if isRightClickPressed and (self.isGrabbing or (self.isEntityTargeted and self.targetedEntity)) then
                if not self.isGrabbing then
                    self.StartGrabbing()
                end
            else
                self.ReleaseEntity()
            end
        end
        self.UpdateGrabbedEntity()
    end

    function self.HandleInput()
        if not self.inSpoonerMode then
            return
        end

        if not self.previewModelHash and not self.isGrabbing and Keybinds.SelectForEdit.IsPressed() then
            if self.isEntityTargeted and self.targetedEntity and ENTITY.DOES_ENTITY_EXIST(self.targetedEntity) then
                self.SelectEntityForQuickEdit(self.targetedEntity)
            end
        end

        if not self.previewModelHash and Keybinds.AddOrRemoveFromList.IsPressed() then
            local entityToAdd = nil

            if self.isGrabbing and self.grabbedEntity and ENTITY.DOES_ENTITY_EXIST(self.grabbedEntity) then
                entityToAdd = self.grabbedEntity
            elseif self.isEntityTargeted and self.targetedEntity and ENTITY.DOES_ENTITY_EXIST(self.targetedEntity) then
                entityToAdd = self.targetedEntity
            end

            if entityToAdd then
                self.ToggleEntityInManagedList(entityToAdd)
            end
        end
    end

    function self.GetVehicleOfPed(ped)
        if PED.IS_PED_IN_ANY_VEHICLE(ped, true) then
            return PED.GET_VEHICLE_PED_IS_IN(ped, true)
        end
        return nil
    end

    function self.UpdateFreecam()
        if not self.inSpoonerMode or not self.freecam then
            return
        end

        PAD.DISABLE_ALL_CONTROL_ACTIONS(0)
        Keybinds.EnablePassthrough()

        local camPos = CAM.GET_CAM_COORD(self.freecam)
        local camRot = CAM.GET_CAM_ROT(self.freecam, 2)

        local rightAxisX = PAD.GET_DISABLED_CONTROL_NORMAL(0, 220)
        local rightAxisY = PAD.GET_DISABLED_CONTROL_NORMAL(0, 221)

        if not self.ShouldLockMovement() then
            camRot.z = camRot.z - (rightAxisX * self.camRotSpeed)
            camRot.x = CameraUtils.ClampPitch(camRot.x - (rightAxisY * self.camRotSpeed))
            camRot.y = 0.0
        end

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

        local speed = self.camSpeed
        if Keybinds.MoveFaster.IsPressed() then
            speed = speed * CONSTANTS.CAMERA_SPEED_BOOST
        end

        local followDelta = self.GetFollowPlayerDelta()
        if followDelta then
            camPos.x = camPos.x + followDelta.x
            camPos.y = camPos.y + followDelta.y
            camPos.z = camPos.z + followDelta.z
        end

        if not self.ShouldLockMovement() then
            camPos.x = camPos.x + (forwardX * (moveForward - moveBackward) * speed)
            camPos.y = camPos.y + (forwardY * (moveForward - moveBackward) * speed)
            camPos.z = camPos.z + (forwardZ * (moveForward - moveBackward) * speed)
            camPos.x = camPos.x + (rightX * (moveRight - moveLeft) * speed)
            camPos.y = camPos.y + (rightY * (moveRight - moveLeft) * speed)
            camPos.z = camPos.z + ((moveUp - moveDown) * speed)
        end

        CAM.SET_CAM_COORD(self.freecam, camPos.x, camPos.y, camPos.z)
        CAM.SET_CAM_ROT(self.freecam, camRot.x, camRot.y, camRot.z, 2)

        STREAMING.SET_FOCUS_POS_AND_VEL(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)
        HUD.LOCK_MINIMAP_POSITION(camPos.x, camPos.y)

        if self.freecamBlip then
            HUD.SET_BLIP_COORDS(self.freecamBlip, camPos.x, camPos.y, camPos.z)
        end
    end

    function self.ToggleSpoonerMode(f)
        if self.inSpoonerMode == f then
            return
        end

        self.inSpoonerMode = f
        if self.inSpoonerMode then
            local camPos = CAM.GET_GAMEPLAY_CAM_COORD()
            local camRot = CAM.GET_GAMEPLAY_CAM_ROT(2)

            self.freecam = CAM.CREATE_CAM("DEFAULT_SCRIPTED_CAMERA", true)
            CAM.SET_CAM_COORD(self.freecam, camPos.x, camPos.y, camPos.z)
            CAM.SET_CAM_ROT(self.freecam, camRot.x, 0.0, camRot.z, 2)
            CAM.SET_CAM_ACTIVE(self.freecam, true)
            CAM.RENDER_SCRIPT_CAMS(true, false, 0, true, false, 0)
            CAM.SET_CAM_CONTROLS_MINI_MAP_HEADING(self.freecam, true)

            local playerPed = PLAYER.PLAYER_PED_ID()
            local vehicle = self.GetVehicleOfPed(playerPed)
            self.playerWasFrozen = self.isEntityFrozen(vehicle or playerPed)
            if not self.playerWasFrozen then
                ENTITY.FREEZE_ENTITY_POSITION(vehicle or playerPed, true)
            end

            self.freecamBlip = HUD.ADD_BLIP_FOR_COORD(camPos.x, camPos.y, camPos.z)
            HUD.SET_BLIP_SPRITE(self.freecamBlip, 184)
            HUD.SET_BLIP_COLOUR(self.freecamBlip, 5)
            HUD.SET_BLIP_SCALE(self.freecamBlip, 0.8)

            self.UpdateSelectedEntityBlip()

            CustomLogger.Info("Freecam enabled")
        else
            if self.freecam then
                STREAMING.CLEAR_FOCUS()
                HUD.UNLOCK_MINIMAP_POSITION()
                HUD.UNLOCK_MINIMAP_ANGLE()
                CAM.RENDER_SCRIPT_CAMS(false, false, 0, true, false, 0)
                CAM.SET_CAM_ACTIVE(self.freecam, false)
                CAM.DESTROY_CAM(self.freecam, false)
                self.freecam = nil
                self.targetedEntity = nil

                local playerPed = PLAYER.PLAYER_PED_ID()
                local vehicle = self.GetVehicleOfPed(playerPed)
                if not self.playerWasFrozen then
                    ENTITY.FREEZE_ENTITY_POSITION(vehicle or playerPed, false)
                end

                if self.freecamBlip then
                    local ptr = MemoryUtils.AllocInt("blipPtr")
                    Memory.WriteInt(ptr, self.freecamBlip)
                    HUD.REMOVE_BLIP(ptr)
                    self.freecamBlip = nil
                end

                if self.followPlayerEnabled then
                    self.StopFollowingPlayer()
                end

                if self.selectedEntityBlip then
                    local ptr = MemoryUtils.AllocInt("selectedBlipPtr2")
                    Memory.WriteInt(ptr, self.selectedEntityBlip)
                    HUD.REMOVE_BLIP(ptr)
                    self.selectedEntityBlip = nil
                end

                CustomLogger.Info("Freecam disabled")
            end
        end
    end

    function self.ToggleEntityInManagedList(entity)
        if not entity then
            return
        end

        for i, managed in ipairs(self.managedEntities) do
            if managed.entity == entity then
                table.remove(self.managedEntities, i)
                CustomLogger.Info("Removed entity from managed list: " .. tostring(entity))
                if self.selectedEntityIndex == i then
                    self.quickEditEntity = managed
                    self.selectedEntityIndex = 0
                    self.UpdateSelectedEntityBlip()
                elseif self.selectedEntityIndex > i then
                    self.selectedEntityIndex = self.selectedEntityIndex - 1
                    self.UpdateSelectedEntityBlip()
                end
                return
            end
        end

        local networkId = 0
        local networked = false
        if NetworkUtils.IsEntityNetworked(entity) then
            self.TakeControlOfEntity(entity)
            networkId = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(entity)
            networked = true
        end
        local pos = ENTITY.GET_ENTITY_COORDS(entity, true)
        local rot = ENTITY.GET_ENTITY_ROTATION(entity, 2)
        ---@type ManagedEntity
        local managedEntry = {
            entity = entity,
            networkId = networkId,
            networked = networked,
            x = pos.x, y = pos.y, z = pos.z,
            rotX = rot.x, rotY = rot.y, rotZ = rot.z
        }
        table.insert(self.managedEntities, managedEntry)
        CustomLogger.Info("Entity added to managed list: " .. tostring(entity) .. " (netId: " .. tostring(networkId) .. ")")

        if self.quickEditEntity and self.quickEditEntity.entity == entity then
            self.quickEditEntity = nil
            self.selectedEntityIndex = #self.managedEntities
            self.UpdateSelectedEntityBlip()
        end
    end

    function self.SelectEntityForQuickEdit(entity)
        if not entity or not ENTITY.DOES_ENTITY_EXIST(entity) then
            return false
        end

        local foundIndex = nil
        for i, managed in ipairs(self.managedEntities) do
            if managed.entity == entity then
                foundIndex = i
                break
            end
        end

        if foundIndex then
            self.selectedEntityIndex = foundIndex
            self.quickEditEntity = nil
        else
            local isNetworked = NetworkUtils.IsEntityNetworked(entity)
            self.quickEditEntity = {entity = entity, networked = isNetworked, networkId = NetworkUtils.GetNetworkIdOf(entity)}
            self.selectedEntityIndex = 0
        end

        if self.UpdateFreezeToggle then self.UpdateFreezeToggle(entity) end
        if self.UpdateDynamicToggle then self.UpdateDynamicToggle(entity) end
        if self.UpdateGodModeToggle then self.UpdateGodModeToggle(entity) end
        if self.UpdateNetworkedToggle then self.UpdateNetworkedToggle(entity) end

        self.UpdateSelectedEntityBlip()

        if not GUI.IsOpen() then
            GUI.Toggle()
        end

        GUI.AddToast("Spooner", "Entity selected for editing", 1500)
        return true
    end

    ---@return integer|nil entity
    ---@return boolean isInDatabase
    ---@return integer networkId
    ---@return boolean networked
    function self.GetEditingEntity()
        if self.selectedEntityIndex > 0 and self.selectedEntityIndex <= #self.managedEntities then
            local managed = self.managedEntities[self.selectedEntityIndex]
            if ENTITY.DOES_ENTITY_EXIST(managed.entity) then
                return managed.entity, true, managed.networkId, managed.networked
            end
        end

        if self.quickEditEntity then
            if ENTITY.DOES_ENTITY_EXIST(self.quickEditEntity.entity) then
                return self.quickEditEntity.entity, false, self.quickEditEntity.networkId, self.quickEditEntity.networked
            else
                self.quickEditEntity = nil
            end
        end

        return nil, false, 0, false
    end

    function self.UpdateSelectedEntityBlip()
        if self.selectedEntityBlip then
            local ptr = MemoryUtils.AllocInt("selectedBlipPtr")
            Memory.WriteInt(ptr, self.selectedEntityBlip)
            HUD.REMOVE_BLIP(ptr)
            self.selectedEntityBlip = nil
        end

        local entity = self.GetEditingEntity()
        if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
            self.selectedEntityBlip = HUD.ADD_BLIP_FOR_ENTITY(entity)
            HUD.SET_BLIP_SPRITE(self.selectedEntityBlip, 1)
            HUD.SET_BLIP_COLOUR(self.selectedEntityBlip, 1)
            HUD.SET_BLIP_SCALE(self.selectedEntityBlip, 1.0)
        end
    end

    function self.ManageEntities()
        local entity, isInDatabase = self.GetEditingEntity()
        if entity and not isInDatabase then
            self.TakeControlOfEntity(self.quickEditEntity.entity)
        end
    end

    function self.GetVehicleProperties(vehicle)
        local props = {}

        local primaryColorPtr = MemoryUtils.AllocInt("vehPrimary")
        local secondaryColorPtr = MemoryUtils.AllocInt("vehSecondary")
        VEHICLE.GET_VEHICLE_COLOURS(vehicle, primaryColorPtr, secondaryColorPtr)
        props.primaryColor = Memory.ReadInt(primaryColorPtr)
        props.secondaryColor = Memory.ReadInt(secondaryColorPtr)

        local pearlColorPtr = MemoryUtils.AllocInt("vehPearl")
        local rimColorPtr = MemoryUtils.AllocInt("vehRim")
        VEHICLE.GET_VEHICLE_EXTRA_COLOURS(vehicle, pearlColorPtr, rimColorPtr)
        props.pearlColor = Memory.ReadInt(pearlColorPtr)
        props.rimColor = Memory.ReadInt(rimColorPtr)

        local mod1aPtr = MemoryUtils.AllocInt("vehMod1a")
        local mod1bPtr = MemoryUtils.AllocInt("vehMod1b")
        local mod1cPtr = MemoryUtils.AllocInt("vehMod1c")
        VEHICLE.GET_VEHICLE_MOD_COLOR_1(vehicle, mod1aPtr, mod1bPtr, mod1cPtr)
        props.mod1a = Memory.ReadInt(mod1aPtr)
        props.mod1b = Memory.ReadInt(mod1bPtr)
        props.mod1c = Memory.ReadInt(mod1cPtr)

        local mod2aPtr = MemoryUtils.AllocInt("vehMod2a")
        local mod2bPtr = MemoryUtils.AllocInt("vehMod2b")
        VEHICLE.GET_VEHICLE_MOD_COLOR_2(vehicle, mod2aPtr, mod2bPtr)
        props.mod2a = Memory.ReadInt(mod2aPtr)
        props.mod2b = Memory.ReadInt(mod2bPtr)

        props.isPrimaryCustom = VEHICLE.GET_IS_VEHICLE_PRIMARY_COLOUR_CUSTOM(vehicle)
        props.isSecondaryCustom = VEHICLE.GET_IS_VEHICLE_SECONDARY_COLOUR_CUSTOM(vehicle)

        local tyreSmokeRPtr = MemoryUtils.AllocInt("vehTyreSmokeR")
        local tyreSmokeGPtr = MemoryUtils.AllocInt("vehTyreSmokeG")
        local tyreSmokeBPtr = MemoryUtils.AllocInt("vehTyreSmokeB")
        VEHICLE.GET_VEHICLE_TYRE_SMOKE_COLOR(vehicle, tyreSmokeRPtr, tyreSmokeGPtr, tyreSmokeBPtr)
        props.tyreSmokeR = Memory.ReadInt(tyreSmokeRPtr)
        props.tyreSmokeG = Memory.ReadInt(tyreSmokeGPtr)
        props.tyreSmokeB = Memory.ReadInt(tyreSmokeBPtr)

        props.interiorColor = 0
        props.dashboardColor = 0
        props.xenonColor = 255

        props.livery = VEHICLE.GET_VEHICLE_LIVERY(vehicle)
        props.plateText = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(vehicle)
        props.plateIndex = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle)
        props.wheelType = VEHICLE.GET_VEHICLE_WHEEL_TYPE(vehicle)
        props.windowTint = VEHICLE.GET_VEHICLE_WINDOW_TINT(vehicle)
        props.bulletProofTyres = not VEHICLE.GET_VEHICLE_TYRES_CAN_BURST(vehicle)
        props.dirtLevel = VEHICLE.GET_VEHICLE_DIRT_LEVEL(vehicle)
        props.roofState = VEHICLE.GET_CONVERTIBLE_ROOF_STATE(vehicle)
        props.engineHealth = VEHICLE.GET_VEHICLE_ENGINE_HEALTH(vehicle)
        props.engineOn = VEHICLE.GET_IS_VEHICLE_ENGINE_RUNNING(vehicle)
        props.lightsOn = VEHICLE.GET_VEHICLE_LIGHTS_STATE(vehicle, MemoryUtils.AllocInt("vehLightsOn"), MemoryUtils.AllocInt("vehHighBeams"))
        props.lockStatus = VEHICLE.GET_VEHICLE_DOOR_LOCK_STATUS(vehicle)

        props.neonLeft = false
        props.neonRight = false
        props.neonFront = false
        props.neonBack = false
        props.neonR = 255
        props.neonG = 0
        props.neonB = 255

        props.mods = {}
        props.modVariations = {}
        for i = 0, 48 do
            if i >= 17 and i <= 22 then
                props.mods[i] = VEHICLE.IS_TOGGLE_MOD_ON(vehicle, i)
            else
                props.mods[i] = VEHICLE.GET_VEHICLE_MOD(vehicle, i)
                props.modVariations[i] = VEHICLE.GET_VEHICLE_MOD_VARIATION(vehicle, i)
            end
        end

        props.extras = {}
        for i = 1, 12 do
            if i ~= 9 and i ~= 10 then
                props.extras[i] = VEHICLE.IS_VEHICLE_EXTRA_TURNED_ON(vehicle, i)
            end
        end

        return props
    end

    function self.GetPedProperties(ped)
        local props = {}
        props.canRagdoll = PED.CAN_PED_RAGDOLL(ped)
        props.armour = PED.GET_PED_ARMOUR(ped)

        local weaponHashPtr = MemoryUtils.AllocInt("pedWeaponHash")
        WEAPON.GET_CURRENT_PED_WEAPON(ped, weaponHashPtr, true)
        props.currentWeapon = string.format("0x%X", Memory.ReadInt(weaponHashPtr))

        return props
    end

    function self.GetEntityPlacementData(entity)
        if not ENTITY.DOES_ENTITY_EXIST(entity) then
            return nil
        end

        local placement = {}
        local modelHash = ENTITY.GET_ENTITY_MODEL(entity)

        placement.modelHash = string.format("0x%x", modelHash)
        placement.hashName = GTA.GetModelNameFromHash(modelHash) or ""
        placement.handle = entity

        if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
            placement.type = 2
            placement.vehicleProperties = self.GetVehicleProperties(entity)
        elseif ENTITY.IS_ENTITY_A_PED(entity) then
            placement.type = 1
            placement.pedProperties = self.GetPedProperties(entity)
        else
            placement.type = 3
        end

        local pos = ENTITY.GET_ENTITY_COORDS(entity, true)
        local rot = ENTITY.GET_ENTITY_ROTATION(entity, 2)
        placement.position = {x = pos.x, y = pos.y, z = pos.z}
        placement.rotation = {x = rot.x, y = rot.y, z = rot.z}

        placement.frozen = self.isEntityFrozen(entity)
        placement.dynamic = not placement.frozen
        placement.health = ENTITY.GET_ENTITY_HEALTH(entity)
        placement.maxHealth = ENTITY.GET_ENTITY_MAX_HEALTH(entity)
        placement.isInvincible = ENTITY.GET_ENTITY_CAN_BE_DAMAGED(entity) == false
        placement.hasGravity = true

        return placement
    end

    function self.SaveDatabaseToXML(filename)
        if #self.managedEntities == 0 then
            CustomLogger.Warn("No entities in database to save")
            GUI.AddToast("Spooner", "No entities in database to save", 2000)
            return false
        end

        local placements = {}
        local referenceCoords = nil

        for _, managed in ipairs(self.managedEntities) do
            local placementData = self.GetEntityPlacementData(managed.entity)
            if placementData then
                table.insert(placements, placementData)

                if not referenceCoords then
                    referenceCoords = placementData.position
                end
            end
        end

        if #placements == 0 then
            CustomLogger.Warn("No valid entities to save")
            GUI.AddToast("Spooner", "No valid entities to save", 2000)
            return false
        end

        local xmlContent = XMLParser.GenerateSpoonerXML(placements, referenceCoords)
        local filePath = spoonerSavePath .. "\\" .. filename .. ".xml"

        local parts = SpoonerUtils.SplitString(filename, "/\\")
        local folder = ""
        for i=1, #parts - 1 do
            folder = folder .. "\\" .. parts[i]
            FileMgr.CreateDir(spoonerSavePath .. folder)
            CustomLogger.Info("Creating dir: " .. spoonerSavePath .. folder)
        end

        if FileMgr.WriteFileContent(filePath, xmlContent) then
            CustomLogger.Info("Saved " .. #placements .. " entities to " .. filePath)
            GUI.AddToast("Spooner", "Saved " .. #placements .. " entities to " .. filename .. ".xml", 3000)
            return true
        else
            CustomLogger.Error("Failed to save database to " .. filePath)
            GUI.AddToast("Spooner", "Failed to save database", 2000)
            return false
        end
    end

    function self.ApplyVehicleProperties(vehicle, props)
        if not props then return end

        VEHICLE.SET_VEHICLE_COLOURS(vehicle, props.primaryColor or 0, props.secondaryColor or 0)
        VEHICLE.SET_VEHICLE_EXTRA_COLOURS(vehicle, props.pearlColor or 0, props.rimColor or 0)

        if props.mod1a then
            VEHICLE.SET_VEHICLE_MOD_COLOR_1(vehicle, props.mod1a, props.mod1b or 0, props.mod1c or 0)
        end
        if props.mod2a then
            VEHICLE.SET_VEHICLE_MOD_COLOR_2(vehicle, props.mod2a, props.mod2b or 0)
        end

        if props.tyreSmokeR then
            VEHICLE.SET_VEHICLE_TYRE_SMOKE_COLOR(vehicle, props.tyreSmokeR, props.tyreSmokeG or 255, props.tyreSmokeB or 255)
        end

        if props.plateText and props.plateText ~= "" then
            VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, props.plateText)
        end
        if props.plateIndex then
            VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle, props.plateIndex)
        end
        if props.wheelType then
            VEHICLE.SET_VEHICLE_WHEEL_TYPE(vehicle, props.wheelType)
        end
        if props.windowTint then
            VEHICLE.SET_VEHICLE_WINDOW_TINT(vehicle, props.windowTint)
        end
        if props.bulletProofTyres then
            VEHICLE.SET_VEHICLE_TYRES_CAN_BURST(vehicle, not props.bulletProofTyres)
        end
        if props.livery and props.livery >= 0 then
            VEHICLE.SET_VEHICLE_LIVERY(vehicle, props.livery)
        end

        VEHICLE.SET_VEHICLE_MOD_KIT(vehicle, 0)

        if props.mods then
            for i = 0, 48 do
                if props.mods[i] then
                    if i >= 17 and i <= 22 then
                        VEHICLE.TOGGLE_VEHICLE_MOD(vehicle, i, props.mods[i])
                    elseif props.mods[i] >= 0 then
                        local variation = props.modVariations and props.modVariations[i] or false
                        VEHICLE.SET_VEHICLE_MOD(vehicle, i, props.mods[i], variation)
                    end
                end
            end
        end
    end

    function self.ApplyPedProperties(ped, props)
        if not props then return end

        if props.armour then
            PED.SET_PED_ARMOUR(ped, props.armour)
        end

        if props.currentWeapon then
            local weaponHash = XMLParser.ParseNumber(props.currentWeapon)
            if weaponHash ~= 0 then
                WEAPON.GIVE_WEAPON_TO_PED(ped, weaponHash, 999, false, true)
            end
        end
    end

    function self.SpawnFromPlacement(placement)
        local modelHash = XMLParser.ParseNumber(placement.modelHash)
        if modelHash == 0 then
            CustomLogger.Error("Invalid model hash: " .. tostring(placement.modelHash))
            return nil
        end

        local pos = placement.position
        local rot = placement.rotation
        local entity = nil

        if placement.type == 2 then
            entity = GTA.SpawnVehicle(modelHash, pos.x, pos.y, pos.z, rot.z, false, false)
            if entity and entity ~= 0 then
                self.ApplyVehicleProperties(entity, placement.vehicleProperties)
            end
        elseif placement.type == 1 then
            entity = GTA.CreatePed(modelHash, 26, pos.x, pos.y, pos.z, rot.z, false, false)
            if entity and entity ~= 0 then
                self.ApplyPedProperties(entity, placement.pedProperties)
                PED.SET_BLOCKING_OF_NON_TEMPORARY_EVENTS(entity, true)
                TASK.TASK_SET_BLOCKING_OF_NON_TEMPORARY_EVENTS(entity, true)
            end
        else
            entity = GTA.CreateWorldObject(modelHash, pos.x, pos.y, pos.z, false, false)
        end

        if entity and entity ~= 0 then
            ENTITY.SET_ENTITY_COORDS_NO_OFFSET(entity, pos.x, pos.y, pos.z, false, false, false)
            ENTITY.SET_ENTITY_ROTATION(entity, rot.x, rot.y, rot.z, 2, true)
            ENTITY.SET_ENTITY_LOD_DIST(entity, 0xFFFF)

            if placement.frozen then
                ENTITY.FREEZE_ENTITY_POSITION(entity, true)
            end

            if placement.isInvincible then
                ENTITY.SET_ENTITY_INVINCIBLE(entity, true)
            end

            local entityPos = ENTITY.GET_ENTITY_COORDS(entity, true)
            local entityRot = ENTITY.GET_ENTITY_ROTATION(entity, 2)
            ---@type ManagedEntity
            local managedEntry = {
                entity = entity,
                networkId = 0,
                networked = false,
                x = entityPos.x, y = entityPos.y, z = entityPos.z,
                rotX = entityRot.x, rotY = entityRot.y, rotZ = entityRot.z
            }
            table.insert(self.managedEntities, managedEntry)

            CustomLogger.Info("Spawned entity: " .. (placement.hashName or placement.modelHash))

            return entity, managedEntry
        end

        return entity, nil
    end

    function self.LoadDatabaseFromXML(filePath)
        if not FileMgr.DoesFileExist(filePath) then
            CustomLogger.Error("File not found: " .. filePath)
            GUI.AddToast("Spooner", "File not found: " .. filePath, 2000)
            return false
        end

        local xmlContent = FileMgr.ReadFileContent(filePath)
        if not xmlContent or xmlContent == "" then
            CustomLogger.Error("Failed to read file: " .. filePath)
            GUI.AddToast("Spooner", "Failed to read file", 2000)
            return false
        end

        local parsed = XMLParser.ParseSpoonerXML(xmlContent)
        if not parsed or #parsed.placements == 0 then
            CustomLogger.Warn("No placements found in file")
            GUI.AddToast("Spooner", "No placements found in file", 2000)
            return false
        end

        CustomLogger.Info("Loading " .. #parsed.placements .. " placements from " .. filePath)
        GUI.AddToast("Spooner", "Loading " .. #parsed.placements .. " placements...", 2000)

        local spawnedEntities = {}
        for _, placement in ipairs(parsed.placements) do
            local entity, managedEntry = self.SpawnFromPlacement(placement)
            if entity then
                table.insert(spawnedEntities, {entity = entity, managedEntry = managedEntry})
            end
            Script.Yield(0)
        end

        if not self.spawnUnnetworked then
            for _, spawnData in ipairs(spawnedEntities) do
                if ENTITY.DOES_ENTITY_EXIST(spawnData.entity) then
                    local netId = NetworkUtils.MakeEntityNetworked(spawnData.entity)
                    spawnData.managedEntry.networkId = netId
                    spawnData.managedEntry.networked = true
                end
            end
        end

        CustomLogger.Info("Loaded " .. #spawnedEntities .. " entities from " .. filePath)
        GUI.AddToast("Spooner", "Loaded " .. #spawnedEntities .. " entities", 3000)
        return true
    end

    function self.GetAvailableXMLFiles()
        local files = {}
        local fileList = FileMgr.FindFiles(spoonerSavePath, ".xml", true)
        if fileList then
            for _, filename in ipairs(fileList) do
                if filename and filename ~= "" then
                    table.insert(files, filename)
                end
            end
        end
        return files
    end

    function self.isEntityFrozen(entity)
        local isFrozen = false
        local pEntity = GTA.HandleToPointer(entity)
        if pEntity and pEntity.IsFixed then
            isFrozen = true
        end
        return isFrozen
    end

    function self.isEntityDynamic(entity)
        local isDynamic = false
        local pEntity = GTA.HandleToPointer(entity)
        if pEntity and pEntity.IsDynamic and not pEntity.IsFixed then
            isDynamic = true
        end
        return isDynamic
    end

    -- Placeholder functions for feature toggle updates (set by SpoonerFeatures)
    self.UpdateFreezeToggle = nil
    self.UpdateDynamicToggle = nil
    self.UpdateGodModeToggle = nil
    self.UpdateNetworkedToggle = nil

    return self
end

return SpoonerCore
