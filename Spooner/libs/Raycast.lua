local RaycastLib = {}

function RaycastLib.New(CONSTANTS, MemoryUtils)
    local Raycast = {}

    -- Active raycast data
    Raycast.data = nil
    Raycast.frameCounter = 0
    Raycast.currentTarget = nil

    -- Allocate persistent memory for raycast results using MemoryUtils
    local hit = MemoryUtils.AllocInt("raycast_hit")
    local endCoords = MemoryUtils.Alloc("raycast_endCoords", 24)
    local surfaceNormal = MemoryUtils.Alloc("raycast_surfaceNormal", 24)
    local entityHit = MemoryUtils.AllocInt("raycast_entityHit")

    function Raycast.StartProbe(startX, startY, startZ, endX, endY, endZ, flags)
        local handle = SHAPETEST.START_SHAPE_TEST_LOS_PROBE(
            startX, startY, startZ,
            endX, endY, endZ,
            flags,
            0,
            7
        )

        Raycast.data = {
            handle = handle,
            resultChecked = false
        }

        Raycast.currentTarget = nil

        return handle
    end

    function Raycast.CheckResult(isEntityRestrictedFunc)
        if not Raycast.data then
            return false, nil
        end

        local resultReady = SHAPETEST.GET_SHAPE_TEST_RESULT(
            Raycast.data.handle,
            hit,
            endCoords,
            surfaceNormal,
            entityHit
        )

        if resultReady == 2 then
            local hitVal = Memory.ReadInt(hit)
            local entityHitVal = Memory.ReadInt(entityHit)

            Raycast.data = nil

            if hitVal == 1 and entityHitVal ~= 0 and not isEntityRestrictedFunc(entityHitVal) then
                return true, entityHitVal
            else
                return true, nil
            end
        end

        return false, nil
    end

    function Raycast.PerformCheck(freecam, isGrabbing, isEntityRestrictedFunc)
        local isTargeted = not not Raycast.currentTarget
        local targetedEntity = Raycast.currentTarget

        -- Check existing raycast result
        if Raycast.data then
            local ready, entity = Raycast.CheckResult(isEntityRestrictedFunc)
            if ready then
                if entity then
                    isTargeted = true
                    targetedEntity = entity
                    Raycast.currentTarget = entity
                else
                    Raycast.currentTarget = nil
                end
            end
        end

        -- Start new raycast if not grabbing
        if not isGrabbing and not Raycast.data then
            Raycast.frameCounter = Raycast.frameCounter + 1
            if Raycast.frameCounter >= CONSTANTS.RAYCAST_INTERVAL then
                Raycast.frameCounter = 0

                local camCoord = CAM.GET_CAM_COORD(freecam)
                local camRot = CAM.GET_CAM_ROT(freecam, 2)

                local radZ = math.rad(camRot.z)
                local radX = math.rad(camRot.x)
                local forwardX = -math.sin(radZ) * math.cos(radX)
                local forwardY = math.cos(radZ) * math.cos(radX)
                local forwardZ = math.sin(radX)

                local endX = camCoord.x + forwardX * CONSTANTS.RAYCAST_MAX_DISTANCE
                local endY = camCoord.y + forwardY * CONSTANTS.RAYCAST_MAX_DISTANCE
                local endZ = camCoord.z + forwardZ * CONSTANTS.RAYCAST_MAX_DISTANCE

                Raycast.StartProbe(
                    camCoord.x, camCoord.y, camCoord.z,
                    endX, endY, endZ,
                    CONSTANTS.RAYCAST_FLAGS
                )
            end
        end

        return isTargeted, targetedEntity
    end

    return Raycast
end

return RaycastLib
