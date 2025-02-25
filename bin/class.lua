-- metadata for classes
local meta = {}

--[=[
    @method meta:__tostring
    returns a string representation of the class.

    @return string the class name.
]=]
function meta:__tostring()
    return ('class: ' .. self.__name)
end

--[=[
    @method meta:__assign
    assigns values to the class instance.

    @param ... (any) the values to assign.
]=]
function meta:__assign(...)
    for k, v in pairs({...}) do
        self[k] = v
    end
end

--[=[
    @method meta:__call
    creates a new instance of the class.

    @param ... (any) the arguments passed to the constructor.
    @return table the new instance.
]=]
function meta:__call(...)
    local obj = setmetatable({}, self)

    obj:__new(...)

    return obj
end

--[=[
    @function class
    creates a new class.

    @param name (string) the name of the class.
    @param ... (table) the base classes to inherit from.
    @return table the new class.
]=]
local function class(name, ...)
    local new   = {}
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

    return setmetatable(new, meta)
end

return class
