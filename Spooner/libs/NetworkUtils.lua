local eMigrationType = {
    MIGRATE_PROXIMITY = 0x0,
    MIGRATE_OUT_OF_SCOPE = 0x1,
    MIGRATE_SCRIPT = 0x2,
    MIGRATE_FORCED = 0x3,
    MIGRATE_REASSIGNMENT = 0x4,
    MIGRATE_FROZEN_PED = 0x5,
    NUM_MIGRATION_TYPES = 0x6,
}

local NetworkUtils = {}

function NetworkUtils.New(CONSTANTS)
    local self = {}

    function self.IsEntityNetworked(entity)
        return NETWORK.NETWORK_GET_ENTITY_IS_NETWORKED(entity)
    end

    function self.GetNetworkIdOf(entity)
        return NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(entity)
    end

    -- Credits GuseXenvious (Probably sainan too)
    function self.set_can_migrate(entity, canMigrate)
        local Pointer = GTA.HandleToPointer(entity):GetAddress()
        if Pointer ~= 0 then
            Pointer = Memory.ReadLong(Pointer+0xD0)
            if Pointer ~= 0 then
                local Bits = Memory.ReadByte(Pointer+0x4E)
                if not canMigrate and Bits | 1 == 0 then
                    Bits = Bits + 1
                    Memory.WriteByte(Pointer+0x4E, Bits)
                elseif Bits | 1 == 1 then
                    Bits = Bits - 1
                    Memory.WriteByte(Pointer+0x4E, Bits)
                end
            end
        end
    end

    function self.SetEntityAsNetworked(entity, timeout)
        local time = Time.GetEpocheMs() + (timeout or CONSTANTS.NETWORK_TIMEOUT)
        while time > Time.GetEpocheMs() and not self.IsEntityNetworked(entity) do
            NETWORK.NETWORK_REGISTER_ENTITY_AS_NETWORKED(entity)
            Script.Yield(0)
        end
        return self.GetNetworkIdOf(entity)
    end

    function self.ConstantizeNetworkId(entity)
        local netId = self.SetEntityAsNetworked(entity, CONSTANTS.NETWORK_TIMEOUT_SHORT)
        NETWORK.SET_NETWORK_ID_EXISTS_ON_ALL_MACHINES(netId, true)
        NETWORK.SET_NETWORK_ID_ALWAYS_EXISTS_FOR_PLAYER(netId, PLAYER.PLAYER_ID(), true)
        return netId
    end

    -- Save ped task state before mission entity conversion
    function self.SavePedTaskState(ped)
        if not ENTITY.IS_ENTITY_A_PED(ped) then
            return nil
        end

        local state = {
            isWandering = TASK.GET_IS_TASK_ACTIVE(ped, 224),  -- TASK_WANDER
            isWalking = TASK.IS_PED_WALKING(ped),
            isRunning = TASK.IS_PED_RUNNING(ped),
            isSprinting = TASK.IS_PED_SPRINTING(ped),
            isStill = TASK.IS_PED_STILL(ped),
        }

        return state
    end

    -- Restore ped task after mission entity conversion
    function self.RestorePedTaskState(ped, state)
        if not state or not ENTITY.IS_ENTITY_A_PED(ped) then
            return
        end

        -- If ped was moving around, give them wander task
        if state.isWandering or state.isWalking or state.isRunning or state.isSprinting then
            TASK.TASK_WANDER_STANDARD(ped, 10.0, 10)
        end
        -- If they were standing still, mission entity default behavior is fine
    end

    function self.MakeEntityNetworked(entity)
        -- Skip network functions in singleplayer
        local netId = 0
        if NETWORK.NETWORK_IS_SESSION_STARTED() then
            netId = self.ConstantizeNetworkId(entity)
            -- NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netId, false) #Shitty native
            self.set_can_migrate(entity, false)
        end

        if not DECORATOR.DECOR_EXIST_ON(entity, "PV_Slot") then
            ENTITY.SET_ENTITY_AS_MISSION_ENTITY(entity, false, true)
        end

        return netId
    end

    -- Lighter version that just maintains network control without resetting ped tasks
    function self.MaintainNetworkControl(entity)
        -- Skip network functions in singleplayer
        if not NETWORK.NETWORK_IS_SESSION_STARTED() then
            return 0
        end

        if not NETWORK.NETWORK_GET_ENTITY_IS_NETWORKED(entity) then
            return self.MakeEntityNetworked(entity)
        end

        local netId = self.GetNetworkIdOf(entity)
        if not NETWORK.NETWORK_HAS_CONTROL_OF_NETWORK_ID(netId) then
            NETWORK.NETWORK_REQUEST_CONTROL_OF_NETWORK_ID(netId)
        end
        return netId
    end

    function self.MaintainNetworkControlV2(entity)
        -- Skip network functions in singleplayer
        if not NETWORK.NETWORK_IS_SESSION_STARTED() then
            return 0
        end

        local netId = self.GetNetworkIdOf(entity)
        local cPhysical = GTA.HandleToPointer(entity)
        if not cPhysical or not cPhysical.NetObject then return end
        local playerId = GTA.GetLocalPlayerId()
        if not playerId then return end
        local cNetGamePlayer = Players.GetById(playerId)
        if not cNetGamePlayer then return end
        NetworkObjectMgr.ChangeOwner(cPhysical.NetObject, cNetGamePlayer, eMigrationType.MIGRATE_FORCED)
        return netId
    end

    return self
end

return NetworkUtils
