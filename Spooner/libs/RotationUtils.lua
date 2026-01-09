local RotationUtils = {}

function RotationUtils.New()
    local self = {}

    -- GTA5 uses ZXY Euler order: Yaw (Z) -> Pitch (X) -> Roll (Y)
    -- Convert Euler angles to 3x3 rotation matrix (ZXY order)
    function self.EulerToMatrix(pitch, roll, yaw)
        local cx, sx = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
        local cy, sy = math.cos(math.rad(roll)), math.sin(math.rad(roll))
        local cz, sz = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))

        -- R = Rz(yaw) * Rx(pitch) * Ry(roll)
        return {
            {cz*cy - sz*sx*sy,  -sz*cx,  cz*sy + sz*sx*cy},
            {sz*cy + cz*sx*sy,   cz*cx,  sz*sy - cz*sx*cy},
            {-cx*sy,             sx,     cx*cy}
        }
    end

    -- Convert 3x3 rotation matrix back to Euler angles (ZXY order)
    function self.MatrixToEuler(m)
        local pitch, roll, yaw
        local sx = m[3][2]

        if math.abs(sx) < 0.9999 then
            pitch = math.deg(math.asin(sx))
            roll = math.deg(math.atan(-m[3][1], m[3][3]))
            yaw = math.deg(math.atan(-m[1][2], m[2][2]))
        else
            -- Gimbal lock
            pitch = sx > 0 and 90 or -90
            roll = 0
            yaw = math.deg(math.atan(m[2][1], m[1][1]))
        end

        return pitch, roll, yaw
    end

    -- Create rotation matrix from axis-angle representation (Rodrigues' formula)
    function self.AxisAngleToMatrix(axis, angle)
        local rad = math.rad(angle)
        local c, s = math.cos(rad), math.sin(rad)
        local t = 1 - c
        local x, y, z = axis.x, axis.y, axis.z

        -- Normalize axis
        local len = math.sqrt(x*x + y*y + z*z)
        if len > 0.0001 then
            x, y, z = x/len, y/len, z/len
        end

        return {
            {t*x*x + c,    t*x*y - z*s, t*x*z + y*s},
            {t*x*y + z*s,  t*y*y + c,   t*y*z - x*s},
            {t*x*z - y*s,  t*y*z + x*s, t*z*z + c}
        }
    end

    -- Multiply two 3x3 matrices
    function self.MultiplyMatrices(a, b)
        local result = {{0,0,0}, {0,0,0}, {0,0,0}}
        for i = 1, 3 do
            for j = 1, 3 do
                for k = 1, 3 do
                    result[i][j] = result[i][j] + a[i][k] * b[k][j]
                end
            end
        end
        return result
    end

    -- Apply camera-relative rotation to current Euler angles
    -- axis: camera basis vector (fwd, right, or up)
    -- angle: rotation amount in degrees
    -- currentPitch, currentRoll, currentYaw: current entity rotation
    -- Returns: newPitch, newRoll, newYaw
    function self.ApplyCameraRelativeRotation(axis, angle, currentPitch, currentRoll, currentYaw)
        local currentMatrix = self.EulerToMatrix(currentPitch, currentRoll, currentYaw)
        local rotMatrix = self.AxisAngleToMatrix(axis, angle)
        local newMatrix = self.MultiplyMatrices(rotMatrix, currentMatrix)
        return self.MatrixToEuler(newMatrix)
    end

    return self
end

return RotationUtils
