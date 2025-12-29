local KeybindsLib = {}

function KeybindsLib.New(PAD)
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

    -- Controls that should remain enabled while in Spooner mode (passthrough to game)
    -- These allow game features like pause menu and expanded map to work
    Keybinds.PassthroughControls = {
        199,  -- Pause Menu (P)
        200,  -- Pause Menu alternate (Escape)
        20,   -- Big Map (Z key)
    }

    function Keybinds.EnablePassthroughControls()
        for _, control in ipairs(Keybinds.PassthroughControls) do
            PAD.ENABLE_CONTROL_ACTION(0, control, true)
        end
    end

    function Keybinds.SetupDefaultBinds()
        return {
            Grab = Keybinds.CreateKeybind(24, Keybinds.IsPressed),
            AddOrRemoveFromList = Keybinds.CreateKeybind(73, Keybinds.IsJustPressed),
            MoveFaster = Keybinds.CreateKeybind(21, Keybinds.IsPressed),
            RotateLeft = Keybinds.CreateKeybind(44, Keybinds.IsPressed),
            RotateRight = Keybinds.CreateKeybind(38, Keybinds.IsPressed),
            PitchUp = Keybinds.CreateKeybind(172, Keybinds.IsPressed),    -- Arrow Up
            PitchDown = Keybinds.CreateKeybind(173, Keybinds.IsPressed),  -- Arrow Down
            RollLeft = Keybinds.CreateKeybind(174, Keybinds.IsPressed),   -- Arrow Left
            RollRight = Keybinds.CreateKeybind(175, Keybinds.IsPressed),  -- Arrow Right
            PushEntity = Keybinds.CreateKeybind(14, Keybinds.IsPressed),
            PullEntity = Keybinds.CreateKeybind(15, Keybinds.IsPressed),
            MoveUp = Keybinds.CreateKeybind(22, Keybinds.GetControlNormal),
            MoveDown = Keybinds.CreateKeybind(36, Keybinds.GetControlNormal),
            MoveForward = Keybinds.CreateKeybind(32, Keybinds.GetControlNormal),
            MoveBackward = Keybinds.CreateKeybind(33, Keybinds.GetControlNormal),
            MoveLeft = Keybinds.CreateKeybind(34, Keybinds.GetControlNormal),
            MoveRight = Keybinds.CreateKeybind(35, Keybinds.GetControlNormal),
            ConfirmSpawn = Keybinds.CreateKeybind(201, Keybinds.IsJustPressed),  -- Enter key
            CancelSpawn = Keybinds.CreateKeybind(202, Keybinds.IsJustPressed),   -- Backspace key
            SelectForEdit = Keybinds.CreateKeybind(25, Keybinds.IsJustPressed),  -- Right mouse button (select entity for editing)
        }
    end

    return Keybinds
end

return KeybindsLib
