-- for past library usages
pcall(function()
    (getgenv().seoul):Destroy()
end)




-- bootleg require
local rawgit = 'https://github.com'
local repo   = 'kagehana/seoul'
local branch = 'blob/main/bin'

local function get(fname)
    return loadstring(game:HttpGet(('%s/%s/%s/%s.lua?raw=true'):format(rawgit, repo, branch, fname)))()
end


-- services
local tween   = game:GetService('TweenService')
local players = game:GetService('Players')
local uinput  = game:GetService('UserInputService')


-- shortcuts
local insert = table.insert
local concat = table.concat


-- systems
local class = get('class')


-- templates
local ui,
    uifolder,
    uidivider,
    uibutton,
    uiquery,
    uislider,
    uitoggle,
    uidropdown,
    uinotification
    = get('ui')


-- classes
local seoul    = class('seoul')
local window   = class('window')
local folder   = class('folder')
local button   = class('button')
local divider  = class('divider')
local toggle   = class('toggle')
local slider   = class('slider')
local query    = class('query')
local dropdown = class('dropdown')


-- utilities
local conn = {}

--[=[
    connects an event to a callback and stores the connection.

    @param ev (RBXScriptSignal) the event to connect.
    @param cb (function) the callback function.
]=]
local function _connect(ev, cb)
    insert(conn, ev:Connect(cb))
end

--[=[
    enables dragging functionality for a ui element.

    @param target (Instance) the ui element to drag.
    @param ... (Instance) ui elements that trigger dragging.
]=]
local function _drag(target, ...)
    local go     = nil
    local start  = nil
    local pos    = nil

    local function upd(input)
        local delta = input.Position - start
        local position = UDim2.new(
            pos.X.Scale, pos.X.Offset + delta.X,
            pos.Y.Scale, pos.Y.Offset + delta.Y)

        tween:Create(target, TweenInfo.new(0.25), {Position = position}):Play()
    end

    for k, v in ipairs({...}) do
        v.InputBegan:Connect(function(input)
            if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                go     = true
                start  = input.Position
                pos    = target.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        go = false
                    end
                end)
            end
        end)
    end

    uinput.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if go then
                upd(input)
            end
        end
    end)
end






--[=[
    @class window
    the visible container for all ui elements generated by the library.

    @param core (Instance) the core ui instance.
    @param trademark (string) the title of the window.

    @private
]=]
local client = players.LocalPlayer
local mouse  = client:GetMouse()
local twinfo = TweenInfo.new(0.1)
local ddel   = uidropdown.elements.element:Clone()

uidropdown.elements.element:Destroy()

function window:__new(core, trademark)
    local win = core.ui

    if protect_gui then
        protect_gui(win)
    end

    win.topbar.trademark.Text = trademark and tostring(trademark) or 'Seoul'

    win.topbar.minimize.MouseButton1Click:Connect(function()
        self:__minimize()
    end)

    win.topbar.escape.MouseButton1Click:Connect(function()
        self:destroy()
    end)

    _drag(win, win.topbar)

    self._ui        = win
    self._folders   = win.content.folders
    self._folders.layout:GetPropertyChangedSignal('AbsoluteContentSize', function()
        self._folders.CanvasSize = UDim2.fromOffset(0, self._folders.layout.AbsoluteContentSize.Y + 42)
    end)
end

--[=[
    @method __minimize
    shrinks or enlarges the window.

    @private
]=]
function window:__minimize()
    local win       = self._ui
    local minheight = 26
    local expheight = 222
    local ismin     = win.Size.Y.Offset == minheight
    local newpos    = UDim2.new(
        win.Position.X.Scale, win.Position.X.Offset,
        win.Position.Y.Scale, win.Position.Y.Offset +
        (ismin and ((expheight - minheight) / 2) or ((minheight - expheight) / 2))
    )

    tween:Create(win, twinfo, {
        Size = UDim2.new(0, 171, 0, (ismin and expheight or minheight)),
        Position = newpos
    }):Play()
end


--[=[
    @method destroy
    destroys the window and cleans up resources.
]=]
function window:destroy()
    local anim = tween:Create(self._ui, twinfo, {Size = UDim2.new(0, 0, 0, 0)})

    anim:Play()
    anim.Completed:Wait()

    self._ui.Parent:Destroy()
end

--[=[
    @method folder
    creates a new folder within the window.

    @param name (string) the title of the folder.
    @return folder the created folder instance.
]=]
function window:folder(name)
    return folder(self, name)
end

--[=[
    @method ready
    makes the window visible.
]=]
function window:ready()
    if self._ui.Size.X.Offset ~= 171 then
        local show = tween:Create(self._ui, twinfo, {Size = UDim2.new(0, 171, 0, 222)})

        show:Play()
        show.Completed:Wait()
    end
