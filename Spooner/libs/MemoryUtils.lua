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
