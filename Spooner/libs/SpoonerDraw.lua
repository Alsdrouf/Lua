local SpoonerDraw = {}

function SpoonerDraw.New(deps)
    local Spooner = deps.Spooner
    local CONSTANTS = deps.CONSTANTS
    local Raycast = deps.Raycast
    local Keybinds = deps.Keybinds
    local EntityLists = deps.EntityLists

    local self = {}

    function self.PerformRaycastCheck()
        if Spooner.isGrabbing then return end

        local isTargeted, targetedEntity = Raycast.PerformCheckForFreecam(
            Spooner.freecam
        )

        if isTargeted and not Spooner.IsEntityRestricted(targetedEntity) then
            Spooner.isEntityTargeted = true
            Spooner.targetedEntity = targetedEntity
        elseif Raycast.data == nil then
            Spooner.isEntityTargeted = false
            Spooner.targetedEntity = nil
        end
    end

    function self.DrawCrosshair()
        if not Spooner.inSpoonerMode then
            return
        end

        if not Spooner.previewModelHash then
            self.PerformRaycastCheck()
        end

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

    function self.AddInstructionalButton(buttonIndex, keyString, label)
        GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(keyString)
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(label)
        GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
    end

    function self.AddInstructionalButtonMulti(buttonIndex, keyStrings, label)
        GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(Spooner.scaleform, "SET_DATA_SLOT")
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(buttonIndex)
        for _, keyString in ipairs(keyStrings) do
            GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(keyString)
        end
        GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING(label)
        GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
    end

    function self.DrawInstructionalButtons()
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

        if Spooner.previewModelHash then
            self.AddInstructionalButton(buttonIndex, Keybinds.ConfirmSpawn.string, "Spawn Entity")
            buttonIndex = buttonIndex + 1

            self.AddInstructionalButton(buttonIndex, Keybinds.CancelSpawn.string, "Cancel")
            buttonIndex = buttonIndex + 1
        end

        if not Spooner.previewEntity then
            local grabLabel = Spooner.isGrabbing and "Release Entity" or "Grab Entity"
            self.AddInstructionalButton(buttonIndex, Keybinds.Grab.string, grabLabel)
            buttonIndex = buttonIndex + 1
        end

        if Spooner.isGrabbing or Spooner.previewEntity then
            self.AddInstructionalButtonMulti(
                buttonIndex,
                {Keybinds.RotateLeft.string, Keybinds.RotateRight.string},
                "Yaw"
            )
            buttonIndex = buttonIndex + 1

            self.AddInstructionalButtonMulti(
                buttonIndex,
                {Keybinds.PitchUp.string, Keybinds.PitchDown.string},
                "Pitch"
            )
            buttonIndex = buttonIndex + 1

            self.AddInstructionalButtonMulti(
                buttonIndex,
                {Keybinds.RollLeft.string, Keybinds.RollRight.string},
                "Roll"
            )
            buttonIndex = buttonIndex + 1

            self.AddInstructionalButtonMulti(
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
            for _, managed in ipairs(Spooner.managedEntities) do
                if managed.entity == entityToCheck then
                    isManaged = true
                    break
                end
            end

            local listLabel = isManaged and "Remove from List" or "Add to List"
            self.AddInstructionalButton(buttonIndex, Keybinds.AddOrRemoveFromList.string, listLabel)
            buttonIndex = buttonIndex + 1

            self.AddInstructionalButton(buttonIndex, Keybinds.SelectForEdit.string, "Quick Edit")
            buttonIndex = buttonIndex + 1
        end

        self.AddInstructionalButton(buttonIndex, Keybinds.MoveFaster.string, "Move Faster")
        buttonIndex = buttonIndex + 1

        self.AddInstructionalButtonMulti(
            buttonIndex,
            {Keybinds.MoveUp.string, Keybinds.MoveDown.string},
            "Up / Down"
        )
        buttonIndex = buttonIndex + 1

        self.AddInstructionalButtonMulti(
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

    ---@param entity integer
    ---@param networkId? integer
    ---@param networked? boolean
    ---@return string
    function self.GetEntityName(entity, networkId, networked)
        if not ENTITY.DOES_ENTITY_EXIST(entity) then
            return "Invalid Entity"
        end

        local modelHash = ENTITY.GET_ENTITY_MODEL(entity)
        local baseName

        if ENTITY.IS_ENTITY_A_VEHICLE(entity) then
            local displayName = GTA.GetDisplayNameFromHash(modelHash)
            local plate = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(entity)
            if displayName and displayName ~= "" and displayName ~= "NULL" then
                baseName = displayName .. " [" .. plate .. "]"
            else
                baseName = GTA.GetModelNameFromHash(modelHash) .. " [" .. plate .. "]"
            end
        else
            local cachedName = EntityLists.NameCache[modelHash]
            if cachedName then
                baseName = cachedName
            else
                baseName = GTA.GetModelNameFromHash(modelHash)
            end
        end

        if networkId and networkId ~= 0 then
            baseName = baseName .. " (" .. tostring(networkId) .. ")"
        end

        if networked ~= nil then
            baseName = baseName .. (networked and " [N]" or " [L]")
        end

        return baseName
    end

    function self.Draw3DBox(entity)
        if not ENTITY.DOES_ENTITY_EXIST(entity) then
            return
        end

        local minX, minY, minZ, maxX, maxY, maxZ = Spooner.GetEntityDimensions(entity, "3DBox")

        local corners = {
            {minX, minY, minZ},
            {maxX, minY, minZ},
            {maxX, maxY, minZ},
            {minX, maxY, minZ},
            {minX, minY, maxZ},
            {maxX, minY, maxZ},
            {maxX, maxY, maxZ},
            {minX, maxY, maxZ}
        }

        local worldCorners = {}
        for _, corner in ipairs(corners) do
            local worldPos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(entity, corner[1], corner[2], corner[3])
            table.insert(worldCorners, worldPos)
        end

        -- Bottom edges (RED)
        GRAPHICS.DRAW_LINE(worldCorners[1].x, worldCorners[1].y, worldCorners[1].z,
                           worldCorners[2].x, worldCorners[2].y, worldCorners[2].z, 255, 0, 0, 255)
        GRAPHICS.DRAW_LINE(worldCorners[2].x, worldCorners[2].y, worldCorners[2].z,
                           worldCorners[3].x, worldCorners[3].y, worldCorners[3].z, 255, 0, 0, 255)
        GRAPHICS.DRAW_LINE(worldCorners[3].x, worldCorners[3].y, worldCorners[3].z,
                           worldCorners[4].x, worldCorners[4].y, worldCorners[4].z, 255, 0, 0, 255)
        GRAPHICS.DRAW_LINE(worldCorners[4].x, worldCorners[4].y, worldCorners[4].z,
                           worldCorners[1].x, worldCorners[1].y, worldCorners[1].z, 255, 0, 0, 255)

        -- Top edges (BLUE)
        GRAPHICS.DRAW_LINE(worldCorners[5].x, worldCorners[5].y, worldCorners[5].z,
                           worldCorners[6].x, worldCorners[6].y, worldCorners[6].z, 0, 0, 255, 255)
        GRAPHICS.DRAW_LINE(worldCorners[6].x, worldCorners[6].y, worldCorners[6].z,
                           worldCorners[7].x, worldCorners[7].y, worldCorners[7].z, 0, 0, 255, 255)
        GRAPHICS.DRAW_LINE(worldCorners[7].x, worldCorners[7].y, worldCorners[7].z,
                           worldCorners[8].x, worldCorners[8].y, worldCorners[8].z, 0, 0, 255, 255)
        GRAPHICS.DRAW_LINE(worldCorners[8].x, worldCorners[8].y, worldCorners[8].z,
                           worldCorners[5].x, worldCorners[5].y, worldCorners[5].z, 0, 0, 255, 255)

        -- Vertical edges (GREEN)
        GRAPHICS.DRAW_LINE(worldCorners[1].x, worldCorners[1].y, worldCorners[1].z,
                           worldCorners[5].x, worldCorners[5].y, worldCorners[5].z, 0, 255, 0, 255)
        GRAPHICS.DRAW_LINE(worldCorners[2].x, worldCorners[2].y, worldCorners[2].z,
                           worldCorners[6].x, worldCorners[6].y, worldCorners[6].z, 0, 255, 0, 255)
        GRAPHICS.DRAW_LINE(worldCorners[3].x, worldCorners[3].y, worldCorners[3].z,
                           worldCorners[7].x, worldCorners[7].y, worldCorners[7].z, 0, 255, 0, 255)
        GRAPHICS.DRAW_LINE(worldCorners[4].x, worldCorners[4].y, worldCorners[4].z,
                           worldCorners[8].x, worldCorners[8].y, worldCorners[8].z, 0, 255, 0, 255)
    end

    function self.DrawTargetedEntityBox()
        if not Spooner.inSpoonerMode then
            return
        end

        if Spooner.previewModelHash then
            if Spooner.previewEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.previewEntity) then
                self.Draw3DBox(Spooner.previewEntity)
            end
            return
        end

        if Spooner.isEntityTargeted and Spooner.targetedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.targetedEntity) then
            self.Draw3DBox(Spooner.targetedEntity)
        end

        if Spooner.isGrabbing and Spooner.grabbedEntity and ENTITY.DOES_ENTITY_EXIST(Spooner.grabbedEntity) then
            self.Draw3DBox(Spooner.grabbedEntity)
        end
    end

    function self.DrawSelectedEntityMarker()
        if not Spooner.inSpoonerMode then
            return
        end

        local entity = Spooner.GetEditingEntity()

        if entity and ENTITY.DOES_ENTITY_EXIST(entity) then
            local pos = ENTITY.GET_ENTITY_COORDS(entity, true)
            local minX, minY, minZ, maxX, maxY, maxZ = Spooner.GetEntityDimensions(entity, "SelectedMarker")

            GRAPHICS.DRAW_MARKER(
                0,
                pos.x, pos.y, pos.z + maxZ + 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                1.0, 1.0, 1.5,
                255, 0, 0, 150,
                false, false, 2, false, nil, nil, false
            )
        end
    end

    return self
end

return SpoonerDraw
