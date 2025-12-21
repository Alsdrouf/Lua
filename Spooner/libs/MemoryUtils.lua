local MemoryUtils = {}

function MemoryUtils.New()
    local self = {}
    self.cache = {}  -- { [key] = ptr }

    -- Allocate memory with a key, returns cached ptr if already exists
    function self.Alloc(key, size)
        if self.cache[key] then
            return self.cache[key]
        end
        local ptr = Memory.Alloc(size)
        self.cache[key] = ptr
        return ptr
    end

    -- Allocate int with a key, returns cached ptr if already exists
    function self.AllocInt(key)
        if self.cache[key] then
            return self.cache[key]
        end
        local ptr = Memory.AllocInt()
        self.cache[key] = ptr
        return ptr
    end

    -- Alocate V3 with a key, returns cached ptr if already exists
    function self.AllocV3(key)
        if self.cache[key] then
            return self.cache[key]
        end
        local ptr = Memory.Alloc(24)
        self.cache[key] = ptr
        return ptr
    end

    -- Alocate float with a key, returns cached ptr if already exists
    function self.AllocFloat(key)
        return self.AllocV3(key)
    end

    -- Read V3 with float value
    function self.ReadV3(ptr)
        return {x=Memory.ReadFloat(ptr), y=Memory.ReadFloat(ptr + 8), z=Memory.ReadFloat(ptr + 16)}
    end

    -- Get a cached allocation by key
    function self.Get(key)
        return self.cache[key]
    end

    -- Free a specific allocation by key
    function self.Free(key)
        if self.cache[key] then
            Memory.Free(self.cache[key])
            self.cache[key] = nil
            return true
        end
        return false
    end

    -- Free all cached allocations (call on unload)
    function self.FreeAll()
        for key, ptr in pairs(self.cache) do
            Memory.Free(ptr)
        end
        self.cache = {}
    end

    return self
end

return MemoryUtils
