--[=[
    library.lua
    a small settings ui for roblox scripts.

        local ui  = loadstring(game:HttpGet(<raw url>))()
        local win = ui:window({ title = 'My Script' })
        local grp = win:tab('Main'):group('Movement')

        grp:toggle({ name = 'Fly', icon = 'paper-plane-tilt', key = Enum.KeyCode.V,
            slider = { min = 0, max = 400, default = 120, suffix = ' st/s' },
            call = function(on, speed) end })

    every element has :set(...) and :get(). setting a value from code
    repaints the element, so a control never disagrees with the state it
    drives. give an element a `flag` and ui:config() / ui:load() save and
    restore it.

    re-running replaces the previous gui with the same id, and destroying
    that gui runs the previous run's ui:onUnload callbacks.

    sizes are the design's own pixels at scale 1.
]=]




-- services
local cloneref = cloneref or function(x) return x end
local tween    = cloneref(game:GetService('TweenService'))
local uinput   = cloneref(game:GetService('UserInputService'))
local coregui  = cloneref(game:GetService('CoreGui'))


-- shortcuts
local mb1, touch            = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch
local mousemove, keyb       = Enum.UserInputType.MouseMovement, Enum.UserInputType.Keyboard
local autox, autoy          = Enum.AutomaticSize.X, Enum.AutomaticSize.Y
local left, right, center   = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
local medium, semi, bold    = Enum.FontWeight.Medium, Enum.FontWeight.SemiBold, Enum.FontWeight.Bold
local clamp, floor, max, min = math.clamp, math.floor, math.max, math.min


-- library
local library = {
    flags    = {},
    alive    = true,
    _flagged = {},
    _conns   = {},
    _unload  = {},
    _renders = {},
    _binds   = {},
    _painted = setmetatable({}, { __mode = 'k' }),
    _nNote   = 0,
}

local icons -- filled at the bottom of the file


-- theme
local theme = {
    page   = Color3.fromHex('09090a'),
    bg     = Color3.fromHex('111113'),
    elem   = Color3.fromHex('19191c'),
    hair   = Color3.fromHex('1d1d20'),
    rule   = Color3.fromHex('2a2a2e'),
    text   = Color3.fromHex('e7e3db'),
    sub    = Color3.fromHex('9a958c'),
    dim    = Color3.fromHex('5f5b55'),
    accent = Color3.fromHex('c8a676'),
    ink    = Color3.fromHex('16140f'), -- the tick drawn on the accent
}
library.theme = theme

local accents = {
    tan   = { accent = Color3.fromHex('c8a676'), ink = Color3.fromHex('16140f') },
    lilac = { accent = Color3.fromHex('bfa3f5'), ink = Color3.fromHex('17131f') },
}

-- background patterns baked by tools/icons.py: the size one tile is drawn at
-- (the images are twice this, so they stay crisp at 2x), and a default
-- opacity - fine lines read far stronger than a scatter at the same value.
local patterns = {
    dots     = { tile = 16, opacity = 0.08 },
    grain    = { tile = 48, opacity = 0.05 },
    hatch    = { tile = 10, opacity = 0.025 },
    sparkles = { tile = 96, opacity = 0.06 },
}

local family = 'rbxasset://fonts/families/Jura.json'

pcall(function()
    family = Font.fromEnum(Enum.Font.Jura).Family
end)

--[=[
    the same weights as the design. roblox's jura is a static cut and renders
    a touch lighter than the web's; asking for heavier faces to compensate was
    tried and changes the letterforms, which is worse.

    @param weight (EnumItem) the font weight, semibold by default.
    @return Font
]=]
local function jura(weight)
    return Font.new(family, weight or semi)
end

--[=[
    formats a colour for RichText markup.

    @param c (Color3) the colour.
    @return string '#rrggbb'
]=]
local function hex(c)
    return string.format('#%02x%02x%02x', floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5))
end

-- text that goes into RichText labels.
local escapes = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;' }

local function esc(s)
    return (tostring(s):gsub('[&<>"]', escapes))
end






-- utilities

--[=[
    calls a user callback, warning instead of throwing when it errors.

    @param fn (function?) the callback; anything else is ignored.
    @param ... the arguments to pass.
]=]
local function safe(fn, ...)
    if type(fn) ~= 'function' then
        return
    end

    local ok, err = pcall(fn, ...)

    if not ok then
        warn('[library] callback error: ' .. tostring(err))
    end
end

--[=[
    connects and remembers, so unloading disconnects everything. while an
    element is being built (library._owner) it also owns the connection, so
    destroying just that element lets go of its listeners too.

    @param sig (RBXScriptSignal) the event to connect.
    @param fn (function) the callback function.
    @return RBXScriptConnection
]=]
local function on(sig, fn)
    local c = sig:Connect(fn)

    table.insert(library._conns, c)

    if library._owner then
        table.insert(library._owner._conns, c)
    end

    return c
end

--[=[
    creates an instance with no border and no background.

    @param class (string) the class name.
    @param props (table) properties to assign.
    @param parent (Instance?) where to put it.
    @return Instance
]=]
local function new(class, props, parent)
    local i = Instance.new(class)

    if i:IsA('GuiObject') then
        i.BorderSizePixel        = 0
        i.BackgroundTransparency = 1
    end

    for k, v in props do
        i[k] = v
    end

    if parent then
        i.Parent = parent
    end

    return i
end

--[=[
    paints a property from the theme and remembers it, so the accent can
    change.

    @param inst (Instance) the instance to paint.
    @param prop (string) the colour property.
    @param key (string) the theme key.
    @return Instance
]=]
local function paint(inst, prop, key)
    inst[prop] = theme[key]

    local p = library._painted[inst] or {}

    library._painted[inst] = p
    p[prop] = key

    return inst
end

--[=[
    colours that depend on state are drawn by a function; run it now, and
    again whenever the accent changes. the element being built owns it, so
    destroying the element lets go of it (and of the instances it closes
    over).

    @param fn (function) the draw function.
]=]
local function render(fn)
    library._renders[fn] = true

    if library._owner then
        table.insert(library._owner._renders, fn)
    end

    fn()
end

local function corner(inst, r)
    return new('UICorner', { CornerRadius = UDim.new(0, r) }, inst)
end

local function pad(inst, t, r, b, l)
    return new('UIPadding', {
        PaddingTop    = UDim.new(0, t),
        PaddingRight  = UDim.new(0, r),
        PaddingBottom = UDim.new(0, b),
        PaddingLeft   = UDim.new(0, l),
    }, inst)
end

