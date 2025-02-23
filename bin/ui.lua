local seoul      = Instance.new('ScreenGui')
      seoul.Name = 'seoul'

local ui                  = Instance.new('Frame')
      ui.Name             = 'ui'
      ui.Position         = UDim2.new(0.5, 0, 0.5, 0)
      ui.Size             = UDim2.new(0, 171, 0, 222)
      ui.BackgroundColor3 = Color3.new(0.105882, 0.105882, 0.105882)
      ui.BorderSizePixel  = 0
      ui.BorderColor3     = Color3.new(0, 0, 0)
      ui.AnchorPoint      = Vector2.new(0.5, 0.5)
      ui.ClipsDescendants = true
      ui.Parent           = seoul

local topbar                  = Instance.new('Frame')
      topbar.Name             = 'topbar'
      topbar.Size             = UDim2.new(0, 171, 0, 20)
      topbar.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      topbar.BorderSizePixel  = 0
      topbar.BorderColor3     = Color3.new(0, 0, 0)
      topbar.Parent           = ui

local corners        = Instance.new('UICorner')
      corners.Name   = 'corners'
      corners.Parent = topbar

local patchwork                  = Instance.new('Frame')
      patchwork.Name             = 'patchwork'
      patchwork.Position         = UDim2.new(0, 0, 1, 0)
      patchwork.Size             = UDim2.new(0, 171, 0, -6)
      patchwork.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      patchwork.BorderSizePixel  = 0
      patchwork.BorderColor3     = Color3.new(0, 0, 0)
      patchwork.Parent           = topbar

local trademark                        = Instance.new('TextLabel')
      trademark.Name                   = 'trademark'
      trademark.Position               = UDim2.new(0.0467836, 0, 0.15, 0)
      trademark.Size                   = UDim2.new(0, 157, 0, 14)
      trademark.BackgroundColor3       = Color3.new(1, 1, 1)
      trademark.BackgroundTransparency = 1
      trademark.BorderSizePixel        = 0
      trademark.BorderColor3           = Color3.new(0, 0, 0)
      trademark.Text                   = 'Seoul'
      trademark.TextColor3             = Color3.new(1, 1, 1)
      trademark.TextSize               = 14
      trademark.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Bold, Enum.FontStyle.Normal)
      trademark.TextXAlignment         = Enum.TextXAlignment.Left
      trademark.Parent                 = topbar

local escape                  = Instance.new('TextButton')
      escape.Name             = 'escape'
      escape.Position         = UDim2.new(0.824561, 0, 0.2, 0)
      escape.Size             = UDim2.new(0, 24, 0, 12)
      escape.BackgroundColor3 = Color3.new(0.105882, 0.105882, 0.105882)
      escape.BorderSizePixel  = 0
      escape.BorderColor3     = Color3.new(0, 0, 0)
      escape.Text             = 'X'
      escape.TextColor3       = Color3.new(1, 0.164706, 0.164706)
      escape.TextSize         = 14
      escape.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Bold, Enum.FontStyle.Normal)
      escape.TextScaled       = true
      escape.TextWrapped      = true
      escape.Parent           = topbar

local corners2              = Instance.new('UICorner')
      corners2.Name         = 'corners'
      corners2.CornerRadius = UDim.new(0, 4)
      corners2.Parent       = escape

local minimize                  = Instance.new('TextButton')
      minimize.Name             = 'minimize'
      minimize.Position         = UDim2.new(0.666667, 0, 0.2, 0)
      minimize.Size             = UDim2.new(0, 24, 0, 12)
      minimize.BackgroundColor3 = Color3.new(0.105882, 0.105882, 0.105882)
      minimize.BorderSizePixel  = 0
      minimize.BorderColor3     = Color3.new(0, 0, 0)
      minimize.Text             = '-'
      minimize.TextColor3       = Color3.new(1, 0.752941, 0.129412)
      minimize.TextSize         = 23
      minimize.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Bold, Enum.FontStyle.Normal)
      minimize.TextWrapped      = true
      minimize.Parent           = topbar

