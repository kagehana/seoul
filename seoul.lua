-- bootleg require
local rawgit = 'https://github.com'
local repo   = 'kagehana/seoul'
local branch = 'blob/main/bin'

local function get(fname)
    return loadstring(game:HttpGet(('%s/%s/%s/%s.lua?raw=true'):format(rawgit, repo, branch, fname), true))()
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


-- classes
local seoul  =   class('seoul')
local manager  = class('manager')
local window   = class('window')
local folder   = class('folder')
local button   = class('button')
local divider  = class('divider')
local toggle   = class('toggle')
local slider   = class('slider')
local query    = class('query')
local dropdown = class('dropdown')


-- templates
local ui,
    uifolder,
    uidivider,
    uibutton,
    uiquery,
    uislider,
    uitoggle,
    uidropdown
    = get('ui')


-- utilities
local _conn = {}

local function _connect(ev, cb)
    insert(_conn, ev:Connect(cb))
end

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

-- windows
local client = players.LocalPlayer
local mouse  = client:GetMouse()
local twinfo = TweenInfo.new(0.1)
local ddel   = uidropdown.elements.element:Clone()
local core

uidropdown.elements.element:Destroy()

function window:__new(trademark)
    local sgui = ui:Clone()
    local win  = sgui.ui

    if protect_gui then
        protect_gui(win)
    end

    sgui.Parent               = client:WaitForChild('PlayerGui')
    win.topbar.trademark.Text = trademark and tostring(trademark) or 'Seoul'

    win.topbar.minimize.MouseButton1Click:Connect(function()
        self:__resize()
    end)

    win.topbar.escape.MouseButton1Click:Connect(function()
        self:destroy()
    end)

    _drag(win, win.topbar)

    self._ui        = win
    self._folders   = win.content.folders

    core = self
end

function window:__resize()
    tween:Create(self._ui, twinfo, {Size = UDim2.new(0, 171, 0, (self._ui.Size.Y.Offset ~= 26) and 26 or 222)}):Play()
end

function window:destroy()
    local anim = tween:Create(self._ui, twinfo, {Size = UDim2.new(0, 0, 0, 0)})

    anim:Play()
    anim.Completed:Connect(function()
        self._ui.Parent:Destroy()
    end)
end

function window:folder(name)
    return folder(name)
end

-- folders
function folder:__new(name)
    local nf = uifolder:Clone()

    nf.opener.Text = name and tostring(name) or 'Folder'
    nf.opener.MouseButton1Click:Connect(function()
        if self._core.Size.Y.Offset == 20 then
            self:__open()
        else
            self:__close()
        end
    end)

    nf.Parent = core._folders

    self._core = nf
end

function folder:__open()
    local size = 20

    for _, v in ipairs(self._core:GetChildren()) do
        if v:IsA('Frame') or v:IsA('TextButton') and v.Name ~= 'opener' then
            size = (size + v.Size.Y.Offset + 2)
        end

        size = size + 2.6
    end

    tween:Create(self._core, twinfo, {Size = UDim2.new(0, 142, 0, size)}):Play()
end

function folder:__close()
    tween:Create(self._core, twinfo, {Size = UDim2.new(0, 142, 0, 20)}):Play()
end

function folder:divider(name)
    local nd = uidivider:Clone()

    nd.details.Text = name and tostring(name) or 'Divider'
    nd.Parent       = self._core
end

function folder:slider(name, min, max, call)
    local ns = uislider:Clone()

    ns.details.Text = name and tostring(name) or 'Slider'

    local function fill(pos)
        local cabsx = ns.container.AbsolutePosition.X
        local cw    = ns.container.AbsoluteSize.X
        local delta = math.clamp((pos - cabsx) / cw, 0, 1)
        local value = math.clamp(delta * max, min, max)

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

                    call(lastv)
                end
            end)
        end
    end)

    ns.integer.FocusLost:Connect(function()
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

        call(send)
    end)

    ns.Parent = self._core
end

function folder:query(placeholder, call)
    local nq = uiquery:Clone()

    nq.input.PlaceholderText = placeholder and tostring(placeholder) or 'Enter some text...'
    nq.input.FocusLost:Connect(function(go)
        if go then
            call(nq.input.Text)
        end
    end)

    nq.Parent = self._core
end

function folder:button(name, call)
    local nb = uibutton:Clone()

    nb.details.Text = name and tostring(name) or 'Button'
    nb.MouseButton1Click:Connect(call)

    nb.Parent = self._core
end

function folder:toggle(name, call)
    local nt    = uitoggle:Clone()
    local state = false

    nt.details.Text = name and tostring(name) or 'Toggle'
    nt.trigger.MouseButton1Click:Connect(function()
        state = not state

        if state then
            tween:Create(nt.trigger, twinfo, {BackgroundColor3 = Color3.new(0.14902, 1, 0)}):Play()
            tween:Create(nt.trigger, twinfo, {BackgroundTransparency = 0.6}):Play()
        else
            tween:Create(nt.trigger, twinfo, {BackgroundColor3 = Color3.new(1, 1, 1)}):Play()
            tween:Create(nt.trigger, twinfo, {BackgroundTransparency = 0.95}):Play()
        end

        call(state)
    end)

    nt.Parent = self._core
end

function folder:dropdown(name, elements, call)
    local nd = uidropdown:Clone()

    nd.details.details.Text = name and tostring(name) or 'Dropdown'

    local function __resize()
        local size = 67

        if nd.Size.Y.Offset == 67 then
            size = 18
        end

        tween:Create(nd, twinfo, {Size = UDim2.new(0, 131, 0, size)}):Play()
    end

    nd.elements.ChildAdded:Connect(function()
        nd.elements.CanvasSize = UDim2.new(0, 0, 0, nd.elements.layout.AbsoluteContentSize.Y)
    end)

    for _, v in ipairs(elements) do
        local nel = ddel:Clone()

        nel.Text = v
        nel.MouseButton1Click:Connect(function()
            call(v)
            __resize()

            task.wait(0.1)

            self:__open()
        end)

        nel.Parent = nd.elements
    end

    nd.details.trigger.MouseButton1Click:Connect(function()
        __resize()

        task.wait(0.1)

        self:__open()
    end)

    nd.Parent = self._core
end

-- library
function seoul:__new()
    self._windows = {}
end

function seoul:window()
    if #self._windows == 0 then
        local win = window()

        insert(self._windows, win)

        return win
    end
end

function seoul:notify()
    return
end


return seoul