end






--[[
    @class divider
    a spacer/divider for further sorting of added elements.

    @param gui (Instance) the roblox instance representing the divider.
    @param name (string) the title of the divider.

    @private
]]
function divider:__new(gui, name)
    self._instance = gui
    self._name     = name

    self:modify(name)
end

--[[
    @method update
    dynamically updates the divider's title.

    @param name (string) the new title for the divider.
]]
function divider:modify(name)
    self._name              = name
    self._instance.details.Text = tostring(name)

    return self
end






--[=[
    @class slider
    represents a slider ui element for adjusting numeric values.

    @param gui (Instance) the roblox instance representing the slider.
    @param data (table) the initial configuration for the slider.
        @field name (string) the title of the slider.
        @field min (number) the minimum value of the slider.
        @field max (number) the maximum value of the slider.
        @field call (function) the callback function triggered when the slider value changes.

    @private
]=]
function slider:__new(gui, data)
    self._instance = gui
    self:modify(data)
end

--[=[
    @method modify
    updates the slider dynamically with new configuration.

    @param new (table) the updated configuration for the slider.
        @field name (string) the new title of the slider.
        @field min (number) the new minimum value of the slider.
        @field max (number) the new maximum value of the slider.
        @field call (function) the new callback function triggered when the slider value changes.
]=]
function slider:modify(new)
    if new.name then
        self._instance.details.Text = new.name
    end

    self:__assign(new)

    return self
end






--[=[
    @class query
    represents a text input ui element for user input.

    @param gui (Instance) the roblox instance representing the query input.
    @param data (table) the initial configuration for the query.
        @field placeholder (string) the placeholder text for the input field.
        @field call (function) the callback function triggered when the input is submitted.

    @private
]=]
function query:__new(gui, data)
    self._instance = gui
    self:modify(data)
end

--[=[
    @method modify
    updates the query dynamically with new configuration.

    @param new (table) the updated configuration for the query.
        @field placeholder (string) the new placeholder text for the input field.
        @field call (function) the new callback function triggered when the input is submitted.
]=]
function query:modify(new)
    self:__assign(new)

    if new.placeholder then
        self._instance.input.PlaceholderText = new.placeholder
    end

    return self
end






--[=[
    @class button
    represents a button ui element for triggering actions.

    @param gui (Instance) the roblox instance representing the button.
    @param data (table) the initial configuration for the button.
        @field name (string) the text displayed on the button.
        @field call (function) the callback function triggered when the button is clicked.

    @private
]=]
function button:__new(gui, data)
    self._instance = gui
    self:modify(data)
end

--[=[
    @method modify
    updates the button dynamically with new configuration.

    @param new (table) the updated configuration for the button.
        @field name (string) the new text displayed on the button.
        @field call (function) the new callback function triggered when the button is clicked.
]=]
function button:modify(new)
    self:__assign(new)

    if new.name then
        self._instance.details.Text = new.name
    end

    return self
end






--[=[
    @class dropdown
    represents a dropdown ui element for selecting from a list of options.

    @param gui (Instance) the roblox instance representing the dropdown.
    @param data (table) the initial configuration for the dropdown.
        @field name (string) the title of the dropdown.
        @field elements (table) the list of options in the dropdown.
        @field call (function) the callback function triggered when an option is selected.

    @private
]=]
function dropdown:__new(gui, data)
    self._instance = gui
    self:modify(data)
end

--[=[
    @method modify
    updates the dropdown dynamically with new configuration.

    @param new (table) the updated configuration for the dropdown.
        @field name (string) the new title of the dropdown.
        @field elements (table) the new list of options in the dropdown.
        @field call (function) the new callback function triggered when an option is selected.
]=]
function dropdown:modify(new)
    self:__assign(new)

    if new.name then
        self._instance.details.details.Text = new.name
    end

    if new.elements then
        for _, child in ipairs(self._instance.elements:GetChildren()) do
            if child:IsA('TextButton') then
                child:Destroy()
            end
        end

        for _, v in ipairs(new.elements) do
            local nel = ddel:Clone()

            nel.Text = v
            nel.MouseButton1Click:Connect(function()
                self._call(v)
            end)

            nel.Parent = self._instance.elements
        end
    end

    self._instance.elements.CanvasSize = UDim2.new(0, 0, 0, self._instance.elements.layout.AbsoluteContentSize.Y)

    return self
end






--[=[
    @class toggle
    represents a toggle ui element for switching between two states.

    @param gui (Instance) the roblox instance representing the toggle.
    @param data (table) the initial configuration for the toggle.
        @field name (string) the text displayed next to the toggle.
        @field call (function) the callback function triggered when the toggle state changes.
]=]
function toggle:__new(gui, data)
    self._instance = gui
    self:modify(data)