local function vlist(inst, gap)
    return new('UIListLayout', {
        Padding   = UDim.new(0, gap or 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, inst)
end

local function hlist(inst, gap)
    return new('UIListLayout', {
        Padding           = UDim.new(0, gap or 0),
        SortOrder         = Enum.SortOrder.LayoutOrder,
        FillDirection     = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, inst)
end

local function grow(inst)
    return new('UIFlexItem', { FlexMode = Enum.UIFlexMode.Fill }, inst)
end

local function text(parent, props, colour)
    local l = new('TextLabel', {
        FontFace       = jura(semi),
        TextSize       = 13,
        TextXAlignment = left,
    }, parent)

    paint(l, 'TextColor3', colour or 'text')

    for k, v in props do
        l[k] = v
    end

    return l
end

local function block(parent, props, colour)
    local f = new('Frame', { BackgroundTransparency = 0 }, parent)

    paint(f, 'BackgroundColor3', colour)

    for k, v in props do
        f[k] = v
    end

    return f
end






-- icons
-- phosphor bold, baked into this file as png (tools/icons.py). the first use
-- of an icon writes it to the executor's workspace and loads it with
-- getcustomasset. without those functions icons are blank, never an error.
local b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

--[=[
    decodes base64, natively when the executor can.

    @param s (string) the encoded text.
    @return string
]=]
local function unbase64(s)
    local native = (crypt and (crypt.base64decode or crypt.base64_decode)) or (base64 and base64.decode)

    if native then
        local ok, out = pcall(native, s)

        if ok and type(out) == 'string' and #out > 0 then
            return out
        end
    end

    local map, out, acc, bits = {}, {}, 0, 0

    for i = 1, 64 do
        map[string.byte(b64, i)] = i - 1
    end

    for i = 1, #s do
        local v = map[string.byte(s, i)]

        if v then
            acc, bits = acc * 64 + v, bits + 6

            if bits >= 8 then
                bits -= 8

                local b = floor(acc / 2 ^ bits)

                acc -= b * 2 ^ bits
                out[#out + 1] = string.char(b)
            end
        end
    end

    return table.concat(out)
end

local assets = {}
local custom = {}

--[=[
    resolves an icon to a content id, writing its png on first use.

    @param name (string | number) a baked or added icon's name, a content id
    (`rbxassetid://…`, `rbxthumb://…`, `https://…`) used as is, or a bare
    asset id.
    @return string? nil when the icon cannot be loaded.
]=]
local function iconasset(name)
    -- an uploaded image: nothing to write, so it works without getcustomasset
    if type(name) == 'number' or (type(name) == 'string' and string.match(name, '^%d+$')) then
        return 'rbxassetid://' .. name
    end

    if type(name) ~= 'string' then
        return nil
    end

    if string.match(name, '^%a+://') then
        return name
    end

    if assets[name] ~= nil then
        return assets[name] or nil
    end

    -- nothing to load the file with: do not leave pngs in the workspace
    if type(getcustomasset) ~= 'function' then
        assets[name] = false

        return nil
    end

    local ok, id = pcall(function()
        local data = assert(icons[name], 'no icon named ' .. name)

        -- the length stamps the version: a re-baked icon gets a new file. an
        -- added one is rewritten on its first use each session, since a
        -- project can change its png without changing its length.
        local path = 'library-icons/' .. (custom[name] and 'custom-' or '')
            .. string.gsub(name, '[^%w%-_]', '_') .. '-' .. #data .. '.png'

        if custom[name] or not isfile(path) then
            if not isfolder('library-icons') then
                makefolder('library-icons')
            end

            writefile(path, string.sub(data, 1, 4) == '\137PNG' and data or unbase64(data))
        end

        return getcustomasset(path)
    end)

    assets[name] = ok and id or false

    return ok and id or nil
end
library.icon = iconasset

--[=[
    adds an icon, or replaces a baked one, under a name any `icon` option can
    use. draw it white on transparent: elements tint icons through
    ImageColor3. elements built before the call keep what they had.

    @param name (string) the name to use it by.
    @param png (string) the png, as base64 or as raw bytes.
]=]
function library.addicon(name, png)
    assert(type(name) == 'string' and name ~= '', 'addicon: name must be a string')
    assert(type(png) == 'string' and png ~= '', 'addicon: png must be a string')

    icons[name]  = png
    custom[name] = true
    assets[name] = nil
end

local function icon(parent, name, size, colour, props)
    local i = new('ImageLabel', {
        Size      = UDim2.fromOffset(size, size),
        Image     = iconasset(name) or '',
        ScaleType = Enum.ScaleType.Fit,
    }, parent)

    paint(i, 'ImageColor3', colour or 'dim')

    for k, v in props or {} do
        i[k] = v
    end

    return i
end






--[=[
    @class library
    the table this file returns: the root gui, keys, config and notifications.
]=]

-- a previous run's gui with this id: destroying it fires ITS Destroying,
-- which unloads that run from inside its own environment.
local function replace(parent, id, keep)
    for _, c in parent:GetChildren() do
        if c ~= keep and c.Name == id and c:GetAttribute('__library') then
            c:Destroy()
        end
    end
end

--[=[
    @method _root
    makes the ScreenGui on first use, and renames it to the window's id.

    @param id (string?) the gui's name.
    @return ScreenGui

    @private
]=]
function library:_root(id)
    if self.gui then
        -- a notify() before the window made the gui under the default name;
        -- take the window's id now so the next run can still find it
        if id and self.gui.Name ~= id then
            replace(self.gui.Parent, id, self.gui)
            self.gui.Name = id
        end

        return self.gui
    end

    id = id or 'library'

    local parent = (gethui and gethui()) or coregui

    replace(parent, id)

    local gui = new('ScreenGui', {
        Name           = id,
        ResetOnSpawn   = false,
        IgnoreGuiInset = true,
        DisplayOrder   = 100,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })

    gui:SetAttribute('__library', true)

    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        end
    end)

    gui.Parent = parent
    self.gui   = gui

    on(gui.Destroying, function()
        task.defer(function()
            self:destroy()
        end)
    end)

    -- one input path for every key: rebinding first, then bound keys.
    on(uinput.InputBegan, function(i, gp)
        if i.UserInputType ~= keyb then
            return
        end

        local waiting = self._listening

        if waiting then
            self._listening = nil

            local k = i.KeyCode

            if k == Enum.KeyCode.Escape then
                waiting(false)
            else
                waiting(k ~= Enum.KeyCode.Backspace and k or nil)
            end

            return
        end

        if gp or uinput:GetFocusedTextBox() then
            return
        end

        for _, b in self._binds do
            if b.key() == i.KeyCode then
                safe(b.fn)
            end
        end
    end)

    self._notes = new('Frame', {
        AnchorPoint = Vector2.new(1, 1),
        Position    = UDim2.new(1, -20, 1, -20),
        Size        = UDim2.fromOffset(250, 600),
        ZIndex      = 50,
    }, gui)
    vlist(self._notes, 8).VerticalAlignment = Enum.VerticalAlignment.Bottom
    self._noteScale = new('UIScale', {}, self._notes)

    return gui
end

--[=[
    @method _bind
    runs `fn` whenever the key that `key()` returns is pressed.

    @param key (function) returns the current KeyCode.
    @param fn (function) the callback.

    @private
]=]
function library:_bind(key, fn)
    table.insert(self._binds, { key = key, fn = fn, owner = self._owner })
end

--[=[
    @method _listen
    waits for the next key. `done` gets the KeyCode, nil for backspace
    (clear) or false for escape (keep the old one).

    @param done (function) the callback.

    @private
]=]
function library:_listen(done)
    if self._listening then
        self._listening(false)
    end

    self._listening = done
end

--[=[
    @method onUnload
    runs `fn` when the library unloads.

    @param fn (function) the callback.
]=]
function library:onUnload(fn)
    table.insert(self._unload, fn)
end

--[=[
    @method destroy
    unloads: runs the unload callbacks, disconnects everything and destroys
    the gui.
]=]
function library:destroy()
    if not self.alive then
        return
    end

    self.alive = false

    for _, fn in self._unload do
        safe(fn)
    end

    for _, c in self._conns do
        c:Disconnect()
    end

    if self.gui then
        self.gui:Destroy()
    end

    -- a script may keep its ui reference after unloading; everything below
    -- closes over instances, so none of it may outlive the gui
    for _, t in { self._conns, self._unload, self._renders, self._painted, self._binds, self._flagged } do
        table.clear(t)
    end

    self._listening, self._owner = nil, nil
end

--[=[
    @method setAccent
    repaints everything in a new accent.

    @param a (string | Color3) 'tan', 'lilac', or any Color3.
]=]
function library:setAccent(a)
    local set = accents[a] or (typeof(a) == 'Color3' and { accent = a, ink = theme.page })

    if not set then
        return
    end

    theme.accent, theme.ink = set.accent, set.ink

    for inst, props in self._painted do
        for prop, key in props do
            inst[prop] = theme[key]
        end
    end

    for fn in self._renders do
        safe(fn)
    end
end

--[=[
    @method config
    every flagged element's value, keyed by flag.

    @return table
]=]
function library:config()
    local out = {}

    for flag, el in self._flagged do
        out[flag] = el:_save()
    end

    return out
end

--[=[
    @method load
    restores flagged elements. wrong types are skipped, so a hand-edited file
    cannot break a control.

    @param tbl (table) values keyed by flag.
    @return number how many flags were restored.
]=]
function library:load(tbl)
    if type(tbl) ~= 'table' then
        return 0
    end

    local n = 0

    for flag, v in tbl do
        local el = self._flagged[flag]

        if el then
            local ok, took = pcall(el._load, el, v)

            if ok and took then
                n += 1
            end
        end
    end

    return n
end

--[=[
    @method notify
    a card: title, message, and the accent draining along the bottom edge.

    @param o (string | table) the message, or a table containing:
        @field title (string?) the heading.
        @field message (string) the text to display.
        @field duration (number?) seconds before it leaves, 4.5 by default.
]=]
function library:notify(o)
    if not self.alive then
        return
    end

    if type(o) ~= 'table' then
        o = { message = tostring(o) }
    end

    self:_root()

    local dur = tonumber(o.duration) or 4.5

    self._nNote += 1

    local slot = new('Frame', {
        Size          = UDim2.fromOffset(250, 0),
        AutomaticSize = autoy,
        LayoutOrder   = self._nNote,
    }, self._notes)
    local card = block(slot, {
        Size          = UDim2.fromOffset(250, 0),
        AutomaticSize = autoy,
        Position      = UDim2.fromOffset(280, 0),
    }, 'rule')
    corner(card, 2)
    pad(card, 1, 1, 1, 1)

    local body = block(card, { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy }, 'bg')
    corner(body, 1)
    pad(body, 9, 11, 10, 11)
    vlist(body, 3)

    local wide = { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy, TextWrapped = true }

    if o.title then
        local t = text(body, wide)

        t.Text, t.FontFace, t.LineHeight = tostring(o.title), jura(bold), 1.2
    end

    local m = text(body, wide, o.title and 'sub' or 'text')

    m.Text, m.FontFace, m.TextSize, m.LineHeight, m.LayoutOrder = tostring(o.message or o.text or ''), jura(medium), 12, 1.4, 1

    local timer = block(card, {
        AnchorPoint = Vector2.new(0, 1),
        Position    = UDim2.new(0, -1, 1, 1),
        Size        = UDim2.new(1, 2, 0, 1),
    }, 'accent')

    local out = TweenInfo.new(0.3, Enum.EasingStyle.Quint)

    tween:Create(card, out, { Position = UDim2.new() }):Play()
    tween:Create(timer, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 1) }):Play()

    local gone = false

    local function dismiss()
        if gone then
            return
        end

        gone = true

        tween:Create(card, out, { Position = UDim2.fromOffset(280, 0) }):Play()
        task.delay(0.3, function()
            slot:Destroy()
        end)
    end

    new('TextButton', { Text = '', Size = UDim2.fromScale(1, 1), ZIndex = 2 }, card).MouseButton1Click:Connect(dismiss)
    task.delay(dur, dismiss)

    -- five at most: the oldest goes first
    local cards = {}

    for _, c in self._notes:GetChildren() do
        if c:IsA('Frame') then
            table.insert(cards, c)
        end
    end

    table.sort(cards, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)

    for i = 1, #cards - 5 do
        cards[i]:Destroy()
    end
end






-- parts

--[=[
    the keycap: 15 tall, a 1px rim with a 2px bottom lip, at least minw wide.

    @param parent (Instance) where to put it.
    @param label (string) the key's text.
    @param minw (number) the narrowest it may be.
    @return Frame, TextLabel, TextButton the rim, the face and the hit area.
]=]
local function keycap(parent, label, minw)
    local rim = block(parent, { Size = UDim2.fromOffset(0, 15), AutomaticSize = autox }, 'rule')
    corner(rim, 2)
    pad(rim, 1, 1, 2, 1)

    local face = text(rim, {
        Text                   = label,
        FontFace               = jura(bold),
        TextSize               = 10,
        TextXAlignment         = center,
        Size                   = UDim2.fromScale(0, 1),
        AutomaticSize          = autox,
        BackgroundTransparency = 0,
    }, 'sub')
    paint(face, 'BackgroundColor3', 'elem')
    corner(face, 1)
    pad(face, 0, 4, 0, 4)
    new('UISizeConstraint', { MinSize = Vector2.new(minw - 2, 0) }, face)

    local hit = new('TextButton', { Text = '', Size = UDim2.fromScale(1, 1), ZIndex = 2 }, rim)

    return rim, face, hit
end

--[=[
    the tick: 15x15 with a 1px rim; on, it fills with the accent and a check.

    @param parent (Instance) where to put it.
    @return Frame, function the rim and its draw(on).
]=]
local function checkbox(parent)
    local rim = block(parent, { Size = UDim2.fromOffset(15, 15) }, 'dim')
    corner(rim, 2)

    local hole = block(rim, { Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(13, 13) }, 'bg')
    corner(hole, 1)

    local mark = icon(rim, 'check', 9, 'ink', {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position    = UDim2.fromScale(0.5, 0.5),
        Visible     = false,
    })

    return rim, function(v)
        rim.BackgroundColor3 = v and theme.accent or theme.dim
        hole.Visible, mark.Visible = not v, v
    end
end

--[=[
    a row: optional icon, the label filling the middle, controls on the
    right. everything centres on one 26px line box.

    @param o (table) the element's options.
    @param clickable (boolean) a button rather than a frame.
    @return GuiObject, TextLabel, ImageLabel? the row, its label and icon.
]=]
local function row(o, clickable)
    local r = new(clickable and 'TextButton' or 'Frame', { Size = UDim2.new(1, 0, 0, 26) })

    if clickable then
        r.Text, r.AutoButtonColor = '', false
    end

    hlist(r, 8)

    local ic    = o.icon and icon(r, o.icon, 11, 'dim', { LayoutOrder = 1 })
    local label = text(r, {
        Text         = tostring(o.name or ''),
        Size         = UDim2.fromScale(0, 1),
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder  = 2,
    })
    grow(label)

    return r, label, ic
end

-- a value on the right of a row.
local function readout(r)
    return text(r, {
        Size          = UDim2.fromScale(0, 1),
        AutomaticSize = autox,
        RichText      = true,
        LayoutOrder   = 3,
    }, 'sub')
end

--[=[
    the ruler: ticks every 5%, taller every 25%, a 2px fill along the bottom,
    and pins that are one 6x12 box each - a 2px stem and a 6x3 head inside
    it - so the two parts can never drift apart.

    @param indent (number) how far in it starts, to line up with the label.
    @return Frame, function, function the ruler, draw() and track().
]=]
local function ruler(indent)
    local wrap = new('Frame', { Size = UDim2.new(1, 0, 0, 18) })
    local bar  = new('Frame', { Position = UDim2.fromOffset(indent, 0), Size = UDim2.new(1, -indent, 0, 12) }, wrap)

    for i = 0, 20 do
        local major = i % 5 == 0

        block(bar, {
            AnchorPoint = Vector2.new(i == 20 and 1 or 0, 1),
            Position    = UDim2.fromScale(i / 20, 1),
            Size        = UDim2.fromOffset(1, major and 7 or 4),
        }, major and 'dim' or 'rule')
    end

    local line = new('Frame', {
        BackgroundTransparency = 0,
        AnchorPoint            = Vector2.new(0, 1),
        Size                   = UDim2.fromOffset(0, 2),
        ZIndex                 = 2,
    }, bar)
    local pins = {}
    local hit  = new('TextButton', {
        Text     = '',
        Position = UDim2.fromOffset(indent - 4, -6),
        Size     = UDim2.new(1, 8 - indent, 0, 22),
        ZIndex   = 4,
    }, wrap)

    -- fill from a to b; one pin per fraction in `at`. only what changed is
    -- written: a property write is the expensive part, not the maths.
    local last = {}

    local function draw(a, b, at, lit)
        local c = lit and theme.accent or theme.dim

        if c ~= last.c then
            last.c = c
            line.BackgroundColor3 = c

            for _, p in pins do
                p[2].BackgroundColor3, p[3].BackgroundColor3 = c, c
            end
        end

        if a ~= last.a or b ~= last.b then
            last.a, last.b = a, b
            line.Position  = UDim2.fromScale(a, 1)
            line.Size      = UDim2.new(b - a, 0, 0, 2)
        end

        for i, f in at do
            local p = pins[i]

            if not p then
                local box = new('Frame', { Size = UDim2.fromOffset(6, 12), ZIndex = 3 }, bar)

                p = {
                    box,
                    new('Frame', { BackgroundTransparency = 0, Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(2, 12), ZIndex = 3 }, box),
                    new('Frame', { BackgroundTransparency = 0, Size = UDim2.fromOffset(6, 3), ZIndex = 3 }, box),
                }
                p[2].BackgroundColor3, p[3].BackgroundColor3 = c, c
                pins[i] = p
            end

            if p.f ~= f then
                p.f = f
                p[1].Position = UDim2.new(f, -3, 0, 0)
            end
        end
    end

    -- press and drag: move(fraction, ispress), then done() on release
    local function track(move, done)
        local held = false

        local function frac(x)
            return clamp((x - bar.AbsolutePosition.X) / max(bar.AbsoluteSize.X, 1), 0, 1)
        end

        on(hit.InputBegan, function(i)
            if i.UserInputType == mb1 or i.UserInputType == touch then
                held = true
                move(frac(i.Position.X), true)
            end
        end)

        on(uinput.InputChanged, function(i)
            if held and (i.UserInputType == mousemove or i.UserInputType == touch) then
                move(frac(i.Position.X), false)
            end
        end)

        on(uinput.InputEnded, function(i)
            if held and (i.UserInputType == mb1 or i.UserInputType == touch) then
                held = false
                done()
            end
        end)
    end

    return wrap, draw, track
end

--[=[
    a real, finite number or nil. NaN passes `type(v) == 'number'`, and one
    from a corrupted config would otherwise show as "nan" for good.

    @param v (any) the value.
    @return number?
]=]
local function finite(v)
    v = tonumber(v)

    return v and v == v and v > -math.huge and v < math.huge and v or nil
end

--[=[
    numbers snapped to `step`, shown with its decimals, a prefix and a
    suffix.

    @param o (table) min, max, step, prefix and suffix.
    @return table snap(v), show(v), frac(v) and at(f).
]=]
local function numbers(o)
    local lo, hi = finite(o.min) or 0, finite(o.max) or 100

    if hi < lo then
        lo, hi = hi, lo -- math.clamp throws on reversed bounds
    end

    local step = finite(o.step) or 1

    if step <= 0 then
        step = 1
    end

    local dot  = tostring(step):find('%.')
    local fmt  = '%.' .. (dot and #tostring(step) - dot or 0) .. 'f'
    local nums = {}

    function nums.snap(v)
        v = lo + floor(((finite(v) or lo) - lo) / step + 0.5) * step

        return clamp(tonumber(string.format(fmt, v)) or lo, lo, hi)
    end

    function nums.show(v)
        return (o.prefix or '') .. string.format(fmt, v) .. (o.suffix or '')
    end

    function nums.frac(v)
        return hi > lo and (v - lo) / (hi - lo) or 0
    end

    function nums.at(f)
        return nums.snap(lo + f * (hi - lo))
    end

    return nums
end

-- how a key reads on a keycap: the short names people actually say.
local shortnames = {
    LeftShift = 'LShift', RightShift = 'RShift', LeftControl = 'LCtrl', RightControl = 'RCtrl',
    LeftAlt = 'LAlt', RightAlt = 'RAlt', Return = 'Enter', Backspace = 'Bksp', Escape = 'Esc',
    CapsLock = 'Caps', Insert = 'Ins', Delete = 'Del', PageUp = 'PgUp', PageDown = 'PgDn',
    Zero = '0', One = '1', Two = '2', Three = '3', Four = '4',
    Five = '5', Six = '6', Seven = '7', Eight = '8', Nine = '9',
}

local function capname(k)
    if not k then
        return '–'
    end

    return shortnames[k.Name] or k.Name
end

-- KeyCode <-> name, for configs.
local function keyname(k)
    return k and k.Name or nil
end

local function keyfrom(s)
    if type(s) ~= 'string' then
        return nil
    end

    local ok, k = pcall(function()
        return Enum.KeyCode[s]
    end)

    return ok and k or nil
end






--[=[
    @class element
    what every group method returns: get, set, rename, visible and destroy.
]=]
local element = {}
element.__index = element

--[=[
    @method get
    the element's current value.
]=]
function element:get()
    return self.value
end

--[=[
    @method rename
    changes the element's label.

    @param name (string) the new label.
]=]
function element:rename(name)
    self._label.Text = tostring(name)

    return self
end

--[=[
    @method visible
    shows or hides the element, rows under it included.

    @param v (boolean) false hides it.
]=]
function element:visible(v)
    for _, part in self._parts do
        part.Visible = v ~= false
    end

    return self
end

--[=[
    @method destroy
    removes the element and lets go of its listeners, renders and keys.
]=]
function element:destroy()
    if self._flag then
        library._flagged[self._flag], library.flags[self._flag] = nil, nil
    end

    for _, c in self._conns do
        c:Disconnect()
    end

    for _, fn in self._renders do
        library._renders[fn] = nil
    end

    for i = #library._binds, 1, -1 do
        if library._binds[i].owner == self then
            table.remove(library._binds, i)
        end
    end

    for _, part in self._parts do
        part:Destroy()
    end
end

function element:_save()
    return self.value
end

function element:_stored()
    if self._flag then
        library.flags[self._flag]    = self:_save()
        library._flagged[self._flag] = self
    end
end






--[=[
    @class group
    a titled run of rows inside a tab.
]=]
local group = {}
group.__index = group

function group:_add(inst)
    self._n += 1
    inst.LayoutOrder = self._n
    inst.Parent      = self._box

    return inst
end

-- build the row for an element and wrap it in an element.
function group:_row(o, clickable)
    local r, label, ic = row(o, clickable)

    self:_add(r)

    local el = setmetatable({ _call = o.call, _flag = o.flag, _parts = { r }, _label = label, _conns = {}, _renders = {} }, element)

    library._owner = el

    return el, r, ic
end

-- something that hangs under a row (a ruler, an open list), lined up with
-- the label.
function group:_under(el, inst)
    self:_add(inst)
    table.insert(el._parts, inst)

    return inst
end

local function indent(o)
    return o.icon and 19 or 0
end

--[=[
    @method toggle
    a switch, with an optional key and a number that belongs to it.

    @param o (table) the configuration for the toggle.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field default (boolean?) starts on when true.
        @field key (KeyCode? | false) flips it; the keycap is clicked to rebind.
            pass `key = false` for a keycap with nothing bound yet.
        @field slider (table?) { min, max, step, default, prefix, suffix, live },
            drawn as a ruler under the row.
        @field call (function) function(on, number).
        @field changed (function?) function(key), runs when the key is
            rebound, so a script keeping its own config can save it.
        @field flag (string?) the config key.
    @return element
]=]
function group:toggle(o)
    local el, r, ic = self:_row(o, true)
    local sl        = o.slider
    local nums      = sl and numbers(sl)

    el.value  = o.default == true
    el.key    = o.key or nil
    el.number = nums and nums.snap(sl.default or sl.min)

    local val = nums and readout(r)
    local cap, face, caphit

    if o.key ~= nil then
        cap, face, caphit = keycap(r, '', 15)
        cap.LayoutOrder = 4
    end

    local box, tick = checkbox(r)

    box.LayoutOrder = 5

    local drawruler, track

    if nums then
        local wrap

        wrap, drawruler, track = ruler(indent(o))
        self:_under(el, wrap)
    end

    local listening = false

    local function draw()
        tick(el.value)

        if ic then
            ic.ImageColor3 = el.value and theme.accent or theme.dim
        end

        if val then
            val.Text = esc(nums.show(el.number))
        end

        if drawruler then
            local f = nums.frac(el.number)

            drawruler(0, f, { f }, el.value)
        end

        if face then
            face.Text       = listening and '…' or capname(el.key)
            face.TextColor3 = listening and theme.accent or theme.sub
        end
    end
    render(draw)

    local function changed(silent)
        draw()
        el:_stored()

        if not silent then
            safe(el._call, el.value, el.number)
        end
    end

    function el:set(v, silent)
        self.value = v == true
        changed(silent)

        return self
    end

    function el:setNumber(n, silent)
        if nums then
            self.number = nums.snap(n)
            changed(silent)
        end

        return self
    end

    function el:setKey(k, silent)
        self.key = k
        changed(true)

        if not silent then
            safe(o.changed, k)
        end

        return self
    end

    function el:_save()
        return { on = self.value, number = self.number, key = keyname(self.key) }
    end

    function el:_load(v)
        if type(v) == 'boolean' then
            v = { on = v }
        end

        if type(v) ~= 'table' then
            return false
        end

        if face and type(v.key) == 'string' then
            self.key = keyfrom(v.key) or self.key
        end

        if nums and finite(v.number) then
            self.number = nums.snap(v.number)
        end

        if type(v.on) == 'boolean' then
            self.value = v.on
        end

        changed(false)

        return true
    end

    -- the keycap is a button inside the row button. deferred, so that a click
    -- which landed on the keycap has stamped capat by the time this looks.
    local capat = -1

    on(r.MouseButton1Click, function()
        task.defer(function()
            if os.clock() - capat > 0.05 then
                el:set(not el.value)
            end
        end)
    end)

    if caphit then
        on(caphit.MouseButton1Click, function()
            capat     = os.clock()
            listening = true
            draw()

            library:_listen(function(k)
                listening = false

                if k == false then
                    draw()
                else
                    el:setKey(k)
                end
            end)
        end)

        library:_bind(function()
            return el.key
        end, function()
            el:set(not el.value)
        end)
    end

    if track then
        track(function(f)
            local n = nums.at(f)

            if n ~= el.number then
                el.number = n
                changed(sl.live == false)
            end
        end, function()
            if sl.live == false then
                safe(el._call, el.value, el.number)
            end
        end)
    end

    el:_stored()

    return el
end

--[=[
    @method slider
    a number on a ruler.

    @param o (table) the configuration for the slider.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field min (number) the lowest value.
        @field max (number) the highest value.
        @field step (number?) what values snap to, 1 by default.
        @field default (number?) the starting value.
        @field prefix (string?) drawn before the number.
        @field suffix (string?) drawn after the number.
        @field live (boolean?) false calls back only on release.
        @field call (function) function(number).
        @field flag (string?) the config key.
    @return element
]=]
function group:slider(o)
    local el, r = self:_row(o)
    local nums  = numbers(o)

    el.value = nums.snap(o.default or o.min)

    local val                    = readout(r)
    local wrap, drawruler, track = ruler(indent(o))

    self:_under(el, wrap)

    local function draw()
        val.Text = esc(nums.show(el.value))

        local f = nums.frac(el.value)

        drawruler(0, f, { f }, true)
    end
    render(draw)

    local function changed(silent)
        draw()
        el:_stored()

        if not silent then
            safe(el._call, el.value)
        end
    end

    function el:set(n, silent)
        self.value = nums.snap(n)
        changed(silent)

        return self
    end

    function el:_load(v)
        if not finite(v) then
            return false
        end

        self:set(v)

        return true
    end

    track(function(f)
        local n = nums.at(f)

        if n ~= el.value then
            el.value = n
            changed(o.live == false)
        end
    end, function()
        if o.live == false then
            safe(el._call, el.value)
        end
    end)

    el:_stored()

    return el
end

--[=[
    @method range
    two pins on one ruler, read as what they mean: "45% – 90%".

    @param o (table) the slider's fields, with:
        @field default (table?) { lo, hi }.
        @field call (function) function(lo, hi).
    @return element
]=]
function group:range(o)
    local el, r = self:_row(o)
    local nums  = numbers(o)
    local d     = type(o.default) == 'table' and o.default or {}

    el.value = { nums.snap(d[1] or o.min), nums.snap(d[2] or o.max) }

    local val                    = readout(r)
    local wrap, drawruler, track = ruler(indent(o))

    self:_under(el, wrap)

    local function draw()
        local a, b = el.value[1], el.value[2]

        val.Text = esc(nums.show(a) .. ' – ' .. nums.show(b))
        drawruler(nums.frac(a), nums.frac(b), { nums.frac(a), nums.frac(b) }, true)
    end
    render(draw)

    local function changed(silent)
        draw()
        el:_stored()

        if not silent then
            safe(el._call, el.value[1], el.value[2])
        end
    end

    function el:get()
        return self.value[1], self.value[2]
    end

    function el:set(a, b, silent)
        a, b = nums.snap(a or self.value[1]), nums.snap(b or self.value[2])
        self.value = { min(a, b), max(a, b) }
        changed(silent)

        return self
    end

    function el:_save()
        return { self.value[1], self.value[2] }
    end

    function el:_load(v)
        if type(v) ~= 'table' or not finite(v[1]) or not finite(v[2]) then
            return false
        end

        self:set(v[1], v[2])

        return true
    end

    local which = 1

    track(function(f, press)
        local n = nums.at(f)
        local v = { el.value[1], el.value[2] }

        if press then
            -- take the nearer pin; on a tie, the one that can move that way
            local da, db = math.abs(n - v[1]), math.abs(n - v[2])

            which = (da < db or (da == db and n <= v[1])) and 1 or 2
        end

        v[which] = n

        if v[1] > v[2] then
            v[1], v[2] = v[2], v[1]
            which = 3 - which
        end

        if v[1] ~= el.value[1] or v[2] ~= el.value[2] then
            el.value = v
            changed(o.live == false)
        end
    end, function()
        if o.live == false then
            safe(el._call, el.value[1], el.value[2])
        end
    end)

    el:_stored()

    return el
end

--[=[
    @method keybind
    a key on its own row.

    @param o (table) the configuration for the keybind.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field default (KeyCode?) the starting key.
        @field call (function) runs when the key is pressed.
        @field changed (function?) function(key), runs when it is rebound.
        @field flag (string?) the config key.
    @return element
]=]
function group:keybind(o)
    local el, r = self:_row(o)

    el.value = o.default

    local cap, face, hit = keycap(r, '', 15)

    cap.LayoutOrder = 4

    local listening = false

    local function draw()
        face.Text       = listening and '…' or capname(el.value)
        face.TextColor3 = listening and theme.accent or theme.sub
    end
    render(draw)

    function el:set(k, silent)
        self.value = k
        draw()
        self:_stored()

        if not silent then
            safe(o.changed, k)
        end

        return self
    end

    function el:_save()
        return keyname(self.value)
    end

    function el:_load(v)
        local k = keyfrom(v)

        if not k then
            return false
        end

        self:set(k)

        return true
    end

    on(hit.MouseButton1Click, function()
        listening = true
        draw()

        library:_listen(function(k)
            listening = false

            if k == false then
                draw()
            else
                el:set(k)
            end
        end)
    end)

    library:_bind(function()
        return el.value
    end, function()
        safe(el._call, el.value)
    end)

    el:_stored()

    return el
end

--[=[
    @method button
    a row that runs `call` when clicked.

    @param o (table) the configuration for the button.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field call (function) the callback.
    @return element
]=]
function group:button(o)
    local el, r = self:_row(o, true)
    local arrow = icon(r, 'arrow-right', 10, 'dim', { LayoutOrder = 5 })

    on(r.MouseEnter, function()
        arrow.ImageColor3 = theme.accent
    end)

    on(r.MouseLeave, function()
        arrow.ImageColor3 = theme.dim
    end)

    on(r.MouseButton1Click, function()
        safe(el._call)
    end)

    return el
end

--[=[
    @method field
    a read-only value; nil reads "Not set".

    @param o (table) the configuration for the field.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field value (string?) the starting value.
        @field placeholder (string?) shown instead of an empty value.
    @return element
]=]
function group:field(o)
    local el, r = self:_row(o)

    el.value = o.value

    local val = readout(r)

    local function draw()
        local unset = el.value == nil or el.value == ''

        val.Text       = esc(unset and (o.placeholder or 'Not set') or el.value)
        val.FontFace   = jura(unset and medium or semi)
        val.TextColor3 = unset and theme.dim or theme.sub
    end
    render(draw)

    function el:set(v)
        self.value = v
        draw()

        return self
    end

    return el
end

--[=[
    @method textbox
    a line of typed text. `call(text, enter)` runs on enter, or on any focus
    loss with `onLost`.

    @param o (table) the configuration for the textbox.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field default (string?) the starting text.
        @field placeholder (string?) shown while empty.
        @field clear (boolean?) empties the box after each call.
        @field onLost (boolean?) calls back on any focus loss.
        @field call (function) function(text, enter).
        @field flag (string?) the config key.
    @return element
]=]
function group:textbox(o)
    local el, r = self:_row(o)
    local box   = new('TextBox', {
        Size             = UDim2.fromScale(0.5, 1),
        FontFace         = jura(semi),
        TextSize         = 13,
        TextXAlignment   = right,
        Text             = tostring(o.default or ''),
        PlaceholderText  = tostring(o.placeholder or ''),
        ClearTextOnFocus = false,
        ClipsDescendants = true,
        LayoutOrder      = 3,
    }, r)
    paint(box, 'TextColor3', 'sub')
    paint(box, 'PlaceholderColor3', 'dim')

    el.value = box.Text

    on(box.Focused, function()
        box.TextColor3 = theme.text
    end)

    on(box.FocusLost, function(enter)
        box.TextColor3 = theme.sub
        el.value       = box.Text
        el:_stored()

        if enter or o.onLost then
            safe(el._call, box.Text, enter)

            if o.clear then
                box.Text = ''
            end
        end
    end)

    function el:set(v, silent)
        self.value = tostring(v or '')
        box.Text   = self.value
        self:_stored()

        if not silent then
            safe(self._call, self.value, false)
        end

        return self
    end

    function el:_load(v)
        if type(v) ~= 'string' then
            return false
        end

        self:set(v)

        return true
    end

    el:_stored()

    return el
end

--[=[
    @method label
    a paragraph.

    @param s (string) the text.
    @return element
]=]
function group:label(s)
    local l = text(nil, {
        Text          = tostring(s),
        FontFace      = jura(medium),
        TextSize      = 12,
        LineHeight    = 1.4,
        Size          = UDim2.fromScale(1, 0),
        AutomaticSize = autoy,
        TextWrapped   = true,
    }, 'sub')
    pad(l, 4, 0, 4, 0)
    self:_add(l)

    local el = setmetatable({ _parts = { l }, _label = l, value = l.Text, _conns = {}, _renders = {} }, element)

    function el:set(v)
        self.value = tostring(v)
        l.Text     = self.value

        return self
    end

    return el
end

--[=[
    @method table
    rows of two columns: a fixed-width key, and a value that wraps. a cell is
    a string, or a list of pieces `{ text, colour }` where colour is a theme
    key ('text', 'sub', 'dim', 'accent') - the library escapes and colours
    them, so a highlight follows the accent.

    with `sep`, a value that is a list is laid out as items instead: each
    piece is one unbreakable item, `sep` (dim) follows every item but the
    last, and a line only ever breaks between items - never inside one, and
    never before a separator. roblox wraps at a no-break space too, so this
    is the only way to keep a name whole.

    @param o (table) the configuration for the table.
        @field rows (table?) the starting rows: `{ { key, value }, ... }`.
        @field width (number?) the key column, 38 by default.
        @field sep (string?) lays list values out as items, joined by this.
        @field empty (string?) shown with no rows.
    @return element
]=]
function group:table(o)
    o = o or {}

    local width = tonumber(o.width) or 38
    local box   = new('Frame', { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy })
    pad(box, 4, 0, 4, 0)
    vlist(box, 5)
    self:_add(box)

    local el   = setmetatable({ _parts = { box }, value = {}, _conns = {}, _renders = {} }, element)
    local rows = {}

    library._owner = el

    local function piece(p, colour)
        local s, c = p, colour

        if type(p) == 'table' then
            s, c = p[1], theme[p[2]] and p[2] or colour
        end

        return string.format('<font color="%s">%s</font>', hex(theme[c]), esc(s or ''))
    end

    -- a cell as markup, in the theme's colours of the moment
    local function markup(cell, colour)
        if type(cell) ~= 'table' then
            return piece(cell, colour)
        end

        local out = {}

        for _, p in cell do
            table.insert(out, piece(p, colour))
        end

        return table.concat(out)
    end

    local function cell(parent, props)
        return text(parent, {
            FontFace       = jura(props.weight or medium),
            TextSize       = 12,
            RichText       = true,
            TextWrapped    = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder    = props.order,
            Size           = props.size,
            AutomaticSize  = autoy,
        })
    end

    -- the value column as items: one label each, in a layout that wraps
    local function flow(parent, n)
        local f = new('Frame', {
            Size          = UDim2.new(1, -(width + 8), 0, 0),
            AutomaticSize = autoy,
            LayoutOrder   = 2,
        }, parent)
        local h = hlist(f, 0)

        h.Wraps, h.VerticalAlignment = true, Enum.VerticalAlignment.Top

        local items = {}

        for i = 1, n do
            -- the height is the line pitch: a wrapped paragraph's, at 12px
            items[i] = text(f, {
                FontFace      = jura(medium),
                TextSize      = 12,
                RichText      = true,
                Size          = UDim2.fromOffset(0, 15),
                AutomaticSize = autox,
                LayoutOrder   = i,
            })
        end

        return items
    end

    local function draw()
        for _, r in rows do
            r.key.Text = markup(r.data[1], 'text')

            if r.items then
                local n = #r.items

                for i, l in r.items do
                    l.Text = piece(r.data[2][i], 'sub') .. (i < n and piece({ o.sep, 'dim' }) or '')
                end
            else
                r.val.Text = markup(r.data[2], 'sub')
            end
        end

        if el._empty then
            el._empty.Text = markup(o.empty or '', 'dim')
        end
    end

    function el:set(list)
        self.value = type(list) == 'table' and list or {}

        for _, r in rows do
            r.frame:Destroy()
        end

        table.clear(rows)

        for i, data in self.value do
            local f = new('Frame', { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy, LayoutOrder = i }, box)
            local h = hlist(f, 8)

            h.VerticalAlignment = Enum.VerticalAlignment.Top

            data = type(data) == 'table' and data or { data }

            local r = {
                frame = f,
                data  = data,
                key   = cell(f, { weight = semi, order = 1, size = UDim2.fromOffset(width, 0) }),
            }

            if o.sep and type(data[2]) == 'table' then
                r.items = flow(f, #data[2])
            else
                r.val = cell(f, { order = 2, size = UDim2.new(1, -(width + 8), 0, 0) })
            end

            table.insert(rows, r)
        end

        if o.empty and not el._empty then
            el._empty = cell(box, { order = 0, size = UDim2.fromScale(1, 0) })
        end

        if el._empty then
            el._empty.Visible = #rows == 0
        end

        draw()

        return self
    end

    render(draw)
    el:set(o.rows)

    library._owner = nil

    return el
end

--[=[
    @method dropdown
    a list that opens under its row.

    @param o (table) the configuration for the dropdown.
        @field name (string) the label.
        @field icon (string?) an icon name.
        @field options (table | function) a list of strings, or a function
            returning one - called again every time the list opens, so it
            can be live.
        @field default (string | table?) the starting pick, or picks.
        @field multi (boolean?) several picks; the value is a list, in the
            order picked.
        @field ordered (boolean?) show that order on the row: 1Z 2X 3C.
        @field keys (boolean?) draw each option as a keycap.
        @field describe (function?) function(option) -> grey text beside it.
        @field search (boolean?) force the search line on or off (default:
            on past 6 options).
        @field placeholder (string?) shown with nothing picked.
        @field call (function) function(value).
        @field flag (string?) the config key.
    @return element
]=]
function group:dropdown(o)
    local el, r, ic = self:_row(o, true)
    local multi     = o.multi == true

    el.value = multi and table.clone(type(o.default) == 'table' and o.default or {}) or o.default

    local val   = readout(r)
    local caret = icon(r, 'caret-down', 10, 'dim', { LayoutOrder = 5 })

    -- the open list: under the row, lined up with the label, on the raised surface
    local drop = new('Frame', { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy, Visible = false })
    pad(drop, 2, 0, 6, indent(o))

    local panel = block(drop, { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy }, 'elem')
    corner(panel, 2)
    pad(panel, 4, 8, 6, 8)
    vlist(panel)
    self:_under(el, drop)

    local search = new('Frame', { Size = UDim2.new(1, 0, 0, 26) }, panel)
    local q      = new('Frame', { Size = UDim2.new(1, 0, 0, 24) }, search)
    hlist(q, 6)
    icon(q, 'magnifying-glass', 10, 'dim', { LayoutOrder = 1 })

    local query = new('TextBox', {
        Size             = UDim2.fromScale(0, 1),
        FontFace         = jura(medium),
        TextSize         = 12,
        TextXAlignment   = left,
        Text             = '',
        PlaceholderText  = 'Search',
        ClearTextOnFocus = false,
        LayoutOrder      = 2,
    }, q)
    grow(query)
    paint(query, 'TextColor3', 'text')
    paint(query, 'PlaceholderColor3', 'dim')
    block(search, { Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 1) }, 'rule')

    local list = new('Frame', { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy, LayoutOrder = 1 }, panel)
    vlist(list)

    local foot  = new('Frame', { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, Visible = multi }, panel)
    local note  = text(foot, {
        FontFace       = jura(medium),
        TextSize       = 11,
        Size           = UDim2.fromScale(0.7, 1),
        TextYAlignment = Enum.TextYAlignment.Bottom,
    }, 'dim')
    local clear = new('TextButton', {
        AnchorPoint    = Vector2.new(1, 0),
        Position       = UDim2.fromScale(1, 0),
        Size           = UDim2.fromScale(0.3, 1),
        FontFace       = jura(medium),
        TextSize       = 11,
        TextXAlignment = right,
        TextYAlignment = Enum.TextYAlignment.Bottom,
        Text           = 'Clear',
    }, foot)
    paint(clear, 'TextColor3', 'accent')

    local open, items, signature = false, {}, nil

    -- where each option sits in the picks, rebuilt once per draw: a find per
    -- row made a long list O(options x picks)
    local ranks = {}

    local function rerank()
        table.clear(ranks)

        if multi then
            for i, v in el.value do
                ranks[v] = i
            end
        elseif el.value ~= nil then
            ranks[el.value] = 1
        end
    end

    local function rank(v)
        return ranks[v]
    end

    local function summary()
        if not multi then
            return el.value ~= nil and esc(el.value) or nil
        end

        local v = el.value

        if #v == 0 then
            return nil
        end

        if o.ordered then
            -- 1 Z  2 X  3 C: a small accent number on the letter's baseline. the
            -- space after it is set at the number's size, so it is narrower
            -- than the two between pairs and each number stays with its letter.
            local parts = {}

            for i, x in v do
                parts[i] = string.format('<font color="%s" size="9" weight="700">%d </font>%s', hex(theme.accent), i, esc(x))
            end

            return table.concat(parts, '  ')
        end

        return esc(v[1]) .. (v[2] and ', ' .. esc(v[2]) or '') .. (#v > 2 and ' +' .. (#v - 2) or '')
    end

    local function draw()
        rerank()

        local s = summary()

        val.Text       = s or esc(o.placeholder or 'Not set')
        val.FontFace   = jura(s and semi or medium)
        val.TextColor3 = s and theme.sub or theme.dim

        if ic then
            ic.ImageColor3 = s and theme.accent or theme.dim
        end

        -- swapped, not rotated: roblox draws rotated objects unrotated inside
        -- a clipping frame, and the window clips
        caret.Image = iconasset(open and 'caret-up' or 'caret-down') or ''
        note.Text   = o.ordered and 'Picked in order' or (multi and #el.value .. ' picked' or '')

        local q = query.Text:lower()

        -- rows are only written when their own state changed: one pick in a
        -- long list touches one row, not all of them
        for _, it in items do
            local n     = rank(it.v)
            local shown = q == '' or it.lower:find(q, 1, true) ~= nil

            if shown ~= it.shown then
                it.shown       = shown
                it.row.Visible = shown
            end

            if n ~= it.n or it.accent ~= theme.accent then
                it.n, it.accent     = n, theme.accent
                it.name.TextColor3  = n and theme.text or theme.sub
                it.desc.TextColor3  = n and theme.sub or theme.dim
                it.num.Text         = (n and o.ordered) and tostring(n) or ''
                it.mark.Visible     = n ~= nil and not o.ordered
            end
        end
    end
    render(draw)

    -- the grey text beside an option; a failing describe() costs only the text
    local function describe(v)
        if not o.describe then
            return ''
        end

        local ok, d = pcall(o.describe, v)

        return ok and d ~= nil and tostring(d) or ''
    end

    local function build(options)
        local sig = table.concat(options, '\0')

        if sig == signature then
            return
        end

        signature = sig

        for _, it in items do
            it.row:Destroy()
        end

        table.clear(items)

        for i, v in options do
            local b = new('TextButton', {
                Text            = '',
                AutoButtonColor = false,
                Size            = UDim2.new(1, 0, 0, 24),
                LayoutOrder     = i,
            }, list)
            hlist(b, 8)

            local it = { v = v, lower = v:lower(), row = b, shown = true, n = false }

            if o.keys then
                local cap, face, hit = keycap(b, v, 22)

                cap.LayoutOrder, it.name = 1, face
                hit:Destroy()
            else
                it.name = text(b, {
                    Text          = v,
                    TextSize      = 12,
                    Size          = UDim2.fromScale(0, 1),
                    AutomaticSize = autox,
                    LayoutOrder   = 1,
                }, 'sub')
            end

            it.desc = text(b, {
                Text         = describe(v),
                FontFace     = jura(medium),
                TextSize     = 12,
                Size         = UDim2.fromScale(0, 1),
                TextTruncate = Enum.TextTruncate.AtEnd,
                LayoutOrder  = 2,
            }, 'dim')
            grow(it.desc)

            it.num = text(b, {
                FontFace       = jura(bold),
                TextSize       = 10,
                Size           = UDim2.new(0, 10, 1, 0),
                TextXAlignment = right,
                LayoutOrder    = 3,
            }, 'accent')
            it.mark = icon(it.num, 'check', 9, 'accent', {
                AnchorPoint = Vector2.new(1, 0.5),
                Position    = UDim2.fromScale(1, 0.5),
            })

            b.MouseButton1Click:Connect(function()
                el:pick(v)
            end)

            b.MouseEnter:Connect(function()
                it.name.TextColor3 = theme.text
            end)

            b.MouseLeave:Connect(function()
                it.name.TextColor3 = rank(v) and theme.text or theme.sub
            end)

            table.insert(items, it)
        end

        search.Visible = o.search == true or (o.search == nil and #options > 6)
    end

    local function fetch()
        local src = o.options

        if type(src) == 'function' then
            local ok, got = pcall(src)

            src = ok and got
        end

        local options = {}

        for _, v in type(src) == 'table' and src or {} do
            table.insert(options, tostring(v))
        end

        build(options)
        draw()
    end

    -- the rows only exist once the list has been opened: a dropdown that is
    -- never opened costs its row and nothing else
    function el:setOptions(options)
        o.options = options

        if open then
            fetch()
        end

        return self
    end

    function el:setOpen(v)
        open = v == true

        if open then
            fetch()
        else
            query.Text = ''
        end

        drop.Visible = open
        draw()

        return self
    end

    function el:pick(v)
        if not multi then
            self:set(v)

            return self:setOpen(false)
        end

        local picks = table.clone(self.value)
        local at    = table.find(picks, v)

        if at then
            table.remove(picks, at)
        else
            table.insert(picks, v)
        end

        return self:set(picks)
    end

    function el:set(v, silent)
        if multi then
            local picks = {}

            for _, x in type(v) == 'table' and v or {} do
                table.insert(picks, tostring(x))
            end

            self.value = picks
        else
            self.value = v ~= nil and tostring(v) or nil
        end

        draw()
        self:_stored()

        if not silent then
            safe(self._call, self:get())
        end

        return self
    end

    function el:get()
        return multi and table.clone(self.value) or self.value
    end
    el._save = el.get

    function el:_load(v)
        if (multi and type(v) ~= 'table') or (not multi and type(v) ~= 'string') then
            return false
        end

        self:set(v)

        return true
    end

    on(r.MouseButton1Click, function()
        el:setOpen(not open)
    end)

    on(clear.MouseButton1Click, function()
        el:set({})
    end)

    on(query:GetPropertyChangedSignal('Text'), draw)

    el:_stored()

    return el
end






--[=[
    @class window
    the visible container: tabs along the top, the title and status line
    under them, and one scrolling page per tab.
]=]
local window = {}
window.__index = window

--[=[
    @class tab
    a page of groups. elements added straight to a tab go into an untitled
    group.
]=]
local tab = {}
tab.__index = function(_, k)
    if tab[k] then
        return tab[k]
    end

    if type(group[k]) == 'function' and k:sub(1, 1) ~= '_' then
        return function(self, ...)
            return group[k](self:_plain(), ...)
        end
    end
end

--[=[
    @method window
    creates the window.

    @param o (table?) the configuration for the window.
        @field title (string) the heading.
        @field key (KeyCode?) toggles the window (default RightShift).
        @field accent (string | Color3?) 'tan' (default), 'lilac', or a Color3.
        @field pattern (string?) 'dots', 'grain', 'hatch', 'sparkles', or an
            image id; drawn behind the content at `patternOpacity` (each
            pattern has its own default, from 0.025 for hatch).
        @field patternOpacity (number?) the pattern's opacity.
        @field scale (number? | 'auto') 1 (the default) draws the design at
            its own pixel size; 'auto' grows it with the screen, in whole
            steps, so it reads the same on a large monitor.
        @field size (Vector2?) the window's size at scale 1.
        @field id (string?) the gui's name; a re-run replaces the same id.
        @field onClose (function?) what the x does; without it the x hides
            the window.
    @return window
]=]
function library:window(o)
    o = o or {}
    self._owner = nil

    local gui = self:_root(o.id)

    if o.accent then
        self:setAccent(o.accent)
    end

    local w, h        = o.size and o.size.X or 300, o.size and o.size.Y or 396
    local barh, headh = 28, 53

    local win = setmetatable({ _tabs = {}, _key = o.key or Enum.KeyCode.RightShift, _W = w, _H = h }, window)

    -- a 1px rim around the window, drawn as an outer frame so it stays inside the 300px
    local main = block(gui, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(w, h) }, 'rule')
    corner(main, 2)

    local scale = new('UIScale', {}, main)
    local inner = block(main, {
        Position         = UDim2.fromOffset(1, 1),
        Size             = UDim2.new(1, -2, 1, -2),
        ClipsDescendants = true,
    }, 'bg')
    corner(inner, 1)

    win._pattern = new('ImageLabel', { Size = UDim2.fromScale(1, 1), ZIndex = 0 }, inner)
    win:setPattern(o.pattern, o.patternOpacity)

    -- tabs on the page colour; the active one sits on the window colour
    local bar   = block(inner, { Size = UDim2.new(1, 0, 0, barh) }, 'page')
    local strip = new('ScrollingFrame', {
        Position            = UDim2.fromOffset(4, 0),
        Size                = UDim2.new(1, -52, 1, 0),
        CanvasSize          = UDim2.new(),
        AutomaticCanvasSize = autox,
        ScrollingDirection  = Enum.ScrollingDirection.X,
        ScrollBarThickness  = 0,
    }, bar)
    hlist(strip)

    -- past the strip's edge there is no scrollbar to say so, so the side with
    -- more tabs fades into the bar. the fades sit on the bar, not the strip,
    -- so they stay put while the tabs scroll under them.
    local function fade(side)
        local f = block(bar, {
            AnchorPoint = Vector2.new(side, 0),
            Position    = side == 0 and UDim2.fromOffset(4, 0) or UDim2.new(1, -48, 0, 0),
            Size        = UDim2.new(0, 24, 1, 0),
            ZIndex      = 2,
            Visible     = false,
        }, 'page')

        new('UIGradient', {
            Transparency = NumberSequence.new(side, 1 - side),
        }, f)

        return f
    end

    local fadel, fader = fade(0), fade(1)

    local function edges()
        local x = strip.CanvasPosition.X

        fadel.Visible = x > 0.5
        fader.Visible = x + strip.AbsoluteSize.X < strip.AbsoluteCanvasSize.X - 0.5
    end

    on(strip:GetPropertyChangedSignal('CanvasPosition'), edges)
    on(strip:GetPropertyChangedSignal('AbsoluteCanvasSize'), edges)
    on(strip:GetPropertyChangedSignal('AbsoluteSize'), edges)

    local ctl = new('Frame', {
        AnchorPoint   = Vector2.new(1, 0),
        Position      = UDim2.new(1, -6, 0, 0),
        Size          = UDim2.fromOffset(0, barh),
        AutomaticSize = autox,
    }, bar)
    hlist(ctl, 10)
    pad(ctl, 0, 4, 0, 4)

    local function control(name, order)
        local b = new('ImageButton', {
            Size        = UDim2.fromOffset(10, 10),
            Image       = iconasset(name) or '',
            ScaleType   = Enum.ScaleType.Fit,
            LayoutOrder = order,
        }, ctl)
        paint(b, 'ImageColor3', 'dim')

        on(b.MouseEnter, function()
            b.ImageColor3 = theme.text
        end)

        on(b.MouseLeave, function()
            b.ImageColor3 = theme.dim
        end)

        return b
    end

    local minb, closeb = control('minus', 1), control('x', 2)

    -- the title, and the status line under it
    local head = new('Frame', { Position = UDim2.fromOffset(0, barh), Size = UDim2.new(1, 0, 0, headh) }, inner)

    win._title = text(head, {
        Text     = tostring(o.title or 'Untitled'),
        FontFace = jura(bold),
        TextSize = 17,
        Position = UDim2.fromOffset(14, 12),
        Size     = UDim2.new(1, -28, 0, 20),
    })
    win._status = new('Frame', { Position = UDim2.fromOffset(14, 35), Size = UDim2.new(1, -28, 0, 14), Visible = false }, head)
    -- whole pixels, and one below the line's centre: centred on 14 it landed
    -- at 4.5 and rounded up, and jura sits low in its line box, so this is
    -- the middle of the lowercase letters.
    win._dot    = new('Frame', {
        BackgroundTransparency = 0,
        Position               = UDim2.fromOffset(0, 6),
        Size                   = UDim2.fromOffset(5, 5),
    }, win._status)
    corner(win._dot, 3)
    win._statusText = text(win._status, {
        FontFace     = jura(semi),
        TextSize     = 11,
        RichText     = true,
        Position     = UDim2.fromOffset(11, 0),
        Size         = UDim2.new(1, -11, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    win._pages = new('Frame', {
        Position = UDim2.fromOffset(0, barh + headh),
        Size     = UDim2.new(1, 0, 1, -(barh + headh)),
    }, inner)
    win._main, win._scale, win._strip, win._folded = main, scale, strip, barh + headh + 2

    -- scale 1 is the design's own pixels, and the default: a settings menu
    -- should sit small beside the game. 'auto' grows it with the screen, in
    -- WHOLE steps only: at 1.5x a 1px rim lands on one or two real pixels
    -- depending on where it falls, so identical boxes come out different.
    local function fit()
        local cam = workspace.CurrentCamera
        local vp  = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local s   = o.scale == 'auto' and max(1, floor(vp.Y / 700 + 0.5)) or tonumber(o.scale) or 1

        while s > 1 and (h * s > vp.Y - 24 or w * s > vp.X - 24) do
            s -= 1
        end

        scale.Scale, self._noteScale.Scale = s, s

        -- whole pixels: a 0.5 scale on an odd viewport put the window on a
        -- half pixel, and each child then rounded its own way - the status
        -- dot sat a row off its text.
        main.Position = UDim2.fromOffset(floor((vp.X - w * s) / 2) + w * s / 2, floor((vp.Y - h * s) / 2))
    end

    fit()

    if workspace.CurrentCamera then
        on(workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'), fit)
    end

    -- drag by the bar or the title
    local dragging, from, at

    local function grab(i)
        if i.UserInputType == mb1 or i.UserInputType == touch then
            dragging, from, at = true, i.Position, main.Position
        end
    end

    on(bar.InputBegan, grab)
    on(head.InputBegan, grab)

    on(uinput.InputChanged, function(i)
        if dragging and (i.UserInputType == mousemove or i.UserInputType == touch) then
            local d = i.Position - from

            main.Position = UDim2.new(at.X.Scale, at.X.Offset + d.X, at.Y.Scale, at.Y.Offset + d.Y)
        end
    end)

    on(uinput.InputEnded, function(i)
        if i.UserInputType == mb1 or i.UserInputType == touch then
            dragging = false
        end
    end)

    on(minb.MouseButton1Click, function()
        win:minimize()
    end)

    on(closeb.MouseButton1Click, function()
        if o.onClose then
            return safe(o.onClose)
        end

        win:toggle(false)
        library:notify({
            title   = win._title.Text,
            message = 'Hidden. Press ' .. (win._key and win._key.Name or '?') .. ' to show it again.',
        })
    end)

    library:_bind(function()
        return win._key
    end, function()
        win:toggle()
    end)

    render(function()
        for _, t in win._tabs do
            t:_paint()
        end

        win:_drawStatus()
    end)

    return win
end

--[=[
    @method toggle
    shows or hides the window.

    @param v (boolean?) the state; nil flips it.
]=]
function window:toggle(v)
    if v == nil then
        v = not self._main.Visible
    end

    self._main.Visible = v

    return self
end

--[=[
    @method isOpen
    whether the window is showing, as opposed to hidden by its key or the x.

    @return boolean
]=]
function window:isOpen()
    return self._main.Visible
end

--[=[
    @method minimize
    folds up to the tabs and the status line, whose clock keeps running.
]=]
function window:minimize()
    self._small = not self._small

    local h = self._small and self._folded or self._H

    tween:Create(self._main, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Size = UDim2.fromOffset(self._W, h) }):Play()

    return self
end

--[=[
    @method setKey
    changes the key that toggles the window.

    @param k (KeyCode) the new key.
]=]
function window:setKey(k)
    self._key = k

    return self
end

--[=[
    @method setPattern
    a pattern name tiles; any other image id fills the window, cropped.

    @param pattern (string? | false) the pattern or image; falsy hides it.
    @param opacity (number?) overrides the pattern's default.
]=]
function window:setPattern(pattern, opacity)
    local img, spec = self._pattern, pattern and patterns[pattern]

    img.Visible = pattern ~= nil and pattern ~= false

    if not img.Visible then
        return self
    end

    local tile = spec and spec.tile

    img.Image             = tile and (iconasset('pattern-' .. pattern) or '') or tostring(pattern)
    img.ScaleType         = tile and Enum.ScaleType.Tile or Enum.ScaleType.Crop
    img.TileSize          = UDim2.fromOffset(tile or 0, tile or 0)
    img.ImageTransparency = 1 - (tonumber(opacity) or (spec and spec.opacity) or 0.06)

    -- a pattern is tinted with the theme; a picture keeps its own colours
    if tile then
        paint(img, 'ImageColor3', 'text')
    else
        library._painted[img] = nil
        img.ImageColor3       = Color3.new(1, 1, 1)
    end

    return self
end

--[=[
    @method setTitle
    changes the window's heading.

    @param s (string) the new title.
]=]
function window:setTitle(s)
    self._title.Text = tostring(s)

    return self
end

--[=[
    @method destroy
    unloads the library.
]=]
function window:destroy()
    library:destroy()
end

--[=[
    @method status
    the line under the title.

    @param s (string?) what the script is doing, in plain words; nil clears it.
    @param opts (table?) containing:
        @field timer (boolean?) a stopwatch from 0:00. the same text again
            keeps it running; different text restarts it.
        @field countdown (number?) seconds: counts down to 0:00 and stops there.
        @field idle (boolean?) drawn grey, for "not doing anything".
]=]
function window:status(s, opts)
    opts = opts or {}

    local keep = s ~= nil and s == self._sText and self._sMode == 'up' and opts.timer

    self._sText, self._sIdle = s, opts.idle == true

    if s == nil then
        self._sMode = nil
    elseif opts.countdown then
        self._sMode, self._sFrom, self._sLen = 'down', os.clock(), tonumber(opts.countdown) or 0
    elseif opts.timer then
        if not keep then
            self._sFrom = os.clock()
        end

        self._sMode = 'up'
    else
        self._sMode = nil
    end

    self:_drawStatus()

    -- one thread per window, only while a clock is showing. it sleeps to the
    -- next whole second of the clock, so the digits change on time and the
    -- label is written once a second.
    if self._sMode and not self._ticking then
        self._ticking = true

        task.spawn(function()
            while self._sMode and library.alive do
                task.wait(1 - (os.clock() - self._sFrom) % 1 + 0.01)
                self:_drawStatus()
            end

            self._ticking = false
        end)
    end

    return self
end

function window:_drawStatus()
    local s = self._sText

    self._status.Visible = s ~= nil

    if s == nil then
        return
    end

    local colour = self._sIdle and theme.dim or theme.accent

    self._dot.BackgroundColor3, self._statusText.TextColor3 = colour, colour

    local str = esc(s)

    if self._sMode then
        local t = os.clock() - self._sFrom

        t = self._sMode == 'down' and math.ceil(max(0, self._sLen - t)) or floor(t)

        local clock = t >= 3600 and string.format('%d:%02d:%02d', t // 3600, t // 60 % 60, t % 60)
            or string.format('%d:%02d', t // 60, t % 60)

        str ..= string.format(' <font color="%s" weight="500">· %s</font>', hex(theme.dim), clock)

        if self._sMode == 'down' and t == 0 then
            self._sMode = nil
        end
    end

    if self._statusText.Text ~= str then
        self._statusText.Text = str
    end
end

--[=[
    @method select
    shows a tab.

    @param tab (tab) the tab to show.
]=]
function window:select(tab)
    self._active = tab

    for _, t in self._tabs do
        t:_paint()
    end
end

--[=[
    @method tab
    creates a new tab within the window.

    @param name (string) the tab's name.
    @return tab
]=]
function window:tab(name)
    library._owner = nil

    local b = new('TextButton', {
        Text            = tostring(name):upper(),
        AutoButtonColor = false,
        FontFace        = jura(bold),
        TextSize        = 10,
        Size            = UDim2.fromScale(0, 1),
        AutomaticSize   = autox,
        LayoutOrder     = #self._tabs + 1,
    }, self._strip)
    paint(b, 'BackgroundColor3', 'bg')
    pad(b, 0, 9, 0, 9)

    local page = new('ScrollingFrame', {
        Size                = UDim2.fromScale(1, 1),
        CanvasSize          = UDim2.new(),
        AutomaticCanvasSize = autoy,
        ScrollBarThickness  = 2,
        ScrollingDirection  = Enum.ScrollingDirection.Y,
        Visible             = false,
    }, self._pages)
    paint(page, 'ScrollBarImageColor3', 'rule')
    vlist(page)
    pad(page, 0, 0, 8, 0)

    local nt      = setmetatable({ _page = page, _groups = 0, _n = 0 }, tab)
    local hovered = false

    function nt._paint()
        local active = self._active == nt

        page.Visible             = active
        b.BackgroundTransparency = active and 0 or 1
        b.TextColor3             = active and theme.text or (hovered and theme.sub or theme.dim)
    end

    on(b.MouseButton1Click, function()
        self:select(nt)
    end)

    local function hover(v)
        hovered = v
        nt._paint()
    end

    on(b.MouseEnter, function()
        hover(true)
    end)

    on(b.MouseLeave, function()
        hover(false)
    end)

    table.insert(self._tabs, nt)

    if #self._tabs == 1 then
        self:select(nt)
    else
        nt._paint()
    end

    return nt
end

--[=[
    @method group
    creates a new group within the tab. groups are separated by 6px of space
    and one line; rows inside a group have no lines between them.

    @param name (string?) the group's heading; nil for none.
    @return group
]=]
function tab:group(name)
    library._owner = nil
    self._groups += 1

    if self._groups > 1 then
        self._n += 2
        new('Frame', { Size = UDim2.new(1, 0, 0, 6), LayoutOrder = self._n - 1 }, self._page)
        block(self._page, { Size = UDim2.new(1, 0, 0, 1), LayoutOrder = self._n }, 'hair')
    end

    self._n += 1

    local box = new('Frame', { Size = UDim2.fromScale(1, 0), AutomaticSize = autoy, LayoutOrder = self._n }, self._page)
    pad(box, 10, 14, 4, 14)
    vlist(box)

    local g = setmetatable({ _box = box, _n = 0 }, group)

    if name then
        local h = new('Frame', { Size = UDim2.new(1, 0, 0, 18) })

        text(h, { Text = tostring(name), FontFace = jura(bold), TextSize = 11, Size = UDim2.new(1, 0, 0, 14) }, 'dim')
        g:_add(h)
    end

    return g
end

function tab:_plain()
    self._plainGroup = self._plainGroup or self:group(nil)

    return self._plainGroup
end






-- icons
--[[ICONS]]
icons = {
    ['caret-down'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAd0lEQVQ4y+3QsRGAIAyFYbILFWzkKA7gALqkTPHbpOA8IcHKO3mdR95HMISZHwUIwALEgU7UTvMQ4ASSA8tA0U58GgjA7kGBpDNopzkowNFDdbMaE+spdzS/xhpoUaj+Z36ss+n4ZgbqwsybFFj1cxMRrM7Mx3IB6i7y4OzIVicAAAAASUVORK5CYII=',
    ['caret-up'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAc0lEQVQ4y+2OsQ2AMAwE37ukSjZiFXoWyJIwxdFEAiGHBGgQ4iRXfp9f+nkd1goAJmmUhKTJzLj9DTAgs5HLg8eyucw96UG2AKnMclnqNEu7XbrU1JFFJxO7pIBashOpGwo9soo01BoO7rIuDeWm9+TnE6x2vPPkWahgFAAAAABJRU5ErkJggg==',
    ['caret-right'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAYUlEQVQ4y+XUsQ2AMAxEUcMsoYGNMgtTwJIwxadIkCjo8pFAXG09+WTJEZ8NEEACNDBTsgKdASZgs9Hx3+gE7E+g56bz3Uzf4puVl6bKNna9sLKZhg1azQpmDaug+75ekwPzy+1PGqtVrAAAAABJRU5ErkJggg==',
    ['check'] = 'iVBORw0KGgoAAAANSUhEUgAAABIAAAASCAYAAABWzo5XAAAAaElEQVQ4y+3QsQmEQBRF0cEWtgJLsgAzA2NzA5vYMixFOxAbkWNgMhi4MCqI7M3/4fNC+Hdb+KBHcRYZbNVXIB2ejCDgi/IAGX9+ggwTFlRJSHSQY46x5E12WHNq2AiTjOywAW0y8p5WczTmHTMqJssAAAAASUVORK5CYII=',
    ['minus'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAL0lEQVQ4y2NgGAWjYBgCRhjj////kxgYGGLJNGcxIyNjHgMDAwPTQPtoFIyCIQEA/isFBITvUhoAAAAASUVORK5CYII=',
    ['x'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAgklEQVQ4y+WUQRKAIAhFnfZ6C7snh8Nr/RbRjJkSGatip34e/EEN4d8BIAMgAMmgTaJdNRFhD9agAmPRkgaMlbALbWB866ZJKHWCnBUzbJBYZH3Zezqgthuehg3sm2wuU5VedOdj2XUortfGcmk7mqgB3Z/e8TmMq56hBCA/GtD3YgNRMYKufJe4ngAAAABJRU5ErkJggg==',
    ['magnifying-glass'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAABT0lEQVQ4y62SPUpDQRRGvzEaFDRgF56NWmcDQaLuwlYSsgDdgXUaIY29likEQVdg0DZpAmlULGJhCi0C4vPY3MCQvJ8RM83lMeee+72ZkRa8XNoGEEmqSYokTST1JT045+I/TQC2gQ4QM79egAaQGsTNyPYk3UjalPQm6VrSUNK6pANJh9ZzJek4M60lG1uSc2AtgakCT8a08n61M5XlcDs2OAYqqRdgwCgpWQJ/YsPbacCRAReBF1c2vje7t2Q1sjoMETrnRpI+JW2lCSdWNwITLkta9frmhH2r+yFCSVVJK17f3MSCPdofoJqTTsCtnWE9C2wY9AzsZsjOjBsAxSyhAy4NHgOnQHl6ZkDNSwbwCJTyDrsAtIBvr/ED+PK+ByYDuM+VmrgCtIEe8A68AndAHSgCJZOFSwOG+tIuEPTkQqRdkzb/LfSkzYUkTFq/aHOc1v7e8H4AAAAASUVORK5CYII=',
    ['arrow-right'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAcklEQVQ4y+2UMQ5AQBBF/0pEXMFB9jY6l+AYegU9zuM0T2ELChLZqZZXTTF5mfnJjPRzB+CBDsithCMHi4kUqIAtSNdvSy+ZulNTL6l+4S0klaEenHONJGXR44Z5LFeeo3J8yi8hWRBO1qfngdbsOaTDDtaowpuzm7HHAAAAAElFTkSuQmCC',
    ['gear-six'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABhUlEQVQ4y8WVMU4CURCGB6OdDQdAExKJoBgiNhr0FtTcgKvAAdSCjgYKbfAKiqV0UmBpRUGQKJ8F/8ZxWcKKGCd5ycs38/7Nm5k3a/YfBqSBbATfB9KrCOaAW2AKfAANIKXVEJsCN0AurmgFGDOzCfCu/UgLsYn2Y6ASR7ivAy1gFzgC7viyDpCXry3WjyM8UHDeMQPOgFPAx+YVOwjrbEZoJ4JzjhXN7ET7NzN7DMUkbJEBSaDmcpoBtt11vbXky7ic14FkWLQMvLqD17p+IDoCmlojJ27ApToEaZS98JMcD8CFWNGJFlxswYkfi5WAe7GeFx4KphyrijUj0taUr+pYSmxoZraxvLN/YUDPpaL0g1QUxc51di4VvnhTFWRZ8dqKuXJF/1481271mO3Wlm/PtVttrt1CHwhe3qFjRRWzGlxf/ECxL2GdqJcX9Zq6ZrYl1nU8iJnGKeSzu+4us3nQcWkIhtCOHgnEHEIV/mJsSjzHbIivb9CHPrDo15RllV/TOuwTM3RFvsdUp5EAAAAASUVORK5CYII=',
    ['sliders-horizontal'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABHUlEQVQ4y+2TsUoDQRRFz0jsgoKIIrFLQEEQBe2sLW3yEX6ARWoLO3sLP8BCaz9AsLWzCGwqowgiiqJFkBwLZ3GJ67KSVMEDU+zM7JnLezz4JxKKDtUJYAXoAe0QQilpIeqSeu03l+r8nxOrAagDlbh1AqwBT8AkUAXOgb1fXB9AJ4TgYMKWP3lXZ9Rly9FKfZWMOwFuM3tzMekqsJBJ9ViQOClT49OcRIejaF5VPVIf1Dv1QK0MLR4f1G31Sn1VL9SNUUjX1d5AQ5/VWtFPTbWr3heslyg7U+txGlN5V22mvmyXG0CNciRAB7iJ39NxNdILRSOdxxZwDMjXMC0CfWAHaJM30iVrjLqfqfObujt08zIPzKqb6tTIpOPLJ0zENu1y2qkrAAAAAElFTkSuQmCC',
    ['house'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAA6ElEQVQ4y9WRMQ6CQBBFB5TSxspTkFDbWHoHTmAiXsCEQ0DBiWy5hQW1hSFRv4Wzum6GZRdIjD+Z7GZ2/uNnIPq1AMQA4qmhOT7Kp4Y+uMbDDeieaxzchGr94XADmgnvmTfcgB4sc+7wvqSD4ABSaacOcH3nqTRQ8WPh9UNe3oK9leqFwtzZFyx5Qts0gAhADeBqVA0gsnnnPUmWRJQI/YTfmi6jNbGmlohWXK2LoS/xeytBEDS8HrgYXBN7S0q80UItLN4MwEV5bOA7n1suXTfhfhQ+phhf4JLPmWA4afcdEa07oCX9rZ7R2i22j9MpfQAAAABJRU5ErkJggg==',
    ['user'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABX0lEQVQ4y82UwUpCQRiFZxJd6E5cSIggLkJ0dVdtgrCVyza16zmEFj5AQo/hK+gDJCQtWha0KSREVwkupPRrc6Jh0tvcIuiHYbhzzvlm5s7ca8wflQ0xAbvGmD093ltrn381K9AEhnytIdD8KbQNrAVaArdqS42tgXZS6KkTvgTyjpbX2MekJ6HQDDBWqBPj68gzBjIh4JYCj0A6xpeWB6Dl6zsbMpH6gbX2dRtY2sDLxIKz6ucBb27uZWLBT+obAeCGl9leQAVYAW9APcZXl2cFVAIWYQzQ06HcAeUNelkaQC8IqmABeFDwBegCx2pdjSFPIQnYAGfOR7Cp1vIEQ0tA34NMgRu1qaf1gdJ30AiYKLAALoCauyrtpiZtIe8EiLZBq8BMxlHISesGjZSZAVXfkAKuZbgCcgnOI6cMYqRc8dCZtRh8yp/5orPbfVfI6hodJYU6jAPgPO7H9b/rHQmTHKsZ5OgfAAAAAElFTkSuQmCC',
    ['users'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABo0lEQVQ4y+3TPWhUURCG4bmLboRgQuxttJAlCCLiFmIKa7XQ3kKwsbAQSxEEC7HUWmstJNgoiKCxjSnEWFhE0IAgm+APRgkhPhbOusfr3RCwzTQH5v3mO3fmzonYioyqKYltEbEvIkYjYqGqquUa3xUReyNiJSLeVFW1vuEtaOMKlgxiHY8wmZpjWCt4D5exfZjpCJ4UBUtYSGP4hikcwddky4X+MdpNxtdS8Amn0Mr8bjxM9gE7i5oWTmcNXK2b7sCXhMeHdPM6+fkGfjLZZ4yUoJvgHYaN6mJq7jawwPvkhyMiWsn67fWqqnFRIiJ6Ne1gtX7X/MX7xm/z7GBsiHE3z4WGLx6PiE7N608rL7KV26hqhV38SH60xircSTbbNMOpYj+f4QxO4Aa+Z/5eoT+Ymplka/VL+8I2pg2PFRxI7X78rPHpf/YYHcwXolW8wiw+1vKXMIYHqVkt+Dw6fdNJgye8iLMYrc3/EO4XBtcLPpo1i8WLnQzMZeI5JmKDwDmDJz5VYxPFvOcCt/JnjccmAhfwEnua1g5PcXMzXlvxf/EL+k6V3WCFf1wAAAAASUVORK5CYII=',
    ['eye'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABKUlEQVQ4y+2UIW4CURCG5yEIcjG43gC5d0BxiBWgwK2sohfgDtT2BGCLak1tZRMgDQKBIYF+Nf82k1c2m802Ne0kz/z/zD/zZuY9s3+ThSoHoGVmN2bWE/RuZm8hhI/a2YAADIEH4MB3O4gbApXFFaIp8BQJHYFXnWPEPQNplegIOClgD9wBfV+VbtMXt5fvCRiXiU5cFfdAV3gHyIGlTg50xHXlW9g0Fh0AZ5G3gDnR9ZUePzpxUwzABRgUwQmwETGPEubCd0CmsxOWR75z4VsgMWAm4AVoR84rcZnDMmHLyLctDYBZq/Yu1tjZROX/VCs2QOKHd6kxvHXJ8M5fw3MZpy5wUbJuqyvrtnBxk7K2jBs8kFFVz1M9U2/NnnRUVaNP6He/zb9pn7eDzAt0HH3GAAAAAElFTkSuQmCC',
    ['eye-slash'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABk0lEQVQ4y9XUPWsUYRAH8NkrrgvcgdjGFHaSKpbaRgRRG7+AmsrUIl6apLQwvhRaR9AmpY2fQRtLAxYWSSMoGBQlyc/iZvVxud27gE0GHljm5T87M/+ZiBMtuIF76P1v4I/G8gSlfojz+eaPnRjXcZDgo9QFPvlXvmIbV1DNCv4gg49wO3WvsJNvv5HkHZamga7gVxF0gGsNnwrnsIHP6fez/olJoKsF4As8y+/vuNASM8RWEXen6bCMwzSuZV97eJm6L1hsAQ+MigqXa8MAe2l41Ajq403adrHQ0cbNwm8QWE/Fe/QnBMzhbfp8wOkW4H5iwPpUPlZV9S0iLkfETkScjYjXmJuEne9PprIVmx2lLmSZsj39hv1h2vYwmDS8Ubl1jeDFHKQcbC/1N1N3iEtddNvCsAX8In6k3+NkxVou1GrbH60k2SX5N3IZqsKnV9AL7ufSnOocFpZyTUvZ71jpI9yaRoIavDI+MNvGB6cp9RF6XizG1ZnAG6XP+3s2zxRDCzytOX4s4BkT39U4VidPfgM0QdavQMk+QwAAAABJRU5ErkJggg==',
    ['star'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABmUlEQVQ4y8WUsWpUURRF180MogiZZpQUaS1iEUgUpvEDUvkFTmMgIkIqawVrSwst8gOWNtpHGCMkaC2WFnGmiBBUFLJsdvAyTF6eIeCBw32cu/Z+593Du/A/Qx2on5OD8zQe+TdG52W6EsPvSdWV03RzLbzvZ32ZrGtn7ranHqbLQdLUek3a7pTRBaCfvALcBi4Du8BOsF3gBvBEfQVMgDEwKaX8mu7sjrqvHjk71it2/QTmKB5DgBL4azoE+FF3AXwCHpZSfoa9CDwFrlVf1gcuRT8upVw97mInb/2iLp9hFsvRqr6vNxbVD9n4pq79g+laNKof1cVpYF59HeC3utHC9F5Y1Tfq/ElgV31eDWTYYDqsuBdql6ZQUbcj2GzgNsNsq63OrKjjiFYbuNUwY7W0Mb5eDbGT2oK6lVxIrVMNbamN8UY1jDn1gXpQnedBap0wzhr0rEvoVtZD4B3wDOgBb5O91EZhak1jx3tTv+pEvZuzL3meTDF7bYwfV//+ltqfwfSzd3y3PGpjjHqzzUDUpbCn+p5b/AGq1UTQ+W1WdQAAAABJRU5ErkJggg==',
    ['heart'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABXElEQVQ4y+2UsWoCQRCGFwURzBU+gJ1Y5QVEME1KbQR7iwRSWJl0lhbBLqWVhXmGPIK9rZoIFnkCCwNyfmn+g/HYE71LmYHljpl/vtmdm1vn/s1nQAl4BubAN7AE3oG60dTlW0ozB16AUhK0Bqzx2xF41TomaNZALQ4NgC8JPoEecAs0gQkQGkAoX1OannIQI7DgoQJLoOw5Td+A+554WbkAQxtYyNlNaFMO+NDKJWi6YiyscydnJcOHr4ixc865qPpez5sMQxXl7i042v59BnCUe9KKRzMyhRRtKJhRfbCBIrBVYJQCPFLuFijGgy0Nfwh0roB2lHMEWkmisSr/AO0LoG1pAcbnhDlgJuEBeAJ8OqfYQdpZ0nzbpLx+2cim9oLRRTU18QmQv7RvDhiYHa2AO62VOdHAd6JLCjSAjbnhopttAzSuJ57CA+BNOzzoPcgEjRWoAtU/A6a1X+Z4VEPQ3G2XAAAAAElFTkSuQmCC',
    ['shield'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABEUlEQVQ4y+2UMWoCQRSG3+g2IvEEASvTW3oBz7CElLlBBMEjCLnBYhlsPIxdklqExNrA2nw2/+LsYHR2rAL5YXnDzPe+3Vl2x+w/iqsGwL2ZvZnZQ6Lr08wenXOb2iww5/bMK1/mue9UX82saPi0z2b24jlq4io759x7EyuwC+daie/zav62uFTtJHg6gaMm3qr2E8T9wFETr1VHCeJR4DgF6AJ7fejDWCMwVM8e6P4GLQStGohX6llcggZAKTCPkOZiS2BwDZ4J/gHGF7ixGIBZzNZawFINB2ACtL31tuYOYpZA3P8AZEDhnVprbTvXuEoBZFFST27AE/B15nj81lojZ3iDHjAFPnRNgV668cYcAahFVlhl4jFaAAAAAElFTkSuQmCC',
    ['sword'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABiUlEQVQ4y9WUPS8EURSG30GFQmQ1bGUrCT/AVhqJYhOJ0i7ZUFGp/QOFikStIEIjISTrD+g2dFYUKxqJRBBU49GckZMxu2YUEqeae869zz0f71zpv1mQ9QAwJ6mYEAolbQRBcJU5C2AG+KC1bUZ7uzJARyVtW5W7ki5deELSlKTOTGCgX9KhpF5Jp5LmgyAIXVwG/rKOFNBOSXuSCpIakmY9tJX9CJa0JmlS0rOkaUk9wBGwmLaNUYbjQBnoBio2lBAoAUNAw3zHUUXAjvm2WkGX3NTrwJt9r8agDVv3ASfm+zApfoMuOOirk9A+kE+AjgBX5nsBZlplexdpERgF7m19ngAtAU/muwHG2vW2ZhubwHAMHkHz1pbQfGcmxbZDywEXDl5IyPzAXbQOpPvBgBV38DYBDvAOVLLIrOpKfGgDrwPdaaFFB10HBmLwqOeRWsppwct24BEYNLi3JrDh9DqeFpwDrh0cq2DFDTSCLqXur8HzDh4CVXdpzXSe7X2IZb4MFH8F+Av7BLYnqh3xc0+4AAAAAElFTkSuQmCC',
    ['crosshair-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABHUlEQVQ4y72VMW7DMAxFv+wl8NI1QzejyCV8Fx8jOUkMFDlFrtO1S1APXYI2Gfq6UAXrRrZru+Uk8FNf4idFSX9kYSgAyCQ9SLo317OkpxDCx6QTgRJogJaf9gLsgfI3hAHYARdH9JpYvwNbIIwhPbiNR6ACCucrzHd0vsdecrspwBWonX/lSFbOX1sswLZP05h+3cFy07oF8g5WO1nKW8RNTD9x8BpYJ7Aoy74LZK761YQOqly3ZB7YuIoXpmk+gjC32MJ1y0aSInts/jtJZ0lvkk6p1KM0kk4We7a9X1yZ5hlDKS0uxdLFa78Vz8Al2q25Bc59IJfkUJr5pHd9Wk0dQoexE27s2LxY7OCH0dU8Nehbw5KD/v+/prn2Ceh8rUCHkznyAAAAAElFTkSuQmCC',
    ['target'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAB3UlEQVQ4y72VwWpTURCG/3MrXbmpUFDS0oJNFde60XanrvMA1b6GLSUFwXeoBdFHsK7rG8TuFBt3UtC2xgpuTKF8XWQu/JzkJG504JB7Z/7zZ+afuedI/8jSJAAwJemWpEa4jiR1U0oXGW5G0s2UUmcS4TKwC/xk2HrADrAU2AZwGLG7JcIK2ALOjegXcAB8AM7M3weeA9147wLXSqRvbOM7YBWoMsxKxNy+AI1StlsBOgfWM7LFWJWV/91I58ZpWpe/Hr5pYBs4scxOgBdWfpk0SHbr8o30vRH+jpWXPwfMAx+BZ0MjZd1fDd+2TUAr5JgHTq1RjcDeC98P74eAOxE4C4LKym+Zpt2c1HpQJ3bbiR+H8yDeF638CkjAJ+8+MAvcMI5OxB9K0pXaX/h1u5D0WdIjSd8kfZV0FbieUvpTatwoKY4zKSobtVbEjg0/UoqpaBLASvjaI5pXxXONbQf2gWGrPOuXEdyzcdsfM277wHRg34ZvZ5QcTQbfPsBTI2+bLHX5bSNdC38faJa03jDQk2ycFmL5ubFmyWyO+/oS8Mqy2wv9qgxz38oHeA2MP9tj44ZlQnS8E8vP5z6wOZE0+4MlBod5j2HrRbObpf1/ezUta3A1JRWupv9ml0R/xiTWRNSwAAAAAElFTkSuQmCC',
    ['lightning'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABV0lEQVQ4y6WUsUoDURBFLwFJQAKpxB8wVeqAkEYCqYJF0miZH1DS2dgkn2D6LbQRK38g+Q21sgxKsFGQoHssvMGXxSzZ3an2zZs5szNzeVJGA6rABOhmzU2DVoApvzZLiy1lgO5IupV0ZNdzYTBQkhRJOg7cj0Xbl2cK8Aks/N0rCh4b9AX0gbnPjSLQoSExMABqPn8DlbzQgYEAQ/uaPr8B9TzQvlsHGAX+Fn8WW3qnQHkbaMdLArgCkvdt4A5YBkVegfM06CHw7uBry2xT7D5w6XkDPIT3ycRI0q6kWNKTpL2U5l4k1c34kDRI++Mzt7WypdtuJ+LkMa203dlmxmXgxIuJgyKtIGYUantLTawVObC0AJr2rWk7M9SQSrCc2n/azgtuGDJPaHucG2pwz6BFoO1JUtt5wBes202atrOAowB678e+uAEzQ6e5X7MN4K5nWs2a+wN37g5UmxaIbwAAAABJRU5ErkJggg==',
    ['sun'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABb0lEQVQ4y7WVsUoDQRRF71tSJLIWqWOTMqCtoJ1oor2flS+wNoVprPUPtFMIBNII/kAKgxEJHovcwLKazSj6YJi3O/ce9jHzZqXEADpAJ1WfCq0BLx61FE+SyLq8kC82GbLSl10A90CrpHuX9OzxXvK07LmoKvmOZUyAvLS2BWyV3m1bC3BXBW5Z+OZcQA8YAA8el0DXazvWTr6p8gs8N7QBDFkfV0Dd2lwp4a9ZQedAHzgBjp3PC/DE/V+CewXowTfrBwV4twpUc1mZnwc29Ss8fWsu/ZyZUZOkzN00lTSX9OSd37X/pqKwW8979jyZMQU6mf4psogYS2pKakhqR8SrpJHXzyq8p55H9rTNaJr5q807LGxeL7mMiuN2Ujpuw+Tj9oMGGVqzuUESW3rgdyv95pb+xSWUr7uEyvfxo+fziJgVAJmksfN2RHxIUkTMgCNJ1wVverijVlFP8aT+QRaSZoX8b8ARsQD2V3mK5xPsrT2oapvkvQAAAABJRU5ErkJggg==',
    ['moon'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABgklEQVQ4y9WUsUpcURCGv7NIMCgoZhUfIGC1pLSMhYJFKtk+Ngp5A7ttrIyCVbS1C2lcsLeRWARiCGki5AFignYxIbL7pRnxcHfdvbiCZJo5zJnz3Tn/nLnwEKaOqqvqljp6H0DUZfWHN7Y4KLSi7tpp04OCNwJ0pa7H+q86EPS52lZbal0dD3BLHRoE/D5A25nWFxGr3RU6E4DfajWLNyPeuCv4VQAOCvGliP9UJ8ryKtn6afjPhZwmcAJUgb2yWufgx+F/5QkppTawHPEXwH6ZynPwefiO95pS+gIsZfBTtaHW1KFo8rS6qI4UNa6Hlic9+lBTPxYGpxXv/NpeFw+NqZexOdsDXomGNtXzLhO60u3QTmx+UB/10zEkGM8m9KxDikicyn48b0vC6zH+qi97Jc7FkFxXPntLXlXdDo2N2940/DY48A6YjNAn4Aj4DowAz4B5YBgQ2ATW4mn2veKU+iZraDc7jiI6LJX4wBiwEFU+Af4A34DDlNLXvhX+N/YPTQfsHrlSs+cAAAAASUVORK5CYII=',
    ['fire'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABoElEQVQ4y8WUMUtcQRSFz6iIREFBLERkje6KkDZNAiLaBlshYOFPsDEo+Q+ClY36B8QUCqIQO7HYQrHQcnEVwSKF4iJRIp/NWTI89+0+QfE28+bec76ZN/fNk947gA7gFNgBul4TPMP/OAZ6Xgu8Z+iDxyOg86WQZmAWGPW8H3gE/gFfgXPDt4Gml4B/2vgXmATmPd91/RNw49xCVugIcB+d5z1w5efpSDcVLT6cBbxhwy9gLVrgFmhP0a43gg5FZ5kHmoBlm1dr6PPWPgIf64EXDNmKcsEN+5Di2bJnPs4nOzrmcbOaCCEQQjgIIdyl7Gcz4a0Jzns8ztBnJbSFeuDq61Ya9GIcWHQzKwmvJKkl4fkjqVdSn6TTFGibpBVJg5K2JYXIm7rjosdvKdDPknYMvZC0H2mLSgtgIvpmczXq1dt2DXwBctYCTNQDC/ht4SHQnaj/AJYM7LYGe1Q3/MO5tKEMfAdao3qrc2VrLoF+ZQmgAJxE17ni3R36uRonQCETNO4+MAeUeB4l19rS/CHDAvJXMODUmaRSCA2tbxNP234g5rYsBZAAAAAASUVORK5CYII=',
    ['drop'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABlElEQVQ4y7WUTSttURzGn4UiBiipW+R4ORgY3onRzRn6APfqfg+UfAIDZe4bKGXipTAyMhCKgcHJS2YSrgGhn4FHVsc5+6xz5V+r1f4/z/Pba++1WkEJBTRImvbjXAjhKSVXDdoObPFR20D7V6GdwIGB1x4Ah0Dn/0JbgX2DzoBhjzP3DoC2WqF1wJoB50Au0nLuAWwA9bWAZxy8A0bK6CPWAGZToUPAg0MTGb4Jex6B4RTwkgPLCd7lJC/QC7wAz8BgAnjQ3hegP9bqSrx/3FsPIZxUA9uz7szvLPAvzytV/9lHrZRky4Lzng9rAL97B7LAzZ7/ZZGAMWAeaIm8zbGnoSRzJemHpC5JxxWgTZIWJfVJWo0Wd5W14l3P4xWgP/W2WX2SLiTtRN5dVSqg4HN5D/SU0W+t3wCjQI+9AIUssIBNG/eAjhJ9ClgwsMMenFFmAd3AZXQB/QUaI73RvfeL6BLoVkoBeeAoutzvvbq96NOxJ58EjXcfmASKfK6itaZK+ZDwAvkU5Nw6lVQMoWr0e+oVe+/pB2o85KEAAAAASUVORK5CYII=',
    ['snowflake'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABaUlEQVQ4y92UwUoCURSG/ysuJFBaarucVS0EH0B6gVy1LQqiXZhEusqeoVYtWtlrGEJP0CLsEYIWJhTtzK9FRziM46C4iX4Y5p5/zvnvP/eee6V/B6AJHLn4EGiuKpoHJvyibQ/GFZYVKwEdoGTxBbNo2bcicAkUFxHuWPGN49pOtO34a+OuFhHeteQXx+WccM7xA+PqcZ1MTDSSVLZwC6ilGKhJ2rZwEyjPS2wkrOUEuAcix5WBrttUj9OpXtZpDyW9S3qS9ChpQ9KJpANJey7vWdKapG9Jd5JeJe1IqprGQh1SAfoJzvpAJa02s9AMqwA4BkbAg7XcLTA2h1/O7XQ8tpyO1QyB/SThpIOQtHmRcUmbdzbPdRTrjprxM30M1LygtWrqktQteeC41Q6IoWrvnuMabux/txerSXUcv4RaCWvZSspdplMKzL8282m12bSPIYQP4FzSKITQtcneJK2HED6Xcvnn8QMq0kiu+yadHwAAAABJRU5ErkJggg==',
    ['sparkle'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABlklEQVQ4y63TsUuVcRTG8dsVBbHVze6Q0BZxcXBxabCxxpYbNTY1KYYgTeISSFNDuTU0SpNYW39A4NSWloHYUCEGQfJp6Hnh18u96r3es9x7fu9zvu/5nfO8jcaAgQdYQ3NQRi/wV//i2rCAHTzHr4Bf4wlG+gWNoI3Lyb/pHtf7gTawlcJ9TOImlnCU86e4j766nal1tVA8+5yzq8kf4T0mzwN+luKD/O5UneEWHuZWd7EXzQu0ToOO4jDiOzjO/3ZNd6XLvF+eBr4d0R6aeJV8vaa7hMfFrd7gRjfgVJbzKcLVnM8nP8J6nFLWreHLf2PAWPy5jT/Flb5jurDdh9qVd7DQc2HYLMQneIt7mOji6fmM5bio2a98Xgf/iOA3FjF+hluaWehBAW93E66k0yp+YgNzNd00VgtrVbGl1yeNFpbxsVY0l+cTmXkVh/H5jPN8dTH8LN4FsJHzTvLdjGH0bFr3F8wWYxnPQmFpIGCt82osi9nBCaYuBA58uXALbF8YGnCr5pbOUMCBr8TnmxgbGnjQ+Au82vR8S+1sGQAAAABJRU5ErkJggg==',
    ['leaf'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABm0lEQVQ4y+WUSytFURiGn+UykBSZHZKJlPsPkFLIbaSkFBMjEwNDxUS5FAOlmDA+TAwYKJL8AUZyjWLikk65FnlNvlO70177HEP5Jrv1vu9++r619trw18r9JiwpG6gGaoByoBjIAwQ8A4vOudtMYVmSuiTFJSUUXTPJ93LSQDuAOaAqID8Bh8AlcA+8AU1AO1AQCZaUCywAwyY9ACvAOnDknFNK/tvAzgu2fYwDPcAXMAtMO+deI4bLt+d71Pjjtl+vktpC/BJJW5KGAtqyvTPmg5ZKerdQn8c/M38zoO+Y1u8DT1hg19PpufmnkmKmO0mPptf5wPsWGAiBngWgJQGvwfSEnU8o+NpCDZlAzZ8yby3q4JLgelvHDOaD5ku6M787CnyQPDjr1Au1/KT5x5KyosDJsbZTxo+FZFskfVqmk6iSVJty932d9kp6scxSGCv15j0BCaDQ1ldAo6QTW9cCg0CrrTeAkXTdxgLjp/uLfdg3n+3jBTseBSqAC6AZKAL6gUagzDLXwB6w6py7IZOSVClpPmxP/0f9AFZ8DKryuoDDAAAAAElFTkSuQmCC',
    ['map-pin'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABqElEQVQ4y8XUv0vVYRTH8XNDCTTdaotADHFxqbWCiASFoBYnR/+JIlwMHMJW/4UgIdRJEFpcqsFL/4G6VvQbRHy1fC59Eb3XH0MPHA7nPO/z5rnf5+FW/Y+FMSyhjW+Jdnpj5xH24yUOnLwOwvSfRbqe4UO8xjRuJKbTOwyzfio5FjPwHZNduMkwsNhLOoL9nGYqvWG8wMfEAoazNxV2HyPdxAs5wWrqK9g+5vtuYzDManoL3cRbgWZSP0u9gyeJnfSehplJvdVNvBtoIvVm6tkGM5veZuqJ1LtN16Wj7uRW8kHyQIMZOLLXOjJbVVV9R8R7VXW9qkarql1V61X1sKoWO9+0qp4nryePJu/WSQuv8rOWU/dj45jL2+i8XSynt9RNfC/QVwyl14c5vEnMoS97Q2HhTjdxC58CzlePhfmwbbR6wY8D/8F4F248DDzqdYhC89G3G5fWZAazB2/R09sZvIa9DK41/2RyoWudt4urp7P+E9zGzwhWcDmxkt4P3DqTtCF/gN8RvUvAL9w/l7Qhv4svjTf8uevTOqP8Jj7gPUYvbrzA+gvHZ7N7on3PawAAAABJRU5ErkJggg==',
    ['compass'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABiUlEQVQ4y72VMU4CURCG/92Eytha2W0McAY4gd4BDoAFVlB7ABsTSIyXwMKEQ3gCojQ2IoFWLPgsnKfDssuuGH0JCfvmn3/f/PO/WemPVlQEAGJJJ5KObetZ0iSKovVebwQSYAjM2V6vwABIfkIYAX1g5YgWwIP9Fm7/DegBURnSW5c4Ahomx5c0tjdyuJud5HZSgHegVaK6lmEBers0DeW3CghrQAc4NPIgS5IFHobyc8hi4AwYA2vDdiwWZBlkJYXuN1KxCtAFJilnrIG6YRrOLbFPrrruxyniriObAU/2f5w6WHBLVZICSTD/1BvfXnJuj5f6vCgH9nwdcJYz9Vwbp8tYp5ISSTNJV5IuJB1JepR0X+SaXCmsUVj5L06SbkaPll6K3OYBddf9sCameSVF3LT4PN2jLbuZT0P3x2a1TOmAO8MOs4IbF8TM3wFqBTK2LWdF3lDa40q33ZXu7wKWHUJNVz6WU2rCpcfmku+xuXT7K8MWfjDSmucN+rnFcgf9/3+afrs+ACmT7ebKybh3AAAAAElFTkSuQmCC',
    ['globe-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABY0lEQVQ4y72VMU4CURCG/6UCLLU0NgRJOANUHISWG8AdpIbEcAYK1Nob0GljlIZOGhIMQuFn8695kV12RXSSye7/z7zZ2Zn35kl/JFGWA1CQVJV0bmou6SmKoo+DvghUgCGwYFdegQFQ+UnACOgBG7LlHegCUZ6go2DhBJj7/d6KuUngd703uDMF2AJtoGX8BlxYV+Za9tkad/fVNP79trmxcT/w65sbG7eDslSSAg/j3zcuA2tztcCvZm4NlM3FZRnsbKmg+w1zTeOXhCRmtjWNG8FuKUhSwb5VSaeSlpKmQFFS3bZHoBiqpAfb6sZTrz1zrK8M4iYdQ1phxkeXOPDcz6WkE0klSR1zd8ah3trWMT7x2jBWZvNmCc17TmneIm7eIdvtMthuJXM35oZKyCLvAblKOSAb0oYS6Ud6RfaR7qV2ksOH0IicEy7v2NzYN/PC+F7ztEG/sC110P//1fRb+QR0OEh75bhmnQAAAABJRU5ErkJggg==',
    ['paper-plane-tilt'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABeklEQVQ4y83UMUscQRQA4FM7CxGuEHOVlYV/4BoFIdokYCX5A7ES7Ozsoo02Wqsg/gVtxCo2ihALU6mtYIoUQohBkPssfAePwbt4eoXTLPv27TdvZ95OpfKeBwYwicFuYCNYwCHuPY3rjnH0oo4VnGs9Jl+C9WMGW7gpgHscYB7jKTbQChvGHPZwV2C/sYvZDAQOhyU2hiWcolFgF1jDBPpaFHMQuQs5OFtgDzjCIkZRIh+wj6+pI5qbN5ITdxK6iWqbNa/FF8B+Kgx+lskfi7X8jqlnKq3hMnIuUYv4bsRWWlWyjr9pgmN8Qk8btC82FOrt2msIq/iTJviBqxKN/ImI/0LvS/q3im+4TRNcZTTy1uLZ1n/R4sVBbMfLZ+hJzyppI2c6ghPerPxzio9G7A79HcOBLAdy0uyW6HPYexWa1ry5oVMRO4r7uVfDAa2mPq/GH9rA8FvhofQjbcb19E1owjeKA2qpW3AN/wJtYKwrcODTcT58aZf3CBWe4T6QdAXxAAAAAElFTkSuQmCC',
    ['rocket'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAB1klEQVQ4y7WVMUtcURCFz0iQoMLCokQRBVsxkCaQwsXGahEsRNZCSBuwSGNhaWuR/IKkSBGIoI1CCvMDZH+AqCgWFkogIiLafmnOi9e3z92nwYHh7p0552P23vd2pRIBVIFPzmoZTxnoKHDIXRwCI/8LrQIHBh45ce1pkwMCthLooDODbwFPAs8bcAOMJ/Vx1wDmHwsNYN/mlYL+inv7QDwGPGXjBdBT0O9xD2CqiNH1ALvudSMiboE+4LuzLyJuJW3ktKUm3vE0i943kset4dqi9ztloRPAtU0114aAPeeQazVrroGJTtAB4CSZbrKNdjLRnQADhWcMdEvalDSW9IfbzJH2xiRtmtFyeR8l1SRdSNp27W0bcNbbtqdmRgu43+u6pK/+PFv0nLo26+0Xe1LGPfGcz6sJvAQuvZ8u0E67d2lt0/u5TPMi0e96fZNMsizpM/Azx64nmkg8uy3giDgDTiWNSnonqdet186i6LW2W9JpRJz94+W+4g9JDUlXkiqSkPRN0u8c8JWk9/Zn2vWIWCi6PEn65bXim56R9EHSsaRz57FrM9ZUct7WALqAJWAt+5dIXt00sld9xNol4N6QHX/ygH5Jq8mZ30hajYg/nbzPEn8BHb3fdVPCJPEAAAAASUVORK5CYII=',
    ['flag'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABXklEQVQ4y9WUvUoDURCFzyQiiBaCghCs/SEoKcVCtDFP4AP4ABaW+hZa2Qg22ltrpYIognaJIIqFGIyNkkby89nchetlN6urhTmwLDt773fuzM6s1GuyMABI0ryksqRRSTVJJ5JOzayTyQUYB46J1wOwBgwk7B0EJpLA1w7SAHaBTXd/8QyegQ2gEGUILABVoAOU4sA1t3kuiPcDq8CtZ9ABHp2Rr3I38FRCRnlgxZWr6cHe3ZUNHKwdAkrAjMvo3Af3ZfrKksysIenGM/ryPpcVnKbeAyfVOO/6MZq8ipm1/wJ8JmnYe64DB5K2zez+x8f32g03bZdA3Ys1gT2gGOwbACrf6eN1IO9iOWAJOHTTFk3dBbAF7ABPnnGxGzhp8maBfeAj5id1ByxGay0ESxqTNG1m1S4lG5G0LGlSUlvSlaQjM2ul1Th1pNMU9vGrpJakt9+CwxMXYov/n/QJprjP6L2aulgAAAAASUVORK5CYII=',
    ['bell'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABcklEQVQ4y7WVz0oCURTGvysuMjFCoYWBCNEThGjvIbhrFa1b+hK9QSvdC75ECwkKXEYESi1CAs1yUfhr4ZkcpknvSB24XOac7/vNnftvpH8K5yMCSpIO7PHeOTfY+I2AA06APj+jbzWvgYWhGaAbAs2AG2uzUL4LZJKMtGPGKXAOZEP1rOWmpul4jRxomOENqK7QVU0D0PAB90zc9NA2TdtbJywAc+ATyHuA86adA4VwLRXRlrXYggPn3Ms6sGkG5imvAm9ZP1s7Z8uYRbyx4F3rJwnAk4g3FhycrmEC8DDijQXXrL9NAA60x7FVIAeMbftUfKlAxTxjIBfk0yHNmaQdSU+S0kDNk+3MUzTGRRQc7MOipKsEU6EYxvLaBPYkXUo6DAlLkrYlPUp6tVxO0r6kdy32cBB3kk6dc88+89ey+WsDKWtty7U2/Krvhfkw0IM1LOe9wL/B68AodAePgPo6n++vKSPpyPTXzrkkR/5v4ws+m1+bXmveiQAAAABJRU5ErkJggg==',
    ['clock'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABP0lEQVQ4y72VPU7DQBCF37pKyQHoLJRDOGcxx0hOEkuIMhcI96Cjo0hDhxWXYAo+mlkYNv5ZgmCkKTw/zzNvZ2elP5IwFwAUkq4kXZrpSdJjCOH9rD8CJdAALafyDGyB8ieAAdgAvQM6AvemR2d/BdZAyAG9dYl7oDI6Pqkx297F3UyCW6UAb0Dt7AJ2pj6+tliA9RSnsf068S1cdYvEVztayiHgJrY/4BsFNn+kZZs6Cnf61RnAlZuWwjuW7vSLGeAL+44aC4vTspSkCBKH/5Ax+J2kF6c7yzl4rEJ50kt6yIz91uokFRYTEgpSKjpPRdbhZRS2stz2pLCpccsAvrPcZsg5ekFmQK8tpx9dSmNXegY0XunNVGDuElq59rGcrA2Xrs2Or7XZOXtvsbMPRsr52KJvzTe66P//afqtfAB6iqOZ3RlldAAAAABJRU5ErkJggg==',
    ['timer'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABnklEQVQ4y7WUPUpDQRDHZ4hBEzVJYaUQQUEEtY2gvSBYaKFVEHIBLbQyRfAIXkGPoL03sBFMtIhorTYPNZDEn4XzYHl5Xwk4sMXO/2OXmd1RiQlARKQhIssBqCUi56oqIwUwDfQYjB4wHacdiwNV1QO2RGQpAD2pqherTXnzGRGZt+2Lqr6NVoM/swngGLgPKcU9cASMD2u6CrQcoy7QttV18k1gJa3pGvBhwheg5jbKGlozDOAdWE0yzQGPJrgFSjHcknEwzUSc8akRn4FiBGcbuAYWgaJxAU6iTMW5bTWCswN0jHNouartW1HGc0boALkE00sg45TPz8+GGW/6nQ7BMsCn4Ve+qYM3Ddvwc2E/7yeYUNU+cCEiGRE5U9V+hGbwwwFlO/VrmIcPjAPfpi1HNa9thP0hjA9M07ZpGEqq+x0G8ilMJ52XVI8jTjk/6ibOHMgbx/+hU0m3qACeCR6AXSDr4Flgz3kJHlBJW7d14NUZNh5wZ8tz8q/Aetp++OYFoBE4wDVsAIUofeKgB1REFsQZ9CLSVlWStP8SvxQ5dYsn/+mMAAAAAElFTkSuQmCC',
    ['key'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABqUlEQVQ4y8WUv0scYRCG34knRKuUEntjo6QRYiHYSPQ/EFLYJJH7A6wulT9SKhZWKezENm0KFQttggZCYmEERc/ETlAUJXdPmneT5di9Ww0h0wzfzjvPzu43M9L/NqAPWAK+AOfAd+AD8Bp4eB9gCZgHauTbN2DgLtAAVpxcA5aBYeAx0ONq9x2/KAwHXjnpChjN0XQC7607ADqK/IJjJ5Qz4i+BXWDc8P08bWPikIVVoJQRP3R81+dJn9ck6UETdp/9ZkT8zIgvSjqStOTzhn2/JJWagDvtL7OCEbEgaSH1KNF1tKr41L5HxSzRVVuBu+wHgbYC4An79VyF+7Puy5huRQTG3Oc14GkR6ByQjrU1aEtAGbi2fjEPOpkFBQTMALfABvAOWHUrJrYKtLeCzhpW8bI5a7InTvyVkeaFoU8kffVlvpVUiQgB25KeWVuXNCXph6RuSVeSPkvayulzCXjut++40jfAnncEHt/uAp3x2xoH5MaVvpDUm7xX0seIqN4FnFQ8klp92w2VFh2QTPAjX0La6n8DjTRc0oD+TONZRHy6d7X/yn4B16MiEaFvAjIAAAAASUVORK5CYII=',
    ['lock'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABI0lEQVQ4y82TMUsDQRCFvwkRLNKnTJX6OBAi2ATSWFnYWuZHCP4D2/SWtloEUtlaCCGWKdKkFftg92zmYHMX73bPCD5YZng3893cMmc0SNIpcANcuPUKPJrZV1NvHXQgaa2q1pIGbaEdSUsHbSXd+dm6t5TUaQOeOOBTUj/w++5J0uSn/ro3Zh4XZvZRmJ4vSjVJ4BOPuwPPdqWairrBJwJcA0O3xh5zSbelvryo8T6ADfBkZpU7ner3mlYmBs48vgHvpCkHRs54KIMLPZvZfQrVr2oUeul7GKlosKRMUhZbHwWWdA6sgJXnjerGFAG9YIjeMcEvwFWQHwfsSz+PHAL4w604NHH4m8ZqXAfeeLz000YFYw888zhMY+1BZy17/4G+AXbs3dOF3FCKAAAAAElFTkSuQmCC',
    ['lock-open'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABL0lEQVQ4y82TPUsDQRRFz4tRLFLZWIlVbGNAiIXFYmVlIVa2+RES/4DYprKxFWy0EKysBUFiJ0IUxE4ES9tr8xYm2eynK3hhuTN35x3ezs4YOZK0CBwAWx7dAedm9p1XmwVdlfSkpF4krVWFNiQ9OOhN0pGkgaRXz54lLVQBbzvgU9JykC9Jevd3+2n1jQz2uvuNmX3EoZl9Aac+nasCnnef9ZOOgRUzu0grbgafCLAHtD2K3LuSDlO2K5yOgUszSyzq6/fqJzoGNtzvgUfKqQv0nHE2DY51ZWYnZai+Vb0wa5QBlFFhsKSOpE6tYEmbwAgY+ThXzSKLgFbQRKtO8C2wG4zrAfuhvy7YBPCHp2JWx9HUVS2iKAs8dt/xp4pixgR46N4ux5qADivW/gP9ABg53YxqxlPhAAAAAElFTkSuQmCC',
    ['play'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAAyElEQVQ4y8XVIW6CQRCG4aUB0SoOQFBU4GnSIyDwmJ6iBo3gBtyior6CO1T8qfmDI0ETBCQkD4IVW0l2t/3kzOw7k9md2RD+Ugh4wag0eOWmC9bolwI3fmuPN3RywT8R+I7vJMEG4xLgV3RjgkO0nWOrnrLAiW2Aj6T6LWbZ4MQ3RZsk+MQwGxz9j1jiFOOOWKCXBU7invGVVN9gkg2OsQFz7OKZNoQQHu5qfq7+rRVVLq/4cys+ILVGuvgSqrY2qy36Ol9TCV0Bdl0YgvKCxg8AAAAASUVORK5CYII=',
    ['pause'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAAsklEQVQ4y+2UMQrCUBBE34iFCpYSCyurHMxOtLG0trQRvFBukAtYWUQsA367tdnAL/LTBQlkuhmG2YGFgaFBMTGzDXAElpH8Ae6SHu7ZAntgEXlq4Cbp2XrFzAprRxl5yoSn6GpcARlwBd7e/Ax8Jc3dE4AZcPGmK+AEvCStU40rv547z5yHyBNcy5znzqs4a9LX88bgMXgM/kfwNKHvzKwZoRQOZtaMUDf6nM1+hn4Q+AHXesjhfbY2LgAAAABJRU5ErkJggg==',
    ['stop'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAAhUlEQVQ4y+2UwQ2EIBQF5288e/VsO8ZqKMRqzNZivNgDDTwP7ibEgAH3tjI34GfyIHlA5YOFC0kjMAFtoccDzszm6KmkVfdZQ1dzcn+TDsCWmbYH3udbNonhzcyWHKuk6P6r8C2zqeIq/gdxqnl9qlGx2RyxBzqO7pfir8SOH77NG2GewA6OXFTTH+2psgAAAABJRU5ErkJggg==',
    ['arrows-clockwise'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABSElEQVQ4y9WUPUpDQRSFv1GjWKdIZ+UajPgDYiLYuxQFNyC4ASGgrZbuIKAQFP9WIFpYClpZaAz62VzlEZKX8ETUU72Zezjz7pk5F/4b0iCCOgXMABXgFbgBzlJKz4VOVFfVE3vjSd1RK8GdU2/UtTzBkrqbEWmrLfVAPVRvM7UHta5uxrqRJ7wepI66rZa76qjz6nnwXtTmMMJV9UitDbCqpO53WdTgO1CXwp4L9b2X8FhB7Tqw0GP/8fNj4HPr88cTwCIwmtl+A1oppfa37Pg1fFnxY+2pW31StlVEL/sqskEQuALaQLOI8EiORdfAckrpOKfLWoSpmmdFI1pvRkyN2M6r3dxyxL0TvI1hhDfVlRgwn7iNAXQQiWtnantqKU94LUbfXKwrMRqf+lzqqbraT2+YQT8JzALTwDhwD1ymlO6KXOrfxQcfc7UW1r44uAAAAABJRU5ErkJggg==',
    ['trash'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABXElEQVQ4y+2UvUoDURCFv5NESIoQQhrTCVaC1lb2VoJBguALaGvjW9haWwgWgpIXsLBJOgvrYJdGCWKzRJNjkStJ1uy6EQQLP7gsc2fm3Nm5PyIF2wVgC6jEXC/AnaR3FsV2yXbbybRtl5LyCynaTWATeAIeYr714GsC54sKL4fvlaSj2N+cAYdTMV/QVPAOcArkw1QFqAKvwHMsrwaUgX7oN8AQOJbUile8AazOWbwcxjyqYUxrtOIV54B94AJ4BHbJxjWwAhwAl5JGMxVLGtnuBjOSdB8WLAJDSW/BXgLykqJgRyGn+ykKkEsrJYh2gc7UdAfoBl8iaacCxhtYj/VxDSgGX5SUmOOX+BfOLDwAzOwmRWFukJaYeiok9W03mFxbgAZQkdT/sXAQv4nZt1lakSRcs32SRYDxg5SO7brtyIsT2a4nViypZ3sb2GPyfH7HkPGb3csY/0f5ANzZvsH4FbmdAAAAAElFTkSuQmCC',
    ['plus'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAAiUlEQVQ4y+2UwQrDMAxD5VFKrvvJ0r/vdfTgt0taPFY6MxpGRwUBJWAZyyLS3wIYgOFo0R7wevpMTZfUvkmywFMFTXAJr3hZXt34VrMSObCl5WY2v73WnDrfw2POm1lh8fLBiqnyu6RH2oo9ACWMXDI154vb+YSzv5tLIvBjhM1sBsaFt5ryt3gCbkqA2Ac5k3QAAAAASUVORK5CYII=',
    ['copy'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAA7ElEQVQ4y9WUKw7CQBBA3wAJHAGJxlXhSCUWzx0wJHAFJIEEhcNjkVgUmnOgKprBTMmG7KckRfQlzTSZ2bfT6bbQNiSUUNUhsAH6NV0lsBeRZ7RKVVf6O4dqfS/i7lq8A5dEtzkwc9ZExRUPEdkmng4Tf+g5ySGwcHbNLWaquvb4CuAkIi/fZm7HG2DpqZnY5W0W2KXE1du/A4/EeKbAGBiECnwzvtSY6dHEQTr8ifaJ65zjGHNVHQFZ0+Lvo1g0Jb4CN7svgXNT4lvoaPrEuX37MbJUgSsuLc74+qFEKEMJV7y32KUeBc5M288bO6lpHE/TTWYAAAAASUVORK5CYII=',
    ['floppy-disk'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABM0lEQVQ4y9WUr0sEURSFvzPuBlmNYt6goBatBtEoGK0bBIMgGBbE4n9gE8Ru8C/YYFSDmLRpsJlsgrrgD+RY3sAwzNudWVHYA8O787j3vG/uGy4Mm5QGtmvADjBVof4eOJL0Hc2w3fZgOrE9kverZeKU9Aw4L0E7BuwCrQC2UUhu+zgQ7JXtg+012+9F5Emfwi3bN7Zvc8+p7URSB1gHPgL5dlErirQKLBTsTwOjQFdSx/YBsA/MlDVuBWPl9h8ldTPvb/nCnsaSXoCLsj3PKhmkqIyixLbHgSWgHkn5Ai4lvZY2tl0HroHZPmB3tuerEDeD6SdwFclZDDnNKsZp758lrUS+6gmYJHJPf3Z5//pXLAMTIW70mB2NsG4Cc9ETfjE2s2oXER+Gtcqgz+oh4zGE+gGKYvYPuUwfiQAAAABJRU5ErkJggg==',
    ['download-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAA5ElEQVQ4y+2TvU5CQRBGz+WnsKGjpaGx40lMtMTW1s7wJITO3peg9E18AaBl9dhM4vWyFxZyjYnxSyY72cl3Mju7C78tdapOu4b21W1Ev8QzKGQPgVEtfz9l6HV6tL8LVkeX1I6C1Vtgoy6BqlaqYm+j3rX5j72KHfABPAJXtf0l8AAkYHvRnNS5uvdQe3VeCpmpz+okA081aGpC1Ul4ZznwKoyLls5TxH2mvgjvKjfjXmP9uq2qelHfIn/NHPjAW/ql24Ct+rEPkut4rF6fyRmXgJ8iOut4DdxwxtwbSsH413d9Avs3qvCbsgJXAAAAAElFTkSuQmCC',
    ['info'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABZUlEQVQ4y72VMU4DQQxFvQMRaTgAEkqzQrkDm5or0IUj0JFcgoImQUBBmTZUXICSE1CkoWOVNBQECR6NB6zJTHYAgaXVSv723/W3xyPyR1Y0BQBORPZEZFddjyLyUBTF+4++CJTAGKhZtSdgBJTfISyAIbA0RHPgXp+58b8AA6DIIb0yiVOgUjk+pVHf1MRdrCXXPwV4BfoB1gFaga+vsQCDdZr68kPSE/XfARIh97KUMeKxLz+CTRR7BjYiuJdlFALOdL+KJHaAU+AgUW1lpsVZoGu67yKJO8AhsJ0gdmZauiIinsQP/ywx+GciMhGR2xix5swsl5M8u9b3PrCVmZMlRdvMbDshxcJKkdu8JuKeYvXKjzWMWwt4U/w4gt8oNo7JkTwgil8qdh74j9S/TC6lhiPt53kzIPVHeriuiblLqGfKR3OyNly4Nhd8rc2F8S81tvHCCDVPLfpaseSi//+r6bf2ATsOsZqX2Ag8AAAAAElFTkSuQmCC',
    ['warning'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABb0lEQVQ4y8WVvWoCQRSF70jwp1chmM5eBA3xGSwFi4DJM1hIgmBrkbyAYCPExxDERjDkBWzER0gidjF+aQ7JIqNZf0IuXHbn3Hu+WWZnd8z+KFyYJsCZ2aWGL845jp4ZiAIDfmIARE8Bbgj4rgRoHAtNA2+CXSuRlj4G3BVoDDjlWFr3UGgeWAGfQDGgF6WtgPy+UANGerKetBgQ031PtRHssUGAqowL4ByIADNlRNpCPdWw0AQwl6kpLR7YbnFpTY3nQCIMuCXDLADxgePqAWj9Bs0ASzVXAnosAI4F9Iq0JZDZBX5S43DzpQBtoO15yUN5+tugJWCtbZTz1LNA1qPn5FkDpc2iAyaaueMxF4APZcFT78g70Q/ru1BT4RVIeozlwBqXPfWkvAC1YGEqsb5lmRxwq3RbeupiTM3MzqSndL0A7m133G352lIbVzPgkdPFg5lOECBiZjdmdmUhTxXfapjZs5n1nXPrAxn/GF9huXEdqDBa2AAAAABJRU5ErkJggg==',
    ['question'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABkklEQVQ4y72VvU4CURCFzyUktkSlMXaE+AJ00PESVFhDb6Cx0XeAxEhpYouJFa3RigcwtnYQthVN+GxmcbK7LKjRm0wgZ2bO3Dt/K/3RCdsMgIKkqqRjg14lvYQQVj+KCFSAITAnfWbAAKh8hzAAfWDpiBbA1GTh8DegB4RdSK+d4xioWzrWqTFs7OyucsntpgDvQNvhNeDMpObwttkC9PJyGj+/7W43ysjxKH6FkcdpqWQRD+PnO6xj2BK4MYmDd5xdnJZBqqVc9esOnxjWdVjXsInD6q5bCpIUF6Uq6UBSJOnJxfyw36nD9hM6mU8k6dC41hGbFtETCCgDDft/DjwAK7NtJWynhjclqZjXfiGEmaQZsCfpwt30UtKtth3gxA1CIUNfAJ5NjjboI+M42Vq8hHMRKG7QNcx3nrpYVrslcv1oUs7Q35nvMCtqakCcruWGI1m0U9fr2UspZ6RLwL1JKUEaj3Q/r4i7LqGGez7ms9OGS67NiK+1GTl8abZbPxjJnG9a9HPTbVz0//9p+u35BDfL8BONSvuuAAAAAElFTkSuQmCC',
    ['skull'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAByElEQVQ4y72UP0tbURjGn5OkoaE4SckgFoIlo6BbIW2g4KJxFPwE+g38CKHQbtKpXTo1X6GOgoSiW0CySJYMikPTgCBE/XXoc+H09qY3KaUHDue87/Pnvue+517pfw+gAGwDn4A+MPbsO7cNFOY1bQA98kcPaMxqugdMLLwC2kATWPZsOndlzgTYyzPdAR4s+AAs/IG7YA7W7EwjVoFvJr4BZjmdzMXaahbpnQkn8zTFTT6x9m0aDMClwY25Ov1Tv2HtJRBioG5gBBT/wrhoLUBdkpIjL3u9CCHcm7wGdICPwFJksuRcB1iTJGsuYq9SwvcaLH4s6Yukp87XJb3y/rOkl96/Bp6FEG4TbeQlAc99jDFQAmqpD2EUcUcprGbN2PFKunlDA5uOjyPxYcQ9jPLH5m46Hv7SPAvaBs9cQQXYBVrx9fP1ahmrmHtqbTurs4vAtQnvf3ty9m0I5mLt4jRiC7hLzJ1bBw6AsucBsG4sMb0DtvKq2Dd54PgoevfJuzwyNnC8n/YpZXh/TcWPvJYzctM0mRWvuopboAt8d9z3xLmuOQCrsxiXgXNmH+dAOe0Tppg/kfRCUt5/415SN4Rwk1vxvxo/AJnt9UFMHjmKAAAAAElFTkSuQmCC',
    ['coins'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAB2klEQVQ4y+2UzYvNYRTHP49uFFcTWTDykpqRJi87mSalsPVeivIHUFPCAmujJLEaiymFbkppmoUwsqOskKQwxZi8JAujuQzjM4t7pn7dfj/3t+esnvPyfL/nnOc5B/5LSMoq6ipgB7AJ6AAWARXgO/AeeAoMA3dTSpMt0dV29aY6ZTkZUw+pxRmri4HHwDLgN3AHuAc8Bz6HbT6wEtgI7AFWxP1TKaUzRdn2RRbP1M4S1VXU43Hnh9pWFFiLoEtlH0ZdqtbjXr+6S60WAasOqtvUOQWAy9Vj6qecvo+r52YIkloD9jdh/ARe5fR4SQ7fdWAD0BX6E2BzNuPz6gX1Y4sfMaweUL+GvlpF3aK+DdvpWcCLYNoHDAFXQr8B7I1qdmcyPAh0AwuAcWA0pURK6QFwLWK6KsDF+ELrgftAPZxzgUlgAliYAX4Tvj9Ab0ppQu0AjgCHmx+lGo3/VnJAVF+qQ+pIjq/WTDBP3alejoBf6kP1dQuSunpLHcgFzhC0xedXPREVzUhv2I6qt8N2Vu2MIVPt+9sQnMyAjWbOPeoada16NWwfojrVdzbWRCEwNhbNWMmeT9lYZO3QtDYLCGYD24GtwDoay6oag/MlBukRMJhSGmmF9w/KNMZ3i+jr9ipBAAAAAElFTkSuQmCC',
    ['package'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABf0lEQVQ4y8WVMUhCURSGz9UkGxqCXNykJXHVtSEIwfaGaqqtNZDmGpvCJWh3r2h1taHNocUUmowIIiS1xK+hE5yuPn2h0A8X7jv/+f97Ltxznsh/AYgCe8CDrn0gOo2hAJtAjWHUlPuzaRaoGKMWcKCrZeIVIBvGMAWUgYFX4RWwojmLwDHQVm6gmlTQtU+Arib3gQvgHPjUWA84A5ZVk9ScvvJd9fhlnDPVfQAFw6WBS8O/AkfAgvIF1fwgZ43z3tU7wCmwZHLWgFuT86gVdzxtfpRxHbgxSS/AITCveQ7Y9SpENfVxxlX9XgfujLAJ7OhqeqZbqqlONDbVbQMNhtEA3nW/Oso4EvT0nHM458oikhaRoqGKGnsb93QjMgHOuZ6IlEyopLGxmJvYNcG4F5GYiDyFMZ54A4MNEYk55zqBWq9BroGMx8cNH/e4jGpGNkhQSyeDjAnT0uYAfwi1+R44CWOcIOwQGnGAPzafA/bhxqZnPvtB7x0w21/TtPgC9k5HK4xd2loAAAAASUVORK5CYII=',
    ['gift'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABU0lEQVQ4y+2SMU5CQRCG/yUQnxRKbKxMxEYTE+mMnMAbUFhxBm+hhRzBeAZCaUFlpUKMBRRUFNhoQiNEw2czLy7LexICWvknk92df+bfmdmV/hpAFegAQ6AO7JjVzdcBqouKVpjFk1mIyiLCTUu6BA6BvifUN9+FnZtJGpkU7U1bH5xzz5JqHlcz32MQO4WsV2VW0p5d1pJUknQDnErqeTnrwLWkMzu3gANJE0k959yn33oeaLM82kDer7gs6UjSh6TXlPFs2/qSwm+ZRlnSbSwcr/fOuXLCY0aS3u2465wbJcTcSTqJtbIBnzGREL4vApIqnvoIsXBcwbFXWRre5vDf3QA5oLGCx2sAuZmrgIEFlIDIs4KXXAi4kvkHSaMIMfYfKJjpKODGcwe+SvyacNooikH7a95+P2i/OPcWoLvEj+j+VPG5pCtJGwt2PrTcf8ziC8Ui1Mvk50+lAAAAAElFTkSuQmCC',
    ['wrench'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABtklEQVQ4y7XUPWhUURCG4blrTNgtxLVKGguDRNAgCNpYCAFtbAOK9iqI9dprEWKrYGdlUirBKils1iJqI1qIEFtRC934AwaXx2JHuC7uL2SaufMx573nzJk5EbtkxSjJKCLicEQcjIifEfGmKIrtsf+OCq5gy7+2g1vjQifxqARr4V0pXh8XfDcB33EVB7CZ2hZmxoEeRRu/sYApbCT0A2YzbwbruD0seCkhK13xFxxPbbZU+x3si4ioDGCfSP8k/Z70D4uieJXwZkQcSn1vRMxHREwMANfSt9Jvpl9ERMTliNgfEc8joh6dVqwOU4rVPGIj42n86Gq5jbzQVsZzw4DvZ/KLkjaNRdzJmk9lt8D7HKKewALLpV01+uQuZCvCtX7QCTzIxDaup34TL9HAeVzCSrYiPEalF7SGtUz8hQup39Db2riHyV7QOpqZ/A1nU7+Yi2XNV/EsB2IJx/odP/A0F3/CydTP5c5heeBt/wc8X5qoudRO5c5lzUd6Yv+CTyfgrc4TeQSfU1vDoEHqCa7iYwn+Nb+bqI0FLcHPlOCy5vVxeUUXvBqdh2c7Il4Xxehl3XX7A+aSfOQKlLfKAAAAAElFTkSuQmCC',
    ['code'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABLUlEQVQ4y92UP0oDQRTGvzWBVIFItpEUpk+TI6QRJUcQNAcQLAKmEVLZpsgZkkMoEbxDGquUai1YCj8LP9EMk81EthAfLMO878++ffNmpX8fQA24AXplG5/zGfdFvL1feJ95vSuz2hbw7qe1U8VADlwA+xH+qaSKpIcsy56AJnAJ5Nsq6gAr9/A6wAQsjQ2cG3u/AjqbTPvAq4mPwGGAd429AXXn2uZibT+sZOi+AdwCjciLJ8bnQb5hDfYYAhIw4jumQDViWgGezTmJ4FVrv2KUOm5Hkg4kvUhaJClSWgHMjU0i+ngrCg6v7XzdBwbQDUw3H17BuI2dG3i/XKskddx+kHMPfdP7hcVXEW7aBYkIk69wGNumYu0Kl2l87HW206cmtKLnn3qtVOM/GR+MwMw1tBx8fwAAAABJRU5ErkJggg==',
    ['list'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAAcklEQVQ4y+2TQQqDQBAEa0LwG3ld/I0Xr74urxBEtnJaULztGsmCdZrpQ9PM0HDzayIP6gt4A89CrxWYIuKzU9XBeobst003AnNt4uuPfhaxXdQOeBR6pYhYDqraq6nicUnts19puj84RTPclW640u3xBage8IOO3jmlAAAAAElFTkSuQmCC',
    ['palette'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABuElEQVQ4y82Tv2pUURCHv3NNGWRFIohFwDXGxtIqbCGpXDsLCRYpkmcw+AJWgmnUYGGnD+CfkAcIpJHtUiim0oCgkqQQMQr5LJwNw81N3KwIDhyWOzP7nd/5nTnwj6L8qUGtgAngXKQ2gY1Syt5QO6ptdUn94sH4rD5Uzx8HWNQ76m4Cbam9WNsp/129rZZBoE/SH5+rU2HHvjVqR32V+h4fCQ+lqj/U2ZRvqcuxWpFDnYte1YXDoBfS8WdrtZmkbqZWm0u2tJvAS+n4qHfVFXVCHVPXYo1FbiV6SLY8OjBS6fan1PGkcLFBxGKqj4fnBqPKjZPp9iv1RPj5Ue00gDtRW47eKk3LZG6cjmTvmOOeGb1gTANU9fqw4Hr0wR/itz2IFQ1qR4D+K9wEGImPDeATcAa4Gt/dqN0AVgNwGbgFnKqxLwGtgL6r73o/PFoN1fvjFvXr6TE0xTf1Wp9XEvgs8AY4CdwDFkopeeO3wEXgBbBWU/wVeFlKeX+YVzfVvVDwVD0d+dGkbHSo21Tn05F31AfxGg3Vw4d6RX1d83BX7Q7KKEfAC78npAv8BJ6VUtb/SvF/Hb8AYHt7MndA80EAAAAASUVORK5CYII=',
    ['cursor'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABdUlEQVQ4y9XUv0pcQRTH8blZTWJpk943WGyCBBJEsDAgFvb6AhbWPoAWrqAIYqGNb6CW9j5GAv5HBXvRTwrPwmTYu3sXm+RUc885v++ZmXPmpvS/WdVdYCSltJJS+pJSOk0pnVdV9fruClj1t11jF9NovQe8HsAH3BdF7rCPWYwOC/4WkHt8xgz2cFMUecQhfuJTE/CHOD7MZP4WvmMHF0WRJxxhAWP94Lsh2KuJV5hCB7+KIg9o14GnI+lmUMOiyFecZ/CtuuRWNAp+9IFOxK6vMugr5vvtZD8Sd2rio8Vd32Ibk4OaOBuCS1Q94uN4iZyDeFiDLXb0GMKpwj8e642Iv2CpETiEhyHsZHd6EaCNaFwngy83Bc+F6HdAtorR6oR/cyg4Psbwi5HqPpyD7H43e8AXm8CPQtCd01uMYKkH/Di+z5qAF4rjb2ex5Qx+gudYrzUBj8Uz7Q7/ZBHP4bz9sKqB4BC3o3HzNfFFnGGtMfSftT/x58irW3ZTUgAAAABJRU5ErkJggg==',
    ['hand-pointing'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABuUlEQVQ4y8WUT4hNYRjGf+/4M6SusRkkRVnYkSiysbGYKAtri4kSC5nYWInEyl7Kn1go6bKj1DQboigLlFhMiRrKv5qYuu7PYl515jr3nMtMeer09r3P8z0953vPd+B/QO1Tz6gT6nv1hBpzYXzUPzHcy96+Gn5P1mPA6Y5eJebX8IuyvgCWdfRmlbgM/eo6tTLUvxjvAF4D4+r2uTQGmARWAU11VG2q24qCGa+j9gO7gQZwt4vpo0w9AQzmAzCkbomI5zMSqw3gMXALuAy8AtYWDH9m/RQRU8CPXJ8E7jE91H1lR3EQ2JBJnmbq5QX+PnABOJ/rr0AbuASMZa9RdhRrsl4HTgEvgdW/yYj4Ahwq6HcBgxHxTq0c3mjWA8Bi4EjV9CLiTUQ87MYXjZs5mAGmb9kd4CbwHRinGguztkpZdavaVlvqRjXUJTWmqDfyP3K8SnQtRQ/U2u9cHVC/5Z7NVcIV6ucUjvRgfDG1T8qG2CkeTvGUurOLZp56LnWtqutd3IR6pWB+Vt2krlTXq/vVZ8m31cO1pgXzBepVq/FB3duzaUfyIfW2+ladVD+qY+qIuvSvTWeLXyZwZZCZgEWiAAAAAElFTkSuQmCC',
    ['person-simple-run'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABkElEQVQ4y7WUMUhWURiGn6N/qKDWVEmgRShORmE0NjiYk4Ozg7OLay2FoLi4BkKLEE0GTfJPTk0OIS06KkqhiAUq6o/6OHjIy/W/ea+/ftO933nPc9/vO9+5cEsRiojVeqAXuAMshhAqNTtQ29WfXsSa+uwmwOUI3FLX4/OyWqjqNLSkHkfYE7VZ3Yvvj6vtKeVknwC7wD3gDfAbaAROY76mVox7OWaz9KUMyAPgNdAG/AUWgQ/AHjDC+VTMAe/zuqpXP6qVKu5+qIPqtcrtjJAT9bs6G6dhP/GBb2pHUTDqkPoilb+rbifgh+ontU9tVRvUHjXvMPwDD0TgH3Xe7MjX8wgtqUtx42TMvVRn1NUEdF0dKAKeSGz+onal1pvUltyHGvs9pp6myq2o7wpf5QjsUb8mYG/VV+pcIjedB3Y/jteS+it1+qMp7XDiv9F/Ffh5quR99bPanaGfirqFLGZIiLuBh5xf4eUQwtF/jDwCNoBjoDWEcFCo31dUuRNdP622XlcDuwysAJs35jZPnAFnOBPKwk1T/AAAAABJRU5ErkJggg==',
    ['chat-circle'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABQElEQVQ4y7WVPU4DQQxGv9megpo0EEC01EnFBbhBBIcAUeQY/AiJK0SwuQbKCZBSJQUCKQVFgIJH4wnDkuxmHWJptdqx/WZsj73SmiRUGQCZpD1JDVsaSXoKIXy5dgSawDXwyl95Aa6AnTrAAFwAHwloAgzsmSTr78A5EJaB3iWOOdC2dMxSY2t5YndbCreTYqftLBFdB/g0n7OynMbwK6EFeEzL9jyDmxi+o9B9870sKrKk+i0HuG2+z79yDRwk1c8c4Cy5LbuSFCFb9h56Lr75DO2zkYJnm9eFLpIIHtu76U2FpNiFo2KO/r94pozXrecA53OvmylPTDmoCa1skHsz6NaELm5pYAOYmsEx0LVJ1gNa7iEEHFEuvrEJbAJjM54CD8CpFdQ16EMKl3Qo6TGE8JaGLmlfP9252q9pVfkGABRITDpXtf0AAAAASUVORK5CYII=',
    ['tag'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABEUlEQVQ4y9WRMU4DMRBF/yyQhoPkAkhpQ0WTGg5Ako6aG0CPkKBAipQLsEgUKdPRhGuEC1CB0KOZoJW19toLDVNZnu83T2Ppv5XtDsBQ0oWkvUT+U9LSzDbZE4Bb8uodGHfx9hvnnelK0jqSP5Z0IukZmJjZWl0F3LnRZSIzAB5zzKsEZAK8AOc/H2L2IelM0pOkQzdPryU0dijANmJep8yrxKwHSW+S7sOGm59mmefsuGTnVS6krRo7r6PmwI1PXgGDkgEt5qNm88gv8VAf+Ku/X4TNcQNel8CBGfDlb+dtgWJ4AL0CosFseAC9jkIj8NadF0Nz4L2hCfgBMP0VNALf/Ak0Ak//fg/4CFgA8y7oN5m4D987eON6AAAAAElFTkSuQmCC',
    ['shopping-cart-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAABdUlEQVQ4y7WUPUscURSGn7ObIggRLSSipLDQxjZgY6oNq51YWNhYBAS18wf4O0z+QGytDGsIISRC0tqJoCAWkiZFUMSPfVJ4I7ub2eyMux4Yztzhnee+54V74ZEqANQpYAC4BL5GRL1rsjptc631xLI6pO6oBwn8oaeZqBMJfK4+7ZYXDWCAI2As9asHMj9HRHOc6qbd1xnAk5bdasAKcAosFHS6CiwBn7Jy7lev1Lo6WoSq7iXHS+0EX5LgTQHooHqTDA0DlDJ0u6nPFDBcAcrAfkSctQPXUn+tlnOCZ1r+zRyrpP5McUzliAH1JOkrf7//4zjdEx/TcjaH20ngBXAOfLvntHGxCLzn7pD86gDuA54B2xEx32m8srpV4FAcquNNk3fYYATo7+D4BjiOiNscsYG6rH5XN9I9kqVZV3+o63mhz9XbhlFfZmjGW+JoiqLUhn2ZHoA68DtDcwFcp/frtM7l+pX6Vp37j6aqvlOruaC9qD8QeIDd68wcJgAAAABJRU5ErkJggg==',
    ['pattern-dots'] = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCRcBARiwYFwzAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTIzVDAxOjAxOjI0KzAwOjAw2eQUTwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0yM1QwMTowMToyNCswMDowMKi5rPMAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMjNUMDE6MDE6MjQrMDA6MDD/rI0sAAAAN0lEQVRYw+3QoREAIBADwdf0b7/WQ2BAwxBz20AmVyVJki4BIzneLB15zul/iWiBvURsXJKkFyaESC5x/EuNUwAAAABJRU5ErkJggg==',
    ['pattern-grain'] = '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',
    ['pattern-hatch'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCRcBARiwYFwzAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTIzVDAxOjAxOjI0KzAwOjAw2eQUTwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0yM1QwMTowMToyNCswMDowMKi5rPMAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMjNUMDE6MDE6MjQrMDA6MDD/rI0sAAAAOUlEQVQ4y+3OsQ0AIAgAQRZh/zHPRmNhCYkNP8Dlwy2jEBKiEztgGwYV68FKc4MNNthgH7ENtmHIBXHfazCTp1k8AAAAAElFTkSuQmCC',
    ['pattern-sparkles'] = 'iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAYAAABS3GwHAAAIDUlEQVR42u3dX4wdZRnH8d+00DYUawjF0AJajEATSkra0iIItSklKkYxAS8E/HcBJmCINxIVNLFIIV5glIR/EbjxQoGLNikkIE1IoKKxtBeNEapQLIYE8A9NsdBSvl6cZ/W40bbS3fPu7vl+ksmeMzO7feZkZt73efueeRJJkiRJkiRJkiRJkiRJkiRJkiRJkiRJkiRJkiRJkiRJOgLAXOBW4OvAjNbxSAMFfA7YD+wCTmsdjyaHo1oHcKSAOUk+nGRxHc/7kiyvVmBH13X7WscojQugA34I7Ab20vMu8CbwGvCF1jFqYptULQAwK8mnk5yZ5IkkzySZk+TYJNRuXZJZSaYnmd06ZmnMAF8G/lF3+peApcAJwCeAH9X63cD1wCrgWGC2SbEmvTqRH+M/revb/vnq/rwCLKx1y4EngXVeBJrUgPOAv9VJ/kZdAFuBD9T2ecCPgRuAWcAZwP2135+By4H3tz4O6T0Bbq6TeVfd0d8G3gIu7dunq58nAdtGtRZvAd9vfRyaWKa1DuBwACck+WS9/VWSe5O8kGRmks8A05Kk67qRRPidJG8k2T/yJ5K8mWR362OR/i/A0cBVNcz5DnBVrf9JXzK8fOQi6Pu9E/sS453Ax2sUSZrYgOnAAuCrwHrg9TqRnwM+WPtcXOP9IxfBfcBna1RopCt0JvBz4BvApBry1RACZtaQ5r3AH+uOP+KvwLf7Tu45wM/6hkVH+vnbak7QUmAacNTo1kGakICvAXv6Tug9wK+B7wHLgJmj9p8DrKnu0O8rMR7xJ+BjrY9JOizADGBD3wn8Ul0Qxx/G73bAqXXn3933N25qfVzSYQNu6Tt599Vd/S7gU//tQqguzimVJP8CeBk4UL//JnBZ62OSDhu9Of3fAX47qm+/t9Zd1rfvDOBbwA5606BH/B34JfCl0V0maVIAjq+7/l3AH/qS4d+MtATAOX2jQ28BzwI/AD4KOAlOk19fF2dtXQR7gUtq23fr5P8L8MW6aLrWMU8V9KaW3EfNq1JD9X8CO+qEv7NO9mfq/Xq7OmOjBhNOrpvOPTWg8DBwYuvYxstkGR9/Kcmmer0qyeVJFqU3xWFD13Vvtw5wiliQZEOSG+rn80k2JllGbzqKWgEuqS7QvpraQP1n2amtY5sqgKuB31WudQawEPgKvW/X/bR1fONhsrQASe/bX9uTHJ3kQ7VuU3qtg44AcAxwfpIrk9yRZGeSa9KbQLgtyeYkT7aOc+jVEOmI3cAnj/yvDjfgQmBj5VS3VX51HvAgsAW4vXKC6a1jHQ+TqQVIknuSrEvySJJv5t95gd67hUlWJHk1yWPpTSN/Lr3PdnaSlUnSdd2B1oEq/xoaneGQ59igNwFxBb0vGW0HLqqW4KnKCRb4WWso1FSU9cDmygmk4QGcWyM+G4FjWscjDRS9hwlcDaxsHYskSZIkSZIkSZIkSZIkSZIkSZIkSZIkSZIkSZIkSZI0mtUTNXSGsXrisJhsFWJaWRCrJ05JXgCHZ02SWUmWJ9mRXjE5ktyf5NbWwem98wI4CKsnamgNe/XEYWEL8L9ZPVHDy+qJUrF6ooaa1RM11KyeKEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEkaEB/tN4nUoxhvrLc3d11H65ikgahHta8Gnq1ltU+p05QGTAMWA4uA5cAu4EAtu4BlrWOUxg2wFNhZywXAqr4WYBVwFvCR1nFOZke1DkAHdWmS+fX64q7rbgIeSK8808tJ7k4CcH3XddtbByuNGWAusBV4pJatwNzaNh24k54DwEOt45XGDHAccC2wB7iylj3AdcBxtc9pwCbgCWBR65ilI1IJ7xJgLbAN2FsFOU6qZXOt21b7nA2cbg6gKQE4B3gB2A88Wnf9+X3b5wNX1Lb9lRgvbh33ZGeRPEntHaILNB94elQXaAngDUxTTyXB1x0sCdbYcC7QBFVDno8neaVWzUuypuu611vHJg1EdXX21bK2dTzSQFU//8ValrSOZyqyCzSBVZK7tN5u6bru3dYxSZIkSZIkSTokYB5wH7CwdSzSQAAdcDJwCnAPsBt4GDixdWwaboOaTbggyYYkN9TP55NsTLIMOKH1h6DhNagLYE2SWUmWJ9mR5Mr0vth9f5JbW38IGl7jegHUw5zOT++EvyPJziTXJHkzybYkm5M82fpDkMYccCGwEXgGuA04HjgPeBDYAtxeOcH01rFqeI1nC7AwyYokryZ5LMkbSZ5LsinJ7CQrk6TrugOtPwRpzAEzgRXAOmA7cFG1BE8BVwML6mGv0tQG3AKsr++4nt86HmmggHOB1yon8InGGi7ArOr2rGwdiyRJkiRJkiRJkiRNeU5G04RTkyRvrLc3d11H65ikgagvUa3uq4e82vljmtKqOs5iYBGwHNhV5V8P1OtlrWOUxg2wtIr+7QQuAFb1tQCrgLPGqxqmleI1EVyaZKQi5sVd190EPJDegxNeTnJ3EoDru67b3jpYacwAc4GtwCO1bK3yUAGmA3fScwB4qHW80pipYoDXHqwYIHAasAl4AljUOmbpiByiHOxJ9bq/HOzZwOnjlQNIAwWcA7xQ1e4frbv+/L7t84Eratv+SowXj1c8FlqWpEE5RBdoPvD0qC7QkioWKE0tlQRfd7AkeLw5F0hN1ZDn40leqVXzkqzpuu711rFJA1FdnX21rG0djzRQ1c9/sZYlg/y37QKpuUpyl9bbLV3Xvds6JkmSJEmSJEmSJEmSJEmSJEmSNHH9EzuT5zaqII/jAAAAAElFTkSuQmCC',
}
--[[/ICONS]]






-- finished!
return library