local corners3              = Instance.new('UICorner')
      corners3.Name         = 'corners'
      corners3.CornerRadius = UDim.new(0, 4)
      corners3.Parent       = minimize

local corners4        = Instance.new('UICorner')
      corners4.Name   = 'corners'
      corners4.Parent = ui

local content                  = Instance.new('Frame')
      content.Name             = 'content'
      content.Position         = UDim2.new(0.0350877, 0, 0.117117, 0)
      content.Size             = UDim2.new(0, 159, 0, 189)
      content.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      content.BorderSizePixel  = 0
      content.BorderColor3     = Color3.new(0, 0, 0)
      content.Parent           = ui

local corners5              = Instance.new('UICorner')
      corners5.Name         = 'corners'
      corners5.CornerRadius = UDim.new(0, 4)
      corners5.Parent       = content

local outline                 = Instance.new('UIStroke')
      outline.Name            = 'outline'
      outline.Color           = Color3.new(1, 1, 1)
      outline.Transparency    = 0.699999988079071
      outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      outline.Parent          = content

local folders                        = Instance.new('ScrollingFrame')
      folders.Name                   = 'folders'
      folders.Position               = UDim2.new(0.5, 0, 0.5, 0)
      folders.Size                   = UDim2.new(0, 151, 0, 183)
      folders.BackgroundColor3       = Color3.new(1, 1, 1)
      folders.BackgroundTransparency = 1
      folders.BorderSizePixel        = 0
      folders.BorderColor3           = Color3.new(0, 0, 0)
      folders.AnchorPoint            = Vector2.new(0.5, 0.5)
      folders.Active                 = true
      folders.ScrollBarImageColor3   = Color3.new(0, 0, 0)
      folders.ScrollBarThickness     = 2
      folders.Parent                 = content

local folder                        = Instance.new('Frame')
      folder.Name                   = 'folder'
      folder.Position               = UDim2.new(0, 0, -4.16907e-08, 0)
      folder.Size                   = UDim2.new(0, 142, 0, 20)
      folder.BackgroundColor3       = Color3.new(1, 1, 1)
      folder.BackgroundTransparency = 1
      folder.BorderSizePixel        = 0
      folder.BorderColor3           = Color3.new(0, 0, 0)
      folder.ClipsDescendants       = true
      folder.Parent                 = nil

local corners6              = Instance.new('UICorner')
      corners6.Name         = 'corners'
      corners6.CornerRadius = UDim.new(0, 4)
      corners6.Parent       = folder

local opener                  = Instance.new('TextButton')
      opener.Name             = 'opener'
      opener.Size             = UDim2.new(0, 142, 0, 20)
      opener.BackgroundColor3 = Color3.new(0.356863, 0.356863, 0.356863)
      opener.BorderSizePixel  = 0
      opener.BorderColor3     = Color3.new(0, 0, 0)
      opener.Text             = 'Folder'
      opener.TextColor3       = Color3.new(1, 1, 1)
      opener.TextSize         = 14
      opener.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      opener.Parent           = folder

local corners7              = Instance.new('UICorner')
      corners7.Name         = 'corners'
      corners7.CornerRadius = UDim.new(0, 4)
      corners7.Parent       = opener

local symbol                        = Instance.new('ImageButton')
      symbol.Name                   = 'symbol'
      symbol.Position               = UDim2.new(0.03, 0, 0, 0)
      symbol.Size                   = UDim2.new(0, 20, 0, 20)
      symbol.BackgroundColor3       = Color3.new(1, 1, 1)
      symbol.BackgroundTransparency = 1
      symbol.BorderSizePixel        = 0
      symbol.BorderColor3           = Color3.new(0, 0, 0)
      symbol.Image                  = 'rbxassetid://134427085389711'
      symbol.Parent                 = opener

local toggle                  = Instance.new('Frame')
      toggle.Name             = 'toggle'
      toggle.Position         = UDim2.new(0, 0, 0.469388, 0)
      toggle.Size             = UDim2.new(0, 131, 0, 18)
      toggle.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      toggle.BorderSizePixel  = 0
      toggle.BorderColor3     = Color3.new(0, 0, 0)
      toggle.Parent           = nil

