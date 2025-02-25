--[=[
    @function class
    creates a new class.

    @param name (string) the name of the class.
    @param ... (table) the base classes to inherit from.
    @return table the new class.
]=]
local function class(name, ...)
    local new = {}

    setmetatable(new, {
        __call = function(cls, ...)
            local obj = setmetatable({}, cls)

            if cls.__new then
                cls.__new(obj, ...)
            end

            return obj
        end,
        __tostring = function(cls)
            return 'class: ' .. cls.__name
        end
    })

    local bases = {...}

    for _, v in ipairs(bases) do
        for k, v in pairs(v) do
            if not k:find('^__') then
                new[k] = v
            end
        end
    end

    function new:__assign(...)
        for _, v in ipairs({...}) do
            for k, vv in pairs(v) do
                self['_' .. k] = vv
            end
        end
    end

    new.__name  = name
    new.__bases = bases
    new.__index = new

    return new
end

return class
