local XMLParser = {}

function XMLParser.New()
    local self = {}

    function self.ParseAttributes(tag)
        local attrs = {}
        for name, value in string.gmatch(tag, '(%w+)="([^"]*)"') do
            attrs[name] = value
        end
        return attrs
    end

    function self.Parse(xmlString)
        -- Remove XML declaration and comments
        xmlString = xmlString:gsub("<%?[^?]*%?>", "")
        xmlString = xmlString:gsub("<!%-%-.-%-%->" , "")

        local result = {}
        local stack = {result}
        local current = result

        for closing, tagName, attrs, selfClosing in string.gmatch(xmlString, "<(/?)([%w_]+)(.-)%s*(/?)>") do
            if closing == "/" then
                table.remove(stack)
                current = stack[#stack]
            else
                local node = {
                    tag = tagName,
                    attributes = self.ParseAttributes(attrs),
                    children = {}
                }

                if not current.children then
                    current.children = {}
                end
                table.insert(current.children, node)

                if selfClosing ~= "/" then
                    table.insert(stack, node)
                    current = node
                end
            end
        end

        return result.children or {}
    end

    function self.EscapeAttribute(str)
        if type(str) ~= "string" then
            str = tostring(str)
        end
        str = str:gsub("&", "&amp;")
        str = str:gsub("<", "&lt;")
        str = str:gsub(">", "&gt;")
        str = str:gsub('"', "&quot;")
        str = str:gsub("'", "&apos;")
        return str
    end

    function self.GenerateXML(rootTag, options)
        local lines = {}
        table.insert(lines, '<?xml version="1.0" encoding="UTF-8"?>')
        table.insert(lines, '<' .. rootTag .. '>')

        for key, value in pairs(options) do
            local escapedValue = self.EscapeAttribute(value)
            table.insert(lines, '    <Option name="' .. key .. '" value="' .. escapedValue .. '" />')
        end

        table.insert(lines, '</' .. rootTag .. '>')
        return table.concat(lines, '\n')
    end

    function self.ParseConfig(xmlString)
        local config = {}
        local parsed = self.Parse(xmlString)

        for _, node in ipairs(parsed) do
            if node.tag == "SpoonerConfig" then
                for _, optionNode in ipairs(node.children or {}) do
                    if optionNode.tag == "Option" then
                        local name = optionNode.attributes.name
                        local value = optionNode.attributes.value
                        if name and value then
                            -- Convert string values to appropriate types
                            if value == "true" then
                                config[name] = true
                            elseif value == "false" then
                                config[name] = false
                            elseif tonumber(value) then
                                config[name] = tonumber(value)
                            else
                                config[name] = value
                            end
                        end
                    end
                end
            end
        end

        return config
    end

    -- ============================================================================
    -- Menyoo Spooner XML Format Generation
    -- ============================================================================

    function self.GenerateSpoonerXML(placements, referenceCoords)
        local lines = {}
        table.insert(lines, '<?xml version="1.0" encoding="ISO-8859-1"?>')
        table.insert(lines, '<SpoonerPlacements>')
        table.insert(lines, '\t<Note />')
        table.insert(lines, '\t<AudioFile volume="400" />')
        table.insert(lines, '\t<ClearDatabase>false</ClearDatabase>')
        table.insert(lines, '\t<ClearWorld>0</ClearWorld>')
        table.insert(lines, '\t<ClearMarkers>false</ClearMarkers>')
        table.insert(lines, '\t<IPLsToLoad load_mp_maps="false" load_sp_maps="false" />')
        table.insert(lines, '\t<IPLsToRemove />')
        table.insert(lines, '\t<InteriorsToEnable />')
        table.insert(lines, '\t<InteriorsToCap />')
        table.insert(lines, '\t<WeatherToSet></WeatherToSet>')
        table.insert(lines, '\t<TimecycleModifier strength="1"></TimecycleModifier>')
        table.insert(lines, '\t<StartTaskSequencesOnLoad>true</StartTaskSequencesOnLoad>')

        -- Reference coordinates
        if referenceCoords then
            table.insert(lines, '\t<ReferenceCoords>')
            table.insert(lines, '\t\t<X>' .. string.format("%.6f", referenceCoords.x) .. '</X>')
            table.insert(lines, '\t\t<Y>' .. string.format("%.6f", referenceCoords.y) .. '</Y>')
            table.insert(lines, '\t\t<Z>' .. string.format("%.6f", referenceCoords.z) .. '</Z>')
            table.insert(lines, '\t</ReferenceCoords>')
        else
            table.insert(lines, '\t<ReferenceCoords>')
            table.insert(lines, '\t\t<X>0</X>')
            table.insert(lines, '\t\t<Y>0</Y>')
            table.insert(lines, '\t\t<Z>0</Z>')
            table.insert(lines, '\t</ReferenceCoords>')
        end

        -- Add all placements
        for _, placement in ipairs(placements) do
            table.insert(lines, self.GeneratePlacementXML(placement))
        end

        table.insert(lines, '</SpoonerPlacements>')
        return table.concat(lines, '\n')
    end

    function self.GeneratePlacementXML(placement)
        local lines = {}
        table.insert(lines, '\t<Placement>')
        table.insert(lines, '\t\t<ModelHash>' .. placement.modelHash .. '</ModelHash>')
        table.insert(lines, '\t\t<Type>' .. placement.type .. '</Type>')
        table.insert(lines, '\t\t<Dynamic>' .. tostring(placement.dynamic or false) .. '</Dynamic>')
        table.insert(lines, '\t\t<FrozenPos>' .. tostring(placement.frozen or false) .. '</FrozenPos>')
        table.insert(lines, '\t\t<HashName>' .. self.EscapeAttribute(placement.hashName or "") .. '</HashName>')
        table.insert(lines, '\t\t<InitialHandle>' .. (placement.handle or 0) .. '</InitialHandle>')

        -- Vehicle properties if type is vehicle (2)
        if placement.type == 2 and placement.vehicleProperties then
            table.insert(lines, self.GenerateVehiclePropertiesXML(placement.vehicleProperties))
        end

        -- Ped properties if type is ped (1)
        if placement.type == 1 and placement.pedProperties then
            table.insert(lines, self.GeneratePedPropertiesXML(placement.pedProperties))
        end

        -- Common entity properties
        table.insert(lines, '\t\t<OpacityLevel>' .. (placement.opacity or 255) .. '</OpacityLevel>')
        table.insert(lines, '\t\t<LodDistance>' .. (placement.lodDistance or 16960) .. '</LodDistance>')
        table.insert(lines, '\t\t<IsVisible>' .. tostring(placement.isVisible ~= false) .. '</IsVisible>')
        table.insert(lines, '\t\t<MaxHealth>' .. (placement.maxHealth or 1000) .. '</MaxHealth>')
        table.insert(lines, '\t\t<Health>' .. (placement.health or 1000) .. '</Health>')
        table.insert(lines, '\t\t<HasGravity>' .. tostring(placement.hasGravity ~= false) .. '</HasGravity>')
        table.insert(lines, '\t\t<IsOnFire>' .. tostring(placement.isOnFire or false) .. '</IsOnFire>')
        table.insert(lines, '\t\t<IsInvincible>' .. tostring(placement.isInvincible or false) .. '</IsInvincible>')
        table.insert(lines, '\t\t<IsBulletProof>' .. tostring(placement.isBulletProof or false) .. '</IsBulletProof>')
        table.insert(lines, '\t\t<IsCollisionProof>' .. tostring(placement.isCollisionProof or false) .. '</IsCollisionProof>')
        table.insert(lines, '\t\t<IsExplosionProof>' .. tostring(placement.isExplosionProof or false) .. '</IsExplosionProof>')
        table.insert(lines, '\t\t<IsFireProof>' .. tostring(placement.isFireProof or false) .. '</IsFireProof>')
        table.insert(lines, '\t\t<IsMeleeProof>' .. tostring(placement.isMeleeProof or false) .. '</IsMeleeProof>')
        table.insert(lines, '\t\t<IsOnlyDamagedByPlayer>' .. tostring(placement.isOnlyDamagedByPlayer or false) .. '</IsOnlyDamagedByPlayer>')

        -- Position and rotation
        table.insert(lines, '\t\t<PositionRotation>')
        table.insert(lines, '\t\t\t<X>' .. string.format("%.6f", placement.position.x) .. '</X>')
        table.insert(lines, '\t\t\t<Y>' .. string.format("%.6f", placement.position.y) .. '</Y>')
        table.insert(lines, '\t\t\t<Z>' .. string.format("%.6f", placement.position.z) .. '</Z>')
        table.insert(lines, '\t\t\t<Pitch>' .. string.format("%.6f", placement.rotation.x) .. '</Pitch>')
        table.insert(lines, '\t\t\t<Roll>' .. string.format("%.6f", placement.rotation.y) .. '</Roll>')
        table.insert(lines, '\t\t\t<Yaw>' .. string.format("%.6f", placement.rotation.z) .. '</Yaw>')
        table.insert(lines, '\t\t</PositionRotation>')

        table.insert(lines, '\t\t<Attachment isAttached="false" />')
        table.insert(lines, '\t</Placement>')

        return table.concat(lines, '\n')
    end

    function self.GenerateVehiclePropertiesXML(props)
        local lines = {}
        table.insert(lines, '\t\t<VehicleProperties>')

        -- Colors
        table.insert(lines, '\t\t\t<Colours>')
        table.insert(lines, '\t\t\t\t<Primary>' .. (props.primaryColor or 0) .. '</Primary>')
        table.insert(lines, '\t\t\t\t<Secondary>' .. (props.secondaryColor or 0) .. '</Secondary>')
        table.insert(lines, '\t\t\t\t<Pearl>' .. (props.pearlColor or 0) .. '</Pearl>')
        table.insert(lines, '\t\t\t\t<Rim>' .. (props.rimColor or 0) .. '</Rim>')
        table.insert(lines, '\t\t\t\t<Mod1_a>' .. (props.mod1a or 0) .. '</Mod1_a>')
        table.insert(lines, '\t\t\t\t<Mod1_b>' .. (props.mod1b or -1) .. '</Mod1_b>')
        table.insert(lines, '\t\t\t\t<Mod1_c>' .. (props.mod1c or -1) .. '</Mod1_c>')
        table.insert(lines, '\t\t\t\t<Mod2_a>' .. (props.mod2a or 0) .. '</Mod2_a>')
        table.insert(lines, '\t\t\t\t<Mod2_b>' .. (props.mod2b or -1) .. '</Mod2_b>')
        table.insert(lines, '\t\t\t\t<IsPrimaryColourCustom>' .. tostring(props.isPrimaryCustom or false) .. '</IsPrimaryColourCustom>')
        table.insert(lines, '\t\t\t\t<IsSecondaryColourCustom>' .. tostring(props.isSecondaryCustom or false) .. '</IsSecondaryColourCustom>')
        table.insert(lines, '\t\t\t\t<tyreSmoke_R>' .. (props.tyreSmokeR or 255) .. '</tyreSmoke_R>')
        table.insert(lines, '\t\t\t\t<tyreSmoke_G>' .. (props.tyreSmokeG or 255) .. '</tyreSmoke_G>')
        table.insert(lines, '\t\t\t\t<tyreSmoke_B>' .. (props.tyreSmokeB or 255) .. '</tyreSmoke_B>')
        table.insert(lines, '\t\t\t\t<LrInterior>' .. (props.interiorColor or 0) .. '</LrInterior>')
        table.insert(lines, '\t\t\t\t<LrDashboard>' .. (props.dashboardColor or 0) .. '</LrDashboard>')
        table.insert(lines, '\t\t\t\t<LrXenonHeadlights>' .. (props.xenonColor or 255) .. '</LrXenonHeadlights>')
        table.insert(lines, '\t\t\t</Colours>')

        table.insert(lines, '\t\t\t<Livery>' .. (props.livery or -1) .. '</Livery>')
        table.insert(lines, '\t\t\t<NumberPlateText>' .. self.EscapeAttribute(props.plateText or "") .. '</NumberPlateText>')
        table.insert(lines, '\t\t\t<NumberPlateIndex>' .. (props.plateIndex or 0) .. '</NumberPlateIndex>')
        table.insert(lines, '\t\t\t<WheelType>' .. (props.wheelType or 0) .. '</WheelType>')
        table.insert(lines, '\t\t\t<WheelsInvisible>' .. tostring(props.wheelsInvisible or false) .. '</WheelsInvisible>')
        table.insert(lines, '\t\t\t<EngineSoundName>' .. self.EscapeAttribute(props.engineSound or "") .. '</EngineSoundName>')
        table.insert(lines, '\t\t\t<WindowTint>' .. (props.windowTint or 0) .. '</WindowTint>')
        table.insert(lines, '\t\t\t<BulletProofTyres>' .. tostring(props.bulletProofTyres or false) .. '</BulletProofTyres>')
        table.insert(lines, '\t\t\t<DirtLevel>' .. (props.dirtLevel or 0) .. '</DirtLevel>')
        table.insert(lines, '\t\t\t<PaintFade>' .. string.format("%.6f", props.paintFade or 0) .. '</PaintFade>')
        table.insert(lines, '\t\t\t<RoofState>' .. (props.roofState or 0) .. '</RoofState>')
        table.insert(lines, '\t\t\t<SirenActive>' .. tostring(props.sirenActive or false) .. '</SirenActive>')
        table.insert(lines, '\t\t\t<EngineOn>' .. tostring(props.engineOn or false) .. '</EngineOn>')
        table.insert(lines, '\t\t\t<EngineHealth>' .. (props.engineHealth or 1000) .. '</EngineHealth>')
        table.insert(lines, '\t\t\t<LightsOn>' .. tostring(props.lightsOn or false) .. '</LightsOn>')
        table.insert(lines, '\t\t\t<IsRadioLoud>' .. (props.isRadioLoud or 0) .. '</IsRadioLoud>')
        table.insert(lines, '\t\t\t<LockStatus>' .. (props.lockStatus or 1) .. '</LockStatus>')

        -- Neons
        table.insert(lines, '\t\t\t<Neons>')
        table.insert(lines, '\t\t\t\t<Left>' .. tostring(props.neonLeft or false) .. '</Left>')
        table.insert(lines, '\t\t\t\t<Right>' .. tostring(props.neonRight or false) .. '</Right>')
        table.insert(lines, '\t\t\t\t<Front>' .. tostring(props.neonFront or false) .. '</Front>')
        table.insert(lines, '\t\t\t\t<Back>' .. tostring(props.neonBack or false) .. '</Back>')
        table.insert(lines, '\t\t\t\t<R>' .. (props.neonR or 255) .. '</R>')
        table.insert(lines, '\t\t\t\t<G>' .. (props.neonG or 0) .. '</G>')
        table.insert(lines, '\t\t\t\t<B>' .. (props.neonB or 255) .. '</B>')
        table.insert(lines, '\t\t\t</Neons>')

        -- Doors Open
        table.insert(lines, '\t\t\t<DoorsOpen>')
        table.insert(lines, '\t\t\t\t<BackLeftDoor>false</BackLeftDoor>')
        table.insert(lines, '\t\t\t\t<BackRightDoor>false</BackRightDoor>')
        table.insert(lines, '\t\t\t\t<FrontLeftDoor>false</FrontLeftDoor>')
        table.insert(lines, '\t\t\t\t<FrontRightDoor>false</FrontRightDoor>')
        table.insert(lines, '\t\t\t\t<Hood>false</Hood>')
        table.insert(lines, '\t\t\t\t<Trunk>false</Trunk>')
        table.insert(lines, '\t\t\t\t<Trunk2>false</Trunk2>')
        table.insert(lines, '\t\t\t</DoorsOpen>')

        -- Doors Broken
        table.insert(lines, '\t\t\t<DoorsBroken>')
        table.insert(lines, '\t\t\t\t<BackLeftDoor>false</BackLeftDoor>')
        table.insert(lines, '\t\t\t\t<BackRightDoor>false</BackRightDoor>')
        table.insert(lines, '\t\t\t\t<FrontLeftDoor>false</FrontLeftDoor>')
        table.insert(lines, '\t\t\t\t<FrontRightDoor>false</FrontRightDoor>')
        table.insert(lines, '\t\t\t\t<Hood>false</Hood>')
        table.insert(lines, '\t\t\t\t<Trunk>false</Trunk>')
        table.insert(lines, '\t\t\t\t<Trunk2>false</Trunk2>')
        table.insert(lines, '\t\t\t</DoorsBroken>')

        -- Tyres Bursted
        table.insert(lines, '\t\t\t<TyresBursted>')
        table.insert(lines, '\t\t\t\t<FrontLeft>false</FrontLeft>')
        table.insert(lines, '\t\t\t\t<FrontRight>false</FrontRight>')
        table.insert(lines, '\t\t\t\t<_2>false</_2>')
        table.insert(lines, '\t\t\t\t<_3>false</_3>')
        table.insert(lines, '\t\t\t\t<BackLeft>false</BackLeft>')
        table.insert(lines, '\t\t\t\t<BackRight>false</BackRight>')
        table.insert(lines, '\t\t\t\t<_6>false</_6>')
        table.insert(lines, '\t\t\t\t<_7>false</_7>')
        table.insert(lines, '\t\t\t\t<_8>false</_8>')
        table.insert(lines, '\t\t\t</TyresBursted>')

        -- Mod Extras
        table.insert(lines, '\t\t\t<ModExtras>')
        for i = 1, 12 do
            if i ~= 9 and i ~= 10 then
                local value = props.extras and props.extras[i] or true
                table.insert(lines, '\t\t\t\t<_' .. i .. '>' .. tostring(value) .. '</_' .. i .. '>')
            end
        end
        table.insert(lines, '\t\t\t</ModExtras>')

        -- Mods
        table.insert(lines, '\t\t\t<Mods>')
        for i = 0, 48 do
            if i >= 17 and i <= 22 then
                -- Toggle mods (bool)
                local value = props.mods and props.mods[i] or false
                table.insert(lines, '\t\t\t\t<_' .. i .. '>' .. tostring(value) .. '</_' .. i .. '>')
            else
                -- Regular mods (value,variation)
                local modValue = props.mods and props.mods[i] or -1
                local modVariation = props.modVariations and props.modVariations[i] or 0
                table.insert(lines, '\t\t\t\t<_' .. i .. '>' .. modValue .. ',' .. modVariation .. '</_' .. i .. '>')
            end
        end
        table.insert(lines, '\t\t\t</Mods>')

        table.insert(lines, '\t\t</VehicleProperties>')
        return table.concat(lines, '\n')
    end

    function self.GeneratePedPropertiesXML(props)
        local lines = {}
        table.insert(lines, '\t\t<PedProperties>')
        table.insert(lines, '\t\t\t<CanRagdoll>' .. tostring(props.canRagdoll ~= false) .. '</CanRagdoll>')
        table.insert(lines, '\t\t\t<Armour>' .. (props.armour or 0) .. '</Armour>')
        table.insert(lines, '\t\t\t<CurrentWeapon>' .. (props.currentWeapon or "0xA2719263") .. '</CurrentWeapon>')
        table.insert(lines, '\t\t</PedProperties>')
        return table.concat(lines, '\n')
    end

    -- ============================================================================
    -- Menyoo Spooner XML Format Parsing (Loading)
    -- ============================================================================

    -- Helper to get text content between tags
    function self.GetTagContent(xmlString, tagName)
        local pattern = "<" .. tagName .. "[^>]*>([^<]*)</" .. tagName .. ">"
        return xmlString:match(pattern)
    end

    -- Helper to parse a boolean string
    function self.ParseBool(str)
        if str == nil then return false end
        return str:lower() == "true"
    end

    -- Helper to parse a number (supports hex format 0x...)
    function self.ParseNumber(str)
        if str == nil then return 0 end
        str = str:match("^%s*(.-)%s*$") -- trim
        if str:sub(1, 2) == "0x" or str:sub(1, 2) == "0X" then
            -- Remove 0x prefix and parse as hex
            local hexStr = str:sub(3)
            return tonumber(hexStr, 16) or 0
        end
        return tonumber(str) or 0
    end

    -- Parse a single Placement block
    function self.ParsePlacement(placementXml)
        local placement = {}

        placement.modelHash = self.GetTagContent(placementXml, "ModelHash") or "0"
        placement.type = self.ParseNumber(self.GetTagContent(placementXml, "Type"))
        placement.dynamic = self.ParseBool(self.GetTagContent(placementXml, "Dynamic"))
        placement.frozen = self.ParseBool(self.GetTagContent(placementXml, "FrozenPos"))
        placement.hashName = self.GetTagContent(placementXml, "HashName") or ""
        placement.opacity = self.ParseNumber(self.GetTagContent(placementXml, "OpacityLevel"))
        placement.health = self.ParseNumber(self.GetTagContent(placementXml, "Health"))
        placement.maxHealth = self.ParseNumber(self.GetTagContent(placementXml, "MaxHealth"))
        placement.isInvincible = self.ParseBool(self.GetTagContent(placementXml, "IsInvincible"))
        placement.hasGravity = self.ParseBool(self.GetTagContent(placementXml, "HasGravity"))

        -- Parse PositionRotation
        local posRotBlock = placementXml:match("<PositionRotation>(.-)</PositionRotation>")
        if posRotBlock then
            placement.position = {
                x = tonumber(self.GetTagContent(posRotBlock, "X")) or 0,
                y = tonumber(self.GetTagContent(posRotBlock, "Y")) or 0,
                z = tonumber(self.GetTagContent(posRotBlock, "Z")) or 0
            }
            placement.rotation = {
                x = tonumber(self.GetTagContent(posRotBlock, "Pitch")) or 0,
                y = tonumber(self.GetTagContent(posRotBlock, "Roll")) or 0,
                z = tonumber(self.GetTagContent(posRotBlock, "Yaw")) or 0
            }
        else
            placement.position = {x = 0, y = 0, z = 0}
            placement.rotation = {x = 0, y = 0, z = 0}
        end

        -- Parse VehicleProperties if present
        local vehPropsBlock = placementXml:match("<VehicleProperties>(.-)</VehicleProperties>")
        if vehPropsBlock then
            placement.vehicleProperties = self.ParseVehicleProperties(vehPropsBlock)
        end

        -- Parse PedProperties if present
        local pedPropsBlock = placementXml:match("<PedProperties>(.-)</PedProperties>")
        if pedPropsBlock then
            placement.pedProperties = self.ParsePedProperties(pedPropsBlock)
        end

        return placement
    end

    -- Parse VehicleProperties block
    function self.ParseVehicleProperties(vehXml)
        local props = {}

        -- Parse Colours block
        local coloursBlock = vehXml:match("<Colours>(.-)</Colours>")
        if coloursBlock then
            props.primaryColor = self.ParseNumber(self.GetTagContent(coloursBlock, "Primary"))
            props.secondaryColor = self.ParseNumber(self.GetTagContent(coloursBlock, "Secondary"))
            props.pearlColor = self.ParseNumber(self.GetTagContent(coloursBlock, "Pearl"))
            props.rimColor = self.ParseNumber(self.GetTagContent(coloursBlock, "Rim"))
            props.mod1a = self.ParseNumber(self.GetTagContent(coloursBlock, "Mod1_a"))
            props.mod1b = self.ParseNumber(self.GetTagContent(coloursBlock, "Mod1_b"))
            props.mod1c = self.ParseNumber(self.GetTagContent(coloursBlock, "Mod1_c"))
            props.mod2a = self.ParseNumber(self.GetTagContent(coloursBlock, "Mod2_a"))
            props.mod2b = self.ParseNumber(self.GetTagContent(coloursBlock, "Mod2_b"))
            props.tyreSmokeR = self.ParseNumber(self.GetTagContent(coloursBlock, "tyreSmoke_R"))
            props.tyreSmokeG = self.ParseNumber(self.GetTagContent(coloursBlock, "tyreSmoke_G"))
            props.tyreSmokeB = self.ParseNumber(self.GetTagContent(coloursBlock, "tyreSmoke_B"))
        end

        props.livery = self.ParseNumber(self.GetTagContent(vehXml, "Livery"))
        props.plateText = self.GetTagContent(vehXml, "NumberPlateText") or ""
        props.plateIndex = self.ParseNumber(self.GetTagContent(vehXml, "NumberPlateIndex"))
        props.wheelType = self.ParseNumber(self.GetTagContent(vehXml, "WheelType"))
        props.windowTint = self.ParseNumber(self.GetTagContent(vehXml, "WindowTint"))
        props.bulletProofTyres = self.ParseBool(self.GetTagContent(vehXml, "BulletProofTyres"))
        props.engineHealth = self.ParseNumber(self.GetTagContent(vehXml, "EngineHealth"))

        -- Parse Neons
        local neonsBlock = vehXml:match("<Neons>(.-)</Neons>")
        if neonsBlock then
            props.neonLeft = self.ParseBool(self.GetTagContent(neonsBlock, "Left"))
            props.neonRight = self.ParseBool(self.GetTagContent(neonsBlock, "Right"))
            props.neonFront = self.ParseBool(self.GetTagContent(neonsBlock, "Front"))
            props.neonBack = self.ParseBool(self.GetTagContent(neonsBlock, "Back"))
            props.neonR = self.ParseNumber(self.GetTagContent(neonsBlock, "R"))
            props.neonG = self.ParseNumber(self.GetTagContent(neonsBlock, "G"))
            props.neonB = self.ParseNumber(self.GetTagContent(neonsBlock, "B"))
        end

        -- Parse Mods
        local modsBlock = vehXml:match("<Mods>(.-)</Mods>")
        if modsBlock then
            props.mods = {}
            props.modVariations = {}
            for i = 0, 48 do
                local modValue = self.GetTagContent(modsBlock, "_" .. i)
                if modValue then
                    if i >= 17 and i <= 22 then
                        -- Toggle mods (bool)
                        props.mods[i] = self.ParseBool(modValue)
                    else
                        -- Regular mods (value,variation)
                        local val, var = modValue:match("([^,]+),([^,]+)")
                        props.mods[i] = tonumber(val) or -1
                        props.modVariations[i] = tonumber(var) or 0
                    end
                end
            end
        end

        return props
    end

    -- Parse PedProperties block
    function self.ParsePedProperties(pedXml)
        local props = {}
        props.canRagdoll = self.ParseBool(self.GetTagContent(pedXml, "CanRagdoll"))
        props.armour = self.ParseNumber(self.GetTagContent(pedXml, "Armour"))
        props.currentWeapon = self.GetTagContent(pedXml, "CurrentWeapon") or "0xA2719263"
        return props
    end

    -- Parse full SpoonerPlacements XML file
    function self.ParseSpoonerXML(xmlString)
        local result = {
            placements = {},
            referenceCoords = nil
        }

        -- Parse reference coordinates
        local refCoordsBlock = xmlString:match("<ReferenceCoords>(.-)</ReferenceCoords>")
        if refCoordsBlock then
            result.referenceCoords = {
                x = tonumber(self.GetTagContent(refCoordsBlock, "X")) or 0,
                y = tonumber(self.GetTagContent(refCoordsBlock, "Y")) or 0,
                z = tonumber(self.GetTagContent(refCoordsBlock, "Z")) or 0
            }
        end

        -- Parse all Placement blocks
        for placementXml in xmlString:gmatch("<Placement>(.-)</Placement>") do
            local placement = self.ParsePlacement(placementXml)
            table.insert(result.placements, placement)
        end

        return result
    end

    return self
end

return XMLParser