end

--[=[
    @method modify
    updates the toggle dynamically with new configuration.

    @param new (table) the updated configuration for the toggle.
        @field name (string) the new text displayed next to the toggle.
        @field call (function) the new callback function triggered when the toggle state changes.
]=]
function toggle:modify(new)
    self:__assign(new)

    if new.name then
        self._instance.details.Text = new.name
    end

    return self
end





--[=[
    @class folder
    a functional folder/tab that acts as a categorizer for ui elements.

    @param name (string) the title of the folder.

    @private
]=]
function folder:__new(win, name)
    self._window = win

    local nf = uifolder:Clone()

    nf.opener.Text = tostring(name)
    nf.opener.MouseButton1Click:Connect(function()
        if self._instance.Size.Y.Offset == 20 then
            self:__open()
        else
            self:__close()
        end
    end)


    nf.Parent = self._window._folders

    self._window   = win
    self._instance = nf
end

--[=[
    @method __open
    expands the folder to display its contents.

    @private
]=]
function folder:__open()
    local size = 20

    for _, v in ipairs(self._instance:GetChildren()) do
        if v:IsA('Frame') or v:IsA('TextButton') and v.Name ~= 'opener' then
            size = (size + v.Size.Y.Offset + 2)
        end

        size = size + 0.6
    end

    tween:Create(self._instance, twinfo, {Size = UDim2.new(0, 142, 0, size)}):Play()
end

--[=[
    @method __close
    collapses the folder to hide its contents.

    @private
]=]
function folder:__close()
    tween:Create(self._instance, twinfo, {Size = UDim2.new(0, 142, 0, 20)}):Play()
end

--[=[
    @method divider
    creates a new divider element within the folder.

    @param data (string) the title of the divider.
    @return divider the created divider instance.
]=]
function folder:divider(data)
    local nd   = uidivider:Clone()
    local inst = divider(nd, data)

    nd.Parent = self._instance

    return inst
end

--[=[
    @method slider
    creates a new slider element within the folder.

    @param data (table) the configuration for the slider.
        @field name (string) the title of the slider.
        @field min (number) the minimum value of the slider.
        @field max (number) the maximum value of the slider.
        @field call (function) the callback function triggered when the slider value changes.
    @return slider the created slider instance.
]=]
function folder:slider(data)
    local ns   = uislider:Clone()
    local inst = slider(ns, data)

    local function fill(pos)
        local min   = inst._min
        local max   = inst._max
        local cabsx = ns.container.AbsolutePosition.X
        local cw    = ns.container.AbsoluteSize.X
        local delta = math.clamp((pos - cabsx) / cw, 0, 1)
        local value = math.clamp((delta * max), min, max)

        tween:Create(ns.container.fill, TweenInfo.new(0.04, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(delta, 1)}):Play()

        local rounded = math.floor(value + 0.5)
        ns.integer.Text = tostring(rounded)

        return rounded
    end

    ns.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputState == Enum.UserInputState.Begin then
            local lastv = fill(mouse.X)

            local movec = mouse.Move:Connect(function()
                lastv = fill(mouse.X)
            end)

            local endc; endc = uinput.InputEnded:Connect(function(ninput)
                if ninput.UserInputType == Enum.UserInputType.MouseButton1 then
                    movec:Disconnect()
                    endc:Disconnect()

                    inst._call(lastv)
                end
            end)
        end
    end)

    ns.integer.FocusLost:Connect(function()
        local min   = inst._min
        local max   = inst._max
        local value = tonumber(ns.integer.Text)
        local send  = 0

        if value then
            value = math.clamp(value, min, max)

            local rounded = math.floor(value + 0.5)
            send = rounded
            ns.integer.Text = tostring(rounded)

            local delta = (value - min) / (max - min)
            fill(ns.container.AbsolutePosition.X + delta * ns.container.AbsoluteSize.X)
        else
            local midpoint = math.floor((min + max) / 2 + 0.5)
            send = midpoint
            ns.integer.Text = tostring(midpoint)

            fill(ns.container.AbsolutePosition.X + (ns.container.AbsoluteSize.X / 2))
        end

        inst._call(send)
    end)

    ns.Parent = self._instance

    return inst
end

--[=[
    @method query
    creates a new query (text input) element within the folder.

    @param data (table) the configuration for the query.
        @field placeholder (string) the placeholder text for the input field.
        @field call (function) the callback function triggered when the input is submitted.
    @return query the created query instance.
]=]
function folder:query(data)
    local nq   = uiquery:Clone()
    local inst = query(nq, data)

    nq.input.FocusLost:Connect(function(go)
        if go then
            inst._call(nq.input.Text)
        end
    end)

    nq.Parent = self._instance

    return inst
end

