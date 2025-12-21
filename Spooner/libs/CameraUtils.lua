local CameraUtils = {}

function CameraUtils.New(CONSTANTS)
    local self = {}

    function self.GetBasis(cam)
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

    function self.ClampPitch(pitch)
        if pitch > CONSTANTS.PITCH_CLAMP_MAX then
            return CONSTANTS.PITCH_CLAMP_MAX
        elseif pitch < CONSTANTS.PITCH_CLAMP_MIN then
            return CONSTANTS.PITCH_CLAMP_MIN
        end
        return pitch
    end

    return self
end

return CameraUtils