local corners8              = Instance.new('UICorner')
      corners8.Name         = 'corners'
      corners8.CornerRadius = UDim.new(0, 4)
      corners8.Parent       = toggle

local details                        = Instance.new('TextLabel')
      details.Name                   = 'details'
      details.Position               = UDim2.new(0.0248856, 0, 0.1875, 0)
      details.Size                   = UDim2.new(0, 107, 0, 11)
      details.BackgroundColor3       = Color3.new(1, 1, 1)
      details.BackgroundTransparency = 1
      details.BorderSizePixel        = 0
      details.BorderColor3           = Color3.new(0, 0, 0)
      details.Text                   = 'Toggle'
      details.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details.TextSize               = 14
      details.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details.TextWrapped            = true
      details.TextXAlignment         = Enum.TextXAlignment.Left
      details.Parent                 = toggle

local trigger                        = Instance.new('TextButton')
      trigger.Name                   = 'trigger'
      trigger.Position               = UDim2.new(0.906, 0, 0.49, 0)
      trigger.Size                   = UDim2.new(0, 11, 0, 11)
      trigger.BackgroundColor3       = Color3.new(1, 1, 1)
      trigger.BackgroundTransparency = 0.949999988079071
      trigger.BorderSizePixel        = 0
      trigger.BorderColor3           = Color3.new(0, 0, 0)
      trigger.AnchorPoint            = Vector2.new(0.5, 0.5)
      trigger.Text                   = ''
      trigger.TextColor3             = Color3.new(0, 0, 0)
      trigger.TextSize               = 14
      trigger.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      trigger.Parent                 = toggle

local corners9              = Instance.new('UICorner')
      corners9.Name         = 'corners'
      corners9.CornerRadius = UDim.new(0, 111)
      corners9.Parent       = trigger

local outline2                 = Instance.new('UIStroke')
      outline2.Name            = 'outline'
      outline2.Color           = Color3.new(1, 1, 1)
      outline2.Transparency    = 0.4000000059604645
      outline2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      outline2.Parent          = trigger

local slider                  = Instance.new('Frame')
      slider.Name             = 'slider'
      slider.Position         = UDim2.new(0, 0, 1.26531, 0)
      slider.Size             = UDim2.new(0, 131, 0, 36)
      slider.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      slider.BorderSizePixel  = 0
      slider.BorderColor3     = Color3.new(0, 0, 0)
      slider.Parent           = nil

local corners10              = Instance.new('UICorner')
      corners10.Name         = 'corners'
      corners10.CornerRadius = UDim.new(0, 4)
      corners10.Parent       = slider

local details2                        = Instance.new('TextLabel')
      details2.Name                   = 'details'
      details2.Position               = UDim2.new(0.025, 0, 0.08, 0)
      details2.Size                   = UDim2.new(0, 107, 0, 11)
      details2.BackgroundColor3       = Color3.new(1, 1, 1)
      details2.BackgroundTransparency = 1
      details2.BorderSizePixel        = 0
      details2.BorderColor3           = Color3.new(0, 0, 0)
      details2.Text                   = 'Slider'
      details2.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details2.TextSize               = 14
      details2.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details2.TextWrapped            = true
      details2.TextXAlignment         = Enum.TextXAlignment.Left
      details2.Parent                 = slider

local container                  = Instance.new('Frame')
      container.Name             = 'container'
      container.Position         = UDim2.new(0.0248856, 0, 0.49, 0)
      container.Size             = UDim2.new(0, 91, 0, 12)
      container.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      container.BorderSizePixel  = 0
      container.BorderColor3     = Color3.new(0, 0, 0)
      container.Parent           = slider

local corners11              = Instance.new('UICorner')
      corners11.Name         = 'corners'
      corners11.CornerRadius = UDim.new(0, 4)
      corners11.Parent       = container

