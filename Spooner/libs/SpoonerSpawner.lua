local SpoonerSpawner = {}

function SpoonerSpawner.New(deps)
    local Spooner = deps.Spooner
    local CONSTANTS = deps.CONSTANTS
    local MemoryUtils = deps.MemoryUtils
    local CustomLogger = deps.CustomLogger
    local Keybinds = deps.Keybinds
    local NetworkUtils = deps.NetworkUtils

    local self = {}
    self.isRunningPreviewSpawn = false

    function self.LoadModel(modelHash, timeout)
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

    function self.GetModelSize(modelHash)
        STREAMING.REQUEST_MODEL(modelHash)
        local timeout = Time.GetEpocheMs() + 1000
        while not STREAMING.HAS_MODEL_LOADED(modelHash) and Time.GetEpocheMs() < timeout do
            Script.Yield(0)
        end

        if not STREAMING.HAS_MODEL_LOADED(modelHash) then
            return 10.0
        end

        local minX, minY, minZ, maxX, maxY, maxZ = Spooner.GetModelDimensions(modelHash, "modelSize")

        local sizeX = maxX - minX
        local sizeY = maxY - minY
        local sizeZ = maxZ - minZ
        local diagonalSize = math.sqrt(sizeX * sizeX + sizeY * sizeY + sizeZ * sizeZ)

        return diagonalSize
    end

    function self.SelectEntity(entityType, modelName, modelHash)
        if Spooner.previewModelHash == modelHash then
            return
        end

        Script.QueueJob(function()
            -- Clear existing preview if any, but keep the rotation
            self.ClearPreview(true, false)

            local modelSize = self.GetModelSize(modelHash)
            local previewDistance = math.max(5.0, math.min(modelSize * 1.5, 50.0))
            Spooner.grabOffsets = {x = 0, y = previewDistance, z = 0}

            Spooner.previewEntityType = entityType
            Spooner.previewModelName = modelName
            Spooner.previewModelHash = modelHash
        end)

        CustomLogger.Info("Selected " .. entityType .. ": " .. modelName .. " - Press Enter to spawn, Backspace to cancel")
    end

    function self.SpawnProp(hashString, propName)
        local hash = Utils.sJoaat(hashString)
        local name = propName or hashString
        self.SelectEntity("prop", name, hash)
    end

    function self.SpawnVehicle(modelName)
        local hash = Utils.sJoaat(modelName)
        self.SelectEntity("vehicle", modelName, hash)
    end

    function self.SpawnPed(modelName)
        local hash = Utils.sJoaat(modelName)
        self.SelectEntity("ped", modelName, hash)
    end

    function self.ClearPreview(keepRotation, keepOffset)
        if Spooner.previewEntity then
            Spooner.DeleteEntity(Spooner.previewEntity)
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

    function self.CreatePreviewEntity(modelHash, entityType, pos)
        if self.isRunningPreviewSpawn then return end
        self.isRunningPreviewSpawn = true
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
    
        self.isRunningPreviewSpawn = false
    
        return entity
    end

    function self.GetCrosshairWorldPosition()
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

        local defaultPos = {
            x = camPos.x + fwdX * defaultSpawnDistance,
            y = camPos.y + fwdY * defaultSpawnDistance,
            z = camPos.z + fwdZ * defaultSpawnDistance
        }

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

            local dx = hit.x - camPos.x
            local dy = hit.y - camPos.y
            local dz = hit.z - camPos.z
            local hitDistance = math.sqrt(dx*dx + dy*dy + dz*dz)

            if hitDistance < maxRaycastDistance then
                finalPos = hitV3
                didHitGround = true
            end
        end

        return finalPos, didHitGround
    end

    function self.UpdatePreview()
        if not Spooner.inSpoonerMode or not Spooner.previewModelHash then
            if Spooner.previewEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
                Spooner.DeleteEntity(Spooner.previewEntity)
                Spooner.previewEntity = nil
            end
            return
        end
    
        -- Create preview entity if needed
        if not Spooner.previewEntity or not ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
            Spooner.previewEntity = self.CreatePreviewEntity(Spooner.previewModelHash, Spooner.previewEntityType, {x=0,y=0,z=0})
        end
    end

    function self.ConfirmSpawn()
        if not Spooner.previewEntity or not ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
            return
        end

        -- Create actual entity
        Script.QueueJob(function()
            -- Remove status
            ENTITY.SET_ENTITY_COLLISION(Spooner.previewEntity, true, true)
            ENTITY.SET_ENTITY_INVINCIBLE(Spooner.previewEntity, false, false)
            if Spooner.previewEntityType ~= "prop" then
                ENTITY.FREEZE_ENTITY_POSITION(Spooner.previewEntity, false)
                ENTITY.SET_ENTITY_VELOCITY(Spooner.previewEntity, 0, 0 ,-1)
            end
            local networkId = 0
            local isNetworked = false
            if not Spooner.spawnUnnetworked then
                NetworkUtils.MakeEntityNetworked(Spooner.previewEntity)
                networkId = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(Spooner.previewEntity)
                isNetworked = NetworkUtils.IsEntityNetworked(Spooner.previewEntity)
            end
            local pos = ENTITY.GET_ENTITY_COORDS(Spooner.previewEntity, true)
            local rot = ENTITY.GET_ENTITY_ROTATION(Spooner.previewEntity, 2)

            ENTITY.SET_ENTITY_COORDS(Spooner.previewEntity, pos.x, pos.y, pos.z, false, false, false, false)
            ENTITY.SET_ENTITY_ROTATION(Spooner.previewEntity, rot.x, rot.y, rot.z, 0, false)

            ---@type ManagedEntity
            local managedEntry = {
                entity = Spooner.previewEntity,
                networkId = networkId,
                networked = isNetworked,
                x = pos.x, y = pos.y, z = pos.z,
                rotX = rot.x, rotY = rot.y, rotZ = rot.z
            }
            table.insert(Spooner.managedEntities, managedEntry)
            CustomLogger.Info("Spawned " .. Spooner.previewEntityType .. ": " .. Spooner.previewModelName .. (isNetworked and " [Networked]" or " [Local]"))
            Spooner.previewEntity = Spawner.CreatePreviewEntity(Spooner.previewModelHash, Spooner.previewEntityType, {x=0,y=0,z=0})
        end)
    end

    function self.HandleInput()
        if not Spooner.inSpoonerMode or not Spooner.previewModelHash then
            return
        end

        if Keybinds.ConfirmSpawn.IsPressed() then
            self.ConfirmSpawn()
        end

        if Keybinds.CancelSpawn.IsPressed() then
            self.ClearPreview()
            CustomLogger.Info("Spawn cancelled")
        end
    end

    return self
end

return SpoonerSpawner
