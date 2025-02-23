-- bootleg require
local rawgit = 'https://raw.githubusercontent.com'
local repo   = 'kagehana/seoul'
local branch = 'refs/heads/main/bin'

local function get(fname)
    return loadstring(game:HttpGet(('%s/%s/%s/%s.lua'):format(rawgit, repo, branch, fname)))()
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
local library  = class('library')
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
    local speed  = 0.25
    local start  = nil
    local pos    = nil

    local function upd(input)
        local delta = input.Position - start
        local position = UDim2.new(
            pos.X.Scale, pos.X.Offset + delta.X,
            pos.Y.Scale, pos.Y.Offset + delta.Y)

        tween:Create(target, TweenInfo.new(speed), {Position = position}):Play()
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
local core

function window:__new(trademark)
    local win = ui:Clone()

    if protect_gui then
        protect_gui(win)
    end

    win.topbar.trademark.Text = tostring(trademark) or 'Seoul'

    _drag(win, win.topbar)

    self._ui        = win
    self._folders   = win.content.folders
    self._ui.Parent = game.Players.LocalPlayer:WaitForChild('PlayerGui')

    core = self
end

function window:folder(name)
    return folder(name)
end

-- folders
function folder:__new(name)
    local nf = uifolder:Clone()

    nf.opener.Text = tostring(name) or 'Folder'
    nf.opener.MouseButton1Click:Connect(function()
    end)

    nf.Parent      = core._folders

    self._core = nf
end

function folder:__resize()
    local ti = TweenInfo.new(0.4, Enum.EasingStyle.Linear)

    if self._core.Size.Y.Offset ~= 20 then
        local size = 2

        for _, v in ipairs(self._core:GetChildren()) do
            size = (size + v.Size.Y.Offset)
        end

        tween:Create(self._core, ti, {Size = UDim2.new(0, 131, 0, size)}):Play()
    else
        tween:Create(self._core, ti, {Size = UDim2.new(0, 131, 0, 20)}):Play()
    end
end

function folder:divider(name)
    local nd = uidivider:Clone()

    nd.details7.Text = tostring(name) or 'Divider'
    nd.Parent        = self._core
end

function folder:slider(name, min, max, call)
    local ns = uislider:Clone()

    ns.details2.Text = tostring(name) or 'Slider'

    local function fill(pos)
        local delta = math.clamp((pos - ns.container.AbsolutePosition.X) / ns.container.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + (max - min) * delta)

        fill.Size       = UDim2.new(delta, 0, 1, 0)
        ns.integer.Text = tostring(value)

        call(value)
    end

    ns.container.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            fill(input.Position.X)

            local movec = input:GetPropertyChangedSignal('Position'):Connect(function()
                fill(input.Position.X)
            end)

            local endc; endc = input:GetPropertyChangedSignal('UserInputState'):Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    movec:Disconnect()
                    endc:Disconnect()
                end
            end)
        end
    end)

    ns.integer.FocusLost:Connect(function()
        local value = tonumber(ns.integer.Text)

        if value then
            value = math.clamp(value, min, max)

            ns.integer.Text = tostring(value)

            fill(ns.container.AbsolutePosition.X + (value - min) / (max - min) * ns.container.AbsoluteSize.X)
        else
            ns.integer.Text = tostring(math.floor((min + max) / 2))
        end
    end)

    fill(ns.container.AbsolutePosition.X + (ns.container.AbsoluteSize.X / 2))
end

-- library
function library:__new()
    self._windows = {}
end

function library:window()
    local win = window()

    insert(self._windows, win)

    return win
end

function library:notify()
    return
end

-- package
return library