local fill                  = Instance.new('Frame')
      fill.Name             = 'fill'
      fill.Position         = UDim2.new(0,0,0,0)
      fill.Size             = UDim2.new(0, 0, 0, 12)
      fill.BackgroundColor3 = Color3.new(1, 1, 1)
      fill.BorderSizePixel  = 0
      fill.BorderColor3     = Color3.new(0, 0, 0)
      fill.Parent           = container

local corners12              = Instance.new('UICorner')
      corners12.Name         = 'corners'
      corners12.CornerRadius = UDim.new(0, 4)
      corners12.Parent       = fill

local integer                        = Instance.new('TextBox')
      integer.Name                   = 'integer'
      integer.Position               = UDim2.new(0.763359, 0, 0.49, 0)
      integer.Size                   = UDim2.new(0, 24, 0, 11)
      integer.BackgroundColor3       = Color3.new(1, 1, 1)
      integer.BackgroundTransparency = 0.8999999761581421
      integer.BorderSizePixel        = 0
      integer.BorderColor3           = Color3.new(0, 0, 0)
      integer.Text                   = ''
      integer.TextColor3             = Color3.new(255, 255, 255)
      integer.TextStrokeTransparency = 0.9
      integer.TextSize               = 14
      integer.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      integer.TextScaled             = true
      integer.TextWrapped            = true
      integer.PlaceholderText        = '0'
      integer.PlaceholderColor3      = Color3.new(255, 255, 255)
      integer.Parent                 = slider

local corners13              = Instance.new('UICorner')
      corners13.Name         = 'corners'
      corners13.CornerRadius = UDim.new(0, 2)
      corners13.Parent       = integer

local outline3                 = Instance.new('UIStroke')
      outline3.Name            = 'outline'
      outline3.Color           = Color3.new(1, 1, 1)
      outline3.Transparency    = 0.4000000059604645
      outline3.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      outline3.Parent          = integer

local dropdown                  = Instance.new('Frame')
      dropdown.Name             = 'dropdown'
      dropdown.Position         = UDim2.new(0, 0, 0.547945, 0)
      dropdown.Size             = UDim2.new(0, 131, 0, 18)
      dropdown.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      dropdown.BorderSizePixel  = 0
      dropdown.BorderColor3     = Color3.new(0, 0, 0)
      dropdown.ClipsDescendants = true
      dropdown.Parent           = nil

local corners14              = Instance.new('UICorner')
      corners14.Name         = 'corners'
      corners14.CornerRadius = UDim.new(0, 4)
      corners14.Parent       = dropdown

local details3                        = Instance.new('Frame')
      details3.Name                   = 'details'
      details3.Size                   = UDim2.new(0, 131, 0, 18)
      details3.BackgroundColor3       = Color3.new(1, 1, 1)
      details3.BackgroundTransparency = 1
      details3.BorderSizePixel        = 0
      details3.BorderColor3           = Color3.new(0, 0, 0)
      details3.Parent                 = dropdown

local details4                        = Instance.new('TextLabel')
      details4.Name                   = 'details'
      details4.Position               = UDim2.new(0.0248856, 0, 0.1875, 0)
      details4.Size                   = UDim2.new(0, 107, 0, 11)
      details4.BackgroundColor3       = Color3.new(1, 1, 1)
      details4.BackgroundTransparency = 1
      details4.BorderSizePixel        = 0
      details4.BorderColor3           = Color3.new(0, 0, 0)
      details4.Text                   = 'Dropdown'
      details4.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details4.TextSize               = 14
      details4.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details4.TextWrapped            = true
      details4.TextXAlignment         = Enum.TextXAlignment.Left
      details4.Parent                 = details3

local trigger2                        = Instance.new('ImageButton')
      trigger2.Name                   = 'trigger'
      trigger2.Position               = UDim2.new(0.839695, 0, 0, 0)
      trigger2.Size                   = UDim2.new(0, 18, 0, 18)
      trigger2.BackgroundColor3       = Color3.new(1, 1, 1)
      trigger2.BackgroundTransparency = 1
      trigger2.BorderSizePixel        = 0
      trigger2.BorderColor3           = Color3.new(0, 0, 0)
      trigger2.Rotation               = 90
      trigger2.Image                  = 'rbxassetid://114068220693200'
      trigger2.Parent                 = details3

