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
    win._dot    = new('Frame', {
        BackgroundTransparency = 0,
        AnchorPoint            = Vector2.new(0, 0.5),
        Position               = UDim2.fromScale(0, 0.5),
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
        main.Position = UDim2.new(0.5, 0, 0.5, -floor(h * s / 2))
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
    ['caret-down'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABBUlEQVRo3u2XMQ6CQBQFP6VaKQex95xaaCOFF/IoRi1lLPxEYzCyLCub+CbZhLDJ/hkq1kwIIYQQQgjRk6LtJdA8zsxs6c9HM7uamRVF8fXgPgw2FzBgCqyBs68dUPpeEnlfpc86Axdg4y7Bh62AE09uQJUi4k2+8lkNJ3eJDkgS8UU+KmAKbIE6VUQH+dodJn0CDFgA+5aDoyPeZlQfZux9P3xGyogOXz5OPmVExzPj5VNE/Fx+yIjR5IeIGF0+JiIb+ciIPOR7RCyAeVbygREHX3nJB0TUtP+KjC8fEJGvfGBEnvIdI/KWb4koefwGN7e5bSr5wS+3L4I/vU8LIYQQQvwjd2KmjH30cC6fAAAAAElFTkSuQmCC',
    ['caret-up'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABBElEQVRo3u2Xuw6CQBBFLy1W6n9orb+pjTRa+EP6J8RYwrVwCMb4WHAXJvGeZJINEeachEIAIYQQQoj/JYv9QJLNcQJgaecTgCsAZFn0lXHlbeYkC5IXm8KuPQb64kn+QLJiS2XXfEZ8kfcdESjvMyJAvrbxFxEgX5E82lSuIgLl9ySnNns3ER3kZw+/nbmI6CnvI6KP/It7x4n4RX70iBjyo0XElB88IoX8YBEp5QeJsBty3v8G17HlO0TU5pD3CViTLFPJd4gozeXngOjygRElyVXfV2jL9qtql0L+RcTcdjV7N59eoezdw4wJgIWdz0j8Xfu0dwmAQ+wVQgghhBDiT7kBqCSNkw2of2UAAAAASUVORK5CYII=',
    ['caret-right'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAA60lEQVRo3u2ZzQqCQBwH/3bLTuV71Dmfs4te6tAL1ZtIdNTp4IZiH6hE7tZvQFgUZQZUll0zIYSYkmjsjcB9uDCzjRufzOxqZhZFox/9HQADYmAHXNyRA4m7NrVir4AtUNBQAocgIl4EhBPh5OZABlTBRdzFgBWwd9KKUIQiFKEIRSjCK/4loqKeisdeBnQilsCRRwogHRowmzosCHq+Qhn19Hxq3cHypTu/8u4j/hX5xP0mJS95yUte8pL3B5rV6ZznS4v+yrcCUp4v7vot/yYgDPlWQHeDI/u2/Ke2mNZufLZQtpiEEOIj3AA3W4sp30llXgAAAABJRU5ErkJggg==',
    ['check'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABB0lEQVRo3u2YMWrDMBhGPyUnSS9SQ7qlx+ixOjT0IjlFunvqDUqG8LoopDGJa8lg/cP3wMhgkN7DsgdJxhhjjGlHai0wBnC5XefxLEkpXbVXrSUnyHeSPiTtJT0PnsUEuFw7oOfKEdiEDhiRB/gBtmED/pGP/QYmyPf5WbxvwPKWt7zlLR9HPk+QgCfgJY9pzqRLywvogC/glMfqyRfdNnmSFfB5Z5HX0kUW3/MjAcURTT7YwRbqayOa/m0mLv4woqn83IgQ8rURoeRnRMSRr4iIJ18Q8Z2vePIFEXHlKyLiyRdExJWfELG4fPXh7h/BTtJbvn+XdJBuD2BDBgwiHp4eG2OMCc0vcg8C5aWht+kAAAAASUVORK5CYII=',
    ['minus'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAiUlEQVRo3u3TvQ2CQACG4Qd1EBNjQW/tNBaOZME0xi2MiYvI2UAChB4x39Pd5Yr3/oiIiIiIiIiIVaqmE6WUfn6PI7YLN37wxBulqsbJo1EXD2fccFg4vvfCFXcYbmI3s3iDC+qlqwfqrumBdhq7anM30KLByW89ocbk9PmDTxwRERERERERK/UFRYwbVJNa74UAAAAASUVORK5CYII=',
    ['x'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABfUlEQVRo3u2ZQVKEMBREG/UCwGH0Sl7BuYe60lnM2rmGXkZPAO2CnyqkEJKfDwlV6aqsJkm/noSE+QMUFRUVFUWoWutA0vW7BdABYFWtDlNJ41V5TFgDeATwAOALwAuAbwCwCiI+ANCI1714PQP4UfmQdO2JZM9BHckzydZ9bgEvrSX5Lh4Uz5PaRwbekbzyr8xCTODPI3inqzCYrYBZCA/4Xrz1X5IMrkm+zRioQ3jAd7Kd6qhtOjJqJvtTHWIy5xJ8Y/KcWYbwnMsO3jJEMniLEMnhY0JkAx8ZIg94RYiGw1GYD3xgiIu0vOADQvScv8XTwweEyBd+JkQtW+Y/XaSPGfxN6vDJdegtdOiHeATf8mjH6AR+7X0+r4ssAL5hbq8SSvg8QmjgZ8bu8yvMEt5yjmTwyUJsYbhriK32bUAIfVllZHLiBrepR4i4whaXS4smS+wR4oPGpUXzk2IhhNcKhJTXXcn7FfuU1z8xlPIXy+uH/4OjqKioqChKvzT3IrZ4vN59AAAAAElFTkSuQmCC',
    ['magnifying-glass'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEDUlEQVRo3u2Zy29VVRSHv1samkALtiWhTgQpNkgLMYGRDJTwJ+hY40wnPmKYgwNNTEgYGXHiK+BA+RN8JQ5tJEqiKdSqE14qPtpqX/dzsPdN9z09t/fce05rSfglJ7n3dO+112+tvdZdaxXu4z5KodbtRrXxsRcYBkaAPUB/fD8L3AFuAr8DywC1WtdHVkMgKr4NOACcAk4CE5HAjkiIqPBcJHAV+Az4FJgB6lUTKaS4WlOPqOfVn9QVi2NFnVHPqYejrE1THHW3elr9pQOlW2FGfVnd1ZC/0cqPqp+oS20Uq6uL8am3WbuofqTuL0Oi5UVMBI4DF4ATecuAW8DXwCRwHfgj/u0B4CBwDDgO7G1x3pfA88APUFGQZyz/VQsL/qieUSfUvqwVExl9cc2ZuCcPX5T1RB6B3erHLVx/qZNAdDUBHI57F3PkXlIHShNILHdaXc4cMq+eVfs7tVYitz/KmM/IXlJfKu2FKOCo+nOO5c+q28scEOVvj7KynphWH+1afuLq8zkuvtiwfFkknriYc86bXXshbnzEkKezATtRVZAl12kiJ7CvqQ8XPacnFRpxCtiXWfcBoRyoJM0lMq5G2SkOAE9mdGpPIKKXUNukWt4ALlelfA6Jy/GMVKeTOboVIjBMKMxSTAJTlWm+FlPxjBRHgcFuCIwQfjGzBBY2kMBCDoEHc/QoRGAPsDP5LjAN1dfxGZnT8awG+gm3oWMC/azW8xBq+ruVa74Wd+NZDfTSbMjCBO45ZAnM5liiUDCVxCDNnl8idHMdE7iT2VgDRqFYTu4UicxRmlP3LPBrNwRuxifFcaCvcu1X0UfoGVLcAG53Q+A34LvMu2PA2AYSGMsh8C0Fk0eWwArwOc0pbQR4Gqq9Romspwh5v4E6YYJR70qoejCnwNrMYm7K2J11K7hmGH1sTMdE23L69VKGipvHcyyzpL5m7H9LKt+qoZlSx6royFBfce0YZT6SGOjUSrZvKf9VX6jkmkYhuwxzmywa85xxq23qv+/67q9jrf2GkUceZqIlj1h+rKJh9PiuOtSJF4oMtg4BbwNP5C0jDLYmCcOtaVbz9yDhF7bdYCtFndChvUqYaJerghMr7lvH9Sk6GS3+E69NNs668kQREgPqi22uQVFcMwTsQ1HZ7JS7WhIJkZp6yDD6uO7awdd6WI6Kv2FMlfEZ2jQSCZEeQ4A/p36oXlFvqXPqQnzm4rtv1PfVZw1XsaehTBUkqvgX0zbCJHovoQ1sdFJzhJL4NmFivQJrgzKRMwScA56huUarNrA3Av/bddpAEu/lkKirF9QdW5JAhsRwCxJ/qo9vWQIFSPylntjSBHJIvKP+rc6qb2Wv0BYL52YSETuBx+LnK8Shw5bLRPdxr+I/74UMj7KOsDEAAAAASUVORK5CYII=',
    ['arrow-right'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABV0lEQVRo3u2ZS07DMBRFT8pnF0ggxIA5Yz5igmhZAxJC4rMiBjBhC4gxsAiYIiXsgRG9DOJSJzGiokmw0TtS1Y+r+tw4iZ9dMAzDMOYg67oDSZOXC+75AyDL2ul60JP8LnDrHnu1tniRhKQ1SS+akks6cm1/rThTgH1J76pSJBHCG4FnNYk/xERO0qE7dZIOMbQQFsJCWIh4+G8hDiS9/iZEFvpR9/kqsMG0iuySMTACzoClWtsbcAncQbOKrbzzUm4DV8B6D/Jf3QPLhEv8AjgGHuohFgNfHgCnwGaP8j+xApwAT5SjVZFNmtAIjIFrYIt4TqEcuKF29CG+i/ic5kEtgAvgHtpbirbCDLfR3M0T8c0Fnvzom4nM5E3e5GPB5COQH7rSOB15L0B9azENeS9AaGsxfnkvQGhztzX5TisjT3CHco0BZVX5CO0UZsn/wWEYhmHMxSfuSPx5FFtabQAAAABJRU5ErkJggg==',
    ['gear-six'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFm0lEQVRo3u2ZTWxUVRTH/6+l0EhxA20CCvK5MZayEYygKInRDRsxujFqdKHEYhWEnXHFSqMmwEItJoKJLEyMYsSNLgDjR9QEQQi2UvlQoQQQLLQytD8X90x7571730xnRnHRf/LSznvn836cc+490gQmUBOSahkBSWqUNFvSfEm/SeqRNJIkSR5Pg6RFkm6S9Iukk3k8dQcgYDKwHNgG9AKDwAlgMzDXaNI8sm+bjXbQeLcBd5rMEr5/w/AEWAK8A5wnixHgMLAOmOEZPh3otG8jAb7zJnOJ6ai74QJagOdt9MqhAOwHHgEeBvbZu3I4YTqm1WU2PONvBnYCVyswwsegPePBVeA9YHbNTpiAKWZ8bKS/BrornJkijhvPNzkzs9N01+zAHKAvoOAw8AxurSfAYuAt4EKO4eeBN402AVqBtcCRAG2f6a7ZgfnAqZTwPcBCf4rt/yZgFfBxaukMAh8B9xpNeokuNJk+TpruXBsnVeBHKEDvldQrScX4nSSJgIKkLyR9K+kBSXdLwug/k3Q5wCOTtc948vRW7UBaGL4ho4RjvwckfWBPvvAxJ0JDXdaJShwYN8ygRC5TS9KwJMpk26oWe00zEDC6SdKtckunQ1Kbfe6XdADYK+mwpELAmbTMkN7KHPA2TrOk5ZJaYso82nZJXZJWS2qNOH1W0m5JbwCHpJJll3ZgmqQVkk4BQynaOCwqNALLgPeBgUCIe86LIAmwBlfXVIoe4EHjLcrpCtBdBnYBd5hNZQ0XsAB4BTgTUX4GWOrRPwT0j8N4X84aT85S4HQO7atmWzY728tJwJPAUcIFF8BFYBPQYDyLbTTTKNiMfG5PL+GM+zPQbrIagBfJT4RHgafM1owDK4BzEca/cYnmPiwRmZDuAG0f8CwuizbbM8fe9QXo3y4aZH9XAZ8AQxFbzpmtmaWzPkA8DPwAPAHc6NEK6CA75X3ASuLngZUBJ06bLJ9uGvAo8J3ZkMaGUR0e05YU0UXgZWAW2ZJBuJrfxzVczR+sID2+TqP10RnRMRN4CfgzRb+1SNNg8hss9Pk4JOk1Sb8nSRIKYYtTv3+1EBkMd9673UbroyNNa/R/SHpd0k8p+lazedSBRklTU0QDkq5GgtYkjSWpIo7LJaxy6DdaH22KJ9WC2eLjBrN51IH/O6IJoOjAsKxS9NAiaXKE75qyo32LsrMSQpvR+ug3mSE0yWVlH1fM5lEHRuTSvI/bJL0gaWZkY/6Y+j1XroyIbmLDaqONyvL0zZK03mzxcdZsLtnxGyJh9HvgMbyD9n8URh833flh1FOQl8iGcMllFaVJJ5bIOskmsk7Ciazbk9mES5afkp/I7iKQiSspJS7g0n2xlGintlKih9JSYiPZmF/ECLFSIjXN5Yq505QWc2uorpjrp7SYu51qi7mAI424EnYX4XK6y1NcTTndazx+Ob0uQDeAK+mXUa6cjsxGM24zXUoJ3kQ27bfj1vMZwktwxL5tZ2zZ+DI2pugvme7mvFEPZr9i2sedhPZLuqTSWJwEaA9KWitpiyJHSrnbidiRMv3iL0lfShrKO4lVe6jPandKCnJn3wMa/6E+dAQtu2YqcSAkKN8SZyiKZ9eKBqUS1DQDQEnl6a3TqZLul1tKkru0ylxspXiqmoFc2OaZR/bidg+wKLARm4B7gA+BKx59tVeL8yqOPDkOzAaOBaLKEdzFbKuFw3bcxW2o8VFE8XK33XimA0/jLorTOGa6a3ZgCrAjYlABd0XejbsyrxTHcWfhr4j3HN6lTtfr16PBscN01rVL04LLwNW0mPZTeYupy3TVt+HHWNnQgcumoco11uSbYe/ymnzbTXZ9m3wRR5pwrdGtuIrSb7POS4+e50jZNut4UWuju0Gu0b1ArtHdK2m4TKO7Ua7RPUvXo9E9gQmU4h8/xzPqeff6pwAAAABJRU5ErkJggg==',
    ['sliders-horizontal'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABv0lEQVRo3u2XzUrDQBSFv6St4KLgI4gi4lrXunblE7jrvgi+gHsfwZUv4bp73RZEKn0E6aotJsdFbyCtaZu/pgnMB0P+ZoZzk3snc8DhcDgcBfCKTiApOvWBFhAAIYDnFZ5+dwGYcA84B26BS+AI+AE+gDfgE1AVgWQWL+lQUl/SWFKoZUK737d++5b8T3xH0pOkmTYzs36dWgRh4pF0J2midEysP7sIop0kkkVuHwNnLAozTgt4ALrxYcAY+AZObGyU+F3rHwBBjiAC4Mvm31xPsTd8LWloKbDa5gk5P5B0IenAjoOEmpivmS9NG5qmzV/ROviSXlOmhyQFku5jwWPXQYY50vBq2pY0+6UnZcW0E+6FwAtwBZwmPPdsXJSMPtAD3oGRjemtvBwBv3bMw8g0hUlilkhZxI/AzYrAMclFDDAAnlkUZFbSF/E26riM5g0i+pFNt4ifqk4/spUgarGVaPxmrvHbace+qfwbl51ylQVQl6LPLb4uy25e8c7BrSOPI8tKUQdXuiPL2spwcDt1ZFnJ6+CcI8tLGQ6uVEeWlaIOrjxHlpUqltGqgnAObh2N38w1fjvtcDgcjkL8Ad06iS55fIr1AAAAAElFTkSuQmCC',
    ['house'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACBUlEQVRo3u2XPU7DQBCFvw2EniISR6CnASJ6RA2U1BwEiQtQcAhKzgBFhEQThERDFyQi0VGQwKPIGDnBkLW9GzuSR1rFWWfevC/74zU00USpcKEFJSWXG8CmXT8CLwDOBS8Z1ryklqQjSfeS3q3dSzq2e1XbnGv+RNJQv2No9+oH4WG+vhA5zNcPwsP8k7X6QXiY70vattavFYSn+R37HXZdD4gC5usDkdf8TF61EEXN1wKirPlKIUKZrwQitPmFQsQyvxCI2OajQpigi22+AISbWy8ltidpENt8DoiBefq/bkroYlHmc0Bc+AK0JV3PJD9L6sYynwHRtZrpuDZvUzmtDB2X0f8A9CDuO21Ku2c1Z73+Kt5iyWM1hIgNqzO9eUMkYAwoxGiWBjDz68ApsAuszEn5BG6AS0lvZSFKAaQW1Clwhv+UPLDPc0ml1lWINdAGdnJqtSynXbZ4CIBk7ucNn/XiJRIjXoE7Jgs2gdwCOqELxQK4Aw6BD/u+BlwB+8sCIGBkDSYjEOURvvQPsgag6lh6AN9F7Jg8dCQpvXfL+ovs50E0fQG2mGyDWTtJssfnjSCavgAdwu/hQTSz1kBy3C0TY6b/2RiafwKMgFvgq2ChL8sfpfpiaAIzU8g5lxyRL63L53yfjp+zfqIHRNH88ZyVkfMNayqVP962Ymg20UQT8A3FIdWVAilxygAAAABJRU5ErkJggg==',
    ['user'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEPklEQVRo3u2ZzW9UVRjGf7fUkTjRFpJ2YOWidVG/iIkRjWBckZjWjUtjXPiRoBtTFupfYMSNMTG4Y0FwYZSwcekCIS7EhQpE1FJdQIulQKiAQzttHxf3vfZwe+7M/TgzddEnmWTm3nOe53nfc84977kDm9hEJUShiCQlX+vADqAB3G8afwNXgL+AWwBRFEa6Eotj+l7gCWAC2AuMAANAze4vAQvANHAK+Br4EVgMGUxh85L6JD0l6XNJ15Uf163PbuPYEPN1SQckzRYwnsascdR7FoSZH5T0qaTFNuZWJbXss9qm3aJxDZYJotDkM4E6cBB4C+hLNWkBvwAngZ+JFy7AMLALeA54GLgn1W8V+Ax4D7jdlTVhmceG3Jf5M5JelzQsKXKzaf0iu/eatfWNxIFEp1vmd0ua8UyVrySNdBJ3eEasT3pqzZhG2CCMsCbpqCdzX0oayivqBDFkfdM4alrBA3ha0jXPtBktmjEniFHPdLpmWrm4+jo1cIjGge3OrWXgE+ACFNuMnLYXjGPZub3dtMJMI60980+kMvWTpEYVEeNuGJeLE8q5N3QcAcMO4vLAxUlgrnqKmDMuFyOmGSyAYWAwde1MAPNZXAOmGSyAB7h781nGNqkqm47T9wp3r4MacSUbLIAeV1v5kTeAm8QlcYJ+bIirLmLDsHEmWDLNYAHMATdS13aVdr4ej6d+3yDnA6JIANOpa3uJT11V0SAu8lxMhw7gNvFJysUjwItQbho5fSaMy8Up0wwDp5C76iklHgpcSlxNCrrQAdQkHfEUX8esTA5VzB3pVjGH4vPvJU85fSxPUZejnL5kGl09E0zKf6A5K+kNVTvQTBY1X+ZIeR/wIfA2sCXVpAWcZ+1ImTxJOh0pV4BDwPvAP119zWIZGpD0saSmspH3UN80roEy0ybvY9QdAYAm8A0w26Z5RLy79tN+pC8bVzOl0ZXMb5G0R9IXkhYUDgvGucc0ghtPDh4fSJrPaWpF0pJ9VnL2mTeNRt7FHHUyb3gS+Ah4PqOPgHniBXwWmCJewLfsfvLCd5S47hkDhtpwfQu8C/wAJUt2J/PjkqYyMnZH0neKH3+PyY6Bvsw5fHVrO2l972RwT5l28XXhiL2k9e+BkulxWtIrkrYVFXH4txnH6YxpNmMe8vM75PskXcxYcAcl7SyVHb/WTuP0PRgumpfOWg7ho5LOZZC9LKm/ivEM3X7j9iXtnHlqH4TWNqnjHpI/cmei2mjsM600jqvdZucQvKN493RxufSCKhfEuGm6aJk3vwetVYm/pzo2Je3vtnlPEPu1vlT5VdKD7QJ4QesrzcOStvbCfMrLVtN2cVPSs+0CGJP0p9PhN7vWk+x7RmFM0nnHz/eyp1+CyO1kvyeAN4lfNB0iLrR6/k+iY/IZ4FXzc5j4383//EQZnWrEW3prI8x7PCUGtJFeNrGJ/yP+Bd4wX8kmD+GAAAAAAElFTkSuQmCC',
    ['users'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFSElEQVRo3u2ZW4iVVRTHfzOOlqkl1mgXu4hlZREp3eghSOqlsih7CAqqp6KisIhuD0UgFD1FPQRBFHQheupiV8qgK9r9YlczDNFKrTRLZ5z59bDX0e2e7zvnO/oW5w/DOHt/a63/WnvtvdbeQg899NBDD3uBvm4F1NY/+4EBYBQYAezra6YudPQB4+L3SOihqY6uHAiD/cBM4HTgFOAoYAqwA/gVWAl8AHwJbC3JZI7PBc4FTgCmRxC2AKuBj4DlwNpuAtKWePwco96nfq8OW48/1VfVRerElnyma776bRv5oZhfos7O5feU/Hj18g5Gq/CP+oQ6KwsC6t1d6FipXqYOdO1EGNtHvV3d0iX5HO+rJ2UO3Nil/F/qreqExk6EoT71pohkiVH1d3WFKV2WmVJrWw2J97KVOFh9Sl0XMm+FjhXqhtBdYqt6fXBqnPNnq79WKFuj3qOerB4QqzRRPUy9WF2qbq+Qe9xde2I/dY56aIxNCF3z1HvDRol16ll22hPxwf7qKxVK3lFPqYpE5vgU9Q51c0UUF7UjkK38abFqJV5UJ9c6kJG4SP23EP5EPa5TBGJ+IJwYKnS8HNFvkgFz1c8qgnB+LYeY6FcfKwT/Vi/puHxjV3FpoWeTenonHZkTlwbpHI9atxdCaIb6VSH0ujqpCfmCwCWO3dg3NQlElo5vFvJfqIO5fH8he2j85HiLqKxNkFXP5cCaYnpuUz2k6rysgt8h+UDpwIHAxOzvEeCHglhTbCS1BDlmkFqHpkH4nuiRAvsFx1oHxhVjo8D2bplnskPF2ADdNZDbCwdaDWStA38XRseTGq496UkmAtOKsc2kVW2LzFar2WthKDjWOrAe+LMYO7Vb5oFZpI41x2p2j2g79FXY/oPU+dY6sA74rhg7FzimKessehcBB2VTw8DH0Hg/zQHOKca+C461DvwDvFGMzQZuADo2VNn8qcDVxfQqYEXDAEwIm7OK6TeAf9sKR8X9qaIKLrZNV5id/8dF21FiScNKPkG9paKIrTL1UHRSgHqXOlJRkR80XTR2VsNMZpKpofu0gvzX6tEdnO+Pbx6qID+i3lkVgL4qZaTcfQI4r5wGfoqlXA78DuxD2iMLgDOBSYXMZuBa4BlI+R82BoDjgSNI9eE00n6bVcFrKXAlsLHj/skieqz6rvUYNTVsO9p8syXSYeetKtN/jbo+dIy20fFOcKlMv/42vqwFXiedHlXoI9WJcW10/Ai8zdizfxC4LiI/nvriNhyrvZYmCC/HqQvU16y/ZXWDX0x34elZ9AfVzxvKbwsuC4Jb27SZYtrAGxooHonlH+6QAq1vl6ln1KTQiJ2xIbhNydMp762nA/cDV1DdcG0jNXYfAV/Fsm6Nb6cBRwPzgZNDV1Va/AwsBp6P1DseOByYDBwGnEh6c5oD7FshvwN4ErgN+C2P/qD6bE0kN6vPqRfGd/3lMmZR3Vc90XTkrazRt950WdltU7rrKB0MW8859mpq6HzW1r3AdM98pMLYqPqhujCIdXMjQz1SfcD02FVijenhYIzOIhgLg0MVt0fUyZjefsrNOmx6SZjZlHiNIwMR7dUVTnxoepnoFIiZwaV8Edym3o5jT4Md6sOme23XxGtInK3+WNgZUi/oZMNdd+yHHFtzPkN9qRh8Rp26t+QrnFio/pbZ2WicSg11TFWfLri+2HpwfcHUwD0dubvnj6r1BPrVq2LFv1FvNr29dhOEI00ve6vU59V5rWN0EjAV2ES0q3v9tF1BgnS0Hkg6QjcAI13+nwKk43Ua8BddPDb00EMPPfTw/8R/DX04Ivtzt2IAAAAASUVORK5CYII=',
    ['eye'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAD9ElEQVRo3u2Zz29UVRTHPzNYoMUAIm40tSVuurIsIBIlyAKErutC/wBNSGRnaIhGjbLAFUmDGw1r/wBJjHEhMQItFlcuZCHVxJhIKzZUmkGY+bh4Z5zX1/dmpp0ZonG+yUvfvHd+fO995557zi300UcfffTRAUrdNqjWbzcB5bivAVWAUqm7LjuyFmTLwC7gGWAs/j4J7AS2hmgFWAJ+BX4EfgBuAr8DtU4GtW7N1AzvBg4CE8ABYBR4lMasF5oAloGfgBngc+AysADd/0KriMc1rL6pzqkVO0dFvR42n6776QXxHeoJ9Xu12gXiWVTD9onw1dZASq3IB/YB7wEvAQNNVCokcb1IEvOVeL6VZE3sBh6nsTbycB/4Mvx9C83DqvBNkB8AXgXeB0YKRP8A5oBL4XAeuB3kH4TMI0F6F7AH2A8cjol5rMDuz8A7wKfA/XWtjfh8g+pb6p2CT/6Lek59Th1q95OnQnIwdM+FrTwsq2+H7LrID6lnCxbpn+oF9Vm1nDacIrdTHVePxjUez8iRL4etC2E7i3vqh/VJaof8ZvWDUMzihvqKuqWA+FPqlDqjLsYEVOJ+Rj0VMnkD2RK2b+T4/Us9k/WbR76kvqGu5Bi5pO4tcI56WL2m1ppkmpo6q77YxM7e8JXFinoyOBbG5XH1Vo7yRXW0Bfl528fN0CmyNxo+s7ilTmT16kp7TDaULL6wYINJhc1sAdEHceVhJnSLJnM4fGdxPbiuUhhQz+cIf6eONSGPScxnsaBOq5NxTcezLE61sD0WHLL4KDj/I3xMXcoI/aYesSA92sg2V3PITxoZykammcwZxJWw0SzdHgkuaSyZhDuo29XPMgJV9bR5C2a1g3GTDJPGtPnptRzv0lgMG60Sy2nXli8X1e1lkt3wYEb3CvAJYIsd8AlgW+p3FfiaTIkc97V4V03JbwsbuQg9gY+DUxovAPualb5dLAk7RtEsWiapYy5nXjwPvA4UhlBgAbib+r0JOASsCSGSPuFQyNRxN2zks0v0SsBrwSmNb4C5dP7v5iJ+uc1FfLWDRXwsnYUGIjVl0es0OuXG0uh562k0pdBsIxu2+xvZrN3YyDJKExaXEiPZQaT01ltKzNu8lBhxbWo3uB3Pm8x0zj1pb4u5ay3Ij6tf5eiumBSaxYnFRll7xqSEzaLTcnrKjZXT90xK/M3aXk8wZNJE5PUEvWxolgvIn7WdhiZjeNCkncszqo2W8oC9aynv2KKl7HZTP0dy4vbQmvp2j1X2kxxzHKX1scptkt11ic6OVd6NCenstC71yXf4LzzY2shAenm0mLthNsN//nD3/3e83uag4CH9g6OPPvroo4+O8Dd7jU5z+VzFJAAAAABJRU5ErkJggg==',
    ['eye-slash'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFJ0lEQVRo3u2ZXWxUVRDH/9ta+mGkCkgIsVZBDWhCNEL0AZVKUdRoTXwQHmwT34jokz6g9SOCCcZEY1QSjGj8etQXS4xVkyYmJkrBj5QIRqwaIhWVUqWlFrY/H85c9+zdc/fu3RZtYv/Jptu958yZmTNn5n/mSrOYxf8buaQHQPS11v7mJSmXy2kmoSZF+XZJb0t6U9Ka2LOZC0DAJcBBChgE2uzZf61iRQbcBIxTjP3AynJGRM+AWqDOPrVnyvBgQNtCSyTtlrQs9niPpE5JB6TCmfCUu07SBkmLJNXbb+OSjkv6WdIhm/u9pN8lTU77ufK82AEMUYqPgAt9r9r3K4DvKI9JYAT4CtgJ3AmcP+07ZAJzQBcwHFDkXWChZ6yAjUCebBgH9gIPAi3TaogXy/cDJwKefA1o9gy4Bjia0YAIeWAA2OTLTEMuzQDDaklvSWqNDclLekHSI5LG5GrGRkldkurkYl+SGiSdK2mBpPn2fxJOSeqV9ISkfqnK2mMeqLMQ+rGM5/4CHrOx0bwGoAmYY58mYB4uNa8DtgC9wLEycn8AOiO51SjfCDwK/FnB9o8CDwA1aYt5RjZayD0HHE6Q+wfQbWMzKd8EPG3ejWMEV+Dih3XYPFbxIbSxNcAKYBel5yza4e2mU0UC64GtwERA2LfA3cCluFQaxxAu9WbKJN66Gyiu/r4RWy0cywrJ4TLOWEBIH3ClFwLLgM8D4waBNVUaIVujLyB3DNhsOiZOvoVwGtwNXERxzheOVuwPjE+lHClGtAI9AblHgfUlcu2Hi3EFJY5eYlU3tlibeT2Oz2yXqjWiBfggIHdv5Ex/Qh3wUmDwF8DyJCW8xTqokHJkNGIZsC8g90Wi9GoD1wPHY4N+weXssotTODudhCnHO3iUowoj2k0XH8eBmyMD5gbiLQ88TOjAJC9Wi6sFozFZk8CrGD3IAs85WyhN2+8B5wi4MeC5T4D5VXhsDvA4pfXjNPAsWQpSsdz5ppOPYaCtpszcTATE+MqEpGck7ZDdoQ21ku6T9JCk7NSgnI7TEUIBjzXjmOpkTO4JXJ1JpRyerKQQ6gHmph3i9ikcvoW4O0Mcw8A9aXI9OWspzXAjuJqVmkb3MbVc3gp8HJA7BNxBenq+DOgPzN+Bz1JJL2SZb0qeEsvJQDm8eRcA7yc4dUmRLt6kJCrRY96s1ogkyjEAXO3LpUC13wiM/xW4NagHGclcFUa04S4pcRRRDgoVOB73Y7g6k5xYKNDabYTp9EEc5a2v0ogOwpTjQzzKASy23YkwATxV0bqkX2hO4C4fK6gwHcZ2uItkyvFPewW4C9gDHMBdWc+u2GleHHaTfKU8jLsOXmsGp4YWhRvYZsKUYxeFjkQOd49ehHX2QkjrTtfJdRmeVGlHIsKwXPegT65rNyjpmFxH4rSNOUtSo6R5ch2/1ZI2yXUofOQlPS+pW9LJSroRlbZVVsm1OdaZUUkYl2sX/ibXShyXhCl/ngptlfoyMiYkbZO0XdKpKbcdvZhsxjWdBsjefcuKTJQjqyEtuDZgP6Xd62pwEjgScMoxKqAcUzFkAa4xuxPXqB2hlLyFEDV3vwZeNhlXEaYcR4DbyxkxpQAzoTVyh3OpXCt+qaTFcq3EBlsj1F4/JGuvm7jLJb0uaWVsmQFJt0n66V95veXtUPwFR2IF9easAr6J7cIocP20htEZNnwtxZTjSzt3wXkz6pWjp+QNku6VqwuvSPpUCnepZ5QBMSOi6+5kkvKzmMUspL8Bq4nHQXfgMG4AAAAASUVORK5CYII=',
    ['star'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFVklEQVRo3u2ZW4hWVRTHf984MzrjJUfTgRItDMNKu0k9RA8aXSCzwkiFfEryKVB88KUIeigQggrCh4IeIgSNNCzCjBAsodQSerA0XzRJTfPu5Fz89XDW52zPnJn5nPOJU/SHzXe+fdZel73X2muvfeBfjsq1YKpWH0fEbw9ApVJ/cXXlmCg+CVgCPBz/twPrgD+vlSF1M0BtVzepl+zFpehrT4wcXgjlUVfbP1ZX6YYdQrHJ6u4BDNgdNHWT21Av5QNzgVkDkM4C5uXGXH8DAiOBRUBT0tcVrYom4PmgHT4I93lQPZ5zmS+jpTgetHWRXXoFEkUWAhOTV13Ah9HSVZgYtMMjmGP2p6p7czP9UwTs5HhOsTfGlJZfagUSBR4HZuRebwSORduYezcjxlzfVYjZH6N+lZvhP9TZSW6YHX0ptsbY66o86iPqmZxyH6mNCU1j9KU4E2NLrUJjkWKBBrJtrxkYBYwGxgBjgfFJeyb6qugA1gPdSV939C0EWqJvLLAauB04pZ4CTgFngHPAheDVSbYJXIK+56jL/0LxVuAxsoTUHgreAIwL5VvDmOYwviiGvgOeAk5WhQXvNmAz8FDRgoaSncDfofz5MOZ0GHYE2AZsAS5cYUgs42j1HbXDcliRd4vElVaU5N2hvhu69mH+gnqxpIBf1elFPh0ypqv7Ssq4qC6t6l2NgQbgiXCNwWD4dFcsd0cs92HgbeDAAGMPAKuAlcBNEVetZEeLqlsOViw0h64fA5dSA0YXEJ8DvgYOhR+eAE5GO0VvwJ0HzsZvYcFSqVSqbrUZ+IYsiFvjdxxZrLUBE6K1AVOAR8niL8Xo0PmyAd3AHrIdJcVI4HfgtVC6VDWVjD1fNTaPxP3agNcpPvjtId3lEv/cVeBzPep6I/V7DRNPEo9TQ2ZPgT671duu0CMZeI+6vZ/g2WaSXa+h8rNDVhG+Ve8t1CFhcIv6aT/W/6zOq7cRiex5IaPICzaqtw4oO2F0o/qexdvqIXWxOqIeRoS8EeqS4F20ba4NnWqbuCBsVV+x7zlH9S+zpDSyjBEhZ5S6Uj1ZIOes+qpp4rpK5o3qi+qRAuYd6htqy1CMCP4t6psWZ/+j6jK1aciTFEIq6pMWZ9AL6vwSBswPHnnsj3eV0m6axMUD6s4CYctLGLC8gN8uo2auhe+gFVmSfH4APsm9vgDsKzE/+4JHig3A9znZQzcgR3tnru8wsL+EAfuDR4o7rkavqzGgjb6XVnvJat6h4ljwSDE7ZNXdgFuBabm+3WRFyBVI4qbRpLQsQGfwSDEtZNXHgETw3WQVWh/hqa8G/UhgAdmV+rp4viJnJGPykzCebBXqk+2T2Vyb2y0OmhQvCd1M9YNcAjwbfTPT1bD3EHkwx3ttzVm3RgPGqTtyQrZWk1i08erL6m/2jwNBMz4Z1xK8UuwImXUz4K7IjCnWJH4+V92idjo4uszukeYl8bEmR3M0ZNbNfRar3TklnlNvVt9STwygbFc/707E2CnBK6XrVhfV4ka17kL30/vBDrLy8T7gC7L6dkLBmGr9u4riOnlCjP08+J9N3o0A5tTLfYp8tHsAdzljLmDj+X2LT7YGr+5c3+UYK2tAm31vl4vQYxZ8T6vNqeDg06wuCJqeGvj9GLJLG9CsfjaIsMNmtUN7f36brEZ70B4ehOem/EQM1QDUhf0sf4e6QZ2jNtQiLPg1xJj1FtcCp9VnrUcuCCZN6kvqLyHwvNmxd6lRLV2NoGRiWoPHzuDZYfbxY5mxxQ6Gmi55glGF7KJpBtmdzOWD3FDvihIFJwEzyW7m9pGdUB22X/T/x38J/wDoSfnhAA2BPQAAAABJRU5ErkJggg==',
    ['heart'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEx0lEQVRo3u2Zz4uVVRjHP3fG0dFRxBmdSUcLAjcZRRphoYSQQSCKEAhZrlq47j8oDOkHtCncVC4CWwSaWC4yC8FyYRjRRIt+KaKVmjGjY6Mzcz8t7nOdM+995857x5m5m/nCgct5z/N8v89zznPe95wLc5jDHObQTJSKDFKrY5cAq4BuYBEwDFwH/gSuASMApVKpnh+AecByYCXQCbQBt4ArwGXgBuBEfgoHEIRtwGPATuBp4MEIZB5QBv4D/gZ+AD4DvgghdwNJhHcDzwLbgEeBHmAh0BLBDwB/AKeAI8D3wHCRQGqER1urHlCvWQzD6ll1t9qe+GmPvrMxpgiuBffaqp9GxJfU59S+gmRZ3FLfU7uivRt9U0FfaClNGkSSsZ3q5TpOR9U76sgkYz6JNlpn3Ej4qjfmcmiqmYlSKj7wFHAIeCAT3wjQB3wZ6/1foD1qYlO0zmxOJqi168DpaL8DQ8CyqItngIejxlJcAF4Avk3rK5v9LvVETgYuqa+o3WkWkhlboG5WP58kk6MxZnPY5PnqDq5LOfYn1M6apZQY781ZFr+pW61TSIl9l/q+Ws4hL8ezroK+tgZ3drntrbGPjmXqNxmDfvV5C+4CSQZP5gRwsjqDBf0Q3P0ZP6dDa43BFvVmZvCHalsR0gzxtoyvm9FXeDuMsW2hwYyvLVU/LYnDJ4COxMcglWIeLsTIuML6CjgI3Ix2MPpo8KU0HBoGk76O0FpJRpK1bKQ/qT1FM5YzCx3qk9E6Gsl+xldPaEnxQdVfdauaB3Rl7P8C+htiHJ/hQeBMo/Y56A8tDyV9y0PzSEuVF2jNGI4wto83E4aWFK2hmWoAo1Q+pFIso/KiajbaQ0uKgdB8N4AycDEzqBe4r9nqQ0Nvpu9iaKYlWbN91c5AD7ABaLj4pgMJ5+OhpYpyaKVUKt2dAYBzxHd8oBXYAcyfdfVjmA9sZ3x9Xgmt46ONb5Ojme3qH3XTVLbAe0GyFW8KDSmOhtZcg5esfNqm+Fhd2IQAFgZ3ijvqi7kJjc7l6pmM0S0rp6lZmYUkmbutPQSdCY11DfeoQxnDn9V1Mx1EomFdcKYYCm0Ta4iHi9XD1uKYumIWAlgRXFkcDm2FMrBBPZ9xULZyyF48E0EkyTtg7XnifGiafAUkQbysDuYU0f7pLuqkaPfnbCKDoaXhm4kF6tvWHhGH1NfVRdMRRHAtCp/Z2hsNDQsa5nLslHYoZz3eVt9Rl061sJOZXhq+bufwHDJ7+poCwaoJimpE/UjtbTSIxHdv+Mi7njkW3FPf+RKi+9Xj5uNrdX1RosTn+rDNw/HgvPdtOyFcY2Ury7tx+FXd5STnZ8fOubvUX3L8lINjzbSIzwmi28pxLu9+c0B90ziGpuSJfU+MGcixHw7f3dMqPkfEEvVV9UaOiFH1lJVbg9bEpjX6Tpl/8XVDfS18z+wnS7IM9qgXJljDV9V96spo+6IvDxfCV+Hrm+mcjY1RiHl1Maqei5aX9XLYbpzxrE8SRI/6lrU3aPXQHzY9TRGfE0ibut3KHxjlOsLL6nfqjlldMg3Mxmr1jQnW+9V4trrpWZ8kkFYr1+dHrGyXA+qn0dc63cIb/PesWBCBDuCR+P0jlTvSRu9G5zCHmcb/BZZZbQU1nI4AAAAASUVORK5CYII=',
    ['shield'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADLklEQVRo3u2ZvU8UQRjGf/cBiAmQYEMEjEqikcZgbAQtSGzsTYTOln9BlMLESi2stafAxFBSGBLtLKiAoGIBBZ8VEgSBu8fi3kuGuVnvgN07ovckm9y9N/N8zM7uzuxBHXXUUUctkQoVJRU/dgDXgfM18vcL+AqsAaRSpXZLKmY+BTwERoFrQKZGAXLAN+AF8B5QKMQR83bclbSqs4NV8+TODgDSEVmGKEyfs4IO4FHoh2yg1gBc9mp54LDKprMcHeAr5u2gXIAUpWdmBnhexRBZYAy47dTSBK7ZbIWEm8AUsP/XiygG2BxvBEYqaZ+upNFZRj1ArVEPUGvUA9Qa/2QAUVg6uEj26VWZt7x5KxsgD+x7tXNUd0mdAZq82j6lAxsMkAN+erXWAGGSaDJNF1vmrWwAgHXve3uAMEm0maaLjVDDIwGchdpSIEBnFQNcBC54tSXPY2kAB9+BPed7C9ALlOyI4oTD3WuaReyZpxJEBVjk6DRKAf1U525U1HKxbp4qDrACzHq1AaozjTpNy8Wseao4wG9g2qv1AIOQzDRyOAdNy8W0eaqcTNJNSWve24EpSS1JBTDuKU9zzbwcm6xB0rhHtitpKPR6IwbzGPeupzluXk5E+EDStkf4RVJXAgG6jNvFtnk4/oBZp2ZJE4EXTW8kNcYRwnQajdPHhHk4MTGSBgLXwo6kEUmp04Qw/pRx7QTm/sCppqsjMCYp5wlsSho+aQiHe9i4XOQkPTvtALlC7ZImA6d4Q9JjSdnjCBln1vpuBHgnTfN05h0xJN2QNBMQ27LRait3uh2uVuuzFeCbMa347nSO8B1JCwHRA0kfJPVFnXZnyvRZ24MAz4Kk/ljNB0LckzSnMJYlPZXU7bQvHt3223JE3znjTm7B6Ji5JelThJGcmRmV1GvHE6vlIvp8Ns5EV7t+iG5Jb1X65CwiL2nFjnxEm11J79wzVhU4IZpVuJPM6/iYt77NVTUfEeSqpJc22uWwYm17amY8IkhGhVXjK0mLkg696+KHpNfWJhOX8Vh3WGYqDVwC7mP7Bwrr+Y8U9rX5OP8kSWSL6Ixu8V1SDsL/8/73+AMgQoCUpvA8AQAAAABJRU5ErkJggg==',
    ['sword'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEUklEQVRo3u2ZTWhcVRTH/5PMxJISSBMrQYiLYK3poi6ajS1uBIUkG6moYEEQLYogFK2LSlvciC1tUVBBXUTtSmxd6MIPRMFqhKIgQu3GQNPUqoi2Jlasncz8urj34c3LmZn3mS7Mgbd4c++79/e/595zznsjrdqq/b+tslITAdF81ZTzImlREpXK8sdWRICHXyfpcUlbJXWneLwh6WtJr0m6aIkoHR64DngRaJDNGsAeP9aS8bvKhpfz8k651c86X5ek2yXVrIYy4SVpXNI+SWtyDmmenWrJ8JslHZJ0Q6zLKUlzan0GK5K2SFpfBl8iAcAQ8Imxn78DNgFVoMe4asBa4KPYcx/69nI94CfolfScpLtjzT9L2i3ptCRZESU4NyiBFXoG/ORdkp6Q9HCs+W9J+yV91go+ixUmIHDtPZL2SOoJmhuSXpZ0tEj4wgQE8GOSDkgaiHV5T9JBSfWiE1HuMxDAD0s6LGlDrMtJOY/86fuvlXSbb/tebmsV6pXUAoA+4C0j4swC26IMCgwCrwN/+esVoDeMLL5fj486HaNQEfDdwD6gHptwHtgRwA8Ab8bKiXlgax4B1U6A3noljUoalHRO0oykum97QC40hmMtSjoi6R1/P+DvH1KbcxfMt0HSTUWsroBbgGPAReAy8AtwGOj3qzdrbJ23/bZqtfIATeCNaAv5qwLc6ZNd3D7wSS4V/K3Al8Zgi8Bx4KTR9gUw3AG+4c/MYDBXD/AIcN4Ys0mLajQLfDv7ERjLAN8PvABcMsb8B3gJWFc2/B/A9gzwI8C73qtx+w14EljTET4QMAh8bAy2AHzL8mgTuXhvBvht2NsQ4DQwCXQlgg8E3AdciQ12CXgGV2FacPjfbwamEsBXgQeBsy0W41NgM0n2vCHgWWPQKdxrYbsVvgLMGOLj8H3AflwOiNu/uEQ3lBo+EPCoX4XQZoEJ2icly+Lww8BR7G14wXt5SWbOImAE+MGY4GxKEYu+PYIfA0606DsD3IvL6tngAwECxoG5nCJmgI245LTd31t2gv9Cb3Z4Q8RkGxGTCUREHtiLC7Fxq/vtFCW9/PCGiAngpxwiGtjxfR53kPsKh48J2IR9HtKIsJ7bgQulxYIb8NMdYOZSivgGXz6XDT+aAD6LJ47j6p5rAr+AS2hncoho4krxfOGyjYAh4HMDMColah50NoeI836RSln9x1iehUP46EvzVMLtdKPf96FdBu4qS8CrBtQRfMTwInZj1+2RzeHCbw14GvfyHtoFYEtZAp43gKa9y6sJ4CM74720YLQdI0+900HAHcDvxqRfAYeM1QQ4BZxLICoaZyMlJq9uYFeLVW4av0XemcAuO+Lwo6XAx0TUgKcSbJVpXLLrVDutDHxKEdMhUHCN414FI2/Vcf8RrAy8IWIXSyvJJi5PLAMKRIwAO3FV6P3A9WXCt/yi6iesyv25Ni6pX+5j7PuSfpWu4QfZVVu14uwq0pXvxJD/SHgAAAAASUVORK5CYII=',
    ['crosshair-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAECUlEQVRo3u2Z32tcRRTHP7tNSiIkxZrE11Tbh76JWKqiiSIUpH3XRvpW8jf0j6lGGqT42r4JNoqCSQqilhY0LfoY2mZLI9382NWvD/dsc3b2zu7N3XvXFPKFgWV25ny/58ydc++cgUMcoi9UijAiqfXzKHAcmAReBkatfwt4AjwCasAuQKXSP31uC070GPAG8AFwFjgJvAK8BAzZmCZQBx4D94EV4DvgV+DvopzJLNzalKR5SUuSNrV/bEq6JemypMmW3UEIH5V0UdKqpGYO4SEakpYlfWq2i3fEiT8haUFSvQDhIeqSvpA0XagTTvw7FvUYtiTdMQevWWR9lK/Zf7/Z2BiWJb1diBNO/EeS1iKEG5IWJV1Qsi+Q9LGkHTdmx/pae+eCzdmI2PxD0od9OeHEvxsRvyvppqQZScNufC8HWm3Y5t4wWyF+z70SjuQ1SSspxmuSrkgaDwl6OZDCMW62apHH6cS+ndBetllIMbquJAtV04xmdSAYXzWb6yl8n0sayeyAi8ycOrNNzfqjEbH/zknadvO2rS8LZ7gSdSUpNtsq2MBXUx6dhi11tZshmz8t6a6be9f6es2rGkcj4P5JliCyRn9enS+pG5KO9TLibMwoyTSL9rtnBG3MMePyaCp5Y3e34TbVUmBgQ9Js1mV0Thyxtt95s+pMsd9KGsviwIykp8HkRVmqLBvaS7GLgYankt4LNVT9RMMsMO7GbANfA43S1e+hYZzbrm+c5Iu3bTWrwcSjJJ/EHmvAbRjMJ6/juG3cHmdNY9SB48DrQd/PwMPSlXfioXF7nDSNzzEUDJgEJoK+KnAO8OnzH4vOX4DyrozZqwDTwCngiPv7XzoDPGFtPdWYbeBnKfl/J6Xdy5oeY+Id570IR/g+eCbpfc8XrsBoSt9QRMNp4DLwo0UrD6pm43TG8UMkR9U2Ay80wuhukRzA/U5vkh7hB8BV8kcfm3sVeIvO5AFJgL3GpmmMOvCEpHrgl+k68BXtq+U3ca70WqlUWnvnB+A86Zv4M+CS66ubxqgDj0hKHxOBoW/oI9t0cwIQ8Kc1oC07XQymPDaNzxHugRrJo+HxJjBVqPJsmDJuj/umMerALknRyeMUcMZFplQ4jjPG7bFqGjsdcI/H98CmGzMCfAIMl65+D8PGOeL6Nk1bfM/Zi2XsgH5O38r6OV3GgSaT8z0ONPOZAqGDeaRcNk09V/GgHuq7csYMdiurzGlwZZUF05JNfBCR/7uwtWIa+qrOlV1avKn00uKacRdSHx10cXfNOAutUBdVXr+j7uX1VeMq5Y6g7AuOL5WnmLtPJ1pXTCvqzNd50LSoz6msK6aII0Vc8i2Zjam8wgd9zbpB+zXrL/R5zfrCX3Qf4hB94j+0mD8P4phZyAAAAABJRU5ErkJggg==',
    ['target'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAGNElEQVRo3u2ZTWxVRRTH/7e8Ki2WSinl04WAuCCiIGIiUSjQIFF0AyIao66URA2ihrgwRlm4caE7Y4IiTZSNCmpiBD9AiQuQLw2JBJCFiBRohRb62tL252LOhXnz7u37aGHVfzLJe3PPnPmfuWdmzjlXGsYwBoVoKJQA8c+RksZKGiepTlKV9XdKapN0VlKrpG5JiqKoGJ2jJM2y379LuuSPLdsAb4JaSXMkNUqaJ2maRz5jMr2Sskb+mKQ9kn6SdEBSe2iMp7tO0juSVhvXTZLWS+ocyPiCxK1NBF4AdgMXKR0dwC7gOWC8pzdudcBHQJ835gJwn2dgWcRHAc8AB4DeMoiH6AX2AE8AVQOQL98Aj/wM4DOgqwhi/cBloCeBSBI6jfRsYGPCmH7gQ6DaN6CgI3nCCyS9L+nOFNEu8+8Dkg5LOhn7t6QaSVMkzZQ0W9J0Xd3gPvrlNnqdpMqgv1nSK3L7SEXtAW/llwEnUlauFWgGHgYagIp4XIKeCpN5CNhsYwuhD9gEjA31Fkt+YQr5HuAr4AGgsljlnt5K4H5g6wAuOWjyM3CbNUQbsB4YXZLi5DmmAoeGjLynfBTwaYLif4HVsaukrOxkYB6w1No866sk+ajsHWryAp5NeLVtRv6KUk/+ZmAVsAU4ijvyuoBu+33Unq0Cao38x+SfNuWT9whNAvYHii+b21QE5CuARcAPRrYQuoEdwLYhXflgNV/Enbs+tsU+78lWAmuAM0UQL4Q88sAdwOu4G39iQaM8V9gdKG/FnTa+kZGR7xiA1GVr5ZCfTu7m3oLblwUNWEx+bNNM/gZcDLQkkGnHHa9rgUetvYRzsf4E+STyAp4M5C/gjt2C7rMhmCCLu6TCDbsjgcxBYDkwMkG+uRjyHpcmXHjh4w3S3MgejAS+Cwb9QX60uIr8DXsQmBXIDRSYpW5Y+99A/v3wDXDDQAZMwR13PjbjhQdABhfQhW6zfCjIe1wi3DHr409sM8eoCOwYJ5dR+TgsF0zFGC/p7kBmp6Tvg746Se9KejqYp9jADJvbR71xTDXATwNjJSeDSSZJagjG/SiXccWoksukyiLv9Z0MFq9a0hhfNhOMrZI0wvvfq6shcYwxcrmvL3Minthe712SHi9EXtLtwBK5fPlbSecDA9ol9Xl6RpgRqQZcKySRv03SFjO2T9IHktZJ6ilFcehCnabMN7AmkPlPLnnxZW6VcpKfQ0b4orWNAXlJWmbk45V9RNLkYK4a5XpEn3JdNc+ANjMiRiSXSfnkTklqCcYtUu7e6ZSrHiy19nJAvkpSU6AjKyu3eHPdEnCMyzOpBsR1Gx8zlZt6tkjaF8gslLTkitVRpCiKLkVR9Ku1S8FmbZJLUX3sk3QmWLyZgUyrcUw1oFXS8aBvtnKPrl5JW+PVMtRI2iArQCVdNF7fLElvK9c1u01nr9dXb3P7OBa+gZwJrL0VXB6duBw2DA22lxBKxLf8cpMJsd10hnl4GEq8mRpKeEY0kh9hfkJ+MLcIOJ1AJimYWwt8bc9CnDZdvu5Mwi3cDixIJe8ZUIurmPk4h0WCXouA51NIxSgUTrfjKnNRoHs+cDaQ3YmXjxRyozXkxy9byU9oMkaghdLRYmMzgc4a4PNAts8Wq3CWZkITgL2Bkh7gNZJTykZceF1Mxa7LZBsTdEXAOpvLx17jpILw3sJTuFzARysulE5K6muBlbhKxhHgvJHtst9H7NlKk03SsQLnrj6yxqXkulA1LpQOcQp4jPSySgZXFLgHl5Q0AXOtLxMS8d7iCuCfhPmaCeqhpbyFaQmuFL+JV81fB1vYusnc5lzCPPtwufGgKhTzyU9y4j3xpT0vp7SYwZXKvyC5HHMc7+QrC95kS4BjJOMcLrtaBowLXSvBVeqBB3Hn/NkUnX/hKnoFyZdSXp8v6T1Jc1NEs5KOStovl0n9LanDnvnl9TmSZii5vC4bv1bSL1KRZfQS3sRU3K2cpTD6zM2K/cCRtQ1bns+XYEQ1rmazl6H7xPQb7qisvibkUwwZj7tJdzFwdS4NHcDPuFt/QrnEh+Iz62i5sHehpHvlPrPWK/0z63Fd/cy6XwmfWa+LASnG3ChX2WhQboUjqxI/dA9jGNcJ/wOLUKVMKCdP2gAAAABJRU5ErkJggg==',
    ['lightning'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAD/klEQVRo3s2aT4gURxjF37gmLrosC+saQWKcHKI5moSIERXF83qIB7PXKCQYgrJXveQPJoonFb0pHl11yUFBEPQUYm4xGEgOYb1ESTaElYib1Z2fh/raqa2p7s5M9/TMg4aZ7aqu976vuurVN1tTRQCSj0OS3rfPP0r6V5JqtVpVVDoXAIwA54A54DFwGljpietPGPkh4AywSBNzwNa+FmDkB4FvgGcsxRNgZ98KMPKvAkeBeVrxB7CxLwUY+QHgiEU6hp+A0b4TYOSXAQdtnqfhhmWo47GWdYO8Yb+k45KGM5rPSFooMl6pAjzyeyWdkjSa0+X3MscvTN6uPcBMZLo8BRre9+fAvr6Y/x75D4BfI+TvA5cCAXPAlqICCk8hj8BmSeclvRU0eSDpM0kPJfl+4R9JjyqKcTp5u94G7kYi/xAYt+V0Krj3AzDcsynkkX8TuB0hPwt8ZG2GjbCPKRPWU/LrgOsR8nPAAaBm7d6IvNgnk+f0ivxYZFqA23UPJ9G1a0tkQ/ukDPKdvsQjkk5I+jD4+39ym9dZSYuex39d0io/DpLWSVqTZKnK6MdsMcACznEO+oSsz2QkUwvAz8DXwHvAiq5OKbJt8XPc4WQoJGD9DpGNWWAamADWlp4Vsm1xA7iAO22l9V0P3IwI735WyLfFl+2FVoYAAastwtMW8TzMAteAHR2LIN8WX8ctpbkDeEJWWHS/Au5Z1LNwH6i3LcAbcCIlYreTB7f7cOtTs/meZOVPlnqlBE+B3W2N4ZEfx9mBEN8Dm4rOT2+c5cDHKVP0l7YzYA+tW+cQT3C77PISBWyyoIRIvFR741iH3Za+EA1L9zQFlj2PfJ10LzXRUZCs0wZ7gbLQ0bLnkc/yUgdxC0ih1G4HrgJ/kQ9/M1pN/rI6hluCY1P0CEWdKkuXvXeBL3FlkLxl7xlu01qfIWAEt/mFq848brMsVKlIG7QGvAbs/59ZORSSoOmlTuPsRyi8xUuVijazMukToemljkfaL+IM4lDXyGdkZQz4goyKg7V9hXQvdZEUL1WVkE8DUi8rDjS91GHiG9UUGV6qCvLCHQ99zOCOkUmWDlDQS3VTwABwJSD2suKAO9jHvNQdXEGgN+Q9AcO0llSSisM4roQe4i6uFNM78p6ADbRWHL4FdhEvMd4D3uk5eU9AWHFo4MqIMRvyG7CtL8h7AvaxdFNqEDeBD3CF31LJd1wb9UjUJQ14t2qSBoPmjyR9LumWVO5PqmX8PlDPuf+3pElJ35VNvhBoVipukI5itrgCAaM4LxRDOba4ywI2pqzz88AxyrbFXRCwk1Z/031bXKKArcEeUL0tLihgJe5w8tiEnKNiW9zxmuaR7Om/z7wAmA+8SiaSEdUAAAAASUVORK5CYII=',
    ['sun'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEc0lEQVRo3u2av28URxTHP2vuYmwXdmwsYikyWPkhpUApLjEhXZooUpw+5lfrKG0kUApwayKlAiGBZED+C5BCCmhIRRqQHEyUhmsQQlgkcYh18tnAfVPsW3a87N7Nnm9tTsqTVrc3O/Pe9/vmzeybdwddLkGnFUqKbseBr+z+J+ABQBB03GTnCUjaI+m6YrlubTsNz5vAZ5JqDoGatXXcXk9BPHYDJed7ydq6hsC2SSmt0ZnqAeBDu/8NqIHXQpRnW6ftxook9Us6J2nVrouSRuxZq7EHJD1y1sAja2s1DrNx0bF7zrD4T4spOiTpqQPihaQrrUjYs12SZiQt2TVjbT7gr5itSJ4ali0TiEhcljTo4c0eSaN29Xj0HzTdLxI22ybQJ+mCpEZC4TNJx7JmwfFmYF7fZfet+h833a40DENfFoHURWyyBnwPvAEcJ96xSsBYEgThW30v8BFQAd4FhqzLClAFbku6AywDSizKsQSeBrBgGNb83f+qZ4YlzTveuS+p4jxH0oSkWYv3urKlbn1OS9qf0FGRVHVmed5sN900fEkMSjoq6YQZikKiLGla0u8podZMGpLuSfradEQhVzEbR6N11jZ4D2J95snVHMCT8q+kU81ivCjwZQO/ngFsRdKipBt2LVpbVlidklQqnIQTUoczPP9Q0pykgwr39F67hq1tzvqkzcR0YSGTIDBhCzEpNyV9HK2PjLGB9bmZMn7JdBfu/dkM8C93FQ8d+zNInC5sFkzxmKS7KWEz6WvYITGZEk53Jb1VJIEpvbrPz+X1mkNiLmVBf5lHl7vy9wAHgD7i1Pch8Afw3L5XgF5n/D/AVch31g2CICJ8FZghfmP3mo2f7XkJ+AB4OxpK+FZeAv50vTGu8Ny6JmlD4fa4IemxwkwyWoALCY8t2m7T7oyOmA5XFhS/KGcMg4tpzbCOS3qZ30wBnxMe+8qE+U+ZMLf51manB3gzgeMJdthoU2qmw5UhszVqtvcmMO02rFPweh4pc9VdIgLXgBtAHXgGbNjnMnCeMN4ahFmlK6OEx792ZcB0uLJitp6Y7eUEprphvQZx+voAOEL2Isbaqglj+4D3gL/aJPC+6XCl6tifB27RbBH7SkHb6JmUbXSqW15kBzNeZGNFEuhUKjGRkUrMFpZKOAC2msxNSvolZXyxyVzCg3nT6RFJn1jMp6XTq6az2HTaIdHJA8266SoXDj5BohNHylXTUcyR0gmZIYW1oJNKP9TfU3uH+mkVdah3wI9IuiTpuRmvautllVkbkyyr3Ld+3mWVIAu8yTDwI5sLWwAngR9gU2ocFbYqhMWtd4iTv6iwdQe4jVPYcmydAM44NqLC1nfA35GtPN7v1/aWFo+pjdJiMwJZxd1L6pLiblp5/XKruFR6ef0b7UB5vV/SWcU/NFxQl/3AgaQBY3/I7ltua9bnC21+ya1bWx67n9rV1G5qed1Z7TXgV3/qsQrPtmZ2b/kYeh2PlLmkKAJ14lIMdl/fabJeom3+q8H/f/bYafkPKdXFflcMwfUAAAAASUVORK5CYII=',
    ['moon'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEo0lEQVRo3u2ZS2yVRRiGn0NbUkLCzSJXL4lYNHIRxLgUFpq44GKiWzSQKEZWJu7U6oKNBuOFeEmjMXHrQqMJatC4QBMXCEpBEN0oBasSL5AYStvHxcxJp9P/3NpzDiTyJk37zz+d7zrfvPP9cBWXF6VmLKKW/5wLzALOAZdKpaYs3zqoqF3qevU59Sv1pPqiOi8x7MpCVHyGukF9S/3NiRhRH47zWqpLZ6OKR/QAjwO7gMUFUzuAZa13ZYPKx5816sfqqJVxUd1yxaRQovxG9Zi1Maj2XhEGJMpvUn8sUHY05nyKb9T57TBgRi3lI9YCrwI3ZVMuAK8DX2fjfwL/tsPBVRE93xNzPsev6g51tvpR9m6/OrMdEahYhaLwEqHa3Ju9HgJ2A+/FNUay9zMJlejyIMn7O9UzmXcvRM+n894p2AMLLvce6AQeBZZk4/3Au9nY6ex5MbCw5dpXQvTqupjnKY6o16eejXO3q2PJvGF1WztO4kkRSARuARYlr0aBN4GfC9YZIFSeMrqAjW3w9WREr81RD2beH1CX5R6tMv+4urztEYhYAdyajX0CDFaY/w/waTa2EthWNrLdBqwC5ifPw8AXADnHT54/JJTXdO1HgBtbpn1uQOKplUy87PwOnKix1tFoRIrVwBNAyw61ShHIqfAQ8EeNtUYIm/xMNr4D2J45qKUGdALzsrGq3CZJo0PAG8BY8no2sAd4ECg124giA0qEMpjiYqZUJSMEXiNs+BTXAvuAnbQwncolsVN9PyuJB9TuWoITarFaPVpAAC+or6g3tOSQq8JtDtXL75M17lZPFRgxFo3bHc+V5qVVInxPJvS0enO9gjIjiiKh4RL0vfpypB290UmzIhXvjs+96lb1KfUhdW7V6FXgNhfVzY14Kkun/Va/Qw8bWO9h9fM4/zMDqx2M8stGv6B21DJgvXouE7K30bxNjLhGfdrJ1HwqOK4uqmVAEbc5qi6dSr463ke6Q+1Xh6ZhwMGoX02v9WX/OKLuajQKBWt3qrerz6hfxkiP1qV6QF+qQ6mSIGAdsJ+JlPoIgWb/Mp2+Z+KAOQTieBuBviwnHKIdwALgLiZeTYeA+4DDVeUnnuov8MBeQz90ygZUkIehpHYYKtG+Atn9Ua+6F9zg5I133hb1PRO5Ow2HXorBqE99chOP9DmxpKqeVe9vphGJvAecfJUdNVSxxg49q/eFzsZITDudHG/T7yhQXsO50NOwnCSkay3uiZ43fAtYPpVoJOtfp74U18sxYGgoTy3aiZBN6k8FAsYM3Ypd6pJ6wpyky1L1MfXbgjTV0IvdOO1UzYyo1J2+FL2110A7Vhi+0nQ7zm3mGTjV5hi5gfh/RThWj/J1F/NkkTXA88A9VL7RDROuoUOEy9Awod04n3CuLIzPRRgDDgBPAt/B5Ht4MyLRYzhJm8FtUpxVny1v2GmlTR2GNIvbaPjG9rahFzujEcWnFZsoqItABbYSuti3EOhAtb7rGPA3cJLQT/qA0NVo+NNss78Tl7nNKqCXcW7TReha/EVojv1AaEeeioZMOc9b8iU6MahEIGMlwoV/NP5u3sa8iqv4n+M/c92G+yXUln8AAAAASUVORK5CYII=',
    ['fire'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFCklEQVRo3u2YX2jVZRjHv2ebm/sDdVqxNCvTmkRm1EwYXiwssC6iLqSCLuwiKM3LukgqJuoCoYgiosBIMummiyiIUKQIgkJTZ422mUYybabomrO25vl08T6H8+7de347f+MEfuHA+b1/nuf7fd7/j/Q/R6qaxoHs33pJSMpIUipVObd1VSafkrRW0m5JOyV1B8JqF4CA5cAJcvgVWAfU1bQIIy/gRWbjD+BpoL5mRRj5q4BviGMM2AQ01KQIE7AGGCc//gSeq7mR8KbPa8yNC8BTQKpmRBj5BcDRgOwQcDgiYhR4OCv8v4puGugB7gbmZR179euAyYDoy8AdwPcREUNAV1VFeOQWAp8CfwFnjVizV18P7AoIngNWWf09QH9ExH4buaoKaALeDhz/DWwHWqzNbbj93scXgcieSBuAN4HGiovwHD8JTEQcTwI7gPnAM0DGq8sAGz0b2d8Ttoh9jAOPV3wqmcElkYXpY8pGZ19Q/huwzCfkTbVeYDpofxhYXDEB5qwOeJ25MR0htJvIgUVuM/gsYmcHlbhueMPdjdvufIwA3wbTJTYqj8WmhGd7FXAy6HcauLfsqWQGGoD3AwcZYDNuR/okQcBP1mauAG2OBOI9yj2lzfhK4Exg/GCWGHA98HGekXhjriiS25oPBH1/x50zZU+fVyPzfAMzd5TrgA+By167ceD+AgUIeJbZ62dbydPIOnYARwKj/f608Ai0A+/iLmnjwFvY2VCgr4URXz9YcEoW8BDuxE2MiieiFbfgu8kdbMWM9rbA1yVgbdECPIPbA4NjwOqyFlayz9Xmw8fWpEAkvYnnS+oKygYlDVScfQ4DkoaCsi5JTfk6JAlIS7olKOuXdL6KAs5LOhKULZF0TSkCrpXUHpT9XEXy+Xy0G5eiBaQlNXvfGUkjUmXzOll4NkfMVxYtxiWKhgSbzUH9ZUnj5RIlly9KS2qUdFbStCdg3Hxlg9sQBHIG5kpsVXS78XaSRyR9KelrSS9JSjovEjkkCZiQNO19NyhhKIvAIklbJa2U1CnpBUn3efVpzRz5aeNStIBzki563ylJS4NIFowg+rd7VS2SOrzvpZqZs71oXIoWMCrpVFCWuCcXQL5H0vNyyV7fzyH736TZZ88pa1O0gAuSjkYEdBZDHEhJukHSJkkfSFocNPtc0o/2vzMioN+4FBcx+60PbpjgnoFzTiPPxqO4d0F40wQYBlZ4bXsjN9/1Jd1IrdPNwGBg9Dgu61zINTkNfEccZ3D5Iz+TfTxoM2gciiMfRLAv4vwjoK0AAR3AQKT/MSOfsnZtZjNEX0nRD0gsw2XOfEwBW0jI4ZBLBrxC7ko+CuwE7vQC1Gi2pgIfQ0BnyeSDUdjI7FThJXPcli9KVt4CPIhL4t6FpSK9yG8xWz4m8XJJZYHcQyVMF2ZHYg8u51lQhtnspazPnkjkMV+tZZMPRuFGYC9xnMDtIMtx6cd8L7Yma9PL7AWbxV7zVVD0C7pWeoZulfSOpAdizeQOnIOSDkj6Rbm3Q1ruhO2Su0J05PG9T9IGScekCt96vSgusiGeJBkZmx5TJCe/snN+VzGRL1dEmy2yYcrHsNnKuxlUU0gnbq8eIn7S5sO09ekzGyUTL2uSkXuc3CR3JV4jaYWkBZLaJM2zpv/I3SpPy91t9kv6StJJSZly5npFVokXvTpJV8st0nZJrVY+IXclHpU0JvfiqsrT9AquoEj8C714V1CSbqfPAAAAAElFTkSuQmCC',
    ['drop'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE7ElEQVRo3u2aS2hdVRSG/5ukjU0TMKkhaFptTUmUmkgelYoRgzhwpNIWwYIogoria6AzK1ghEwdOBEWstBOdi1KkIhVHGrXWNmKTPiw21WhLmyZRktzkc3DW5e67s+/j3HuuCegPB87dj3/9a62999l7JyklDCDz2ihpu72PSJqRpFQqlbTJZMXbsxk4AFyx5yBwc6Z+VcIRfxfwNcsxAty9Kp0wUTXAbuAX8uMc8LC1XWnZOeLrgKeAixTHJeBp67NqxL8ATAXEZuaAj6vAS8CaFXPCxNcCzwPTAZFngF3ATnv3MQ28uCKZMPEp4Ik8ET4GDDoTe9DKfEwBTxrXvypewAPAZEDUN0Cv0y7z9Fqdjz8tS9VfnRwx24HxgJgRoMcX4/TrsTY+TgM7quqEI+IG4EhAxHGgP58Ip3+ftfXxFbCpak4Y8Vrg7YDxc8BQMeOOE0PWx8e7QH3iDjiGHwFmAhNxT6mRc7j2sHzpnQUeTTwLRrglsJIsAvuIltO4fLXWd9HjPAF0JOYA2W3Cm4GUfwq0lGPMeFuMw8dbcYNSyIiAO4DfPSMTlawcDvcO43LxB3BnxUPJSfV7noElYG+lBhwn9hqniw+o9CtN9gPkR/97oD2JcWo22oGjgSwMFLNRU4jYsFNSm1O1JGm/pImK1WcxIel9486gVdIuT0vsyLRatP1VIpHoe7bajdvFD0BbIVs1Rbh7Jd3ilX2sZKOfwYRxu+iS1FeoU9ABx+NBSeucqquSDknJHs4drkNmI4NrTEPeYVQoA/WS+r2ycUmjiSlfjlGz4aLPtMR2oFlSh1d2TNLlKjpw2Wy42CKppRwHWiVt8Mp+llTNTTtmw8UGSdeV40CzpAbn95Kk81J1LqcczvPKXU4bTEsQdQU413n1i5KmKxVqkzFlotZKuigp7TgwbbYywa1T7kKSg2LLaKLDxVlJHpT0maQvJb0qqcGp89NbUEMhB2YlpZ3fdSqQyhjYKOkNSQOSOiW9ImnIqb9WuZlPm5bYDlySXcg6kenwIlkyvOjf6lQ1KHerslW5WZgxLbEdmJR0wSsbUIE1uQTx90h6WVKtZ+eovYe+PResTWwHrkg67pX1K0p7ycKBlKR2Sc9JOiBps9fsE0kn7L0r4MCPpiVexOx5LHDke72Uc4DD8RAwCqQDJ69xnGsY43aRNg3xh611ugk46ZGeAW4rRmr1zYSv2jP7/d2O+G6WX0GeNA3xxHsRHA4Y/xBoKsGBNuCnQP9TJj5l7ZqAjwLthsuKvieiCxjziBeIbhTy3uGQvQx4Dfjb+k0C+y3amTb1xrXg2RgDOssW72XhWWDOM/CXGW7KFyUrbwDuBx4Hbseu1J3I7zMuF3Nms/L7ISNZT/R3Lh/zlvptlHjDTPZme5v1nQ/wHjSblYn3srAJOEwYZ4lWkO7MsHKNe8Ol29qezcN1mBh3pCVtKx2irZLekXRfqJmiD853kr6VdFrZs0PmbDGgaJ1vy2P7c0nPSDolJbzrdaK40VI8R2Es2fCYZ/mdj48546ze7bTnRKNNsnEqx7hxNVZVfB5HOonW6jHCX9p8SFufYeMoW3hFg4zs4eRGRVvieyX1SLpe0b8arLGmC4p2lb8p2tt8IemIpF8lLVUy1hOZJU70ahTt59sUnWXXW/msoi3xpKQpRSeu1f1/E//jv4J/AEdpMyj5G7WwAAAAAElFTkSuQmCC',
    ['snowflake'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE1klEQVRo3u2ZS2hdVRSGv5OX2rQ1vVHRBq1CBwpWsD7SWOlAnNRBqJBCCyo6UosPqiKx7cSRIxVasTqxgtUIQgVBBWe+Wh/UloroQMUHNoK26cOCye29v4O9jndl33Nzz01OEqX54QzO2muvx957rb3OOrCABZzbSIoQIimV1Q5UACVJ0jLPvDhghi0DHgTWAF8Au4FjEWvJePqBz4EXgbEinJiR8fZsk1RVQEXSq5J63XivpD02JuPdno7PtwMdkvZpMlInSpKWRcaneNvmzsiGjgL8OAt8CWygdiTbgLuBTkDAZqP967vNOTtXq4ykRZIG7Ol2dGyVX8lY5ao7Wn539ticWP4aexYVdrxM0AWSdko6bc8ur8SeUoOjkmV8KZqbyj9lz06jFebAgKQTzpBTktalCnI6UWe8m7tO0knHe8J0NrWvrSlHjc/zLgFuSQ1wqfA48DgwkiFjxMaOAyRJ4o/IALDU8bbntS2vA98Dv0S0AaArfYmcGAHKjrcMvOmNd+hKF8PhZ9NZmAN/AF9FtOuAPk9whlUJmSaFCLcvGRfXcmBVRDtkOgtzoAp8mkPxdLAqXgjgE9PZFJn3gDub3cDlwLXArYRVbLexLmATcFDSb5C5ujSRv9xkdLnhqun6E/hG0q/AmdzyLSv0SBqW9JGkUUnlBmmxKumwpPskLXXZaL2kccc3brR0fImkeyUdmiLtlk33h5KelHRh06zkFAw3yecxxiW9J+l2SckUDiSSbpP0rqS/W5BfkfSEMi63rCPUDtxE/vhIj9N6QmZ6Hfgxg+dq4A7gLqCnBdmYLalNk2Ijy4EKtdqmzdGOEVLbQaMNAZdFc3uALYQz2+noncDTwGKyS/jfgbcI2epGYCXQSy3eqmZTXWDXCbMt6gEeINT3PxHq968J+fkvm3cDsBUYJAT7dHAGeAd43hZG5uQVhDTdD1wJ7AdeBk62EsiJQrmbxOfOxcr5kjZYsJdbONNlSR9LutNk0EBHQxsKgSbXQI9IOprD+FFJjyqqiaaLVgL1/wO3fZ3/9SPUKIgvAR4Crgd+IATxEUJBN5tBXCVUumkQ3wxcZfpfIqMJMOnNefkMMOyGstLoRuDSrA00w7qd/CyaR540usPsalxS2LadJ+mDFo6Dx5ikFyQ9pvqbeKuNjU1T9j5lNAGygnic0NtpBRPA+7YrDwPfZvB8Z2NDxjvRgvz0ImveBLBduEjSDs1eMbfU5hxW/Ue/D/RRC/anZE2AXHCKuiVdI2lI0l7VF3hvSOpT/TduQwci+X0mw6Niujaa7sWayX3hlN0fKRqXNKjs9DelAxHvYMQr05XL6FY+6tdGtKOE1DpTHDFZHmvz2pbXgYuB1c0UuxVrZ3K6TLvSWauatRCrTWdhDqwEVkS0/bhM4gwrET4T43J6k43FTkyYLI8VprMwB6pYV8FwGjgAdf2dEvAsoRcaYzPwHOGCivtJB0xmigo5P+qbQrW+5S4V01pMu9ZxXzSWX2hrMW7uxsY3aqG32tytkz+rcMq3NTB0b4P7o2pzZmxkEf8HOggf3D7rVIHXCNUqhNbiPdRiLiEUbR3MxT+CRnA7sF1T/2KK46OiUB7MeAeK/Mm3hdoPvN1YI9ehRGgU9AOf0aC+n3MHnBPz8pt1AQs41/EPeyVOxG9Blu8AAAAASUVORK5CYII=',
    ['sparkle'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEk0lEQVRo3s2aTW8cRRCGn/FuQLaMk8iWwRICjANYiBPSIgWBHaFwgQAhhyD+AAQl+QFcOcERTtzIB4GDJQQk4CRIEC5cFiI7IRcIGAQXECheEsGu492Xw9Ti3vZ87DCzu36llmeqq6urqqu6a3scMABIaj+OAhV7rgI3AIIgGIRa2QyQNCzpTUk1a28ZbdDqdW3Abkmr2sCq0TLJGhqgHTuAYed92GiZUO6XtubZwOZsxsxdBoYklYB1QGn50JdsMeV3AoeARwlXfhJ4mI0oaAEXgd/t+SvgbeDaQJPa4h1Jr0pqqns0bQxJeVFYCDmTlOxv05unQracG7IxZcJw6o0BjuITwIvAvL1/CbwP/GEKVIHnMhjRsjHrSUy5g8sMGCeM1wN0xvQHhHH/J1sxB5z4PhIT303ra/MFkrZJGpL0jKSGw9sw2pDxBM64krVN+VDEOXCb53lf/gHjIQgCBUFw0zwcFRrrQMt42prOAceszTurXtgKPO6dqD5qxuOPSzyJjeceSVccnitGy78CjpCnge0JrGPAvgjPLQMnCQu4G/a87PE9CMw4Y2aMhlK21269f7ukJc/jV625WDJedyySRszru+25TZ+TdFxS1cutptGOG08u5ZH0vKS6p+xr1lw0jDfRa9Y/7YVNHC5Lui9PEpeAZ4FbHdoqcMbaqkO/hfAMKHUhd9paGu4F7s9jwDSwx6NVgW+tVb2+PV0qtmItDT8C32U2wAmBJ4C7ve7TwN/WTnt9dwF7PRlxBrwCnAC+Jtxy22gZ7QRwGPg+s/LWxiR96sXkL5JmHZ5Zo7lYlLQ9KRec8Uh6ysuxutGy7ULOaTgj6SVT/h9PuVOSyo7wstHkKbAo6WWTVUoxJPUcSFM6kDQpab+kdyT9pOiSYU3SC573MNpaBH/TZB2z3WnS5opaiTlJJ63NJ3reGTQq6TFJryvcw+tKxrKkqQgFpqwvCXXjeUPhiT0a4YjYWshXfEJh8fW5whIgDWuSLilij1fnWXEpZiV81CR9YTpMqNs4d5RfUPqvpqakXyW9ZyEy5S9/RBhOGe8pG9vNHAttI7rdWY6mCL4m6TPjm1VY8nblIWeObZIeMBnnTWaSEUdT53BibCFG0A8KS4NH5NQr/xeOMSOSKib7aszcC0rYqWCw90LFoM8hVLYQOlJYCDkT9DKJ75B0UL1IYs9DE5IOK9s2elnJ2+h+9XobjZi0yINsKWVsQzEHWRG5kbeUOKj4UuJnJZQShUKbi7nFiFWJKube9Xjqks4qLOZ2ufx9gaPcmBnhopByOisynQPODdlfwEds3N0A3Ak86bzvNdp/9gMfAjVPVv9hHtxlOeHivMITdkTSOa9vxcYUqkuek3gFuODRKsBD1ipe3wW6+63bNwOahGG05tB2EF5i7SO8zG2jAXxM55X7YKEcF1tFIm8x9xtwzqPN0HkdCHDWeLeOAc4ucoZwV4pDDfjEGzN4AxwsAd8k9F80np6gCAOuE36JaUX0tb/SXO+VAblhyTyuzaV4uyQe72WpUNQ3Mkj+yNezk7cwqY4hHZ9Zt/x/ngwa/wLZ0S2Y1oqWyAAAAABJRU5ErkJggg==',
    ['leaf'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFBUlEQVRo3u2ZW4hWVRiGn5nx0DjaOGNjGkUQoYEUkmWGYSrdhEFiFx2IigoCLzOyMuomguiEWBhGpgVZ2eEmuigDK7ywwows6KKLLJJGK8/jOIeni7UG16x//+cRL5oXNvP//97r/d7v3d/69tprYBzj+H+j5VwGV1MdrfFoAYzHcDzCRS2lcs96AonINmA6MAu4OB6zgQvi7x3A5HgdwCDQDxwDdgAfAf15EhPOougWYAYwD1gIXAPMjaI7gUl1GHh7/LtNHXUnxiyBxOnOKHgFsBS4PLrbDDqA5cC2/ETTCSTCZwO3AncBC4ApY2VOYkwryZxoKoFEeBfhFj8EXMmZGq6EYaCPUN9HgePACULND0ahVxPmxwgmj1kCUXwrsARYRyiVSlwngf3Az8A+4Jf4/WBMoA8YiOIFJgLbgZszrSVzpq4EEtenAquBR4CeMpefAH4gdJAvo/hDUWRhS0xijLTQqqg5gUT8TOBZ4J7oVI5e4BPgXeAb4EglwWXQWqBtqOEEsom6AVhF6e08CnwAbAT2AoN1ik7RBpyX/dZPjXelMAG1S33HYnyr3qJOSpJtJlZn5EyxJZ6r7w7EAROBtZx5oIxgiFAq64DfoGptQ+jp8+PnvYS5ko9rB6ZlFIcbdQN1lXo0c2RAXR/dopLzCc8M9XX1eDxeUaekY+N1c9Q/s3hPVotTLvBsdXdB2WxSp1UjzMRvVYcSjiPq9QUJLFaPZfEeKIrVWilwxB3AtdnpncBThAcRNXDMAF4C7s5ilsv+EkY/yfuBP2q3/owTPep3mROH1GV1lk3uvPH7a2r7CE8y5uns2r/UeTWXT0K0Uj2VkW1U2+oQv6WM+M1qd2pE/DxB3Z5dvzdy1Z3AhozoX/WGsRRfMHaW+lM25r1qphURTVN3ZUQ71anliBp1Phu/zNChUjxarWSLiC5T92dEz5cjSsR3NyG+qP6Pq0trFp+QLTS0uRQPVgnerb5ZT9lkHJ3q1wX139NIAsvVvoRowDCpmxJf5e7dZGn/X1+pfMo+BwrOSbYiTEi7gRcJK9R03DCwlbDs/gcqrkrbCEuVqclvJ4FPa7d+tCOLs8k0pN5pac9uuGwyngXqgYzjK3V6XeWTkM5Te8t1g0T85kbKJos10bA0yTlWVxtfiXSmpf34LbV1jMWjrlAPZzzfqxfVLT5z5eOMdJ96YbytVcXXEAP1UksXi4MNu5+Rr82I+9T74u1u2PkkxvmGdVKOHbWYUEuARYblQ4qD6ukxED9VfdnQnlP0Glp4Y+5nQTrUz6yMRspmpmElmhsxoD6mtjQlPgt2f4FLaa1uMrwv18LXpi5RvygoQdU3rLDWajSJK9TfyyRwMM6JHs90pyITOgxvXq/GMUX40NAg6iqdlnLCI7qBF4B7Kf/UPgX8CuwBfgR+J2wVthHexOYSNnvnE7bRcwwD7wMPAweg7j2kQtcr9flqGIq1PaAOV7n2mPqcNU7+ehLoKiN+IJbTaZvDkOFV9TbD86Z54Zn7jxe4N2RY5881TOzPLX16VkO/ukddY9jtaNr1UcUWySYQdoZXJqeGgbeBNcDf8bcO4CrgRmARMIew0dseOSTsOB8lzIs9hI3eXYT90+ZqvUICAE8Az8TzJeJHAifXTyRM+B7C/wva47jjhB3pXsIWjGMhumwCiaguwvb5dcBuwoZttfX8OUGlNtpCaIVDnAXnxjGOcYwN/gNPkqZ3cgwuQQAAAABJRU5ErkJggg==',
    ['map-pin'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFhklEQVRo3t2aXYhVVRTH/3ccnfHbIUcnY5pIsyhiAh8MLCRKxIcwLUIiSnwIKh8ifCmprIeaB6GoSDEqiQQLJKQJQiox0elD+gQNTCskR8fye3KcuTO/Hs46zHLPvnfuuffOWP1hc889Z+3/+q+199lf90r/ceSqTQiklzWSxth1v6QBScrlquuyYjYneKqkGyS12ueVkibZs/OSOiX9LOkH+zxTjYDKrm3CayTNkXSvpLsl3ShpShFeJJ2VtF9Su6Rtkg5KGqh2yxQVbmUW8BzwKzBAdgwAvxnHrJR3NMTngDuBjjKFxwLpMM5c1iBKbjcjrpX0kKQXJc0sYNoj6biSPn/W7k1R8k7MlFRfoN5xSU9LeldSvqpdyjJfAzwKnCmQxV+AV4AlQAswGaizMtnuLQFeNttY650xHzVV606uz98PnIw4PQG8BMwergu4Ljjb6pyI8J00X5W/E058K3Aw4uxHYHHWjLkWXWwcIQ6az8qCMIIJwNaIk33ALTEnLtO1VnIFbGQc+yL8W813xdlfDnQH5IeA+V68E301sBLYAGy3sgF4GGj2wTgf843ToxtYVnYruOy3B8Q9wCrnPC0TgceBA0A+ktE8sN9sJkaCWGXcHu1lt4KR3gacDkg/AiYFAqZZlnsZHheBN4CpAcck4/Y4bRrK7j7rAsILvlmt1AJtQH8J4lP0k4xCtQHXMvPhsS5zN7IK44EdAdm3QGPgdBFwKiKyE9hppTPy/BRwV8DVCHwX2O0wLZkDaGboi7Uxkv0tgc0A8AHJMDjeSqvdCyev9yKtsDGwOWRaMgcwL5LZ1YGzFuBwYLMbaGLoS95kzzwOG4e3Wx1pqXmFAqgpEsc0Xbpu6Zd0VLpkDd8saUZQb6ukY6mdsz1mzzwajcPbdZqvFPVK9hqZAxgbPB9QslDzmGh2KfKSjgSC/PURs0kxzjg8Lpgvr3FcOQH0RYjqAptus0tRm2bUN7m7bjYb76M74KyLJK5PBVAsgHOSet33MZKmB4KOSOoK6q2Q1JTaOdsme+bRZRzebroG99IyDefKCeCvSMXZwfc/JO0N7i2Q9KqSvfF4K612b0Fgu9c4ivk4K+lPZQGDs+vXwYjwMcn6vlrzwKKAq858eHyJm7WzBJADNgdkvwNzuHQJUO5M3JbOAY5rjvnweIsi+4xiXQhJHcG9q9JuAKSjS15Sm6RNKvKyOfSZbZts6+jELTAfoYbsqznLyM3AsSAjHwL1QeZKXY0ewK1GA4564/Y4CtxUrPvkigWgZEh7X9JS9+iUfd8tDY7xZp9TMlTeIelWSbOszlFJX0n6XMmoQ1BPkm6XtF1Sg/O1TdIDknozb/JdZh8E+oLMbAbGFsqMe4cK7sgC27GR960XWAEZV6IR8hnAN8VGkHJB8ZGsA5heCb938FikX38CNFQhgAbj8ugDHqk0Qd5JI7An8lKuKdeJS86aSHJ2AVdULD5wdB9wPjJKLMwahONcaBwe54B7qpL9wGEd8HZkeNyLW9NnEN9idUNsAsZVTXzgdC7wU8TpFkqc7o1nKkN3cgDfYzN9VQMIglgeGTHywHqG2bsyuNdeH+n3J4GlIyI+EDAGeIahc0MP8Kx1tUJ168wmPP/pBZ6imoe6wwQxGXgn0gX+BtaGQTjxa80mxJu4s6bRCCDdpLcXCOIF7ESNwRO+5wuI3w7MHBXxkSCuJVnvh7gIvEYySTXY9cWI3WfANSPa70sI4nrgi4i4PIOHu7HV6S6SUW30xUeCmGvZLBWfAtddVvGRIFpI1vPFfvjrB7aRHMFffvGRIBpJTp57IuJ7gNexFea/RnwkkAnAk0CXE98FPEHWQ9oSMFL/lahRsitbabc3S9qpEfhFfkR+33dZ9n/2qPofPf4X+AeL4nh3tpQydwAAAABJRU5ErkJggg==',
    ['compass'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFUUlEQVRo3u2ZTWxVRRTHf/2MLWkjSNFIF4olaDCKRuIH4keIknanJrRlaQgbFxoNqQuJqXGrie5cSAsbXQhoNJqYQGVh6NNEbCIGqKwkgOkHocBr0r7ydzHn9k3n3dt733ttjUn/yUv77ps5//+cmTn3zBlYxSqqQs1SGJEU/dsIrAPagLVAkz2fBq4BY8AkMANQU1M9fcUWPNEtwDbgBeBJoAO4C2gG6q1NAcgD48BfQA74CRgBbizVYDILt88GSfslDUmaUvmYknRS0j5JbZHdlRDeJKlX0i+SChUIDzEraVhSj9le+oF44u+XNCApn0HYnKQZ+8xlaJ+XdEjSfeUMInXheYaeBj4Btic0nQZGgd+AP4FL2PrG7ZONwFbgcWAzxQ0eIge8BQxDlXvD8/wuSaMJnhuXdFhSl63l2tB7np1aa9MpadD6xuGCpBerWk4e6TMJ4mckfS3pWUkNWck8uw2SdpiNmRj75yU9VdEgPJJNknIxxickHZDUUqmXPI4WszURwzNs+648DhWjzUCM0cuSuuOWShUzXWs2L8fwfS7pjsxcnmf2qjTaTBhRVaHO+tdIqrO/0bPumJnIy4XYbJzW8O6YpTNjU12R5z2R9ZIekdQv6bikPkl3ejNxIGZPnJZ7cWYm2a/Sl9RxSa3lig/W+m65iHXFsztng4jatRqXj4LcG3vxWfAMDAUGxuWiTeal4y2TjUZ+QtJNxeOoLaeo306VhtgT5oRU0uckXQ86D9rUl7tMPpB0VukpR7/XN+o/GLS5Hjkxjfxg0DEv95JK9L7XtzlhmSyGK5K2RbY9W10qDSLvJeqwHxolfRd0GlHKBlIx7H4q6VZG4REOh7OrYrY7ErT91jTOt60NtKwDHgiencEdRBLFG54HXsedA+IwgcuXfNwCvsCdF0KMGbePDtOYOIA2YH3w7CyQtnPrgV5gTfB8DjgHfAi8Y4J95ICfITZpk3H7WB/qCwewNvDgbVxWmZYVPgy8HDy7ALwBvAQcBDYF5LeBLylmrPPwuC5ZuwjNpnGB53w0Bc/m4gjmXVRcPq8B9wTiPgY+s+/t1sbHOeCHFOfcMA2Ro+sDB5fMQCVoB14Nnp0Hvve+dwIPBW2OmYerQjgD07gN1Wjf63CHkRJ43u8EHgx+Pgr8DdwLdAFvB866am3SlmaraYhQIAgE4QCu4aoH0TTVmoeRFEfWAvQE4sZxJ7P3gT3AlkAEwI/AH0mqPee0B7bzpjFxAGMmwN9sW3FHT8UQ7MCVUnysAT7ClVbi3LtY6PRRY9w+xglCergHJoGLwbPHcOE1RFLobDIHxInPA4eAU5C6fNqM28dF05g4gBlcbPaxGXgCCF/hcaEzCf8AR3Cb/V1KX2jz8Di2415cPnKmcYEXibxhnU8BU7gNFHl0D27dFjyCV1gYOkPM4aLRMeArXKViNoPnARqAbhZWLqZImzkV8/ahIAcZl0txozZ1cilwHG7Kpb775FLpGpWXgkcZcZhOn1TGdDr1QGOfPi0sWF21xGy3Kjzsq3ge+SbgLpimdJvKeKSUOwb22cD6JT2qMsorCby1ZnM24B42TWVNY+qhXsHBvFJ49nolTQacedOS3TH6b8oqPYo/BA2Yloo8shKFrVZbNpMxPDnTUFV1bjlLizttw8aVFkeNe0nqo2UXd31Sz05U3O2SdETx5cRI/K4s4pejvH4Gd5IKy+vtFMvrHSSX138F3gROwxJdPXkeXO4LjkFVUswtcxDRFVNOpfG6EhTkrqv2armumBIGshSXfENmY0Olwlf6mnWChdesv1PlNev//qJ7FauoEv8CwwLC9xgesqIAAAAASUVORK5CYII=',
    ['globe-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFFUlEQVRo3u2Zy2+UZRTGf9OU0qKlsdB6i0awRGQhhEhokVgvidGdLkSLcWGirE1cyIqtW/8BxYUFXdqFBlHQkEALibGQaLSQeElAoLRJS4aWlj4uvvPVM2e+r53OTBtJ+iRf0p553nN97y+sYhU1oVAPJZLSP5uAdqADuA9oMfktYBy4DowBtwEKhdrNV63BOd0K7ACeA3YDXcAGYB3QaJxZoAiMAheBIeAHYBiYrFcwFTtuX6ekA5JOSprQ0jEh6YSkdyV1pHpXwvEWSX2SzkqarcLxiBlJg5LeNN31D8Q5v0nSYUnFOjgeUZT0qaTH6hqEc77Hsp6HuRzZXIXcFIOSuusShHP+RUkjOQZHJX0l6UrGbwP2RVyxNqM5On+X9HxNQTjn9+Q4f9uc26NkME+H389L6rJvOPw2Lek9aztguiJ+q7oSzvnNkoYylI9J+lBSq5IZJHJuStrn9OwzmceQtW01XWM53WnTkoPQf7PN4Zzy90lqMN47SmYSjyOSml0AzZL6A2fG2mK6+pTdDT9JdS01+/tVPtuMmaGUc4+kY4FzQ9Jex0m/vSrv88dMR8rpy6hEUckUW1kVjHh/RreYkXTQZT4dH+OBd1RSkzdm3CarjMe46Ug5DWYjVvSMkoWz4uwfUPkiNSCpLWT1UOBMSXo1ZsvxXzOOx6Ggs03lM9eskhV74SoYYb2S7UHsFr3B0DpJxwPvvFUvT/cDki6ENsdNl9fdazY9vlcy4Ev0NmTEsQPYGWRfA6ehZNP1MLA18M4AVxco8lXjeGw1XV73abPp8TSwPSqcD8BF1gusd5wp4EtgJrTtItk2z6sABlkYItmJ+jR2mC6PGbM55WTrSXa8Jd0oVqCJZEvsMQKcSzPkGncBax1vEvg1ZHIeTvYLcNP9tDYNQJLnnTPbHrvNx9wA2oHHg+wn4FpGNh8N/98ALrM4LhvX45EM3jWz7dFlPs6jMRA6gI1B1gC8BDSEAfRUhtFuYJukvNOJSLpCHOXbgVegpHvMZSR4o33/pIJ5Q9bwWeAbktNUillTFtEYDMi4i602BWvrg5yzthENIclF4GXgVNrVYgVaMmSNVIYCsKZCbpajTRXwGilNbuY0elchZvcWSSl9Nv5PXWjWfMwNYJykn/kyHQX6Ka/W+ySDO8UfwEFggvzbjnQQfwRsdvLvgI8Ddw54C3jbyYrmY24A10muPjYGRd8CCuvACyGAAski9WfeFYm1zZoyh0kmD7/WFIC+wBs1H+cRszoGXAqynUBnhtG/wv8bgIdYHA8a1+PvDF4n5VuaS+ZjbgC3LYseW4BdaQZddi8C0453L7DNZboETvYkpVuVadMVV/pdZttjyHwsD8A59iNJP07RDLxB+RR5kdJyFkiW+sWu2LoD53oagMMas9nsZBPmW/4tnm1lW2vYTl+wLXOe7k6VH/Ar3U6fqHQ7PUky89xxsnbgA6DNyYrAqdB2C9CTOuydN/QAT4Q2p0xXijaz5fc8d4AvzLeFodqPlEeUfaRco/KD/bgqO1IO5h2U8gKo5VA/quxD/TOq/lC/X4sdJzOCqOVapV/l1yqfZ1S0kmuVw+ZLZc6HKtTrYut1VXexNWQ+1HQ7V+3V4rBqu1ockRsfVcEFsdKXuyNms6431Ct1vX7WbC3LG8FyP3B8pmouc5cYRPrENKTy2acazFrW92u5nphyAqnHI99J09FZreMr/cx6g9Jn1p+p8Zn1rn/oXsUqasS/NUMGLXyShCQAAAAASUVORK5CYII=',
    ['paper-plane-tilt'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFbUlEQVRo3u2ZW4jVVRSHv5nRxDQt0yzTxltmpqiZZlreoiKoJyEKonqq5wqKIoggIqSkIoMSUjS6Qb3Ukw9qpmHRRbNIK0vTvGKk4yUZZ74e9j66Z8+5zs158AeHmfM/a6+9fmuvvfba6w8XcAGdQt35NiCHWvh3IDAOGA4cAHYApwHq6nqZ2SpqnTpUXai+oK5XD6un49/l6ogo2ysMRu2jNqqL1WXqFvW4pbFcvSgl0GNrkUzanxAac4BFwExgFNC3CjWHgDuAHwth1KcHjK4DLgVuAOYBC4CpwFCgvkaVgwl74iy6lEDi5QbgSuBGYCFwG3AdcEmVqk4AvwFXACOS502EVeg6AonR/YDRwGzgduBmoDE+r6gGOAL8BKyPn/3ARxmBn4GdnSaQGD0ImEjw8EJgOmGJG6pQcwbYB3wLrAU2Ebx+Iv6+ABifjfkCON4hAtHoemAYMC1OMA+YRIjNahLCKeAP4Kto9DfAHqAZQn5PnDOfcBYUcCISaHMOlCSQKOoLXAPMImSNW4CxhGxSkTdwlLD0GwihsRU4DLSWOZAGRAIpfge25YJtCCRGDwAmAHOj0TMIsVjNirUAB4HvgXXAl4RT9FjuvTK4FpiSPdsUibclkB3dMwixPD8qGEJ1oXEa2A1sJoTGZmAXNR79iS1zCWm2gObojHYoeHQMsAS4O3q/GjQB26OH1wE/EGqWlmJGZ6s7NTpmC3HTJvJ9oxNT7CFs9vbOUPur71kZLepBdY36jDpXvSzWMBU9Gz9D1LfVplgyvKVeXBgfZcapu7K5P4xlR1Hls9VDJYw+re6MCh5VJ0fCVRdUmfEroiMKOBYdkcrdrzYnMq3qY6Xm7EM47QYWmftgDKuPCfm6tdYyNplwCPAq8BBty4fcojpC0kiTxSFC2i2+l9Rp6t4i3j+j/qg+rY6pJlRq8HzBs+8UQih+hqvbMrk1aZgVm6iPujQqLIZW9Vf1eXV8B2K+mPEt6kr18ix87lRPZrLPlg3Z+OPl6hL1gKXRGvfDi+pEtb6Y0k4Yj/pSJntUvbXiysfBDep09XX17wpEdkfCk1MiHTE+GTdI3ZjJfxN11RS3DeoU9RX1L8tjr/qaYR81VGH8ioJBqVHx+yz1n2zMUmvIeLnCevX6uKx/WnqPqO5X31Tnq+92wHjUJ7Ix/6n31mx8ESJ16gTDRfu3CkSO2TaHlzU+maOf+lk2boc6slMEihAZqz6nbi/i5WIoa3yi+zrbp/JVlkgUXUGkUX1K/akMkZYYTpWMR30409OiPtKh+K+BCHGJHze0Q85kBJrUReWM8NxeW5mN/duQqrve+BJErlRfLkJiWbkwiGOvjiGZ4vO4L7qXQGbIiLgSKfYZzpZy4+4xZJwUT1YbPrX2ZcphH7CKtgXaVcDDQLvyI/m+kLadi3+BjdDDPdDosVFxY6fYYzgYi8lfpn6dyW9SB1cbPl25AhBuTquzZyMJZXSxkJhEaMuk2EBoBPQ8oldHq79kXt1lONVTOQw3uxQn1btq2bxdvQIQLvPvZ88agQcLxkf0J/SWUvxBaLucP0TPjjeUHSl2GkqSgsxk25fvy63x4tQdKwChCfVB9mws8EDyfQ7hOltAC6Elc57fXnB2FSYaqtgUOwz1VL36QfbbbkNHoqa5umsFIPSMPsqeTQDuI2Smmdlv3wF/1TpJtxBIDqDVhNSa4gFgcSSRYi2xydsr4LnKdWkWKs2GC1CKw+VKjvNNYqrl79iq69SBHSHQnXuggG3ApxVk2r246BVIcv5Nlm7ZNKkLel34ZCQa1FdLEPiko+HT0ySGqW/EDXxKPRLPgnF24urY0y+6+xHeFzcSmsdbaf9+oCb8D9VY6Clh3SlwAAAAAElFTkSuQmCC',
    ['rocket'] = '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',
    ['flag'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAD1klEQVRo3u2ZXYhVVRiGnz2jyYx/UGDUSGWl/VrWRUk3IaHRTUTkldhFXnURRJeKlCRFeBNId11EESZddGFFThQRJCoh/TjCKA4m5E/lXzqj05mZp4u1Tu45Z59z9tk6s8vOC4s57Nlrrfdde33r29+7oYMO/t9IinRSq327499xYAIgSQoNObUCImGAXmApsBy4D1gAzADOA0eBn4F9wBBwqQxBdcRj61WfVT9Xz9gY4+pxdYf6gtqnJqkFKIX83eqH6ojtYUwdUDeqdxYRkuLQHRu5xkh1XKnub5N4LSbUw+rr6l1qVx4Scf5EXaF+ENvjuUTEmxapBxqQuqQeVL9Wv1B3q7+qlRZCjqhb1IfU67LIpBZvrvpS3JJVDKi35RWwKhKtJf6ZIR761J5IZJ66RF2jblNPtHgqJ9Xt6lrDFp2vzorjLVSfM8TbaMb8q/IKeKpmgAl1kzq7xcrNVJepb6lDsV8jjKnH1L3qTvUb9VDGwlUxGnn9M++MNmKqAuwGhrOOxtS1ivoD8CPwLrAmtjuoP7a7gZtiK4Suoh2bIUkSkiQROARsAp4ENhDyxNjVnGtKBGQIGQLejELWAZ8AxwgZPAsCfwADTe4B2ttCVyQEQD0OvA98BCwClgEPALcAcwlP57dI/DvgdmAbYauVJ6BWCPAXMKgOAtu5/F4lk1e8ZWxMq4AmgqQmNvIkO5jiGJgOdASUjY6AstERUDY6AspGoUysLgBuBq6PYwwT3mFOABcAp8uNaEdAAqwAngEeiwJ64/UK8CdwBNgD9Kt7gdNQgrXSoCLTYJvkwYihTn7FUFsXdSRqOdRVZO3GQN77e4BHgS3ATuA1YHERIVeLUCOME7ZPI1ZdwGJgYxSyGbjX6PE0Qup/Pa04FgniYUJt/BVwEBgFbgDuJ8TGUkJxkkZCKGDWA88DO4CP1X3AOQhxkiI+B1gZ72/KsV0B3wNvAP1RSO3E84CHgdXA00Af9YX8QuBFYC2hRt4F7FdPAbOAJcATBP+1t6bvReBMS5YNAqgS/SBaPf64Re5RNxtcuWbWStWyqUSbpREq6jsG76iQgLoTIMcYicEXfVUdbOMUq8Xv6gaDW5fbWrwiARlCblVfVnepw20cx58a/NHMwJ/ymjgmMdVfgLeB94BHCEG6nBDc84GZhI8kIwTLZQ/BfvmWkN0zE+K0FfWpyc+q/cCXwGzgRsKHkjmEwv50FHAKmGiVxUtxJapPhbCyF4DDRcf6z7+NXtMCzhISRxUX47V/P7z8YW+rej62rfFa2fQmITPEnfxZ9cH4+ydSrw8ddHCN4G8inFZYmWtgnQAAAABJRU5ErkJggg==',
    ['bell'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEOklEQVRo3u2ZS28cRRSFv/HEYYQmbxtkCA8lWbBJggUIRAQE2IBXCC8QG8gvYJ0Vv8ArFhb/wGFBEnaAIiEeIQRLWIgsEIpxwI4CdiZEMSQYPH1Y1B1NTXV7enqm2mHhI9Wiq6vPvafqVtWtatjCFgZCJRaRpBbfTuB+YBSo2+s/gRXgd+AWoEoljumBWMxpgD3AMeAV4CngIRMybO//NccXgVngY+A88AdALDGFHLeyU9Lbkr6SdEe9446k85JOGIffGZvm/LikjyStFXA8xJpxjG+KCDNSkfSapMs5ziWS/rGS5LS9bJyVoiJ6Dj6P+A3gPeC+jGarwBzwNfAj0LD6fcBjwLPAOLAj49tl4B3gA4g8L7yweVnS1Ywe/EvSKUkvSaqH4eB9X5f0oqQZ+ybEktmIG05G+Iik2QyjV+Qmci3PsCekJukt+zbErNmK6vyQpKkMYz9ZjxbqMU/IceMIMWU2oziPpCcl/RYYWZY00e9we9wTxuXjmtkcLJQ8I2HvJ5Le7WfVyOCvGFe4Uk3FEjAm6VJA/r2k/THi1GzsN04fl8x21++HerBxBDgY1H0ILA3sfRtLxunjoNnuT4Cn/ChQ817dAs5BnLXa4zhn3C3UzHbXMOplBA4Fz1eB+YE9T2PeuLvZLixgGzAS1C3jdtzYWDVuHyPmQ98ChugMH4DbwHoJAtaN20ctz8c8ARWgGtQ1gTLSRhm3jyo5+VqegCrpEVgDkhIEJMbto0a6AwsJ2E77WNjCakZPxUCT9Nyqmw99C6gDu4K6BuUh5N5FugMLCdiHO+/6uFaigJB7j/nQt4BH6Tx8NIErEPfA4XH9Qmd47jAfignwdr4jtG8WwO2UC9E8T+NnOnfjYXJ2424jcA/wTFC3CPxaooBFKz6eJr0S9iTgEO786mMOuFGigIbZ8DFOl5QiJcAbqglgzHuVAJ9Rzh7QzcYY8Grg28aw/PwBSd8F+fm8pANRD9vZtg+YLR9z5lPqm6GQwPA68HjQ9hNc3j4saXsZBTdpl4BPA9tHgcmsUcjK9KrA86RzkGPAaXpLwQdBgrtb9VEBngOmCbKAbT2SgltSc09Im42s3mwCX1LuZC2KBPiCjBysQ4C3I84AZyknbS4KAWeAU4GPzudU6/YkGQXexM2Hezcg3ov7H+CnvD/gNrtwdBPgYeCwV9fE/S+4QXbefxvX8zO4HyS9pzDenVB1g1WjKukJSdeDJW9a0rCVVtvW83TQ9rpxdLNRzrW7Ee+WdCFwakXSZOtqUO2ryUl75+OCcfTtR5FVKAs3cXPFz5lGgPeB48DnuFB7AReO4QXBWeO4O/Bu1S4qG+tWsnAx1u3eoAKQu6FeUO9YUB+32psh4lt1/52UWJv/h/MZIh6UdFLSN5Iakv620rCQOdkKm1jOR/1B6zm1G3cUHLXnFdxR9Cbchf/CW9jCxvgPvIOpx7oaFRkAAAAASUVORK5CYII=',
    ['clock'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEl0lEQVRo3u2Zz2tcVRTHP5kkxRQy0NrUhVlUTRfShdUa6u8qBaFd6M60WZfiTjfSnf+BQpeCmmrBhRst2G2jbprRYu0iisaCi1KF/KikMGmnk3xd3PPMmTvvJe/NmxkQ8oULyZt7z/ecc889995zYQc7KIWBbgiRlPy5C9gLjAF7gBH7vgbcARaBFaABMDBQnr5jCU7pUeAw8CpwFJgAHgZ2A0PWpwnUgSXgD6AGfAvcAO52y5jcilvbL+mspFlJqyqOVUlXJJ2RNJbI7YfiI5JOS/pBUrMDxWM8kDQn6ZTJ7r4hTvnHJM1IqudQbF1Sw9p6jv51SZ9KOlDEiG0Dzwl6HjgPTGZ0XQMWgJ+AX4BbWHwT1smjwCHgGeAgmws8Rg14F5iDkmvDef64pIUMzy1J+kzSSYvlSuw9J6difU5IumBj0/C7pNdKhZMjfSFD+YakryW9JGnYk7mxg9bSfhuW9KLJaKTI/03Scx0Z4Ugel1RLEb4s6T1JozGBG/uKpIvWjm3Rb9RkLafwzNm6K2aENrPNTIrQ25Km0kLFjT0gad6NmU8WZ0b/ism8ncL3iaSHchvgPDOt9myzbESZHrHfXpd0z427Z9+245xKmYm6QorNNwvW8ZGU0GnYVFe2EmTjT0i678bet2/bjasYR7wmripsnG3jKrEQw5vAkajvZeAjYKMX277J3DCOy9HPk8AbkY7tBhiqwGlg0H1bBj4AVruueTtWgQ+NM8Gg6TQad04z4DBhs/H4hm5sLNvAyb5qnB7PAk9lGuCm5hhhFhKsAV8STpT9QtM419y3KuHE2xJG8QzsIhyJPRaAa5GHegbHcc24PY6ajpkG7AWeiL5dJ1xE+o1F4/aYMB3/w1DUYQzYF32bB8qebyuEGF6XNJjRZ53g8T+NT8btsc/a31kG7CHcpBJsEE6VZcNnCHjf5G2Fm8DbwPf2/y0bk0TKbtOxxTMeI5FR62weictiiBC/W7UngTNOr7umg5fhHZyaRruBf2jNID1DbMAarelykJTNIwduABcJHnxAqELkab8CH7MZalVaN9Rm7Jh4DdwhVA+SaaoA4xByb4F1UAfOAV8QYjZPEvCLOMF45OS66ZhpwCKh9OEz0SHC1TNXJnJG1gk7amHYRjVg3B5LRCk9DqEVQibweJqQXvuNMeP2uGk6ZhrQIFyqPQ4Scnhv6zYGxzFJ2Lg8aqZjuwFu6r+j9dQ5ArxFe7j1EsPAFK2Vi1XTLXstujvqbHShWJL0ckcX7AKI7tNxxeJKcgfPI+Cs2qtuX0mq9sGAqqRLEXfTdNregWWvlCWVr0g6p1Bu9JgznQpNY0eX+hLKo1BzXUm51E8X4lSJskoJz5+S9FcK34zp0pFHChe2OuCoWtispPDUTIdS1bnCpcWccocVMtslpZcWF4y7K/XRwsVdT+rkJMXdk5I+V3o5MVH+eB7le1Fev064ScXl9XE2y+sTZJfXfwTewc5RXbmHOw/2+oHjgjop5hY0Inliqqk9X3eCpsJz1bR69cSUYUg3HvlmTcb+ThXv9zPrMq3PrD9T8pn1f//QvYMdlMS/swpCjE741+gAAAAASUVORK5CYII=',
    ['timer'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE9klEQVRo3u2ZTWhdVRDHfzcvqTFNbE1LbWiL1aTBmqAUFIILRbrQ2qAbURCRgoogqEVx7UL8AHEjtHFREQsiRaUIWlCKViu4KGIbIqVpm4QkSlM/Gm2a0CQvfxdnHjm5797kfrVx0T/cxTsfM/+ZM3PvzHkBOSEJIADagA6gtMSWMvArcAZQEAR5KeQjb8+9kvokTSV8+mxPxQHLakCNpP1Kj/22NxeHmuUzvxjUFiBjDtgH3AW0Jtxz1vbM5VWeO4O8JN4MbCFZEp8GhljuJP4/oHDzvaSsYf40yli4FO3xIkOoGdgK3AG0A+uBRls2AZwD+oFe4CTwNwWEUObdRrwWuBN4FHgAlwONi20DLpkhXwOfmUGzVy0XvI9Xh6QeSeczfAMqGJO0V9LtV+WjZkrqJT0r6WwO4mGckfS0yU7FKdG5eUJvBF4DngPqY5ZPAmO4mP/Xxm7A5cRNQEPMvingfeB14AIUmPDm+TWSPpJUjvDgrKReSW9I2i5pk6QmSdfZ02Rj221Nr+0JoyzpQ0nNhYWTkV9p8T4Xc/y7JbUsFcde/rRIesn2RhmxR1JDbiNMWSDpZUmXIxR9IakzbQJ6hnSajPCpXjanZE9sT8k9kn6PIP+BpLVZlXjy15qssBG/SerKbIRtbJD0ecQxH6jEaVLhHuHVFkJ13lizyQzj00yh5AnuljQREnpcUmtG8g9K+lHSaUnvSlrlzbWabB8Tkh5KfQq2oU7SJyGBU5KeyEi+W9KwJ2tG0pPePCZ7KqTz48pppTVgq8Whj2/kXol5yVfwasiAJtPhY1TSbXE6a6KUGrqAFm9qDjgAXExK3tAN7AU2hZYMAd/Cgg/WRdPhNzotxiXZqXve6Al5YkTSliRCEnh+2OYWkLLf7abLx57EYWsLr5d0OCTksI0nJb8zDfkEuiPrpLimfiWubvExgKtXkuAW4B2qw2YEeB74EmJrnSnT5WMdMWV6nAH1VBddfyQkD3CrGZGWfAV/Rjg0sniMM6AmYm42hQEDwGBG8lG6ovgA8dcqM8B0aKwphQGDRvgZ+70POJKQPFSHy7RxSmzAJWA8NLYR16SXF9McBEElOY8AR224nIJ8iercGTdOVYgLoUncsftoxzU0SyIIgspTtidNc9JsunwMpzVgFjgRGmsFOpOySAvvFdmBewn46CXm5KsM8Dz1E+4kKmgEHg4puxJ4hIU5MGlckp+i5lvIY6EPyqDsBqFoaP6mYyik85hxidy32O30X8DB0Nhm4AVgRZFGmKwVwIvAzaHpg8Ylk0faJPWHPDIh6anEtUkyPUjapereo9845BL8iqpvEEYl7chrRKhuGg3pmDXdufviZkmHYoqyxySVsigw2bWSHo8p+g4p7/WK56Ftkk5FKLkg6U1JG5J6ypO5UdLbksYj5J4ynfnD1FO4Q9V1uuRuE47LXYO0yWvWI2TUyfUUuyWdUPQl2Uia8Ex7tbgTeI/qDw24LmoU+Bn4BVfQ/WNzq3HV6TbcX1EbiH4DDuDeRF9Bwf8leF7skvSDom/pfMxJmrYnydqjynMPlNKIFov9c8qPMUlvKcHVZNGGlCTdLdc7D8fEcxzKtqfHZGR6k0HOv5hMaQlX6N0P3Icrxtbjuqg6WzqDqybHgD7ge+A73N+t5TyxXkiWeN4r4UrudcAa5tvSSVw5cB5395+mP7iGa7iS+A/gDLJTV9TaeAAAAABJRU5ErkJggg==',
    ['key'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE6ElEQVRo3u2ZS2wVVRjHf7dPRCkgUqTiwvhaIFEjG4xKCEGEwsbE+EC3Bte6cmFUiCt3Jm4AjQmRRKMSHzG+EtHEBOJrgWgEo0J5NkiBhbS97c/FOUPPnU7p3HtLq4n/ZBYzZ873/b/HOfN9Z+A/jsp0KlMznS3x0SgQHlYao3LZDIhkATqAG4DbgaXA9UBXHDsH9AEHgB+B34HBZgyaEuLxmqs+pL6jHlWrToyqekx9V31YnZfJmQnybepa9XP1gvVjUP1CXRdlTbvXX1DPNEA8jzPq1smi0XSiJYIXAi8Dm4DWgleHgVOEnB8gLN55wBJgEdBeMGcE2AU8HedO/dpIPP+GOlrgyQH1LfUR9Sa1S+2I1xz1xrhW3lT/miAaO7NIXA7yreqWgkU6qu5R71c7J0qDJP061FXqZ+pITtaI+tKUrolE8fqCnK+q29VrLbmbJPIWqq+qwwWR3FBWXlmF8+OOkcf2mCplSbepLcn9VdGIfEp+qV7dtAGJokcN216KPeriSylJ5l+jPqPuVneoK9VKHOuO6ZRiSH286ShEAZ1RcT7MD0ymII7PUrflvNwXjcjeWV2wsD+Ic5s2YKl6PCf87WzBlpi/XD1dkH7bkih0qLty4yfUZZmOljKEJ8AdQHdyXwXeI9YyJdAFzC54voCx78gQsDvKztAN3Jnd1G1A4t2lufmngG+h9MfmV+BQXjzwTY7wd8CJ5L4C3JZxaTQCFUJVmeIocLIOGX3As8BPhKgNADuA13NOOAUcy81dkjmvrUEDWhkriTOcAS6Usr5SySL5IfADcCtwNhrzd+71zLgUXZHDaKMGVGiyjooelhCJvkblNJpCVeB87tl8YFYzRk2AWVF2ivOEQq9hAzLPpeihdleaKiwCrss9O0JoR+s3IFlc+zMhiaK7gCmpVRIZy6Psi0OEtUKlUmlqG20hhjGiDVjdNPNadAIPUttf9APfpyQaId8LbGF8E9LC1DZJq4A1ueF9wMGGhMarVz1cUAL8qd47FeVulNGjflVQzD1Rt46S5NdPIfm56msFeuovp6eLfKJncSSf7/AG1I116SlJvrdIaDK3JakuL6Wj01CKf+34Rqb+lrIE+cMlyK+M3txuOLC62dCpdcZrrnqL+pjhAOysxdhp6P6mlfyG3NwhQ8OyV/0kXvsMp3bDFqMayS8qnTr1kldnqyviOlgX0+DJmF7NYCCmzfzLTf4V9Vz08GC8qjaOIcNu06u2lyKeI7+mJHmi5wdKkBp0/FlPihH1pKHf3VSP1/Pl9ALgecY3K0eAp4CPoKaenwdcMYmOw8BzhLppGaEZmRPHsuP1/YS+4BCxp6j7CDFafI96vsDzFw+UDFtiu2F73Oj4Y5XhJJV+NvlGOLatticymvp+5CMwh/BDIsMosJXQOUGoyzcDdxPqnu6cjCrwIrA33h8E/sh5dJTaKrYpTNaRVQnpk2FzNGiiInCU0Nh/Ol1/WOqpRtuBFZPMkdoS+19lQIXJI/Yb4bhk2jAZoRZCRzRCaC4W5sb7Cec2AqeBbcScn3bE3WDtJLtKfi//WL0y7iitze4ojSAfgeOEM5juS7xTYzfh19HwTP0Wza+BX4D365jfT+0x4Mwh+dD0GE6I+5PUKboOqPfNRNqkqIl7QqSTcNzXQ3GTPsLYR8oZ+6v+P/5H8/gHrwsIlxQSAuMAAAAASUVORK5CYII=',
    ['lock'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAC8ElEQVRo3u2ZsWsUQRTGf3sXDZILNncYQQymFkFioUUUtNEmKticrZW2+SNstFK0knQG8TBW2lloFwlCSGchJzaSCJHEGDz3nsW+xcnu3O3eOnu3h/fBQu69eTPftztv5s3EwyFEBKAEHAFOADV1bQCfgK9A2/M8Z2M66UmJjwFngJvABeAYcEib/AS+AG+Bp8B74LdLIZmJ61MVkbsisiHJ2NS21TB+0OSPishzEfFTkA/hi0hDYwcjQgeeEJHFLkRb+nTCovaRmUemSWgMeAt4BBw03G3gA/ASWFfbSeAacJogyUP8Au4ATwD6lhP69msismJ54w9FZMqYYuEzpb7oF1nRvvpD3hBwVUT2ImSeicikjYzGTGobE3siMp9VQKnXAGOgs8C44doCHgDbXcK3tc2WYRsHzkX6zk+AETcTsX1E57xtLhu2dW1rYiYrl6wCykAlYvsG7KaI3dW2JiraZ98EeMRXsF6+f7Strb9cBRQGY50cRkKV2f95BThA/I15ahcR6fQ2e4319em4R8SsBvEqUAfOAxOWuFn+VpsQVJyrJE+lXmJ/EBSAS8BmNyH7BGih1eixvskLYd1UtS2zpSh5RR24TjFypKRc6hGOcQGKMjBXEPImzzksS60tiW1rfNr57Qq2PAn3Cj9JgA2rwA2C6jHvklEIqtsGcDmpcVoBArSAVt4lr85xj5Rfu0jzPBNGAgaNoReQNolTw0jCU8BFNb8B1gBxvQg4FWDskleAx8Bx/f0ZuA28EhGnh/c8plAFWDDIo38vEN8gCyngMDBtsU+rr/ACvgNNi72pvsIL2AHuR0Q0gXvqcwqnSex5XpjIr4F54JK6wlXI+e2b82VUCYoSXnPdfxRDv5GNBAwaQy8gbRKnufNxhU53R/8kYJbgiNfvM3EmAT7xDadGivNpztghcqAHew74wDuCfxUVBW3l1F2AsUsuAS8KIqINLCun2E6e9W60X0i8G+2Y6V1up/uJxNvpEUb43/EH6TOh6qSZm6IAAAAASUVORK5CYII=',
    ['lock-open'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADBElEQVRo3u2YvWsUURTFf7MbDZKIhVkRFIMiCBY2sUkRBW0UISLYxNLOwip/gY1YaKMBEcQ2GILaqIVgoaIgBCEIFqIxFoJEUTEaNU6OxdyFl5nZnc3LzO4G98Bjdu/bt3POzP147wbkCEkAJWALsNOuAHPAO+AjEAZBkNs9c/knI94F7AdOAQeB7cAG+8kC8AF4AowDz4DFPIV4E7exWdJ5SXPKxhdJlyVtq65vNfmtkiYkhQ2Qd/FA0u6WibAb90i6UYfkoo1auCupshoBXk7o3PA0cBVY70wvAS+AO8BLs+0FjgMDQNn9K+CcDZoWE/b0K5KepzzxMXMrYqMi6YKkhdiaGUl7mupGRmhY0q8YmZuSNqaRsTXdFsBxnPWNhZIPecMg0O1MfQWuAN/T1pl7/AbGiGqCi0EfLl4CnHW7YrbXmM9n+PIb4GnM9teTh7eAMtAbs30GfjawNgSuAa+AP3a9ThT8K0aXp4CAZAbLdOAgCKou+Bg4RvQW32Iu5ZOFfAV4w0gKmLGxKtQU4ARrmWTuXkfyDQRml6S8Enpoo+bbSVgd4n3ACHAA6ElZNwBUHNscMEUDrrQC/AAeEW0AP9UTskyApD5Jkx77myIQGpe+tDpRipM3jAAn8M9SeaJkXEZiHJMCDGVgqE3IuzyHWB6LQHoQp+X4Ivy7HtJirNe4hVkC0jAFnCQqPEVvGUW0u50EjmT9uFEBAhZpwjHQfDygwbfdTn7uhY6AVmPNC8h9M+cE4T7gkJkfAtOA8k4CuQpwquRRosP+Dvv+HjgD3JOU6+G9CBfqBUYd8tjnUZIFsi0FbAL6U+z9Ntf2Ar4Bsyn2WZtrewHzwKWYiFngos3lilyD2Dnz3geGgcM2Vc1CuXffck+jzpl3ukq6SKz5QtYR0GqseQGNBnERPZ9aqNV3WpWAAaIjXrPPxF4CQpIFp0ID59OCMU/sQA/pMRASNV+9usUFYck41RfgVMlx4FabiFgCbhunRCX37Y02C5m90ZqRXqc73Uxkdqc76OB/xz9uhKajlSqilQAAAABJRU5ErkJggg==',
    ['play'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADjklEQVRo3u2ZTWhcVRTHf5PElEi6iGIQko3ZSF21XVkUFYTixupCqgV1IXVhkSqKVlxLoYofVLSF1oWIlIqLaqX4gYhiQUFaXVQRLIKp2GaRgjVpa5P5ubh34PF63zQzeTPvFfOHB/Nx5r3zu+fcM+feCyta0bLU6MRYbb28Ebg5vv4VOA3QaHR0u/5KRW2oD6jH1fl4HVe3qqujTdWuFjqPerv6l5frovqxeps6WDuIDMCbttcZdac6WatoRGeuUT/xymqqx9SH1JFagEQnhtUjOWfn4pXSvHpAXRfnTi0BvlQfVn+II5/StPqiOl5ZNNoAHImpNaG+FOdASgvqt+q98T61AhiO3w+oG9RD6oUCkL/VfeqavkZjiQCta1R9TD3RZqL/pm5Xx/oCshSAnC3qlPqGOlsAcUn9XL1bHeopRCcAud8MRQe/iA6nNKu+rt7Us2h0A5CLxlhMmZNt0upETL3R0kG6BUiArFH3x8mc0gVDEdhgKAr1AEjcZ5N6VF0sADltKMsTpUSjLIBcNMYNf3CnCiCahj/IzS63JSkTIHfPhrre0HLMF4DMqe+ra+22JekFQC4aI+oWQxNY1JL8oe5Qr+s4Gr0CSIBMGtrxmQKIRfWgen2tAHLPGTQsjA4bFkopiCdb0AOlPLkkxTX1InAU2AJsA6ZzZgPAHcBg681VraGqHcgqpuIgcCvwArARGM6ZNYFvCJGqB0BmDk0S0mYrcEPCtAl8CByAkHKVAmQcHwHuB54D1pLer5oG3gL2AbOtDysDiM43gHXR8fsiSF7zwCHgFeAnwOwGWt8BMqM+TkiVbcBEyhQ4BrwMHAbOw+W7f30FiM4PA/cAOwiTNVUJzxBSZS/wZ8rxvgJkRv0W4BlgM7A6YXoR+BTYBXwPNK+039pTgIzjY8AjwFPAVIH5z8CrwAfAP7C0zeKeAUTnh4A7CTX9roLnnQXeBXYDvy/V8Z4BZEZ9CtgOPEqIQF4LwFeEdPkaWOhme740gIzjo4Qcf5aQ8ymdJIz4e4QIdH22UGYEBghV5XlClVmVsDkHHAReA35ZjuNlAkio408AjxPqe16LwHeEdPkM+Les05zlAqwCHgSeBtaTbgFOAXuA/cAMVHAU1WZBU/n2eicRkNANZnVtgd2PhBbgIwpagCoALhHrdBvNAO8AbxNSpx4nl5lF99V5yJeByB+zzlnxMev/56B7RStK6z9Gv6GPhyso2AAAAABJRU5ErkJggg==',
    ['pause'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAB2klEQVRo3u2ZsU7DMBCGP5fQATq2iJEJdsqEBDMSK0jwBix9BQZeBiRYeQGQ2AozTIwIGIGBpjmGXsANaWpXIIPqT7LUxufz/5/iDGeIRKYbMy5ARPK4ZEx8XwfGmKpcADM6Rm4LpICMyjXWgG5WA9aBPWBJ/4/iFbgAjoFn24glvAnsA5vAfEWuDLgHToArIBtn5Jt4Hbsi8iDu9EXkTESalug8V1Pn+h75HlSDXQRnA4sicuOxmW2iYxUhHx1P8Tk3qqVUa9UrsQIsu9seyrnB8Ds+o89qE+RbVi2lJBUL5wrzGXANPDJ8dgzQBlrWs4aK7lsGGoX8T0CXwYHNEWABWLXMJqrF20CRFDgCzq11AtSBM2DLs7JdYAd4twqSAtuar+6SxMdAvkFmjHmHoU+sxwn7RIAe0Ct8rVKfJJO8k3+KaCA00UBoooHQRAOhiQZCEw2EJhoITTQQmmggNNFAaKKB0EQDofHtzCVATUTs1uIsDhclJRhdKyJitxa9NPkEJ8AhcEB5c9eXNoMeaFlz11lXVeCbViRvstaANce8L3x1ptHfL4WYFm4N4VS1lFJ1Bm6BO9dKWGTAZYmBS53z5U61uPOLV0ynP33F9O8v+f79NWskMu18AILyC1XnHjPiAAAAAElFTkSuQmCC',
    ['stop'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABPElEQVRo3u2ZMU7DMBSGv6QVbMCERC8AB6jELaqeqAiuAYeAjtwAiakTXADWio2qzWPAlaLIDrFE8kD6v8lyXuL/s53FBiGE8KRIPTCzffMQOAcmbfW/jAFvwCvwCVAU8aGjvbXwE+AamANHA4Xf8wE8AIsgk5SICpjZgZndmT+3IUs0a9nicQHMBp71GLOQJcq45cUz4LjRtwWqngOXjVwnIcsqV6C5OlvgBngCRj2F3wGXfO/7erbkThn/9MUaFfAMPHb+mTIJ+3xExiqXXQv/KhLwRgLeSMAbCXgjAW8k4I0EvJGANxLwRgLeSMCbnHOhEpgCOzPr82BrSsbEtglUkdoFwx8txrJ0EngH1sBpx/q+WIcsSdsUL8DSIXCTZcgSpW1GN8BVaM/xueC4Dxk2qaJ/f8UkhBC+fAHMqMtRtMgyLQAAAABJRU5ErkJggg==',
    ['arrows-clockwise'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADjElEQVRo3u2ZT4hVZRjGf+d6m4VtjKzBSknzEiHoRokWWWiCLdvWsqBNoBtXumspCBmRkC5s0bYWMglpLaNdlgzYYDoyZZMiFf7B0Xt/Lr5vuOeeOTP3/CMZOA8c7uU757znfb7zvd953+eFFi1arGokdQ2oi3+fANYDLwDPAU/FsQfAP8B1YA74O46RJLUfX51AdHwNsAV4C9gDbAcmgSeBburyh8Dd6PxF4HvgO2AG6GeJRNsJ8GK0/ztwFbA2aRW1o+5QP1Fn1b7lMFDn1M/VndFe2j7qbnVavR9/dy+eq+M46tPq4ehAE7iufqxOpp7RUU9nrjudJlrV+e3qtwVmfEH9T72l/htncSX01R/UXfE5E+pU5pqpOD7iW7eI8xFvAJ8B23IuGwB/AD8CPwGXgJvAAsPg7gGvAq8Bm4BO6v4O8CbwFfARIUaaQZyRjerPy6zlafWQ2lO7ees09Qa76hb1oPpLvD+LWfWdom+gKIE96t2MwdvqcXWzJYIrRWajejQusSzmXBpjtQhsVX9LGZtX369kcNRuV33PYhtCLQKo+9Vv4vG2mlR1fhnbV6oQGBvESZIsLo+zwPk4XPlL6uhHqkf4GA6AM8CHhKAvjLEEMo4+qDvjEa8DJ4CX0qeL+lOaQMPoAB8ArzRlbLXgBiGnGsHjeAMD4CSwk9EltBIuA6fivSOon8+WxDJBvBL6hKz1Kk1koy1atGjRKJbsSat6mzO/oC5y1C+6GySQV1AXwZdWLbprIC8X6gLPPL5pLIcquZCEYj292C8T8ptBBXv/O4GHwBeEAqTDaBDXKXJgWMxUK5hcXpPJ4kosA2sHbbSRxDL161TJWt52CQLGQvzdWJjXcX4iCgTzKdszBpmmMQJ5MocGSeSoQSKpIq1sNkgztzN276l7myQwZRCbruWQGKgX1AMG0aqIuNUziGHT5otbF9RNRQiUCeIzwD3gU2BrajwhyOrHgIMM5cUZ9SYhICcI8uLLDOXF58nfxqeBA8C1ctM//g1MxPO7DEJs3sylcT8usVsGoXdhzPV99axBtq+2OVhA2o7HpEES/8tmMKceUddXdj5FYGxzIf5fY2hOnIgOjHsjeTM+awjiHVZMQ8Zloyu2dxy2mXrAPkKbaRuhzbSWpW2mO8A88CtB5TsX7ferZrGN5L6OfkmfJTT6NgDr4tgCodH3J6GPcIMGG30tWrRYxXgE1WP8RkaoPpUAAAAASUVORK5CYII=',
    ['trash'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACzklEQVRo3u2Zv2oUURTGf5PNblgMyMJGQUFSaGO7TWwsrIL4AAo2dj6CDyDRNlbpbAQFI2gTrCy0iI1gYyHmASQKYhIJ7O7ssbhnzOzd2flz77iThflgWObsuWe+7947Z86cgTlH4DNYRAAWgavAGnAeWMgYNgL2gY/AF2AYBF403Ijr0RGRDRH5LiIjyY+RjtnQGNFkzFTAkog8EZGwAHEbocZYmpmA2Oyvi8ihB/kIhxrLaRUWPbTcBJZj5yFmb/czxrWAc0BDz5c11lsXEq4CmsCqZfsM3AN+Mz05CHAWeAr0YvZVjTmYlYAgYew+8BXoT8squkVa6mvzcEpFEwJi+7ANdJlMi6Ik2pa9DVwC+iKStgJFx46An8AxgD05Y2cx8peBx5hlTiITACsWkWPgh5JMQ9GxAnwCHgB7SSLGBOixWUJ2KRubSZkq6anZAC5y+nCBk8yVKiAEXgMHVTOO4QB4o9zGMLGZdImawA1MfXMXc09E+Aa8SArmiQZwG7gSs+0BzzB10ztgkLtu0v3WEpEday/uqL005j7XyqocTz18Sol/0BkKMNsgBMRe6jw+LvBeASXWweTpV/rbiS97Hh9XeK1AjMB94KFOyC21PbII5vEpjDLugSZwLRZrQc+bBX0qE5BU2NnFWR6fygRUilpA1agFVI1aQNWoBVSNWgCmazC0bEPGOwx5fCoTMAB2Mf0b9HeX8S5bHh8neJXTQRBEJfWWmtYw769b0f9Apo9PSe39RqYEfmEaYYlvW3l8KhMQESR5nxfyccHcZyGXFQgwb1KS0sQtCtGYheO5COgB25SQAhMmpld0UJaAEDiybCvAesnkp+GIjA5g1j0QAh84yd+zxEiv7d7C1JZfV0Reit/XyKIIRWRbr53KMcgSoOgCd4DrwJn/PPN/gPfAc8yXGdKeF7nu+piQBgk9+pIR6sHMv+DXqDGH+AuKcx2lWgVBSQAAAABJRU5ErkJggg==',
    ['plus'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABTklEQVRo3u2ZQU7CQBSGvxYOQkI0YW/iTtfeQxNP4cJTuOjCq2jceAA2GhKuQUL9XfAI7dguqIPDyPuShvZBZ/pN+5L3KDjOaVMcYlBJ292RfdYARRF/uvKAF38FPNt2HXx3vEhC0kTSXDvmFos+X/Q7YJwD08bx1GLZCIxo51fBLh+yEPgzXCA1LpAaF0iNC6TGBVKTvcA4DFjJWwAT4Iz9i7AauKC9OKXFaklDxvsEloDCpqh1FDQjT7RL4n0oOxZnDXwNHG8B3AOv0O7sxh0/LoFbYDZwsj7Gvzh3Ztf0Fi7C/8sBM6zYPLPH9AhVXef/+JsgUhJfAg8NiTXwCLwPHK83iaNjTf2NpFWjqV9ZLPp82eeAC6TGBVLjAqlxgdS4QGpcoIcaaFZuslg2Ah9savgtC4tFJ3pxHfTVd7ZfAS8Q/01l9q9ZHefU+QYfc33vI5IPrwAAAABJRU5ErkJggg==',
    ['copy'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABs0lEQVRo3u2ZTU7DMBCFPwNlz6In6QpOgFhziF6BPRJX6CE4B6x6Ehbs6c+wiFOlwUknk8RxhD+pqprKtV/s8Xt1IJP53zhrQxEp29/0+R1NV8AeEOf+dmPq2A/+DlgDD8D1iAIOwAewAb5DIjoP3r9eROQgcTj4/sqbd+LKqGMB3Pdo35Ur398i9IWFcu3HJFhrQw7iC9hSFF1fHLAClhpVQ7EFnoEf+u1KAtwC78BjTAEC7IBdn52isj2rZjJWEY5GcAYumJRQ7Ab1685fFxHRTkGrSZkEKE2qLLIqK4p126WITyYlIiaTOhNQMYk18Eq3JbZEUXQBnvz7W92kNIQGmIxJWQUkY1LahhomMakhBUxiUkMKmMSkNMzeyLKAqckCpiYLmJrYkaGJUxT3n0NxPWkB9SgeiutJC7BG8VnVwJ5ABJmLgCPwSZHHzkhlCbXF9erZKPUwmYqAtrje+sc/FQHmuD6XGmhEOwOWM58QTWdKowuwnPm03QyVSQ0pwGw0YxOqgbLqYxI0KauAHYVpHCMNvtGkNJwtIedceXKw8ZdiPsDDcuIRbJHKI9RMJnOZX9bA+rIMFl5KAAAAAElFTkSuQmCC',
    ['floppy-disk'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACyklEQVRo3u2ZvWsUQRjGf3u5EzUSCSQigoKNhVgIKkmhNloIp1gL/gF+tpZioZ2Viha2gk3QxosoYqFlFG1sLEQUA8YgKJEUubvHYmbjuNm9m929vUt0Hxi4nd33nfeZfb9uFkqU+L8RJN2QFP4csqMoCGgCCoIgtfAKCcfwMeAUcBgYLpBAC3gP3APeAGQh8hcBSWOSpiS11D98kFS36+cyHkkX+2x8iE9pSVRi5oaAQwn3isZ24A5QDze0G6oJBDZF5r4BrzEB10sEwF5gawyJs0BDkn9M2Fe3TtJ05NU+ljQsqWbv92rUJB23rpPbnToRmLbzPd1+J+bqWUkMws+X4bhGA+MynyOPdI2JKhnhKNsBnADGPUWbwAzwHFgKgiDU1QDOAbet4S6JG8Astk50NMrXhfSnXjzJkC5/SDrtuobjTkkxcT3OlfK60B7gYAa5EeAkToviuNMj4DzwNSKzC6hFFeUl8B34mVF2FtNGLMMh8RR4G3m+SkzrkzkGLN4BV+yObcavTghTU252eabtY0BmAjb4WsBd4AGw0VO0DcwDi6GePMj1BuzibUylHggGWgdKAiWBVYA1TyB1FnJK+TbgCLAzx0a0gY/AM0xhK56AxX7gFnAgh/EuiRngAvAqrXCWxUeAa8BED4wPbZgArlrdhRPYDUz2wPAoJq3uVMjiQqPAeudamEq8mFLPBsx/iMC5Hu0HgSiawCVMIPrqawJHMX1UzVOmMAIC5oAvvo2ZzWRz9OCUY83XgZLAoFESGDR8s1CASXdLCTJVoCIpTRpN0hOu5ZXSfBfcB0xh+pYtEbkqcBk447soJn120lOxa2Yi0AIWInPjwLEEHRVMc5cX3fQsEDmGCYXiCLzE81ijT2hbmzoTcCrpfcxRyWog0QYeWptWHMOsho98nfALeGGNn/ciEEOk6M+sndCyI/cBWIkS/yp+A1Yv62H+phaPAAAAAElFTkSuQmCC',
    ['download-simple'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACQklEQVRo3u2YP2sUQRjGf3sGISnEnF6viLUgitrYWIhfwcJaK8FU6mdIFRAbucTGxu8hoo2CaUSwD8SApMjlbh+Le5dbxkludm9uh8A8cNzuO3/2+d3N7LwzkJW1kIrYHUqqLteAG3b9HTgEKIroj4wPIGlN0pakv/bZslhqe8EA9yQdaKYDi0V/Xm9JHBeB1dr9qsXODEBnygCplQFSKwOkVgZIrZW2DS0tKIBzwARQaKK2SNsoAGZgHXgG3AE+A28l7Qe27QNPgbvW9o2kP51kqpasIemVpNKStYmkoaS+lT2SdFRL5o4shtUZWhtZH6+rfjv5B6zdbWb7iR7wxK6fAz4nAi4Am1a3mn8FcMv6HDc10nYSj4GvjtEKYhO47JTJYq75quxLG/OtVRsK27WhUGkk6Yek41rs2GIjp2419NY73ezU5sGlEyBC5M6b7gA8EMOGEMszbx0Wkq5KemDfhe8hNYh+A4i55pt4OMnQfUm79vrbtXsiQISab+TBbdyTtOM8eMfi88BPgwgaNk09+F6jK8DAiQ04Zc2oraD7wAbwHihrVUqLbVideedDwR5a50I+CPt1KogR8NiKPwAvA803UjQAD8QLYJvpSvuNJZ3MRQVwDB4Cn2L37+rM7wcyQGplgNQKfQsNgIfAuKOs0beQLQRwE/jYhfOm3kIBesD5jgGCjbkaA3upjXm0h2fb6fsHSuAd0037tdSuTb/MU+kW/JeYaHbodAW4zvTwKaUmwE/gNwscgGVlZWUtR/8AGF8k+ZZg9joAAAAASUVORK5CYII=',
    ['info'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE4UlEQVRo3u2ZS2icVRTHfzN5aIKJ9pEoNYKtyaogKi0+Wx9FxIArwZiuJeBCdNHiRnHrRsG1j8QKLtWiC1eN4qIZBWvRFmvsLiiSF01houNM/i7u+To3d74vc7+ZSUDIHwLhm3vP+Z9zz7n3nnNhF7toC4VOCJGU/NsL7AWGgD1An31fB1aBRWAFqAAUCu2rb1mCR3oAuA94AngQGAX2Af1At42pAmVgCfgdKAHfABeB650yJpq4/Q1LmpI0K2lN+bEm6ZyklyQNJXJ3gnifpElJ30uqtkA8xL+S5iS9aLI7b4hH/qCkaUnlCGI1SRX7q0WML0v6SNLdeYxoGnieoIeB94CjGUPXgXngR+AysIDFNy5P7gQOAw8AY9QTPEQJeA2YgzZzw/P8CUnzGZ5bkvSxpHGL5WLoPU9O0cY8K2nG5qbhN0lPthVOntJHMshXJH0h6TFJPbHKPLk9kh41GZUU+VckPdSSEZ6SQ5JKKcKXJZ2WNNCqlzwdAyZrOUXPnOVdPh2q7zbTKUL/kDTRJFT6JB2x0LtLUiGLgBdaEyY7xIeSbo42wCNxUo27zbIpSvWIfd8n6X1Jq5L+lvSLpOe28qKncyJlJcpyW2zcKtjA21NCp2JLXdyCPJJOSdoI5v4saWQrAt5KnE7JifNyB2e096fUeEh9LmmwiRe7JX2WEgbrkp5qRsBkDJouH1W5E7thFYopcgaBSaDL+7YMvAOsNVnAmo0NUY6Ym2ANeDeQ02WcBmI8cFzStcADM+bdmNV7XNKCN3fDciIqEb2VnAk4XJPbspsSeDMlicZjksjGFMwJH8jt8acssfOeE+Mpm8gbmXLsh15JXwWTLkYlULohXdG7R+P8YdPt40vjeGNsmAN7gXuCbxdwhUi093C1wAHgFlqvORZNt49R45hpwBCwP/h2CWjqQs8rY8AZ4Dvga+BloD/vKpjOS8G3/SG/7mDAHvNegg3crTLPrfAV4Hn7/yDu9nkr8LYkxcgpFAqJQxaMQ+LofuN4A+EK9AVG1ahfiWPQhQsdH73AFHAoh5wE141Dgu7AwannQDuoAWdTjL4DtxodR2jAOq4AT9BFs8PD4IXGp8BbbPZcEehpgd8gmw/UqnHMNGAVd2r6v48AUVuhGVEDfg0MyAVP10jAsWwcMw1YxLU+fBymQ/2jnCiYbh9LBFt6aMAKcDX4dj9ue91pDJluH1eNY6YBFVxR7WMMOAJxYdQuPB1HcQeXj5JxbDTAS8Jv2Xxz7ANeoPHMyIMicFsOJ/QAE2zuXKwZt+wzSfUadTa4gyxJOpbjQveMpH8CGVfsphpTmR1XY8finHFrqrylgiaQca+kv9SIT5RR0XlzByWdDeZVjVPzFVSLJWUwv1euBog2QPWS8nW5dqOPOePUPPi8Vchd1AfzD5gRixZOl7NCyJszKWkl0Fk2LvGbiFpsq6QQusnC6Wm5/k4hg3xRrvPwZ4q+aeMSRz4gsBONrUELm5UUPSXj0FZ3bjtbi8fkEjattThvujvSH83d3PWVenKS5u64pDNKbycm5E/EkN+O9voFXCUVttdHqLfXR8lur/8AvAqchw49PXke3O4Hjhm10szNaUTyxFRS437dCqpyz1UntV1PTBmGdOKRb9ZkDLdKfKefWZfZ/Mz6E20+s/7vH7p3sYs28R+W1h1bb62qEQAAAABJRU5ErkJggg==',
    ['warning'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEUUlEQVRo3u2ZT2xUVRTGv2mHNIQ0FrEpxISa1IixCxPshgWYKBhZSKJulODGKCsUWcEeXNlE2AArFp2wk6hJETGxLljYbkwwQVMJJiUhQSeSJg20tKU/F3OmnLlzZ9577UxnFvMlJ2nPPX++c+65982bkTroYF3INTogIEl5SYMmkjRjspzLNTxl44ibvAhcAO4C8yZ3gYu2Vi6yfeDIvwxMUhuTZtNeRRihzcBlknHZbFtNu4K8gPeBhwHZJyYeD822PXbBiPQDNwKiC8AZk4Vg7Yb5tAV5AV8AywHJcaDXZDyyMydavgtG4CVgOiD4ANjvCtxvOo9p820p+W7g68hBvQDkXQF504U4azFaQl7AXqAYkPobGPakzHbY1jyKFmNjR8kSbgGuBIRWgFMhIVfwKbPxuGKxNrz7H1B6ynpMATtiZMxnh9l4zAMfbtguWKLtVD9x54HDtYi4wg9HCp+0mBvW/ZORUfi2PApOusuH1MkWsw1H72RTd8EReAW4EzmM+wKi+4CCyeuRtfDw37HYzSmCp9fheapxLuj0C8Att37LdH5nzkXinLccTev+G1Q/kP4CdpWTmt1bVH58WDCdt9llvh4PLEfqXejKUEevpBOStjrdiqSLkqYD225VvizlTOcxbb4rTrfVcvSmJZVYgOvEu5IOBMu/SipIUpY3LWdbsBgeByS9F+ReewGG5yUdl9TjdI8knZVUTM28GkWL8cjpeiR9bjnXV4DrwMeSdgfL45KuStm6X4bzuWqxPHZbzrXfSO7gvgrMBIftPrAndthMdxB47Owfm65Wjj3AP0GOGctdt4ikEdok6TNJOwN9QdJUne4/keSzYrpauzAlaSxY3mm5N62n+28Ds0Fn/gCGanUl6TlQx2fIYnvMGodso2QOzwA/BgGXgWP1ApLwJE7wOUb1m91145K5+58Ai0GwX4BtScFcjJxJYgfNZpvl8FgEPk29C2Y4CNwMAs0BhzKQ6QYGTBLfulzRhyyXx03jlIp8DjhNNQpAT70gjkQ/MAr8aTJqOqXw77FcIU6XdzMp+WvAvcD5HjCSkkCXEQ4xamtpGjCSmYOrfiyS/Ezd6itjDFB9m2C6gZQxcsCXkRhj0Slwlb8Tmb/fU81fgwpwcQYtt8eccazcBVM8C0wEDovA0aTRadQIRRp6lOqbcMK4VhkfiRhfB/rSJA1i9QNfkfEQR2L1AT9FmnpkNZabuUuB4dqeglrbNVqnGbFPA5eMs/Jmn5fUH8S4Lek3lT6LJB7gGAdJ/9nfXZLW8g0cxuG2pBGnf844L5ULWJb0b+A8LOkbSXNqwk9RGQroNS4eRUlLsirKhhOSPtLTT3+bJe1tEfF6WJL0c/mfruDF4lqr2aXADwpfpNyBGQK+j9xG7YBF4DvjuHqxrLbfHbA+SQclvSlpu7J9c9EMrEi6r9LYXJM067tfdThdITmVzkirf9hFpUsGT7yDDjoo4X+vZRJqCjv+6QAAAABJRU5ErkJggg==',
    ['question'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFeUlEQVRo3u2ZT2xUVRTGfzO0hSEyQqUYtRAUTEzQiCYElT9KSEzEaMLGCmvFGBfqgrhiL0sTN2gUdOG/DWLUsACKCQmtVCkxmGghMUpoIm0JRWewnfq5uOfR2zv3zczrTElM+iUvmbnvnnO+c+499917LsxjHk0h1wolkpKfHUAn0AUsAwrWXgauAleAMWACIJdr3vysNXiklwDrgaeAjcBa4A5gMdBmfSpACRgBLgD9wEngHHC9Vc40TNyeFZL2SOqVNK7sGJd0QtJLkroSvbeCeEHSLknfS6rMgniISUl9kl403a13xCN/r6SDkkoNEJuSNGHPVAP9S5I+lLQ6ixN1J56n6HHgHWBDStcyMAT8CPwMXMLmNy5P7gHWAY8C9zOd4CH6gTeAPmgyN7zIb5c0lBK5EUkfSdphczkfRs/Tk7c+z0g6ZLIx/CppW1PTyTP6RAr5CUlfStosqb1RY57edkmbTMdERP8vkh6blROekfsk9UeUj0raK2mJbyCI9FJJ3fYsTUYm0neJ6RqN2OmzvMvmhKZXm4MRpZcl9fhTxSNTlLTTkvGMpIv2nLG2ndYndCRvOi9H7H0gaVHDDnhkdqt6tRk1Q7FIbpD0jaQbSscN67MhRUdPZCRKcktsY6NgHe+MTJ0JG+pY5LcpPcljGFKQpN5I7FV1TpyW+3A2HP09qv5IHU6GP+i/RtJgBvIJBk021Fc0Wz4qcl/s2qPgKegNFIzIrTaxYd8fIXdd0lFJb9tz1NpC7E/RuUXVS+xx2aJRz4Gtkq4FwocktUWidZek80HfYbn8KXiECtY2HPQ9bzpCvW1m08e1JIg+8r6g4Umg6PUpA1/gdpQhVgMrg7YDwCdAOZfLJV/SsrUdCPquNB0hKmaz7LUVcTveGdMoHwh24LbEPoaAAYh+1m8HFnr/J4Efwr7e78EgEB1BsPy+A2bbx0aTSXWgE1gTtJ3FHURi+CcgNAn8FXbyIrae6TMCuIPNeIruK2bbx1rjmOpAF7A8aDsPpGXOT8Ap7/8pa7tJ3MgXgN3AK4H8H8BvKbpltn0sD/m1BR2W4U5SCf7F7SrTdoUjwMvA8/b/K2tD0irgOWAV8DCwCbgtkP8aGA6V5nK5xPFLxiEJ9GLjmOpAIWibYnpLXGXE8Dvwrh91i9L7wNOk4xzwXo3gYLanPAfaggBXTaFW4SFgc433F4A3gYvNGgodKDMzKRfgDiNZsYjq0QWX9N/i8qEX6h5YisYhQYWZS2uVkau46kEyTHmgG9zUyHA6uoEb+gSTwBHct+A4tvKk6fNWre4gyCXjeBPhCFzBktDDOrKXX8LV6STwKnAYGPc+cLWQM9s+RgiW9HAExnDz8gGv7RHc8vpnBgdSV6cMo9hltn1cNI7V8PYt+4I9SEnuvDu3dZtqHs+q+jyyL+Rxcwp5kfmOmV/HAvAC8aSsRaDTdpVb7HeWALQDPcysXIwbt/RR1PQZNbad3lKPhEf+QUnHJP1tzzFra1R+a2Q7faLR7XTDB5oU+Q5Jn0X2/p/au3ryRUlHAtmKcao/ispwpEyRvVvx4+WQvaslm5f0lly50Uefcao/+bxRaOhQH5HtlDQQcWAgyYUaNndJGgvkSsal8RxSxrJKhMhrgfMlayNFJi9XeRiO2DtoXBojHxDJVNjyZBdaND+3Z7e1xWwUbdqMRez0G4emqnOZS4ue7AJ7Yu/a5Va2I4qXFofMdkvqo5mLuynRToq7OyR9rHg5MSG/vRHyc1FeP4s7SYXl9W6my+trSS+vnwFeB05Di66evAjO9QXHIc2mmJvRieSKqV/V6/VsUJG7rppRS5ozeI604pKv13SsmC3xW33NOsrMa9ZBmrxm/d9fdM9jHk3iP+RYX5va1of5AAAAAElFTkSuQmCC',
    ['skull'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFnElEQVRo3u2Z3YuUZRjGfzOzKruKKbvmam5Ra2IdhKLkliBZ9CGbJ5l0VoFIB/4BheGRFnUiUQRShxKBhB540JpIGkW6JCGmYvThQa4rrruamzrT7lwdvPe4z9zzvjPvfGwUeMEw7zwf133d9/18vM8z8D9HptWEkkqPWSBnz5NAESCTaa3JptgCsTOBJcCjwCPAg0AX0GH1N4ER4HfgHHAW+AMoNOtUQz1NeAZYDDwHbARWAd3mTDUUgGHgJHAQ+AoYAtTq7MQKt899kt6UdEbShBrHhHG8ZZxhVqdF/ExJmyWdlDTZhHCPSePcbDZS66qZs4CsC9gObAXmJDQvAn8Cl4ErwF9WPhtYANwL3EM0weMwDnwKvEs0Z5qb9MGQeUDSgSpRH5a0T9JWSaskdUuabdGcac/dVrfV2g5XycYBs9n4kArE3y9pIMHYZUm7Ja2QNKOWwYBzhvXZXcWRAbPdmBPWcb5FKy5KA5KelJRrxIDxZ41jICG7+0xDQ+Q5SbtiiG9L+kBSV1MpLs9Ip3HejgnUrrqCFJBukDTqCPOSdkpqb0Z4gs124847m6OmJV2wgqFzJCalH0vqaKV4Z7fDbHgcSTWUgui/JqngSL6RtGg6xDv7i8xWiIKkV2tmwRrMkXTYEVyvK43NOVAavtedhsOmrSbBupjOn0uaNZ3inYZZZtMHcZ3XkA07GtYDc4M2t4DPgPy0q59C3mzeCsrmmrayUeC39FlAnys7D5yA1r/LxyGwccJsh+gzjYkOdAG9ruwk9l7yL2PEbIfoNY2JDiwAOl3ZT0DF4A8mXFZSm6RMmjlifTLWJ1tlYRBwxpV1msY7aHMN5gHtwe8i0WHjTmoDY53AS0Tjcg7wM/CFpEGg6Ieb9csCjwMvA8uI3j6/BvZLulqyk8lkSu0vmoZSoNtNY2JkXnA7YUFSf0m0yl/wDqryMDMsaYvPRhD1Lap8eZswrrIXN3vud/tR3jQmDqFJN1wyTB3Mw6xtB16MqVsI7ALWxMRojdUtdOU549oeMyJylJ9ZZBoTHRgH/nZi/ZxYSnQGTkI3sCnMmGGT1SVho3GH6HROFUxjogNXgRuurLckxtAT45THMme4zcqqodO4Q1t+RRw3jYkOXMEmbYCVlK+9Ny0S1TCO3QMZij5yMSgwdQTFbK50bS6axkQHrgGnXdkKF4nzRHc7SZgEjsY4cBQ3fh3OEa1kJSw12yFOm8ZEBwQcc8YXE02yEkaA3Z4owJfAfphaEg37rS4O14wz3DD7zXYYhGPE7ElT6qNJ1yvpN7fUnZLUEyyjOUmvSBqUdEPRSWpI0h7FnGPd8rvH2t62voPGlQva9ZjNEL9KeijN22hG0keqxM5w57RPl6S1kp6VtFw17nQ0daBfbn3WKjiaBjv7zhj7H6ba7Y1ktaRLjmCktKlNx2t14EC/2QoxpOhKJjVRVtL7MVE4a8611IlA/Gqz4fFeKfv1EPZIOh5D9qOkvlY5EYjvM26P45KW1GUrIH3G0ufxi4Ijpn3aJD0maX3MuC7Nl/XWps3VbTBOjyFJTzcUrID8dUljMeTfSZoXtHtD0U3dLUmHFKxG9nzI6i5b21LdPEnfxvCPKbpcaPp6MWcG/R3RhUDkAlUue9sCkdtc3SnrU3LugqsfNZs1L7Sy1SptE5oEPgH2xjWx7w6iW+cQXQnPWNsOxxFir9mcrHWMrepA4ISAscbymCiyGkZJ+Y9NTQf+62hrom878BRwCVhE+VEU4GHgeXteWmff1sIm2w430YqKjnt5+y66+gmry6vy6Fmr7460K089GbhA+QE7A8yo0j5H5ZGTFH2LZisV6pkDR4DBOto3ikGzlQqpVocgnauBd4AncDdkLUAe+B54G/gB0t0Epl7eAifmEv0jP7/FDowRncqupxV/F3fRAvwD0w3s6eKskSkAAAAASUVORK5CYII=',
    ['coins'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE9ElEQVRo3u2ZT2hcVRTGfy+ZTJoEE6NUKzb+QaqxahUSA4orbWNThVai4KLajbgRXJhWBFEruhAUlAY3IuLCrWjVWgVxJSIhRW212iqmDYVEI5pEmqSZzHwu7pm8O2/edN5kJslmPnjMzJv7zp97zz3fuedBHXXUUcd6Ikg6UFJ+fCvQAVwKtANtQJMNywDngVlgGpgB5gAFQWJVtXHADMaMvRnoBe4AtgBX2f0WM77BxubMiXkzfgL4DfgBGAV+NceolUNFUszwFLAVeAjYaQ60U8GKRcUC/wEngS+Aj+z7Us1WRlL+6pY0LGlCq4cJ09Gd11sL4xslPSrpdAWG5CRlJC3albF7SXHadDau1InAHmwAngRew8V2HOaBc7iY/h0YB6YsNBZtTBq4BNgIdOH2yxZgM26/xGEGeA54B8hVHFI2+9slTcXM0JKkk5Jel9Qv6WpJ6XLL7oVj2p7pNxk/m8wopiTtWFE4SWqTdDhG6BlJQ2ZAULHgYocCkzUkaSxG36eSWlbiQI+kyYiw7yX11WSDxa9Mn+nw8Zek2yrV14CLz3ZfD3AIGIHa5euIrBHT4VvbDlyTdzQpUnb5VgbA7UAzcKFm1hei2XT4etPAqzju+VHSKPAL5YhP0qCk+chyzkl6S1JXrcLIC58ukz1XJj3PSPpO0kuStklKxdpRwoG8kOOSDsgRTtnscxGj0yZjv8mshCskR3yHJN0UtSGQNAh8AGwoZQeuphkFvgWOA2eBf3CF2iKuBgK3p9K4gu8y4FpgG3AXcCewibBuWglOAS8CHwLZIAgSORDFIi4u/7XP8xQSWRuuUu3EkWJzQrk54IQ533URe6aBZ4F3AcWFUM7is9JlrgRxOi5I2i1pk6T7Jb2h0sT3p6R7JcUuZwY4CLwJ/AFkq1jyKLLAmMk+aLqiqzsJfAkcAPrtcywy7grgaaAV89rPCFlJj9tmud6+f1bliuQkHZG0z2RicrPemAW5kmPZSoVJoFfSsYjMSUk9KVyBNktYbDUAz+AOHyPm/d/ADovx/Ex+jtvIHRSeyGZxG3gAaPTuv23PAPSZDj8CZnHJYhlBEOQzzigwDLxHyB3twOZytdB+i8ldFqN+vA7Y7KQkNdmVsnsDMeN3SbrSZJ6J0feJYmohk9csxx0+5iUNJqlGf5J0VK7WL3IgihIOZEzGCSWsRlVMfFGumpc0mDK9XwMvUHweaARusYvI/d3A5ZLyaVS4lNkG3OOFD7hyZWeJjT0NPA985U1CGrgBeBB4DLiVEsfZIO+tKXwEeBm4kWQQLn/nPHmNJD87j+PqnyM47riOkPh6cc2DUrIWgL3Lf3rh0A08BTyMY87VxFncxu3EbfwOwkRRDoUORBxJ4ToRe3DZZCvVdSWqhczgDZ4N8Q5EHIHivlAPxaVwhjCcmiiM/2qQxYXZxziCe4VwhRaAvcmnIMwKDxjp+BiWdJ9d+7Q2xDcnaXcqqQMeqYzjSGej9/fdwPvAMfs9RTHxHcURXzu1I75zFa2nzUSL3AE8itUiviHFE99hSW0rcQAjnfUmvu2SKs8qSt4I85HF1e/f4M4P+bO2T3xPkGzzFzTCKrXfn7V8K/JUhZtzSWErcklr3IqMOrHuzeCqiUmF7fg9uGyyZu34mjGrtD4vRFatNFD4SqrFjO/ErUorIT8s4joba/ZKqo466qijtvgfQE0DBeDDyn8AAAAASUVORK5CYII=',
    ['package'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEoElEQVRo3tWaXYhVVRSAvxln8KeUDErKh+ylXqQfUCyKiV6iMHOygjKKDCyCEnrooZ+nKALBiEIpECoITTI1EkOkSOmHSitfwoIJkcl6UCsdaWa89349nH31zJlz9j137p3Ru+Aw9+7Ze6317Z+1z177QodL12QoVesfp4W/VYCurvaba6vGlONXAPcDfeH7PmAr8OdkgbTseHguUVepB9Sq56Qayh4PddKwF4TjM9Xl6ufqiMUyEuosD23OH0gw3qv2qR+pQ5aXIXVraNs7pRDB8W71OvVt9XjE0WPhKZLj6jvq9UHnpDuOerX6ijoYceyk+oF6s3pT+HwyUn9QfTXobu+0Sjl+ufqsekitFThSU/eod6jTU22nq3equ9ThSNtDwca8lkFSxueoj6jfqZUGc7sa5vaN6SmR0jVbXal+G9FVUb9XHw22mwNJGZuhLlV3R3qtSP5S16nXql05IJepa9RfIqM5HGwvDb40BgmVutQl6mb1VMTJw+pe9XSkzoD6vDo/7UAKZIH6snokouNU8GVJujNiPd9vfIEeUzeoC9WL1fsCyGhB/ar6s7panZsD0h10bTAesQaDb/kj4bmFur9AwZC6Sb1F7UkBo16qPhEcrRa0H1W/VFeos3JAeoLuTZGR3x98LATos3hDGlCX1Z0vGL356gvq75GePK1uV283tYmlIJYFW0Wd2BcDuMv4q8A/6nvqInVaAUiXyeJ93WQxF8nf6kaTiNUbdL4bbBTJSPBxwgB1qUeZa8xZWEHXNHWx+r76b0TXoLpDPVrC7oQAqhGFuVEmM62mm2xsO9X/SjgZs900wKj6pskbZCzK/GROlMmAXKQ+oP5YwvFR9Qv1rYzdcQDdjfY14DPgXuBp4CBQy9TpBm4A1gPbgRXALMeHuxowmtM+W+cg8AzQD+wKPjSWghE4S+zYKDMQ6b1slOkNn7cZ3/Rq6hvqlSl7hf7UpacUHckxUP0DeA34GHgSWAnMy1SdFXrvNmBHKOsH5jYwcQbYDRwNtkr5VRqgDpEMlr8CzwGbSaZWPzAnU30usCqirkJy6G/pgNxoDcRAqsAPwGqSA/xOYLhE82HgE2AdSa+3JBMCqEMEkFFgD/AQ8BjwNUnvZqUCfEMyKg8Ce1t1viWAHJAhYAtwD7CWsdGmFsqWAR9SbqSmBiAH5ATwFWNHoRLKTrQ7J9Q2gPMl5xOgythNylDWMQC/AQOp7wOhrClpah9osxwGniIJwwAbQ9mFD5DaafeRhF2YYAa70RTqARYDsy2TFWgSIjzV8JwFC3ZmA4to0MlZgNOM3R27gReBbSQxvFx6YwKS0jsDuJvkfeuljI9ngo+FChod6reot5pzLs7oafgWmdOmfqjfYguH+mbTKuMSss0AeO4MvVBdbytplYzCMomtIyZJqQWOT5FEAVKddZXtSmzljESZ1GLNJD24xiRdWPZgNDmpxQKQMsndiknC9mGTm5cigJlOdnI3AlImvT6sfqquzQFYG/43Nen1CEiZC45KBrKmnonUn7wLjgKQsldMjWTqrpgKQDrvki8HojOvWQtApvyiu+N/atDxP/boePkfvTNxtDbEioIAAAAASUVORK5CYII=',
    ['gift'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADK0lEQVRo3u2YvWsUURTFf5usmqQwiYUfARsNuGUIARsrUdEmJv4FgpWVdlpFtMw/YKGFiEgsXDQWgoqNNgkiYqVgLCLRTkK+E3dzLPZOfPt2NjubmTG7sAceDO/dj3Pe3H3v7kCTIxPHWVLwmLVYBUCZTGY7+4zZy+ypZp+KAId0F3AKOAv0G6kfwFvgDTDvufYAZ4DTwFEj/w14DbwHVuKKiUTeRk7SE0nLqsS6pJeSBhz7AZtbD7Fftli5wP5/kJ9SbXw025w918JUqiIscJekiQhkArywERUTliM1AeckLXlJVyVNS3onadFbK9pwsWi20+brYslypFY+417CNUk3JXXbzl0PIeWLvWa23ZJuWAwX44mXkQXMSsp7yaYl9ToCu0JsXDwNSsRGr8Vwkbdckbi11aEjOL9drGNnuWEFeGjzPtZsbcWZK4TYBndK4gL+ALPe3CBwBeh05qaAmRD/GVsL0Gm+g57drOVKDs4rHw2p8VV77RclHZK0R9LjkPJ5ZGuHzTZfJdZoPb+BrE/UsA84AfTx73UK6AB+Ascctw5gFLgAfAc+eesB+oEHwABw3HL4mLN454GM8ZHl/IqVm3tbbz055PuA28AIsD8kSbuNNFC04WMBeA6MmZjKlsNe215J99W4uGcct3j7P+IcMJzS7iaBYeO4Bf9YPAJ0e3MFYLPORG0hsZOI02McP1cT4L+RAnCH0vEXte6LwElK9ZpNOE4Fx2yNIJvAB+BV1D7d6rOd8t1OKk4F6rnIGhJNL6BWCbUBQ0BRUj21O0T55iQVp6aAzZD1MeKfHknFqeDoL/6i9Gf84DY2O0USceaNY5lCF1+AyYQIp4FJ41h1VzaAW/Z8CTjgrUe9jOJcZGG+v4G8cdtwF8oOZZV/qLoM3KX+yyjORVbN9yqlTrbiQ1iZ0mBBUoFSa1v3ZRTnItvGdw4ohPk2/T3QErDbaAnYbbQE7DaaXkA9DVbUljhOOx2phY4qIE5rHaedrtlCRxWQdGu9U995vBbaV1sNjdJaV7TQUXfFba1HCP/MmCYWgGeEtNAuqraGNT70po1tP+i20EILLTQO/gKnlEqO/ikedAAAAABJRU5ErkJggg==',
    ['wrench'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFO0lEQVRo3u2ZW4hVZRTH/+c0zpSXNKUZDSsa9aGYxEQzB7oHQ4RF9BClgZBhlwfzwSiNwjGKEIKy6PbWTYICiYTwwVsFhWXqgPqQNWZexhl1nFFzZpzz6+Fbx/n89nfknDnbMz7MHzacs8/ae/3X2muv9f++Iw1jGGUhc6kdAPmPIyVNlFQraYz57pbUZsdpScpkSqN0SQLwSFdLmiHpIUl3SZoiaZydl6ReSScl7ZP0o6R1kv6QlCs1kFTJAxlgFvAZ0EHxOATMs3sMGfmRwBLgYAnEfawFssUGUJUmeUljJTVLelYDZZIwldRnvrOR37vMpnLwMv8ucC6S1V5gJ/AesBB4AzgdsdsN3FbREso7A14EeiKkWoCngVqzuwXYFrH7G7h3qMjPBv4NCOWAb4Gpnt1U4KdiXl7vmixwxSUJzG5abd0mxDde1gVMBn6I2B0DnixAfibwKfA18HApL3cpAcwh2Sp3AdM8ItdaQCG6gMU+Me+a+4A9nu1BXGtOvXyaA1J9wCLv96ssi7nA7gywDKgKyGcs262RgFelVkp2o1HApsDJDqDOC2AucDKw6TUyNQH5rJXTYeLYbD5TC6Ae+CdwssYjL+BO4FRg8yWu7fr3qrJyOkZhHACm+AFkBxuAoU5O2/jYGXxvlXQkONct6UyevKQaSUslrZY0/iL+xsqJwdQCuFoXTtxzko5KF6jKdkl/BtfNsOAlp1JflbRSTqX6OC0p532vDm1SkxIGlJQBZyW1SGoKAlgnaYcl4TG5p+Bjm6QNkpapsCwpO4BuOV2Tdz5C9ogBZTKZfInstEzmn3iNpDvsiOFnSc9IagzI95rP8yi3hNokdQbnpkfsWiR1FHnPDZIWStoj96R8dJrP8mGdY7S1Nh/bsQns2Y0AXgfagf4CHSaHG3aT7Zo6a8k+NqXdRgW8H+nxj5OUBtXAdGABsBonK/ZZi+3CDTtfeizCDUUfzakMMgYm5jycigyxopAjj2ANcL3Nibn5zNoxDSdHfHTgZEsq5LPAfOITs51ByGKPfC1OxYb43J5i2eRHAM8DxyNOjgBPUaJq9MhPNfKhbjoI3F5W+djFVwKvAN0R8q3AI1Zawmn4+4HXgCcssxmfgFeKtbhFT0vkvj3A0kLki5oDduEYuYm5RMmhs1fSC5I22veMpAWS3pGTBn2SdkvaImkXcNTs6uTa7t2SbpabIz5ykj6R9LFU+p6R/2gnAB9FugLAb7gVmW//KNBGHDlcp+qLlEqY+TXAuEGVjUfmOtxWR6x/b8atcX37B4D9lIdDVjbnFetgydcD6wtk8TvgpoD8HGBvGcSPA1/gXtjBLR89Mg3A1oiTfnMyMSDfAPwesf8LN+w24xb+3VYePfb5ALAFt8CZgy1yyiU/GycJQvQCHwDXBOTrjUSIwwzsNozCLUYagSY7Gu3cqEGTjgRwA/BLhMx/wJs4/eOTnwR8X6Ac5qdCrMTsr4qQ6QJeIrmGHQ98FbHvxg27dLdBigigFrcFGGZyMcndg9HAhyS701lgOW5iV4a8R2oWcCIgtBJvgjIwkd8iORf6gLft98qR94jdg9uvyaMHeDAgXwW8bO+Ej37csBtTcfIeuZkkRdpy7/3IAs8R10JrcRO78uS9ACaQ7OVHcfq+yV7wmApdj5vYQ/PPiheAjGyInJVTTLtsxTabhox8EMQkktuFhbAduPWyIB88hQbc6L+YWvwVT4VeNuDCCbvCsnzCulMnbq26Cjexh5x8wRWCEcvILUhulNtBOyVpv9weD0P2X+4whpEe/gdXhpilZeZokAAAAABJRU5ErkJggg==',
    ['code'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADOUlEQVRo3u2ZT0sVURjGn0ldiAhBtDH6Y2EEkSuhRZEpai1s2xeIFn0HV32CFi6jLLEv0B+CcFELV62kK24kJMhFhYFJonl/LebcfO9xnDszZ+7N6D4weJ1zzvs+77zve84z90pttPF/I2qlM6D2scP93ZWkKCpO48hfID8sacZdw97Y4QUg4CywxB4qQH9IAC3JgCF4Q9IFM9TvrsMdgEO3pEnV990XSZ/+lQAuSrrs3Xsn6eOhDsCUz01Jx8zQjqTnkn41m0NwAMBRYIF6VIC+0B2oqRkw5IYkDXrDbyR9DvXRmZNILeCqlOsAmpTUY/7flPSiZiPkgGuYAWc8kjQi6bGkR5KueIGloU/SuHdvUdJ7z8aopFlJT52vKPiAc/XbBdwB1kz9LgKn0hy4tQJuA9te/U+ZcQHngGUzvuZ8dhUKwhjuBe4DGx6BTWA4QwCdwKy39iswVFvr5o0DW968Dee7t8YnL/kTwAyww358AE5nCOA8sOqtfQl0ewH4EqOGHeCJ49I4CEP+EjBPMirAWJpBY+ceUDVrq+7en7Vm7ph7MEmYBwZTg3CDETARZGjPVrd72harLitFH9yE45joMKlZC6XSzRkirneLWeK+SMtaX0rp7m9u0psVcjaTITLl2dkm3pGylF5mPgJ6gOnMETcAJUiHjBUxDfQIGAHWEyatEG9vmQ8U6hvyh2fvQZYMerYix2Elgd86cL1ZWuhA6VA6yiwh04QVz86CK6s8Tz9zCZXSxKZ8UqVDBuL5mjhHxKnbKBmlQwby+bZRz0Dhg4yM0qEB+WIHWQFDdVLCrGsoHVJ8hkmJBINpYm6JWIDZNZmlQ4K/csRcjmbaIt6f7fxc0sHzVZ6cTjCe1NzLxC8hQdLB+Cj3hSbBQUR8Ys8Bz4BRj3xh6WBsjDrbc85X+CtlgpMOd/kNHCQd0uw3QqZvJcy3A7u+Y4cg6XCQ/aaDkqRDCAqLOUPuqqQBb/iVpO9NZx8SgEOnpFuSusy9b5JeS2G/vDQdrnwGKCAdykRoBk5KOm7jUty8P1vCPgQuA2e8Bq6TGK1A4SI1JK9Juus+P5T0Vmpd/Qd5MUGU9rNpG220kQ+/AXiDOSt1aLPjAAAAAElFTkSuQmCC',
    ['list'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAoklEQVRo3u3WMQ6CQBQE0Id6EBNjYW/taSw8koWnMd7CmHgRwQYSILa6YOZ1u6EYWPZniIiImLFqvNE0Tbe/xhbLwhlfuOOJpqqGkQerNjwccMamcPjOAydcof8Sqw8PL3DErnTqnl2b6YZ6HHbWPp1AjQv2pvULXYy+Pn9wiSMiypr9GE0X+pF0odLShSIivmP2YzRd6EfShUpLF4qIiJikN4hEUfpFolJeAAAAAElFTkSuQmCC',
    ['palette'] = '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',
    ['cursor'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEqElEQVRo3u2ZTWxUVRTH/2/KUL9aVEQUQUhQARMVE2NVYhSIC5tIIgl1xUISTXQpLGy0Ji7sAhM1KX4laCIxGhIJC5dYqAlfWkVSBDFqxAiuKPRjymBL+3Nx7zC3d96beW/mjUO0/2TS6bvvnfP/33vuuee8kWYwg/83gqgBoPC1yf6dlKQgCHQloYSNQ3yupGckPW7//1bSPkknJY1diWIuCwDmAjuBSYqYAgaBvUAn0Aa02PsbTXsaeQEveuTDcB74GngNWAW0NkLMtBiwzjOSPpfUkcDOiKQfJfVK+krSgKQhqf5hFiagSdJnngAkTam4ocshJ+mEpL2S9kg6Kum8JOohJkyAJG2R9KYzNCVpu6QJSaslLZXUHMP+mMym32fFHJE0WC8xl0UADwBnvZh/F8gAtwBPAT3AAJAnHi4AR4F3gHZgPhCkvmesgGuBXo/AceBWZ6MHwM3Ak8BbwA/AWEwxeeAYsA1YZ+1mUhHjEOz0nF60zqZlGkfMTcATwFagH8jFFHMROAF8CKwHFgJNNYmxpNqAc56znnKp0hFzI7AaeAM4DIzEFPM38DPwEdAB3F6VGEukBZPnXQzY2E2yktcDjwKvA/uBoZhixoFfgfeB5SQ5YxznXSGx2550Rhx7rcAjwKtAH+YwjINDwJJEfq3DVSEz9nai2YgWcx3wIPAyJmEMYsqVKLxSzSrMscvu4ggwr1oBEWKuAu6zK/5HhIAvwvZDpoKPYZkT1cUySfenQd4iK2mxpIcltUmaE/FITuZATTxDj1GaRbZWG0YUM9UiYCOm6j1D+eIxj8lKyXzaB27ApEIX/ZiSuxrys4DngJPARIwNPAp0A1cnnjAnRrs9ozlgTRKDjq2ngeEKpMcxh1sPsBZornrPWadrKD1Zu5Msqb03C+yKIH0JOAXsADYAC0ijvKDYofV7Dg/b8EpipxX4JoT8IeBZYKkNsdgTUykLFTAoqc+7drekexLOR17SmYixg5J+k3QpCILYjVBFAY6hPZIuOEMtktYWZjcmJiR9KmnUu/6QpI8lrUhoLx7sks7DlMwu9mMOu7D7Bcy2YTPbuTYL2Ex4tXoAWJEkhJIIEKaMcDGEqW38e7M22+y2e2c3plTOOuNbGiGindIOrMsRWPg8T+nhN2JJN0aENTYfU1K76MN5P4Sp4X8Kz5TkQkT8O+HkENzmOTqHaX4K4xsxOT0KjRHhEFyHaQNddDpkdlIZDRWxANPgu+jF1CrLgdPe2EH7qVXEXTWLoFhJfuA5OAusBF7wrk8Cm6zzAzWK2IFNx2mE0XpMA+6iC/jSu/Y7pjyQDYO4Il4KEfEncEdaYbQQUw67OEVp+/kJtotyRPgdXpiIlVa8v8r3piUgA2ynPMYxVaV/RpQTsRnTWoat1HeYd0+pCBCmQyrXkBwHbqP0lC4nYiRk5gviNpHymbAY+KWMgNCXYDFERK1MNhXyXhi9F+F0GNNJhc5YAhHpk/cILMM0Iy7ymG6tbMqLIWK0LuRDCCzBvHTahck6HcRswB0bd9pnT2NecH2P6dAqkq/5VwbHQZOKv+TE7qic55slLZJ0jaS/VO8fQmYwg/8I/gG4FXiLvEhkpAAAAABJRU5ErkJggg==',
    ['hand-pointing'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFGElEQVRo3tWaW2xUVRSGv+kdaSkpRcSqUYQ+IFHpgzFqvRDBeENj4oNRHzQxERMV4pMafTHxlpDYvmisxBAe1BCNqaIhRhNAS/QBK8RLFGyjiEjDRegUOu3M78PaY3d3z7Qzp6dD+ZOTObPP2Wvtf+211l57z8A5jlSSwiTlZVYBOSALkEolqiZZAm7QAI3AGmAVcBFwGvgB6AZ+BHIzSST24N21QtI2ScOaiIOSnpZU65GdHXCDv0xSjybHkCORmjUk3OBTkjaqOPwh6cqkCVRMs//FwNqgLQ18DfwW8e5defKzhcClwOKgrQML5vuB/cGzqxLQmSiBuUC1930E6MEy0M8RBOqxFDtrCIQQlv/97z4Sz6NJEyg7znkCifpjEZgHtANVkv4BDgCnIH65UW4C12ClRRUwCPQCbwLdkjJxSJTbhaqB84AaoAmrm94FngGq46wP5Z6BKNQDzwIHgV5Ji4EzQB9wCMhONjNng0A+1VZ6bQ3AG+5ZPVaG/425W6ekfoiOk3K7UBp4GXgI2B08awIWALWYm10ObADeA1ZAdAky6Qy4DlXAJcASJ/wwVuecjEFgD/AalnlSWFBXTtHnWuBV4EHg36IIeEyXAeuBO4FFTlka26h0MH7VLQaDwLC7P4G5Skggi3mG7y+rsfpqq6RxrjSBgDf4NqDLffqYD9wEXA18VyKBqbAb6MRcZj1Wa4FlrVXA1rBDIRdqwqa6jcJodJYphFFgIGgbcO1RyLrBv48F9Y3YopdHC5aGR/xO44LYs/7twM2BAjklxSIHbMKq0oz73MSY22UZX+yNAsfc/TDmbqGxJ6ShQjNwS/BsCEtze4GngOuKJLELi58lwO9Av/fsV6yUWO6+H3BtJSGKQA02XT6+xzLBKWzB+RAL6oJwgSZsQerzn7mZ7gfWAY+55q6AYGwCOcziPhYCzY5AD/A28EKpynxyjsRO4BvXXIp7/o+ohWwUK7J8tAKP5g0IvAV8G5dAnoS7su6KVZFWhEIduoG/gncfYSwrHQJeZ2KglR2FSom9wOagrQV4EosRgG3AB8E7pWaqyRBOR2SpOoGAF3xd2JGgj/uAW939MLAR+MV7vp8YmSQClUBd0Jah2JXfOzJcJ2kkOKD6QtJ87512SZvd1Z5vjwvXf6GkfYHed0qS7V5ukvRVIGhE0uMeASRVuGvah1ZORpuko4He5+MQQNLdkk4Gwn6StDTpY0JP5xOBvoyke0rW54TVOvcI0SmpKkkSTl+9pO2Brj53iBzbIivd4ayP45LuSMJtAl33SkoHurZIqoylxxP8nKRcILhHUkuCBC6QtDPQMSRp7bQM5TqfL2lHhCt1SKpJIPPUOVmhkT6T1DAtI3mzcFtEdki7rBTrxwtv8C9KOhPIPiZpTSJuqrF0+ZKkbKDoiKQHSiHhGWWRs/zpQGZO0iuxfX8SpQskfRrhSgOSNkiaN5nFvIHPlaXGXREGkaSPJTUnNvhA+RWSeiOUDstS4MOSWmUrdp2LkTmyFXalLM9vlzSoaHwplzanIlBy/eoJvAHbIrZGvDYKHMEOp05g+9g6bE9xIXYwEFVI5oBPsPOgPpih35i9mbhe0h4lg+PO55sTCdoSSCyTLTTpmAMfkvS5pNVKeGUvhcQc2WLzkaTDBYLSR0ZWHmyR1VoNca2eiIN5imuBpdjObTm2CWrE9t4Z4Ci2cd+HbZr+xJ0TxfX1GfnzgkcohW1OUozt1jTr/jNxNvEfu5DfZqTe5poAAAAASUVORK5CYII=',
    ['person-simple-run'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEoElEQVRo3u2ZXYhVVRTHf/eOY34lJRiJmZppkkRJCEkhfVDQS58PCT2liT1ECkFg0UuRPdVLQRg+ZT1V0sdDGX1QFqhFFFaaNmYpampW42jjOHd+Pex1c8/13pm5d+bOTOEfDueee87ee6291v+/1z4HzuEcBoVCswdQAYrARcBlwPnAceBn4Degp1BouhmNGR7HTHWt+r16XD0V5x/UZ+N+2dHRgcz4Reo2+8a2eG70OBHGzFK3OjBsjedH2vRes7+2iqE96uk4V2LtqIhCGDEtcj7HsTDyjjgfq7j/XbQbFQ4sVturzHAx7herRKg92tU1XrFJfkwGxmbX3cCXnJHMnrjuzp4ZG+1GhQPtQFd2PQZYBBSzdWFR/F9GV7SrC2PqbTBA7AX2AVdm/z0U5y3Addl1Gb9Gu5HFf16FMifqXQdmjgrjMweGZSUecBUVnReAKcC8OKYB44FTwGFgD7AbOMgZhZkJrATuBC4lqU0XiSNvAeuAXwAaKer6bZGpxgJgKXA7cDkwqaK9QCdwANgKvA18DBzlTDU6mySV7aRq9DDNrEYjrJPUNer+AeZzGacit1eoFw47QbM8fjiUo1F0qR+qt6gtw+ZEGF9QX6lh2En1oLo3zidqyGMZR01SOX0oo1Ez+bIBVgHPAS2kPN8BvAl8RiJiJ3AeidALgduAxcAFVbrtAb4BXiBx5A9ojLz1RGGy+pj6rvq0UbdXzmCWcuPUm9Vd/fBjs7oy+mtpmoxm8tkClAD7mrF4fgGwCZjeT/clkoR+AXxOiu4RkixPIEn13IjaJ8Dppu6fsyg8VTHjpeBIX+hRO9RD6j71cERK9S/1/qYrWQwwV91dYdxO9R51QxjTCF6vpmJDVk5nqbaMtNDleAPYCDwI3A1sAA6RRGGgOEhKuabNPOr1kQI59qjzs2dQW9Wr1EfV9yJlOqvMerd6RN0YkT0rhYaEEdHpFOBVUqmR40VgNVDKCZgZMg64BJgDzAKmAq1AB2mPsAP4CTgJTZDcbEafCbJWYr/6kmm/29pUEjZofDH0/Hg/JDwajlzRdDWpw/gWdbn6ex1qslNdqo4ZEScyIk5Wn6ghi21BzFINJ9rVx02r9rAb3qreoL5jqjQr8bV6jTpPXW3acVWrZjvVJ4eUF5mRLRHiYvyeqM5W71Vf6yNlvjXbHsYxVV1lqlor0aE+MBhOFHLjAzcBy4GJwN+kSnMqaWt4Mb1fWOXYDDxCqlv+lbus32uB54ElFe32AHcB2/N2jc7+nCBZPTihvqzOqDWTWTRmqx9V6WPdoEkdA9xq9RWxGk6rW9T7BkLGzImrPbtWOqQuHAoH5qg7+jC6x6Tn76vLIr8HnL+ZE6s8W6HWNMKFahy4kVR0TSct6d3An6RlfTvwFfAjDS7tMc4M4ANgfnZrE4kLnYPlQVmFxof6TCjn56BC3HuMgrq+IgJtZR7Vg14vdzPPSyQFahYk1CrDFNK7o331dNSs1+s1kU3SAXrX9+Oo/iJgdDmQoYPeHzgKjdgzkg7sAtqy6zbSe9W6MCKfyDOiLgFWxO/1wKdQn7KN2Df+zIli2FGq1/j/Bf4Be21CZfuMNUAAAAAASUVORK5CYII=',
    ['chat-circle'] = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEi0lEQVRo3u2Zy2vcVRTHPzNmmowhwdbGIgQKakHowgdqtLQliCBmIYjaaFeKKO58YPoH+A/ozkUFrQsFEXzgwlANVXwkUXwsqtG4EYogedXEJDWT+HVxz4+euTO/md9kHukiXxhm+M39ne8555577jn3wi520RRyrRAiKfm5B9gHDAB7gaI9XwcWgXn73gDI5Zqn37YEp3QfcAswDAwBNwH7gauBLhuzCayZAbPAFHAO+An4p1XGZFbcPtdJelrShKRlNY6/JX0m6SlJA4ncTihelPS4pClJpW0oHqMk6RtJJyT1tMUQp/wNkt6UtJZBsS1JG/bZyjB+VdLrkg42YkTdwHOCjgCvAnemDF0Hfge+B84DF4AV+68PGAQOA7cT1kkxRc4k8BwwDU2uDef5+yTNpnhuXtIZSSMWy/nYg05O3saMSHpL0kKKzBlJw02FkyM9kqL8hqQPJB2VVMhK5uQW7N0PTVY1I4a2ZUQU89NVhC9IGpPUt10vOY4+SadSZuPrRteEF16U9EYVoX9KGk1CpVm40Bo12TFOS+rOzOU8c1KV2WbBiFqa6hznaJWZWJX0aGZOG3hAIc/HMT/WKs/XmIlTVdbEl5L21+V1nnhG0mYk5H1J/e1QPuLvt+TgUZL0RN1ZcItqIhIwL+lYq0OnhgOPG6fHuKTeLAYcU6hTPM5I6mqn8pEOBYV9wmNJ0j2xDnn/omEY6Hdj1oF3CRVlp1Ayzkvu2TXA8UjXywYY9hBKYo9Z4FvoTMnrOKaN22MIKPgHsQH7gBujZz8Ac23XvBJzxu1xiDATqQYMEJoRj/NA+4O/EjLumvrFBuwldFIJ/iNUlZ3rmMq5LlDuvF7TMdUA3wYCbHG5JN4JLFOePLqIyvB8Q+KuQMQGrEUWX0VoRnYK/ZRHRHI4kGrAUjQgT+ik2ttwR3Bcg5R3javAxVoGzAEL0bPDtOj8qEHkjDvWb76WAYuEvtbjNkL66jQGjNtjljozsEE4dPI4hDXynaqFDHcZt8ckocyoNMDl3nOE9JWgCJwg2sLbjIJx9rhnF4EvIl0rra9RTh+9EsvpavvACvAOYRNLcC3wcLvdbugHXjTOBJum02o8uMwANzU/E+VbyvNxy2GezQPPAiPR31PAx5GO1YXYZ6xKP/xIu0LI8T7WVFNvg3olnY2EzEgabHMz3/yxigm7o8oCOi0plwhxHtv2jLj3mzrY6vICDfdSvoBKwCeEsjYv6XrgbkLruQW8J2nKxtUtux1PweS8BDxAZZr+FXgB+COLXB8+n0Ze+E3hjPIhm4kZSf9GKXbHDndzngS4FThLedezSKiPDhJ65jS08nj9eawiyNxImbX3S7qk1qAjFxxxbv/LvNZdz17CptJD+v6QJ1vDtAl8B7wCfIQdpWT1fBxC3cBrwJMpSi8BPwLjwFeEkDhJCItGG59lU/xtU3yuEcXTDIAQqy8DD5pSK4Tr0HFgAviF8i29j1D2DhMqyOSatUj6Nesk8DktuGYte8sZ0QPcDBwghNVsonQ1Ivde2kX3GmH25uy7ZRfdu9hFk/gf/jwPHEaIhDsAAAAASUVORK5CYII=',
    ['pattern-dots'] = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCRcBARiwYFwzAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTIzVDAxOjAxOjI0KzAwOjAw2eQUTwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0yM1QwMTowMToyNCswMDowMKi5rPMAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMjNUMDE6MDE6MjQrMDA6MDD/rI0sAAAAN0lEQVRYw+3QoREAIBADwdf0b7/WQ2BAwxBz20AmVyVJki4BIzneLB15zul/iWiBvURsXJKkFyaESC5x/EuNUwAAAABJRU5ErkJggg==',
    ['pattern-grain'] = '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',
    ['pattern-hatch'] = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCRcBARiwYFwzAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTIzVDAxOjAxOjI0KzAwOjAw2eQUTwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0yM1QwMTowMToyNCswMDowMKi5rPMAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMjNUMDE6MDE6MjQrMDA6MDD/rI0sAAAAOUlEQVQ4y+3OsQ0AIAgAQRZh/zHPRmNhCYkNP8Dlwy2jEBKiEztgGwYV68FKc4MNNthgH7ENtmHIBXHfazCTp1k8AAAAAElFTkSuQmCC',
    ['pattern-sparkles'] = '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',
}
--[[/ICONS]]






-- finished!
return library
