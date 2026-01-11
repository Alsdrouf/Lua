local KeybindsLib = {}

function KeybindsLib.New(PAD)
    local self = {}

    function self.GetAsString(key)
        return PAD.GET_CONTROL_INSTRUCTIONAL_BUTTONS_STRING(0, key, true)
    end

    function self.CreateKeybind(key, func)
        return {
            key = key,
            string = self.GetAsString(key),
            IsPressed = function()
                return func(key)
            end
        }
    end

    function self.IsPressed(key)
        return PAD.IS_DISABLED_CONTROL_PRESSED(0, key)
    end

    function self.IsJustPressed(key)
        return PAD.IS_DISABLED_CONTROL_JUST_PRESSED(0, key)
    end

    function self.GetControlNormal(key)
        return PAD.GET_DISABLED_CONTROL_NORMAL(0, key)
    end

    -- Controls that should remain enabled while in Spooner mode (passthrough to game)
    -- These allow game features like pause menu and expanded map to work
    self.PassthroughControls = {
        199,  -- Pause Menu (P)
        200,  -- Pause Menu alternate (Escape)
        20,   -- Big Map (Z key)
    }

    function self.EnablePassthroughControls()
        for _, control in ipairs(self.PassthroughControls) do
            PAD.ENABLE_CONTROL_ACTION(0, control, true)
        end
    end

    function self.SetupDefaultBinds()
        return {
            Grab = self.CreateKeybind(24, self.IsPressed),
            AddOrRemoveFromList = self.CreateKeybind(73, self.IsJustPressed),
            MoveFaster = self.CreateKeybind(21, self.IsPressed),
            RotateLeft = self.CreateKeybind(44, self.IsPressed),
            RotateRight = self.CreateKeybind(38, self.IsPressed),
            PitchUp = self.CreateKeybind(172, self.IsPressed),    -- Arrow Up
            PitchDown = self.CreateKeybind(173, self.IsPressed),  -- Arrow Down
            RollLeft = self.CreateKeybind(174, self.IsPressed),   -- Arrow Left
            RollRight = self.CreateKeybind(175, self.IsPressed),  -- Arrow Right
            PushEntity = self.CreateKeybind(14, self.IsPressed),
            PullEntity = self.CreateKeybind(15, self.IsPressed),
            MoveUp = self.CreateKeybind(22, self.GetControlNormal),
            MoveDown = self.CreateKeybind(36, self.GetControlNormal),
            MoveForward = self.CreateKeybind(32, self.GetControlNormal),
            MoveBackward = self.CreateKeybind(33, self.GetControlNormal),
            MoveLeft = self.CreateKeybind(34, self.GetControlNormal),
            MoveRight = self.CreateKeybind(35, self.GetControlNormal),
            ConfirmSpawn = self.CreateKeybind(201, self.IsJustPressed),  -- Enter key
            CancelSpawn = self.CreateKeybind(202, self.IsJustPressed),   -- Backspace key
            SelectForEdit = self.CreateKeybind(25, self.IsJustPressed),  -- Right mouse button (select entity for editing)
            ResetRotation = self.CreateKeybind(45, self.IsJustPressed),  -- R key (reset pitch and roll to 0)
            DeleteEntity = self.CreateKeybind(178, self.IsJustPressed),  -- Delete key (delete targeted entity)
        }
    end

    return self
end

return KeybindsLib