local layout           = Instance.new('UIListLayout')
      layout.Name      = 'layout'
      layout.SortOrder = Enum.SortOrder.LayoutOrder
      layout.Parent    = dropdown

local elements                        = Instance.new('ScrollingFrame')
      elements.Name                   = 'elements'
      elements.Position               = UDim2.new(0, 0, 0.272727, 0)
      elements.Size                   = UDim2.new(0, 131, 0, 42)
      elements.BackgroundColor3       = Color3.new(1, 1, 1)
      elements.BackgroundTransparency = 1
      elements.BorderSizePixel        = 0
      elements.BorderColor3           = Color3.new(0, 0, 0)
      elements.Active                 = true
      elements.ScrollBarImageColor3   = Color3.new(0, 0, 0)
      elements.ScrollBarThickness     = 2
      elements.Parent                 = dropdown

local element                  = Instance.new('TextButton')
      element.Name             = 'element'
      element.Position         = UDim2.new(0.0877863, 0, 0, 0)
      element.Size             = UDim2.new(0, 119, 0, 12)
      element.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      element.BorderSizePixel  = 0
      element.BorderColor3     = Color3.new(0, 0, 0)
      element.Text             = 'Option No. 1'
      element.TextColor3       = Color3.new(1, 1, 1)
      element.TextSize         = 14
      element.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Bold, Enum.FontStyle.Normal)
      element.TextScaled       = true
      element.TextWrapped      = true
      element.Parent           = elements

local corners15              = Instance.new('UICorner')
      corners15.Name         = 'corners'
      corners15.CornerRadius = UDim.new(0, 4)
      corners15.Parent       = element

local layout2                     = Instance.new('UIListLayout')
      layout2.Name                = 'layout'
      layout2.Padding             = UDim.new(0, 1)
      layout2.HorizontalAlignment = Enum.HorizontalAlignment.Center
      layout2.SortOrder           = Enum.SortOrder.LayoutOrder
      layout2.Parent              = elements

local button                  = Instance.new('TextButton')
      button.Name             = 'button'
      button.Size             = UDim2.new(0, 131, 0, 18)
      button.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      button.BorderSizePixel  = 0
      button.BorderColor3     = Color3.new(0, 0, 0)
      button.Text             = ''
      button.TextColor3       = Color3.new(0, 0, 0)
      button.TextSize         = 14
      button.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      button.Parent           = nil

local corners16              = Instance.new('UICorner')
      corners16.Name         = 'corners'
      corners16.CornerRadius = UDim.new(0, 4)
      corners16.Parent       = button

local details5                        = Instance.new('TextLabel')
      details5.Name                   = 'details'
      details5.Position               = UDim2.new(0.5, 0, 0.5, 0)
      details5.Size                   = UDim2.new(0, 122, 0, 11)
      details5.BackgroundColor3       = Color3.new(1, 1, 1)
      details5.BackgroundTransparency = 1
      details5.BorderSizePixel        = 0
      details5.BorderColor3           = Color3.new(0, 0, 0)
      details5.AnchorPoint            = Vector2.new(0.5, 0.5)
      details5.Text                   = 'Button'
      details5.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details5.TextSize               = 14
      details5.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details5.TextWrapped            = true
      details5.Parent                 = button

local layout3           = Instance.new('UIListLayout')
      layout3.Name      = 'layout'
      layout3.Padding   = UDim.new(0, 2)
      layout3.SortOrder = Enum.SortOrder.LayoutOrder
      layout3.Parent    = folder

local query                  = Instance.new('Frame')
      query.Name             = 'query'
      query.Position         = UDim2.new(0, 0, 0.469388, 0)
      query.Size             = UDim2.new(0, 131, 0, 18)
      query.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      query.BorderSizePixel  = 0
      query.BorderColor3     = Color3.new(0, 0, 0)
      query.Parent           = nil

local corners17              = Instance.new('UICorner')
      corners17.Name         = 'corners'
      corners17.CornerRadius = UDim.new(0, 4)
      corners17.Parent       = query

