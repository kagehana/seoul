local seoul = loadstring(game:HttpGet('https://github.com/kagehana/seoul/blob/main/seoul.lua?raw=true'))()
local s  = seoul()
local w  = s:window()
local f  = w:folder()

local char = client.Character

f:slider('Walkspeed', 0, 500, function(v)
    char.Humanoid.WalkSpeed = tonumber(v)
end)

f:button('Jump', function()
    char.Humanoid.Jump = true
end)

f:toggle('Spin', function(s)
    if s then
        local Spin = Instance.new('BodyAngularVelocity')

        Spin.Name            = 'Spin'
        Spin.Parent          = char.HumanoidRootPart
        Spin.AngularVelocity = Vector3.new(0, 20, 0)
        Spin.MaxTorque       = Vector3.new(0, math.huge, 0)
    else
        for _, v in ipairs(char:GetDescendants()) do
            if v.Name == 'Spin' then
                v:Destroy();
            end
        end
    end
end)

local plist = {}

for _, v in ipairs(players:GetPlayers()) do
    insert(plist, v.Name)
end

f:dropdown('Goto', plist, function(v)
    for _, vv in ipairs(players:GetPlayers()) do
        if vv.Name == v then
            char.HumanoidRootPart.CFrame = vv.Character.HumanoidRootPart.CFrame; break
        end
    end
end)

f:query('Say', function(v)
    game.ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(v, 'All')
end)
