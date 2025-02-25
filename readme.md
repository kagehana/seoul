# **Seoul**  
Your next UI-library. Representing versatility and abstraction. \
Refer to the [**License**](https://github.com/kagehana/seoul/blob/main/readme.md#license) before continuing.

## **Disclaimers**
1. This library mostly assumes you'll pass the right data to generators. Adhering to this assumption is your responsibility. Validation for data might be added in the future, but it's not a priority.
2. If you're not familiar with **intermediate to advanced code**, it's best to stick to the **UI library** and avoid diving into its source code. This library is highly [**abstracted**](https://en.wikipedia.org/wiki/Abstraction_(computer_science)), meaning many internal processes and structures are intentionally hidden to keep things **simple and user-friendly**.  

### **For Beginners**  
* Properties and functions prefixed with `__` (e.g., `folder:__open`) **should not be modified**.
    * Similarly, elements prefixed with `_` (e.g., `window._folders`) are **not meant to be accessed**. 

## **Why Seoul?**
Seoul is designed to be **simple yet powerful**, making it the perfect choice for both beginners and advanced users. Whether you're building a small project or a complex application, Seoul has the tools you need to create a stunning and functional UI.

### Need to know more?  
🎨 **Aesthetic Design**: A clean, neutral color palette that's easy on the eyes.  
⚙️ **Dynamic Modification**: Nearly every element is modifiable.
🌀 **Animated**: Fluid animations for a polished user experience.  
🔗 **Method Chaining**: Built-in support for [**method chaining**](https://en.wikipedia.org/wiki/Method_chaining).
🛠️ **Actively Maintained**: Regular updates and ongoing developmen.

## **Capability**  
`Seoul` currently allows you to generate these element types:
* One window
* Folders/Tabs
* Sliders
* Dividers
* Buttons
* Toggles
* Dropdowns
* Queries/Textboxes

## **Quick Start**
```lua
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
```

## **Advanced Usage**  
### Dynamic Updates  
Most elements support dynamic updates.
```lua
local window = seoul:window()
local slider = window:slider({
    name = 'Walk Speed',
    min  = 0,
    max  = 100,
    call = function(num)
        game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = tonumber(num)
    end
})

-- don't let them go as fast
slider:modify({ max = 80 })
```

### Method Chaining
This is a redundant example. It's just meant to give a perspective.
```lua
window
    :divider('Teleports')
    :modify('Destinations')


window:query({
    placeholder = 'Enter name here...',
    call = function(name)
        print('Hello,', name)
    end
}):modify({ placeholder = 'Enter display here...' })
```

Support for method-chaining on **ALL** elements is planned.

## **Connect** 
- **Direct Contact**: `@asfdajshf` on [**Discord**](https://discord.com/)
- **GitHub Issues**: Report any bugs or desired features.  

## **License**  
### Custom License  
- You may use this code as a library within your application.
- You are not allowed to modify, redistribute, or sell this code in any form.
- This code is provided "as-is" and cannot be distributed in a modified state.