local input                  = Instance.new('TextBox')
      input.Name             = 'input'
      input.Position         = UDim2.new(0.5, 0, 0.5, 0)
      input.Size             = UDim2.new(0, 121, 0, 12)
      input.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      input.BorderSizePixel  = 0
      input.BorderColor3     = Color3.new(0, 0, 0)
      input.AnchorPoint      = Vector2.new(0.5, 0.5)
      input.Text             = ''
      input.TextColor3       = Color3.new(1, 1, 1)
      input.TextSize         = 14
      input.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      input.TextScaled       = true
      input.TextWrapped      = true
      input.RichText         = true
      input.PlaceholderText  = 'Enter some text...'
      input.Parent           = query

local corners18              = Instance.new('UICorner')
      corners18.Name         = 'corners'
      corners18.CornerRadius = UDim.new(0, 4)
      corners18.Parent       = input

local keybind                  = Instance.new('Frame')
      keybind.Name             = 'keybind'
      keybind.Position         = UDim2.new(0, 0, 0.469388, 0)
      keybind.Size             = UDim2.new(0, 131, 0, 18)
      keybind.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      keybind.BorderSizePixel  = 0
      keybind.BorderColor3     = Color3.new(0, 0, 0)
      keybind.Parent           = nil

local corners19              = Instance.new('UICorner')
      corners19.Name         = 'corners'
      corners19.CornerRadius = UDim.new(0, 4)
      corners19.Parent       = keybind

local input2                  = Instance.new('TextBox')
      input2.Name             = 'input'
      input2.Position         = UDim2.new(0.859981, 0, 0.5, 0)
      input2.Size             = UDim2.new(0, 25, 0, 12)
      input2.BackgroundColor3 = Color3.new(0.164706, 0.164706, 0.164706)
      input2.BorderSizePixel  = 0
      input2.BorderColor3     = Color3.new(0, 0, 0)
      input2.AnchorPoint      = Vector2.new(0.5, 0.5)
      input2.Text             = ''
      input2.TextColor3       = Color3.new(1, 1, 1)
      input2.TextSize         = 14
      input2.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      input2.TextWrapped      = true
      input2.RichText         = true
      input2.PlaceholderText  = '?'
      input2.Parent           = keybind

local corners20              = Instance.new('UICorner')
      corners20.Name         = 'corners'
      corners20.CornerRadius = UDim.new(0, 4)
      corners20.Parent       = input2

local details6                        = Instance.new('TextLabel')
      details6.Name                   = 'details'
      details6.Position               = UDim2.new(0.025, 0, 0.188, 0)
      details6.Size                   = UDim2.new(0, 107, 0, 11)
      details6.BackgroundColor3       = Color3.new(1, 1, 1)
      details6.BackgroundTransparency = 1
      details6.BorderSizePixel        = 0
      details6.BorderColor3           = Color3.new(0, 0, 0)
      details6.Text                   = 'Keybind'
      details6.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details6.TextSize               = 14
      details6.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details6.TextWrapped            = true
      details6.TextXAlignment         = Enum.TextXAlignment.Left
      details6.Parent                 = keybind

local divider                        = Instance.new('Frame')
      divider.Name                   = 'divider'
      divider.Position               = UDim2.new(0, 0, 0.469388, 0)
      divider.Size                   = UDim2.new(0, 131, 0, 18)
      divider.BackgroundColor3       = Color3.new(0.239216, 0.239216, 0.239216)
      divider.BackgroundTransparency = 1
      divider.BorderSizePixel        = 0
      divider.BorderColor3           = Color3.new(0, 0, 0)
      divider.Parent                 = nil

local corners21              = Instance.new('UICorner')
      corners21.Name         = 'corners'
      corners21.CornerRadius = UDim.new(0, 4)
      corners21.Parent       = divider

