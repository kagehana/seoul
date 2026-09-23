# library.lua

A settings UI for Roblox scripts: tabs, groups of rows, switches with keys and
sliders built in, dropdowns with search and ordered multi-pick, a status line,
notifications, flag-based config, and a clean re-run.

Every size is the design's own pixels at scale 1. The window is 300 × 396 by
default.

---

## Contents

- [Loading](#loading)
- [Structure](#structure)
- [Window](#window)
- [Tabs and groups](#tabs-and-groups)
- [Elements: shared behaviour](#elements-shared-behaviour)
- [toggle](#toggle)
- [slider](#slider)
- [range](#range)
- [dropdown](#dropdown)
- [keybind](#keybind)
- [textbox](#textbox)
- [button](#button)
- [field](#field)
- [label](#label)
- [Status line](#status-line)
- [Notifications](#notifications)
- [Keys](#keys)
- [Config: flags, save, load](#config-flags-save-load)
- [Theme and accent](#theme-and-accent)
- [Background patterns](#background-patterns)
- [Icons](#icons)
- [Unloading and re-running](#unloading-and-re-running)
- [Executor requirements](#executor-requirements)
- [Gotchas](#gotchas)
- [Full example](#full-example)

---

## Loading

```lua
local ui = loadstring(game:HttpGet('https://github.com/kagehana/seoul/blob/main/seoul.lua?raw=true'))()
```

The module returns the library table itself. Call it **once**. The old Seoul
returned a factory and was called twice (`()()`); doing that here fails with
`attempt to call a table value`.

Build the UI inside a `pcall` if the rest of your script should survive an
HTTP failure:

```lua
local ok, ui = pcall(function()
    return loadstring(game:HttpGet(URL))()
end)
```

---

## Structure

```
ui (library)
└── window            ui:window{...}
    └── tab           win:tab('Name')
        └── group     tab:group('Heading')
            └── element   grp:toggle{...}, grp:slider{...}, ...
```

Methods on the window, tab and group return the new object. Element setters
return the element, so calls chain.

---

## Window

```lua
local win = ui:window({
    title          = 'My Script',
    id             = 'MyScript',
    key            = Enum.KeyCode.RightShift,
    accent         = 'tan',
    pattern        = 'dots',
    patternOpacity = 0.08,
    scale          = 1,
    size           = Vector2.new(300, 396),
    onClose        = function() ui:destroy() end,
})
```

| option | type | default | meaning |
|---|---|---|---|
| `title` | string | `'Untitled'` | Heading under the tab strip. |
| `id` | string | `'library'` | The ScreenGui's name. A re-run replaces the gui with the same id. **Set one per script.** |
| `key` | KeyCode | `RightShift` | Shows/hides the window. |
| `accent` | `'tan'` \| `'lilac'` \| Color3 | `'tan'` | See [Theme](#theme-and-accent). |
| `pattern` | string | none | `'dots'`, `'grain'`, `'hatch'`, `'sparkles'`, or an image id. See [Patterns](#background-patterns). |
| `patternOpacity` | number | per pattern | 0-1. |
| `scale` | number \| `'auto'` | `1` | `1` draws at design size. `'auto'` grows in whole steps with the screen height (`floor(viewportY / 700 + 0.5)`). Any number is used as is. Above 1, it steps down until the window fits the viewport with a 24px margin. |
| `size` | Vector2 | `300, 396` | Window size at scale 1. |
| `onClose` | function | hide + notify | What the X does. Without it the X hides the window and posts "Hidden. Press <key> to show it again." |

### Window methods

| method | effect |
|---|---|
| `win:toggle(v?)` | Show (`true`), hide (`false`), or flip (`nil`). |
| `win:isOpen()` | `true` while showing. |
| `win:minimize()` | Folds to the tab strip, title and status line. Call again to unfold. The status clock keeps running. |
| `win:setKey(k)` | Changes the show/hide key. |
| `win:setTitle(s)` | Changes the heading. |
| `win:setPattern(p, opacity?)` | Changes or (`false`/`nil`) removes the background. |
| `win:status(s, opts?)` | The status line. See [Status line](#status-line). |
| `win:select(tab)` | Shows a tab. |
| `win:destroy()` | Same as `ui:destroy()`: unloads everything. |

The window is dragged by the tab strip or the title area. It opens centred.

---

## Tabs and groups

```lua
local main = win:tab('Main')
local move = main:group('Movement')
local misc = main:group()          -- no heading
```

- `win:tab(name)` takes a **string**. The name is drawn upper-case. The first
  tab created is selected.
- Tabs past the strip's width scroll horizontally. The side with more tabs
  fades into the bar. There are no tab icons.
- `tab:group(name?)` makes a titled run of rows. Groups are separated by 6px
  and a hairline. Rows inside a group have no lines between them.
- Elements added straight to a tab (`main:toggle{...}`) go into one untitled
  group at the point it is first used.

---

## Elements: shared behaviour

Every element is a row: optional icon, the label filling the middle, controls
on the right. Some hang a ruler or a list under the row.

### Options every element accepts

| option | meaning |
|---|---|
| `name` | The label. Plain text. |
| `icon` | Icon name, content id or asset id. See [Icons](#icons). The label is indented to match. |
| `call` | Callback. Its arguments depend on the element. Errors are caught and `warn`ed as `[library] callback error: …`, never thrown. |
| `flag` | Config key. See [Config](#config-flags-save-load). Not on `button`, `field` or `label`. |

### Methods every element has

| method | effect |
|---|---|
| `el:get()` | Current value. |
| `el:set(v, silent?)` | Sets the value and repaints. Runs `call` unless `silent` is `true`. |
| `el:rename(s)` | Changes the label. |
| `el:visible(v)` | `false` hides the row and anything under it (ruler, list). |
| `el:destroy()` | Removes the element and drops its connections, key binds and flag. |

`el.value` holds the raw value. Prefer `get()`, which returns copies where it
matters (dropdown lists).

**Setting from code repaints the control.** A control never disagrees with
the value it holds. Use `silent = true` when your own state is already
correct and only the display needs updating. That avoids re-running the
feature.

---

## toggle

A switch. It can also carry a key that flips it and a number on a ruler under
it.

```lua
local fly = move:toggle({
    name    = 'Fly',
    icon    = 'paper-plane-tilt',
    default = false,
    key     = Enum.KeyCode.V,
    slider  = { min = 0, max = 400, step = 5, default = 120, suffix = ' st/s', live = true },
    flag    = 'fly',
    call    = function(on, speed) end,
    changed = function(key) end,
})
```

| option | type | meaning |
|---|---|---|
| `default` | boolean | Starts on when `true`. |
| `key` | KeyCode \| `false` \| nil | A keycap on the row. The key flips the switch. `false` draws an empty keycap (`–`) the user can bind. `nil` draws no keycap. |
| `slider` | table | A ruler under the row. Same fields as [slider](#slider): `min`, `max`, `step`, `default`, `prefix`, `suffix`, `live`. The number shows on the right of the row. |
| `call` | `function(on, number)` | Runs on every flip and every number change. `number` is `nil` without a slider. |
| `changed` | `function(key)` | Runs when the user rebinds the keycap. `key` is a KeyCode, or `nil` when cleared. Use it to persist the key if you keep your own config. |

| method | effect |
|---|---|
| `get()` | `true`/`false`. |
| `set(on, silent?)` | Flip. |
| `setNumber(n, silent?)` | The ruler's number, snapped and clamped. |
| `setKey(k, silent?)` | Rebind. `silent` suppresses `changed`. |
| `el.number`, `el.key` | Current number and key. |

Clicking anywhere on the row flips it. Clicking the keycap rebinds instead
(see [Keys](#keys)). When on, the tick fills with the accent and the icon
turns accent. The ruler is drawn in accent only while the switch is on.

---

## slider

A number on a ruler: ticks every 5%, taller every 25%, one pin.

```lua
move:slider({
    name    = 'Walk speed',
    icon    = 'person-simple-run',
    min     = 16,
    max     = 200,
    step    = 1,
    default = 16,
    prefix  = '',
    suffix  = ' st/s',
    live    = true,
    flag    = 'walk',
    call    = function(n) end,
})
```

| option | default | meaning |
|---|---|---|
| `min` / `max` | `0` / `100` | Bounds. Reversed bounds are swapped. |
| `step` | `1` | Snap. Decimals shown = decimals in `step` (`0.05` → two). `0` or negative becomes `1`. |
| `default` | `min` | Start value. |
| `prefix` / `suffix` | `''` | Drawn around the number. |
| `live` | `true` | `false`: `call` runs once on release rather than on every change while dragging. |

`set(n)` snaps and clamps. NaN, inf and non-numbers read as `min`. Press
anywhere on the ruler to jump there, then drag.

---

## range

Two pins on one ruler, read as `lo – hi`.

```lua
local heal = grp:range({
    name    = 'Heal between',
    icon    = 'heart',
    min     = 0,
    max     = 100,
    default = { 45, 90 },
    suffix  = '%',
    flag    = 'heal',
    call    = function(lo, hi) end,
})

local lo, hi = heal:get()
heal:set(30, nil)        -- nil keeps that end
```

- Takes every [slider](#slider) option. `default` is `{ lo, hi }`.
- `get()` returns **two values**. `set(a, b, silent?)` puts them in order, so
  `lo <= hi` always holds.
- A press takes the nearer pin. Dragging one past the other swaps which pin
  you hold.

---

## dropdown

A list that opens under its row. One pick or many, plain rows or keycaps,
static or fetched live.

```lua
local target = grp:dropdown({
    name        = 'Target',
    icon        = 'crosshair-simple',
    options     = { 'Bandit', 'Bear Cub', 'Mother Bear' },
    default     = 'Bandit',
    placeholder = 'Nothing',
    flag        = 'target',
    call        = function(v) end,
})
```

| option | type | meaning |
|---|---|---|
| `options` | table \| function | A list of strings, or a function that returns one. **A function is called every time the list opens**, so the list is live. Values go through `tostring`. |
| `default` | string \| table | Starting pick. A list when `multi`. |
| `multi` | boolean | Many picks. The value is a list **in the order picked**. The list gets a footer with a count and a **Clear**. |
| `ordered` | boolean | With `multi`: numbers each pick (1, 2, 3…) in the list and on the row, as `1 Z  2 X  3 C`. The footer reads "Picked in order". |
| `keys` | boolean | Draws each option as a keycap rather than text. |
| `describe` | `function(option) -> string` | Grey text beside each option. If it errors, only that text is lost. |
| `search` | boolean | Forces the search line on or off. By default it shows past 6 options. |
| `placeholder` | string | Shown on the row with nothing picked (default "Not set"). |
| `call` | `function(value)` | Single: the string (or `nil`). Multi: a copy of the list. |

| method | effect |
|---|---|
| `get()` | Single: string or `nil`. Multi: a **copy** of the list. |
| `set(v, silent?)` | Single: a string, or `nil` to clear. Multi: a list. It doesn't need to be in `options`. |
| `pick(v)` | What a click does. Single: set and close. Multi: add if absent, remove if present (so order = click order). |
| `setOptions(list \| fn)` | Replaces the source. Takes effect now if open, else at the next open. |
| `setOpen(bool)` | Opens or closes. Opening fetches. Closing clears the search. |

Behaviour worth knowing:

- **Rows are built only when the list opens.** A dropdown that is never opened
  costs one row. Rows are rebuilt only if the option list changed, and only
  rows whose state changed are repainted.
- The search is a case-insensitive substring match on the option text.
- The row's icon turns accent while anything is picked.
- A single-pick list cannot be un-picked by clicking. Use `set(nil)`.
- Current picks are only shown in the list if `options` includes them. If a
  saved pick can disappear from the source, add the current picks to what
  your options function returns.

Ordered multi-pick with keycaps, labelled from a live source:

```lua
local names = {}

grp:dropdown({
    name     = 'Skills',
    icon     = 'lightning',
    multi    = true,
    ordered  = true,
    keys     = true,
    options  = function()
        table.clear(names)
        local keys = {}
        for _, s in getSkillBar() do
            table.insert(keys, s.key)
            names[s.key] = s.name
        end
        return keys
    end,
    describe    = function(k) return names[k] end,
    placeholder = 'None',
    call        = function(list) end,
})
```

---

## keybind

A key on its own row. It runs `call` when pressed.

```lua
grp:keybind({
    name    = 'Panic',
    icon    = 'warning',
    default = Enum.KeyCode.End,
    flag    = 'panic',
    call    = function(key) end,
    changed = function(key) end,
})
```

- `call(key)` runs on each press of the bound key.
- `changed(key)` runs on a rebind (`nil` = cleared). `set(k)` also calls
  `changed` unless silent.
- `get()` returns the KeyCode or `nil`.

---

## textbox

A line of typed text on the right of the row.

```lua
grp:textbox({
    name        = 'Go to',
    icon        = 'magnifying-glass',
    default     = '',
    placeholder = 'Name…',
    clear       = true,
    onLost      = false,
    flag        = 'goto',
    call        = function(text, enter) end,
})
```

| option | meaning |
|---|---|
| `placeholder` | Grey text while empty. |
| `clear` | Empties the box after each callback. |
| `onLost` | Calls back on any focus loss, not only Enter. |
| `call` | `function(text, enter)`. `enter` is `false` for focus loss and for `set()`. |

`set(v)` writes the text **and runs `call`** (with `enter = false`) unless
silent. `el.value` updates on every focus loss, whether or not `call` ran.

---

## button

A row that runs `call` when clicked. An arrow on the right lights on hover.

```lua
grp:button({ name = 'Unload', icon = 'x', call = function() ui:destroy() end })
```

It holds no value, so it has **no `set`**. It has `rename`, `visible` and
`destroy`.

---

## field

A read-only value on the right of a row.

```lua
local where = grp:field({ name = 'Return point', icon = 'map-pin', value = nil, placeholder = 'Not set' })
where:set('120, 40, -88')
where:set(nil)                 -- shows the placeholder, grey
```

`set(v)` never calls back. It has no `call` and no `flag`.

---

## label

A wrapping paragraph in grey.

```lua
local note = grp:label('Farming from below keeps you out of melee reach.')
note:set('New text')
```

It takes a **string**, not a table. It has no icon, callback or flag.

---

## Status line

One line under the title with a coloured dot. It says what the script is
doing.

```lua
win:status('Farming Bear Cub', { timer = true })     -- Farming Bear Cub · 0:41
win:status('Respawn', { countdown = 12 })            -- counts to 0:00, then stops
win:status('Idle', { idle = true })                  -- grey
win:status(nil)                                      -- hidden
```

| opt | meaning |
|---|---|
| `timer` | Stopwatch from 0:00. **Calling again with the same text keeps it running**; different text restarts it. So you can call `status` every tick without resetting the clock. |
| `countdown` | Seconds. Counts down, holds at 0:00. |
| `idle` | Grey rather than accent. |

The text is escaped, so it is shown literally. Hours appear past 60 minutes.
While a clock shows, one thread per window redraws once a second, on the
second. It stops when the clock does.

---

## Notifications

```lua
ui:notify('Saved.')
ui:notify({ title = 'Farm', message = 'Nothing named Bandit is tracked.', duration = 6 })
```

- Cards stack bottom-right, slide in, and show the accent draining along the
  bottom edge.
- They leave after `duration` (4.5s by default) or on click.
- At most five are shown; the oldest goes first.
- They work before a window exists. They follow the window's `scale`.

---

## Keys

All keys go through one `InputBegan` handler:

- A bound key does nothing while a TextBox has focus or when the game
  processed the input (chat, game UI).
- **Rebinding:** click a keycap. It shows `…` in accent. Then:
  - any key binds it;
  - **Backspace** clears it (`–`);
  - **Escape** cancels and keeps the old key.

  Clicking another keycap while one is listening cancels the first.
- Keycaps show short names: `LShift`, `RCtrl`, `Enter`, `Bksp`, `Esc`, `Caps`,
  `Ins`, `Del`, `PgUp`, `PgDn`, `0`–`9`.
- Several elements may share a key. All of them fire.
- The window key (`key` / `setKey`) is not an element and has no flag. Persist
  it yourself if the user can change it.

---

## Config: flags, save, load

Give an element a `flag` and it joins the config.

```lua
local HttpService = game:GetService('HttpService')
local PATH = 'MyScript/config.json'

-- save
if not isfolder('MyScript') then makefolder('MyScript') end
writefile(PATH, HttpService:JSONEncode(ui:config()))

-- load, after building the UI
if isfile(PATH) then
    local ok, data = pcall(HttpService.JSONDecode, HttpService, readfile(PATH))
    if ok then
        local restored = ui:load(data)
    end
end
```

- `ui:config()` returns `{ [flag] = saved value }` for every flagged element.
- `ui:load(tbl)` restores by flag and returns how many were restored. Values
  of the wrong type are skipped, so a hand-edited file can't break a control.
  Unknown flags are ignored.
- **`load` runs each element's `call`**, the same as a user change, so the
  features switch on. Build the UI first, then load.
- `ui.flags[flag]` always holds the element's current saved form, updated on
  every change.
- The library does no file I/O itself. When and where to write is up to you.
  Debounce saves: a slider drag is dozens of changes a second.

Saved form per element:

| element | saved as | also accepted by `load` |
|---|---|---|
| toggle | `{ on = bool, number = n?, key = 'V'? }` | a bare boolean |
| slider | number | |
| range | `{ lo, hi }` | |
| dropdown | string, or a list when `multi` | |
| keybind | KeyCode name, e.g. `'End'` | |
| textbox | string | |

Keys are stored by `KeyCode.Name`. An unknown name is ignored.

---

## Theme and accent

```lua
ui:setAccent('lilac')
ui:setAccent(Color3.fromHex('7fd1b9'))
```

- `'tan'` (`#c8a676`) is the default; `'lilac'` is `#bfa3f5`. Any Color3 works:
  its tick mark uses the page colour.
- `setAccent` repaints everything already built, including open lists, rulers
  and the status line. You can call it at any time.
- `ui.theme` holds the palette (`page`, `bg`, `elem`, `hair`, `rule`, `text`,
  `sub`, `dim`, `accent`, `ink`). Treat it as read-only; only `setAccent`
  repaints.
- The font is Jura (Regular, Medium, SemiBold, Bold). Roblox downloads the
  heavier weights on first use.

---

## Background patterns

```lua
ui:window({ title = 'X', pattern = 'hatch' })
win:setPattern('sparkles', 0.1)
win:setPattern('rbxassetid://1234567')   -- a picture: fills the window, cropped
win:setPattern(false)                    -- none
```

| pattern | tile | default opacity |
|---|---|---|
| `dots` | 16 | 0.08 |
| `grain` | 48 | 0.05 |
| `hatch` | 10 | 0.025 |
| `sparkles` | 96 | 0.06 |

The built-in patterns tile and take the theme's text colour. Any other string
is used as an image: it is cropped to fill, keeps its own colours, and
defaults to 0.06 opacity.

---

## Icons

Any `icon` option takes one of:

| form | example | needs `getcustomasset` |
|---|---|---|
| a built-in name | `'sun'` | yes |
| a content id | `'rbxassetid://123'`, `'rbxthumb://type=Asset&id=123&w=150&h=150'`, `'https://…'` | no |
| a bare asset id | `123` or `'123'` | no |
| a name added with `ui.addicon` | `'my-logo'` | yes |

Icons are tinted through `ImageColor3`, so draw your own **white on
transparent**.

### Your own PNGs

```lua
ui.addicon('my-logo', readfile('logo.png'))        -- raw bytes
ui.addicon('my-logo', 'iVBORw0KGgoAAAANSUhEUg…')   -- or base64
ui.addicon('sun', myPng)                           -- replaces a built-in
```

Call `addicon` **before** building the elements that use it. Icons resolve
when an element is built, and there is no setter afterwards.

`ui.icon(nameOrId)` returns the content id the library would use, or `nil`.
Use it to put an icon on your own instances.

### Built-in names

Phosphor Bold, 48px:

```
caret-down caret-up caret-right check minus x magnifying-glass arrow-right
gear-six sliders-horizontal house user users eye eye-slash star heart shield
sword crosshair-simple target lightning sun moon fire drop snowflake sparkle
leaf map-pin compass globe-simple paper-plane-tilt rocket flag bell clock timer
key lock lock-open play pause stop arrows-clockwise trash plus copy floppy-disk
download-simple info warning question skull coins package gift wrench code list
palette cursor hand-pointing person-simple-run chat-circle
```

The library itself uses `caret-*`, `check`, `minus`, `x`, `magnifying-glass`
and `arrow-right`. Replacing those with `addicon` restyles its chrome.

On first use, a built-in or added icon is written to
`library-icons/<name>-<length>.png` in the executor workspace and loaded with
`getcustomasset`. Without `getcustomasset` those icons are blank: never an
error, and no files are written. Content ids and asset ids still show.

To add icons to the library permanently, add the names to `NAMES` in
`tools/icons.py` and run it from the `Library` folder (needs ImageMagick and
network access).

---

## Unloading and re-running

```lua
ui:onUnload(function()
    -- stop loops, disconnect your own signals, restore what you changed
end)

ui:destroy()          -- or win:destroy()
```

`destroy()`:
1. sets `ui.alive = false`;
2. runs every `onUnload` callback;
3. disconnects every connection the library made;
4. destroys the gui;
5. empties its internal tables, so a kept `ui` reference holds nothing.

**Destroying the gui by any means unloads.** It runs `destroy()` on its
`Destroying` event.

**Re-running with the same `id`** finds the previous gui by name and destroys
it. That fires the old run's `Destroying`, so the **old run's** `onUnload`
callbacks run inside the old environment. Put all teardown in `onUnload` and
a re-execute cleans up after itself, even where `getgenv()` is not shared
between executions.

Use `ui.alive` as a loop condition:

```lua
task.spawn(function()
    while ui.alive do
        -- …
        task.wait(0.5)
    end
end)
```

The library does not disconnect **your** connections. Do that in `onUnload`.

---

## Executor requirements

| function | used for | without it |
|---|---|---|
| `gethui` | parent the gui | `CoreGui` |
| `cloneref` | service refs | plain `GetService` |
| `getcustomasset`, `writefile`, `isfile`, `isfolder`, `makefolder` | built-in and added icons | those icons blank; content/asset ids still work |
| `crypt.base64decode` / `base64.decode` | icon decoding | pure-Lua decoder |
| `syn.protect_gui` | protecting the gui | skipped |

---

## Gotchas

- **Game code in a callback can break the menu.** Once a thread has run the
  game's own Lua (`require` of a game module, or any function it returns), that
  thread may lose access to anything under `gethui()` and throw "lacking
  capability Plugin" at the next UI write. A coroutine does not isolate this;
  a `task.spawn` does. Run game-facing work on its own task, and do the same
  inside an `options` function that reads game modules:

  ```lua
  local function apart(fn, ...)
      local out, done = nil, false
      task.spawn(function(...) out = table.pack(pcall(fn, ...)); done = true end, ...)
      while not done do task.wait() end
      return out[1] and out[2] or nil
  end

  options = function() return apart(readSkillBar) or {} end
  ```

- **A value your script changes must go back through `set(v, true)`.**
  Otherwise the control shows stale state. `silent` keeps the callback from
  re-running the feature.
- **`load` calls callbacks.** If a callback has side effects you don't want at
  startup, gate them, or load before connecting what they drive.
- **Textbox `set` calls back** (with `enter = false`) unless silent.
- **Single-pick dropdowns** can't be emptied by the user. Offer a "None"
  option or use `multi`.
- **Clicking the toggle's keycap rebinds; it does not flip the switch.**
- **`button` has no `set`.** Calling it errors.
- **`label` takes a string**, unlike every other element.
- **Names are plain text** (not RichText). The status line and readouts escape
  `& < > "`, so markup in them shows literally.
- **Keys don't fire while a TextBox is focused.** That includes the game's
  chat box.
- Roblox throttles an unfocused window to ~10 fps. Don't judge the UI's
  performance with the game in the background.

---

## Full example

```lua
local ui = loadstring(game:HttpGet('https://github.com/kagehana/seoul/blob/main/seoul.lua?raw=true'))()

local win = ui:window({ title = 'Example', id = 'Example', accent = 'tan', pattern = 'dots' })

local S = { fly = false, speed = 120, heal = { 40, 90 }, targets = {}, mode = 'Nearest' }

-- global
local g = win:tab('Global')
local move = g:group('Movement')

move:toggle({
    name   = 'Fly', icon = 'paper-plane-tilt', key = Enum.KeyCode.V, flag = 'fly',
    slider = { min = 0, max = 400, step = 5, default = S.speed, suffix = ' st/s' },
    call   = function(on, speed)
        S.fly, S.speed = on, speed
        if not win:isOpen() then
            ui:notify({ title = 'Fly', message = on and 'On' or 'Off', duration = 2 })
        end
    end,
})

local menu = g:group('Menu')
menu:keybind({ name = 'Menu key', icon = 'key', default = Enum.KeyCode.RightShift, flag = 'menuKey',
    changed = function(k) if k then win:setKey(k) end end })
menu:button({ name = 'Unload', icon = 'x', call = function() ui:destroy() end })

-- farm
local f = win:tab('Farm')
local tg = f:group('Target')

tg:dropdown({
    name = 'Targets', icon = 'crosshair-simple', multi = true, flag = 'targets',
    options  = function()
        -- runs each time the list opens; names repeat, so collapse them
        local list, seen = {}, {}
        for _, h in workspace:GetDescendants() do
            if h:IsA('Humanoid') and h.Parent and not seen[h.Parent.Name] then
                seen[h.Parent.Name] = true
                table.insert(list, h.Parent.Name)
            end
        end
        table.sort(list)
        return list
    end,
    describe = function(name) return name:find('Boss') and 'boss' or nil end,
    call     = function(list) S.targets = list end,
})

tg:dropdown({ name = 'Mode', options = { 'Nearest', 'Lowest HP', 'Random' }, default = S.mode,
    flag = 'mode', call = function(v) S.mode = v end })

tg:range({ name = 'Heal between', icon = 'heart', min = 0, max = 100, suffix = '%',
    default = S.heal, flag = 'heal', call = function(lo, hi) S.heal = { lo, hi } end })

local where = tg:field({ name = 'Return point', icon = 'map-pin' })
tg:button({ name = 'Set here', icon = 'house', call = function()
    local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
    if hrp then
        local p = hrp.Position
        where:set(string.format('%d, %d, %d', p.X, p.Y, p.Z))
    end
end })

-- config
local PATH = 'Example/config.json'
local Http = game:GetService('HttpService')

pcall(function()
    if isfile(PATH) then ui:load(Http:JSONDecode(readfile(PATH))) end
end)

local last
task.spawn(function()
    while ui.alive do
        local now = Http:JSONEncode(ui:config())
        if now ~= last then
            last = now
            pcall(function()
                if not isfolder('Example') then makefolder('Example') end
                writefile(PATH, now)
            end)
        end
        task.wait(1)
    end
end)

-- status
task.spawn(function()
    while ui.alive do
        if #S.targets > 0 then
            win:status('Farming ' .. S.targets[1], { timer = true })
        else
            win:status('Idle', { idle = true })
        end
        task.wait(0.25)
    end
end)

ui:onUnload(function()
    S.fly = false
    -- disconnect your own signals here
end)
```
