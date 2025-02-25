-- initialize the library
local lib   = loadstring(game:HttpGet('https://github.com/kagehana/seoul/blob/main/seoul.lua?raw=true'))()
local seoul = lib()

-- create a window
local window = seoul:window('Hub')

-- add a folder
local folder = window:folder('Folder')

-- add a button
folder:button({
    name = 'Button',  -- button's name
    call = function() -- button's callback
        print('Button clicked!')
    end
})

-- add a toggle
folder:toggle({
    name = 'Toggle',       -- toggle's name
    call = function(state) -- toggle's callback
        print('Toggled:', state)
    end
})

-- add a divider
folder:divider('More')

-- add a slider
folder:slider({
    name = 'Slider',       -- slider's name
    min  = 0,              -- slider's minimum value
    max  = 250,            -- slider's maximum value
    call = function(value) -- slider's callback
        print('Slid to:', value)
    end
})

-- add a dropdown
folder:dropdown({
    name     = 'Dropdown',        -- dropdown's name
    elements = {'1', '2', '3'},   -- dropdown's options
    call     = function(selected) -- dropdown's callback
        print('Selected option:', selected)
    end
})

-- add a textbox/query
folder:query({
    placeholder = 'Enter text...', -- query's placeholder text
    call        = function(input)  -- query's callback
        print('Received input:', input)
    end
})

-- make the window visible
window:ready()

-- notify the user with a default lifespan of 4.5s
seoul:notify('Interface loaded!')

-- optionally, you can pass a duration for the notification
seoul:notify({
    message  = 'Interface loaded!', -- notification's message
    duration = 3.5                  -- notification's lifespan
})