local details7                        = Instance.new('TextLabel')
      details7.Name                   = 'details'
      details7.Position               = UDim2.new(-0.0055344, 0, -0.0342221, 0)
      details7.Size                   = UDim2.new(0, 131, 0, 18)
      details7.BackgroundColor3       = Color3.new(1, 1, 1)
      details7.BackgroundTransparency = 1
      details7.BorderSizePixel        = 0
      details7.BorderColor3           = Color3.new(0, 0, 0)
      details7.Text                   = 'Divider'
      details7.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details7.TextSize               = 14
      details7.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details7.TextWrapped            = true
      details7.Parent                 = divider

local palette                  = Instance.new('Frame')
      palette.Name             = 'palette'
      palette.Position         = UDim2.new(0, 0, 0.469388, 0)
      palette.Size             = UDim2.new(0, 131, 0, 18)
      palette.BackgroundColor3 = Color3.new(0.239216, 0.239216, 0.239216)
      palette.BorderSizePixel  = 0
      palette.BorderColor3     = Color3.new(0, 0, 0)
      palette.Parent           = nil

local corners22              = Instance.new('UICorner')
      corners22.Name         = 'corners'
      corners22.CornerRadius = UDim.new(0, 4)
      corners22.Parent       = palette

local details8                        = Instance.new('TextLabel')
      details8.Name                   = 'details'
      details8.Position               = UDim2.new(0.0248856, 0, 0.1875, 0)
      details8.Size                   = UDim2.new(0, 107, 0, 11)
      details8.BackgroundColor3       = Color3.new(1, 1, 1)
      details8.BackgroundTransparency = 1
      details8.BorderSizePixel        = 0
      details8.BorderColor3           = Color3.new(0, 0, 0)
      details8.Text                   = 'Palette'
      details8.TextColor3             = Color3.new(0.898039, 0.898039, 0.898039)
      details8.TextSize               = 14
      details8.FontFace               = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      details8.TextWrapped            = true
      details8.TextXAlignment         = Enum.TextXAlignment.Left
      details8.Parent                 = palette

local trigger3                  = Instance.new('TextButton')
      trigger3.Name             = 'trigger'
      trigger3.Position         = UDim2.new(0.906, 0, 0.49, 0)
      trigger3.Size             = UDim2.new(0, 11, 0, 11)
      trigger3.BackgroundColor3 = Color3.new(1, 1, 1)
      trigger3.BorderSizePixel  = 0
      trigger3.BorderColor3     = Color3.new(0, 0, 0)
      trigger3.AnchorPoint      = Vector2.new(0.5, 0.5)
      trigger3.Text             = ''
      trigger3.TextColor3       = Color3.new(1, 1, 1)
      trigger3.TextSize         = 14
      trigger3.FontFace         = Font.new('rbxasset://fonts/families/SourceSansPro.json', Enum.FontWeight.Regular, Enum.FontStyle.Normal)
      trigger3.Parent           = palette

local corners23              = Instance.new('UICorner')
      corners23.Name         = 'corners'
      corners23.CornerRadius = UDim.new(0, 2)
      corners23.Parent       = trigger3

local outline4                 = Instance.new('UIStroke')
      outline4.Name            = 'outline'
      outline4.Color           = Color3.new(1, 1, 1)
      outline4.Transparency    = 0.4000000059604645
      outline4.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      outline4.Parent          = trigger3

local gradient          = Instance.new('UIGradient')
      gradient.Name     = 'gradient'
      gradient.Color    = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.247059, 0.701961, 0.498039)), ColorSequenceKeypoint.new(1, Color3.new(0.247059, 0.701961, 0.498039))})
      gradient.Rotation = 3
      gradient.Parent   = trigger3

local layout4           = Instance.new('UIListLayout')
      layout4.Name      = 'layout'
      layout4.Padding   = UDim.new(0, 2)
      layout4.SortOrder = Enum.SortOrder.LayoutOrder
      layout4.Parent    = folders

local layout5                     = Instance.new('UIListLayout')
      layout5.Name                = 'layout'
      layout5.Padding             = UDim.new(0, 6)
      layout5.HorizontalAlignment = Enum.HorizontalAlignment.Center
      layout5.SortOrder           = Enum.SortOrder.LayoutOrder
      layout5.Parent              = ui




-- types
return seoul, folder, divider, button, query, slider, toggle, dropdown
