-- metadata for classes
local meta = {}

function meta:__tostring()
    return ('class: ' .. self.__name)
end

function meta:__assign(...)
    for k, v in ipairs({...}) do
        self['_' .. k] = v
    end
end

function meta:__call(...)
    local obj = setmetatable({}, self)

    obj:__new(...)

    return obj
end

-- class system implementation
local function class(name, ...)
    local new   = setmetatable({}, meta)
    local bases = {...}

    for _, base in ipairs(bases) do
        for k1, v1 in pairs(base) do
            if not k1:find('^__') then
                new[k1] = v1
            end
        end
    end

    new.__name  = name
    new.__bases = bases
    new.__index = new

    return new
end

-- here you go
return class