--[=[
    @method button
    creates a new button element within the folder.

    @param data (table) the configuration for the button.
        @field name (string) the text displayed on the button.
        @field call (function) the callback function triggered when the button is clicked.
    @return button the created button instance.
]=]
function folder:button(data)
    local nb   = uibutton:Clone()
    local inst = button(nb, data)

    nb.MouseButton1Click:Connect(function()
        inst._call()
    end)

    nb.Parent = self._instance

    return inst
end

--[=[
    @method toggle
    creates a new toggle element within the folder.

    @param data (table) the configuration for the toggle.
        @field name (string) the text displayed next to the toggle.
        @field call (function) the callback function triggered when the toggle state changes.
    @return toggle the created toggle instance.
]=]
function folder:toggle(data)
    local nt   = uitoggle:Clone()
    local inst = toggle(nt, data)

    local state = false

    nt.trigger.MouseButton1Click:Connect(function()
        state = not state

        if state then
            tween:Create(nt.trigger, twinfo, {BackgroundColor3 = Color3.new(0.14902, 1, 0)}):Play()
            tween:Create(nt.trigger, twinfo, {BackgroundTransparency = 0.6}):Play()
        else
            tween:Create(nt.trigger, twinfo, {BackgroundColor3 = Color3.new(1, 1, 1)}):Play()
            tween:Create(nt.trigger, twinfo, {BackgroundTransparency = 0.95}):Play()
        end

        inst._call(state)
    end)

    nt.Parent = self._instance

    return inst
end

--[=[
    @method dropdown
    creates a new dropdown element within the folder.

    @param data (table) the configuration for the dropdown.
        @field name (string) the title of the dropdown.
        @field elements (table) the list of options in the dropdown.
        @field call (function) the callback function triggered when an option is selected.
    @return dropdown the created dropdown instance.
]=]
function folder:dropdown(data)
    local nd   = uidropdown:Clone()
    local inst = dropdown(nd, data)

    nd.elements.ChildAdded:Connect(function()
        nd.elements.CanvasSize = UDim2.new(0, 0, 0, nd.elements.layout.AbsoluteContentSize.Y)
    end)

    for _, v in ipairs(inst._elements) do
        local nel = ddel:Clone()

        nel.Text = v
        nel.MouseButton1Click:Connect(function()
            inst._call(v)
        end)

        nel.Parent = nd.elements
    end

    nd.details.trigger.MouseButton1Click:Connect(function()
        local size = 67

        if nd.Size.Y.Offset == 67 then
            size = 18
        end

        local show = tween:Create(nd, twinfo, {Size = UDim2.new(0, 131, 0, size)})

        show:Play()
        show.Completed:Wait()

        self:__open()
    end)

    nd.Parent = self._instance

    return inst
end






--[=[
    @class seoul
    the main library table that manages windows and notifications.

    @private
]=]
function seoul:__new()
    self._windows  = {}
    self._notifs   = {}
    self._instance = ui:Clone()

    getgenv().seoul = self._instance

    self._instance.Parent = client:WaitForChild('PlayerGui')
end

--[=[
    @method window
    creates and returns a new window if none exist.

    @return window the created window instance.
]=]
function seoul:window()
    if #self._windows == 0 then
        local win = window(self._instance)

        insert(self._windows, win)

        return win
    end
end

--[=[
    @method notify
    displays a notification with the given message and duration.

    @param data (string | table) the message to display, or a table containing:
        @field message (string) the text to display.
        @field duration (number) optional duration before auto-removal, defaults to 4.5 seconds.
]=]
function seoul:notify(data)
    local dataistable = type(data) == 'table'
    local msg         = dataistable and data.message or data
    local duration    = dataistable and (data.duration or 4.5) or 4.5
    local notif       = uinotification:Clone()

    notif.content.content.Text = msg
    notif.Parent               = self._instance.notifications

    if #self._notifs >= 4 then
       (table.remove(self._notifs, 1)):Destroy()
    end

    insert(self._notifs, notif)

    local function remove(target)
        if not target then
            return
        end

        local out = tween:Create(target, twinfo, {Size = UDim2.new(0, 0, 0, 0)})

        out:Play()
        out.Completed:Wait()

        target:Destroy()
        table.remove(self._notifs, table.find(self._notifs, target))
    end

    local enter = tween:Create(notif, twinfo, {Size = UDim2.new(0, 142, 0, 56)})

    enter:Play()
    enter.Completed:Wait()

    coroutine.wrap(function()
        task.delay(duration, function()
            pcall(function()
                remove(notif)
            end)
        end)
    end)()

    notif.escape.MouseButton1Click:Connect(function()
        coroutine.wrap(function()
            pcall(remove, notif)
        end)()
    end)
end





-- finished!
return seoul
