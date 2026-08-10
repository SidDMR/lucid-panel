--// Roblox GUI — Lucid Panel v3
--// Lucid Panel v3.2
--// Features: Opacity, Hip Height, WalkSpeed Lock, JumpHeight Lock,
--//           Coordinates (view/edit/copy), Noclip, Anti-AFK, AutoClick, Air Walk
--// Execute with any Roblox script executor

-- Script source URL for reload
local SCRIPT_URL = "https://raw.githubusercontent.com/SidDMR/lucid-panel/main/RobloxGUI.lua"

-- Destroy previous instance if reloading
pcall(function()
    if game:GetService("CoreGui"):FindFirstChild("LucidPanel") then
        game:GetService("CoreGui"):FindFirstChild("LucidPanel"):Destroy()
    end
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local mouse = LocalPlayer:GetMouse()

-- Own executor-wide connections so reload/close cannot leave old behavior running.
local connections = {}
local cleanupActions = {}

local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function addCleanup(callback)
    table.insert(cleanupActions, callback)
end

-- ============================================================
-- STATE
-- ============================================================
local state = {
    walkspeedLocked    = true,
    walkspeedValue     = 16,
    jumpHeightLocked   = true,
    jumpHeightValue    = 7.2,
    noclipEnabled      = false,
    airWalkEnabled     = false,
    infJumpEnabled     = false,
    maxZoomLocked      = false,
    maxZoomValue       = 128, -- Roblox default
    antiAfkEnabled     = true,
    antiFlingEnabled   = true,
    shiftLockEnabled   = false,
    playerLightEnabled = false,
    playerLightRange   = 30,
    playerLightPower   = 5,
    autoclickEnabled   = false,
    autoclickInterval  = 0.01, -- 10 ms
}

-- ============================================================
-- UTILITY: create Instance with properties
-- ============================================================
local function create(className, props)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    if props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

-- ============================================================
-- SCREEN GUI
-- ============================================================
local screenGui = create("ScreenGui", {
    Name            = "LucidPanel",
    ResetOnSpawn    = false,
    ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
    Parent          = game:GetService("CoreGui"),
})

-- ============================================================
-- SCROLLING MAIN FRAME  (taller content now needs scroll)
-- ============================================================
local mainFrame = create("Frame", {
    Name                   = "MainFrame",
    Size                   = UDim2.new(0, 310, 0, 520),
    Position               = UDim2.new(0.5, -155, 0.5, -260),
    BackgroundColor3       = Color3.fromRGB(22, 22, 30),
    BackgroundTransparency = 0.4,
    BorderSizePixel        = 0,
    Active                 = true,
    Draggable              = false,
    ClipsDescendants       = true,
    Parent                 = screenGui,
})

create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = mainFrame })

-- Fit the fixed-size panel on smaller phone/tablet viewports.
local panelScale = create("UIScale", { Scale = 1, Parent = mainFrame })
local function updatePanelScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    panelScale.Scale = math.min(1, viewport.X / 340, viewport.Y / 550)
end
updatePanelScale()
if workspace.CurrentCamera then
    track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelScale))
end

local mainStroke = create("UIStroke", {
    Color        = Color3.fromRGB(90, 60, 180),
    Thickness    = 1.5,
    Transparency = 0.3,
    Parent       = mainFrame,
})

-- ============================================================
-- TITLE BAR
-- ============================================================
local titleBar = create("Frame", {
    Name                   = "TitleBar",
    Size                   = UDim2.new(1, 0, 0, 36),
    BackgroundColor3       = Color3.fromRGB(30, 28, 44),
    BackgroundTransparency = 0.3,
    BorderSizePixel        = 0,
    Parent                 = mainFrame,
})
create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = titleBar })

-- Title-bar-only dragging works on both mouse and touch.
local draggingPanel = false
local dragStart
local panelStart
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingPanel = true
        dragStart = input.Position
        panelStart = mainFrame.Position
    end
end)
track(UserInputService.InputChanged:Connect(function(input)
    if draggingPanel and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            panelStart.X.Scale, panelStart.X.Offset + delta.X,
            panelStart.Y.Scale, panelStart.Y.Offset + delta.Y
        )
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingPanel = false
    end
end))

create("TextLabel", {
    Size                   = UDim2.new(1, -10, 1, 0),
    Position               = UDim2.new(0, 10, 0, 0),
    BackgroundTransparency = 1,
    Text                   = ">>  Lucid Panel v3.2",
    TextColor3             = Color3.fromRGB(200, 180, 255),
    TextSize               = 16,
    Font                   = Enum.Font.GothamBold,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = titleBar,
})

-- Reload button (green R)
local reloadBtn = create("TextButton", {
    Size                   = UDim2.new(0, 28, 0, 28),
    Position               = UDim2.new(1, -64, 0, 4),
    BackgroundColor3       = Color3.fromRGB(50, 170, 80),
    BackgroundTransparency = 0.5,
    Text                   = "R",
    TextColor3             = Color3.fromRGB(255, 255, 255),
    TextSize               = 16,
    Font                   = Enum.Font.GothamBold,
    BorderSizePixel        = 0,
    Parent                 = titleBar,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = reloadBtn })
reloadBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
    task.defer(function()
        loadstring(game:HttpGet(SCRIPT_URL))()
    end)
end)

-- Close button (red X)
local closeBtn = create("TextButton", {
    Size                   = UDim2.new(0, 28, 0, 28),
    Position               = UDim2.new(1, -32, 0, 4),
    BackgroundColor3       = Color3.fromRGB(200, 60, 60),
    BackgroundTransparency = 0.5,
    Text                   = "X",
    TextColor3             = Color3.fromRGB(255, 255, 255),
    TextSize               = 14,
    Font                   = Enum.Font.GothamBold,
    BorderSizePixel        = 0,
    Parent                 = titleBar,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = closeBtn })
closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

-- ============================================================
-- CONTENT CONTAINER (ScrollingFrame for more sections)
-- ============================================================
local content = create("ScrollingFrame", {
    Name                      = "Content",
    Size                      = UDim2.new(1, -20, 1, -46),
    Position                  = UDim2.new(0, 10, 0, 40),
    BackgroundTransparency    = 1,
    BorderSizePixel           = 0,
    ScrollBarThickness        = 4,
    ScrollBarImageColor3      = Color3.fromRGB(90, 60, 180),
    CanvasSize                = UDim2.new(0, 0, 0, 0), -- auto-sized below
    AutomaticCanvasSize       = Enum.AutomaticSize.Y,
    Parent                    = mainFrame,
})

create("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding   = UDim.new(0, 8),
    Parent    = content,
})

-- Collapsible top-level categories. Controls can select a category even when
-- their implementation appears later in this file.
local categories = {}
local currentSection = content

local function createCategory(name, order, openByDefault)
    local wrapper = create("Frame", {
        Name = name .. "Category",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = content,
    })
    local list = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
        Parent = wrapper,
    })
    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(38, 34, 56),
        BorderSizePixel = 0,
        TextColor3 = Color3.fromRGB(205, 190, 255),
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 0,
        Parent = wrapper,
    })
    create("UICorner", { CornerRadius = UDim.new(0, 7), Parent = header })
    create("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = header })
    local body = create("Frame", {
        Name = "Body",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Visible = openByDefault,
        LayoutOrder = 1,
        Parent = wrapper,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
        Parent = body,
    })
    local open = openByDefault
    local function refresh()
        header.Text = (open and "v  " or ">  ") .. name
        body.Visible = open
    end
    header.MouseButton1Click:Connect(function()
        open = not open
        refresh()
    end)
    refresh()
    categories[name] = body
end

createCategory("Player", 1, true)
createCategory("Teleport & Coordinates", 2, false)
createCategory("Automation", 3, false)
createCategory("Servers", 4, false)
createCategory("Lighting", 5, false)
createCategory("Interface", 6, false)

local function useCategory(name)
    currentSection = categories[name]
end

-- ============================================================
-- HELPERS
-- ============================================================
local function sectionLabel(text, order)
    return create("TextLabel", {
        Size                   = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text                   = text,
        TextColor3             = Color3.fromRGB(170, 155, 220),
        TextSize               = 13,
        Font                   = Enum.Font.GothamSemibold,
        TextXAlignment         = Enum.TextXAlignment.Left,
        LayoutOrder            = order,
        Parent                 = currentSection,
    })
end

local function rowFrame(order, height)
    return create("Frame", {
        Size                   = UDim2.new(1, 0, 0, height or 30),
        BackgroundTransparency = 1,
        LayoutOrder            = order,
        Parent                 = currentSection,
    })
end

local function styledBox(parent, props)
    local box = create("TextBox", {
        BackgroundColor3       = Color3.fromRGB(40, 38, 55),
        BackgroundTransparency = 0.2,
        TextColor3             = Color3.fromRGB(220, 220, 230),
        TextSize               = 13,
        Font                   = Enum.Font.GothamSemibold,
        BorderSizePixel        = 0,
        ClearTextOnFocus       = false,
        Parent                 = parent,
    })
    for k, v in pairs(props) do box[k] = v end
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
    create("UIStroke", { Color = Color3.fromRGB(90, 60, 180), Thickness = 1, Parent = box })
    return box
end

local function createToggle(labelText, order, default, callback)
    local row = rowFrame(order)

    create("TextLabel", {
        Size                   = UDim2.new(0.6, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = labelText,
        TextColor3             = Color3.fromRGB(210, 210, 220),
        TextSize               = 13,
        Font                   = Enum.Font.Gotham,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = row,
    })

    local toggleBg = create("Frame", {
        Size              = UDim2.new(0, 44, 0, 22),
        Position          = UDim2.new(1, -48, 0.5, -11),
        BackgroundColor3  = default and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70),
        BorderSizePixel   = 0,
        Parent            = row,
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = toggleBg })

    local knob = create("Frame", {
        Size              = UDim2.new(0, 16, 0, 16),
        Position          = default and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        Parent            = toggleBg,
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

    local enabled = default
    local btn = create("TextButton", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = "",
        Parent                 = toggleBg,
    })

    local function fireToggle()
        enabled = not enabled
        toggleBg.BackgroundColor3 = enabled and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70)
        knob.Position = enabled and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        if callback then callback(enabled) end
    end

    btn.MouseButton1Click:Connect(fireToggle)

    return function() return enabled end, fireToggle
end

local function createInlineToggle(parent, default)
    local toggleBg = create("Frame", {
        Size              = UDim2.new(0, 44, 0, 22),
        Position          = UDim2.new(1, -48, 0.5, -11),
        BackgroundColor3  = default and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70),
        BorderSizePixel   = 0,
        Parent            = parent,
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = toggleBg })

    local knob = create("Frame", {
        Size              = UDim2.new(0, 16, 0, 16),
        Position          = default and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        Parent            = toggleBg,
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

    local enabled = default
    local btn = create("TextButton", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = "",
        Parent                 = toggleBg,
    })

    local function toggle(callback)
        btn.MouseButton1Click:Connect(function()
            enabled = not enabled
            toggleBg.BackgroundColor3 = enabled and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70)
            knob.Position = enabled and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            if callback then callback(enabled) end
        end)
    end

    return toggle, function() return enabled end
end

local layoutOrder = 0
local function nextOrder()
    layoutOrder = layoutOrder + 1
    return layoutOrder
end

-- ════════════════════════════════════════════════════════════
--  SECTION 0 ─ GUI OPACITY
-- ════════════════════════════════════════════════════════════
useCategory("Interface")
sectionLabel("GUI Opacity", nextOrder())

local opacRow = rowFrame(nextOrder())

local opacSlider = create("Frame", {
    Size              = UDim2.new(0.6, 0, 0, 6),
    Position          = UDim2.new(0, 0, 0.5, -3),
    BackgroundColor3  = Color3.fromRGB(50, 50, 65),
    BorderSizePixel   = 0,
    Parent            = opacRow,
})
create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = opacSlider })

local opacFill = create("Frame", {
    Size              = UDim2.new(0.6, 0, 1, 0), -- default 0.4 transparency → 60% opaque
    BackgroundColor3  = Color3.fromRGB(130, 90, 230),
    BorderSizePixel   = 0,
    Parent            = opacSlider,
})
create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = opacFill })

local opacBox = styledBox(opacRow, {
    Size     = UDim2.new(0, 55, 0, 24),
    Position = UDim2.new(1, -55, 0.5, -12),
    Text     = "60%",
})

local function setOpacity(pct)
    pct = math.clamp(pct, 0, 100)
    local transparency = 1 - (pct / 100)
    mainFrame.BackgroundTransparency = transparency
    titleBar.BackgroundTransparency  = math.clamp(transparency - 0.1, 0, 1)
    opacFill.Size = UDim2.new(pct / 100, 0, 1, 0)
    opacBox.Text  = tostring(math.floor(pct + 0.5)) .. "%"
end

local draggingOpac = false
opacSlider.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingOpac = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingOpac = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if draggingOpac and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local rel = math.clamp((input.Position.X - opacSlider.AbsolutePosition.X) / opacSlider.AbsoluteSize.X, 0, 1)
        setOpacity(rel * 100)
    end
end)

opacBox.FocusLost:Connect(function()
    local raw = opacBox.Text:gsub("%%", "")
    local num = tonumber(raw)
    if num then
        setOpacity(num)
    else
        setOpacity(60)
    end
end)

setOpacity(60) -- start at 60% opaque (40% transparent)

-- ════════════════════════════════════════════════════════════
--  SECTION 1 ─ HIP HEIGHT  (Slider + TextBox)
-- ════════════════════════════════════════════════════════════
useCategory("Player")
sectionLabel("Hip Height", nextOrder())

local hipRow = rowFrame(nextOrder())

local hipSlider = create("Frame", {
    Size              = UDim2.new(0.6, 0, 0, 6),
    Position          = UDim2.new(0, 0, 0.5, -3),
    BackgroundColor3  = Color3.fromRGB(50, 50, 65),
    BorderSizePixel   = 0,
    Parent            = hipRow,
})
create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hipSlider })

local hipFill = create("Frame", {
    Size              = UDim2.new(0.5, 0, 1, 0),
    BackgroundColor3  = Color3.fromRGB(130, 90, 230),
    BorderSizePixel   = 0,
    Parent            = hipSlider,
})
create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hipFill })

local hipBox = styledBox(hipRow, {
    Size     = UDim2.new(0, 55, 0, 24),
    Position = UDim2.new(1, -55, 0.5, -12),
    Text     = "0",
})

local HIP_MIN, HIP_MAX = -100, 200

local function setHipHeight(value)
    value = math.clamp(value, HIP_MIN, HIP_MAX)
    hipBox.Text = tostring(math.floor(value + 0.5))
    hipFill.Size = UDim2.new((value - HIP_MIN) / (HIP_MAX - HIP_MIN), 0, 1, 0)
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.HipHeight = value
        end
    end
end

local draggingHip = false
hipSlider.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingHip = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingHip = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if draggingHip and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local rel = math.clamp((input.Position.X - hipSlider.AbsolutePosition.X) / hipSlider.AbsoluteSize.X, 0, 1)
        setHipHeight(HIP_MIN + rel * (HIP_MAX - HIP_MIN))
    end
end)

hipBox.FocusLost:Connect(function()
    local num = tonumber(hipBox.Text)
    if num then setHipHeight(num) else hipBox.Text = "0" end
end)

setHipHeight(0)

-- ════════════════════════════════════════════════════════════
--  SECTION 2 ─ WALKSPEED  (TextBox + Lock toggle)
-- ════════════════════════════════════════════════════════════
sectionLabel("WalkSpeed", nextOrder())

local wsRow = rowFrame(nextOrder())

create("TextLabel", {
    Size = UDim2.new(0, 48, 1, 0), BackgroundTransparency = 1,
    Text = "Speed:", TextColor3 = Color3.fromRGB(210,210,220),
    TextSize = 13, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = wsRow,
})

local wsBox = styledBox(wsRow, {
    Size     = UDim2.new(0, 65, 0, 24),
    Position = UDim2.new(0, 50, 0.5, -12),
    Text     = "16",
})

create("TextLabel", {
    Size = UDim2.new(0, 35, 1, 0), Position = UDim2.new(0, 125, 0, 0),
    BackgroundTransparency = 1, Text = "Lock:",
    TextColor3 = Color3.fromRGB(210,210,220), TextSize = 13,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    Parent = wsRow,
})

local wsToggle, wsGetLocked = createInlineToggle(wsRow, true)
wsToggle(function(on)
    -- Always read the current box value when toggling
    local num = tonumber(wsBox.Text)
    if num then
        state.walkspeedValue = num
    end
    state.walkspeedLocked = on
    -- Apply immediately
    local char = LocalPlayer.Character
    if char then
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = state.walkspeedValue end
    end
end)

wsBox.FocusLost:Connect(function()
    local num = tonumber(wsBox.Text)
    if num then
        state.walkspeedValue = num
        local char = LocalPlayer.Character
        if char then
            local h = char:FindFirstChildOfClass("Humanoid")
            if h then h.WalkSpeed = num end
        end
    else
        wsBox.Text = tostring(state.walkspeedValue)
    end
end)

-- ════════════════════════════════════════════════════════════
--  SECTION 3 ─ JUMP HEIGHT  (TextBox + Lock toggle)
-- ════════════════════════════════════════════════════════════
sectionLabel("Jump Height", nextOrder())

local jhRow = rowFrame(nextOrder())

create("TextLabel", {
    Size = UDim2.new(0, 48, 1, 0), BackgroundTransparency = 1,
    Text = "Height:", TextColor3 = Color3.fromRGB(210,210,220),
    TextSize = 13, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = jhRow,
})

local jhBox = styledBox(jhRow, {
    Size     = UDim2.new(0, 65, 0, 24),
    Position = UDim2.new(0, 50, 0.5, -12),
    Text     = "7.2",
})

create("TextLabel", {
    Size = UDim2.new(0, 35, 1, 0), Position = UDim2.new(0, 125, 0, 0),
    BackgroundTransparency = 1, Text = "Lock:",
    TextColor3 = Color3.fromRGB(210,210,220), TextSize = 13,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    Parent = jhRow,
})

local jhToggle, jhGetLocked = createInlineToggle(jhRow, true)
jhToggle(function(on)
    -- Always read the current box value when toggling
    local num = tonumber(jhBox.Text)
    if num then
        state.jumpHeightValue = num
    end
    state.jumpHeightLocked = on
    -- Apply immediately
    local char = LocalPlayer.Character
    if char then
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then
            h.UseJumpPower = false
            h.JumpHeight = state.jumpHeightValue
        end
    end
end)

jhBox.FocusLost:Connect(function()
    local num = tonumber(jhBox.Text)
    if num then
        state.jumpHeightValue = num
        local char = LocalPlayer.Character
        if char then
            local h = char:FindFirstChildOfClass("Humanoid")
            if h then
                h.UseJumpPower = false
                h.JumpHeight = num
            end
        end
    else
        jhBox.Text = tostring(state.jumpHeightValue)
    end
end)

-- ════════════════════════════════════════════════════════════
--  SECTION 4 ─ COORDINATES  (X, Y, Z boxes + Copy + Teleport)
-- ════════════════════════════════════════════════════════════
useCategory("Teleport & Coordinates")
sectionLabel("Coordinate Grabber", nextOrder())

-- Live display row
local coordLiveRow = rowFrame(nextOrder(), 20)
local coordLiveLabel = create("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Text = "X: 0  Y: 0  Z: 0", TextColor3 = Color3.fromRGB(160, 160, 180),
    TextSize = 11, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = coordLiveRow,
})

-- Edit row: single X, Y, Z paste box
local coordEditRow = rowFrame(nextOrder(), 28)

local coordBox = styledBox(coordEditRow, {
    Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0.5, -11),
    Text = "0, 0, 0", PlaceholderText = "x, y, z",
})

-- Track whether user has edited the coord box so live update doesn't overwrite
local coordEdited = false

coordBox.FocusLost:Connect(function()
    -- Lock the box value if the user typed/pasted something
    local str = coordBox.Text:match("^%s*(.-)%s*$")
    if str ~= "" then
        coordEdited = true
    end
end)

-- Helper to parse the single coord box
local function parseCoordBox()
    local str = coordBox.Text:match("^%s*(.-)%s*$")
    if not str or str == "" then return nil, nil, nil end
    -- Try comma-separated: "x, y, z"
    local number = "([%+%-]?%d*%.?%d+)"
    local x, y, z = str:match(number .. "%s*,%s*" .. number .. "%s*,%s*" .. number)
    -- Fallback to space-separated: "x y z"
    if not x then
        x, y, z = str:match(number .. "%s+" .. number .. "%s+" .. number)
    end
    return tonumber(x), tonumber(y), tonumber(z)
end

-- Buttons row: Copy + Teleport
local coordBtnRow = rowFrame(nextOrder(), 28)

local function coordButton(text, xPos, color)
    local btn = create("TextButton", {
        Size                   = UDim2.new(0, 85, 0, 24),
        Position               = UDim2.new(0, xPos, 0.5, -12),
        BackgroundColor3       = color,
        BackgroundTransparency = 0.2,
        Text                   = text,
        TextColor3             = Color3.fromRGB(240, 240, 255),
        TextSize               = 12,
        Font                   = Enum.Font.GothamSemibold,
        BorderSizePixel        = 0,
        Parent                 = coordBtnRow,
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = btn })
    return btn
end

local copyBtn = coordButton("Copy", 0, Color3.fromRGB(55, 50, 80))
local tpBtn   = coordButton("Teleport", 95, Color3.fromRGB(70, 40, 120))

copyBtn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local pos = char.HumanoidRootPart.Position
        local str = string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z)
        if setclipboard then
            setclipboard(str)
        elseif toclipboard then
            toclipboard(str)
        end
        copyBtn.Text = "Copied!"
        task.delay(1.2, function() copyBtn.Text = "Copy" end)
    end
end)

tpBtn.MouseButton1Click:Connect(function()
    local nx, ny, nz = parseCoordBox()
    if nx and ny and nz then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart
            -- Briefly anchor to prevent physics from fighting the teleport
            local wasAnchored = hrp.Anchored
            hrp.Anchored = true
            hrp.CFrame = CFrame.new(nx, ny, nz)
            task.delay(0.1, function()
                if hrp and hrp.Parent then
                    hrp.Anchored = wasAnchored
                end
            end)
        end
        tpBtn.Text = "Done!"
        task.delay(1.2, function() tpBtn.Text = "Teleport" end)
    end
    -- Clear edited flag so live update resumes
    coordEdited = false
end)

-- TeleportGUI B, integrated: two reusable coordinate presets with one-click
-- capture and teleport. Inputs accept comma- or space-separated coordinates.
sectionLabel("Teleport Presets", nextOrder())
local function createTeleportPreset(name)
    local row = rowFrame(nextOrder(), 58)
    create("TextLabel", {
        Size = UDim2.new(0, 48, 0, 22), BackgroundTransparency = 1,
        Text = name .. ":", TextColor3 = Color3.fromRGB(190, 180, 220),
        TextSize = 12, Font = Enum.Font.GothamSemibold,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    local box = styledBox(row, {
        Size = UDim2.new(1, -52, 0, 22), Position = UDim2.new(0, 52, 0, 0),
        Text = "", PlaceholderText = "x, y, z",
    })
    local grab = create("TextButton", {
        Size = UDim2.new(0.48, 0, 0, 25), Position = UDim2.new(0, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(50, 50, 75), BorderSizePixel = 0,
        Text = "Grab Current", TextColor3 = Color3.fromRGB(220, 215, 240),
        TextSize = 11, Font = Enum.Font.GothamSemibold, Parent = row,
    })
    local go = create("TextButton", {
        Size = UDim2.new(0.48, 0, 0, 25), Position = UDim2.new(0.52, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(75, 50, 160), BorderSizePixel = 0,
        Text = "Teleport", TextColor3 = Color3.fromRGB(235, 230, 255),
        TextSize = 11, Font = Enum.Font.GothamSemibold, Parent = row,
    })
    create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = grab })
    create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = go })

    grab.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local p = root.Position
            box.Text = string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)
            grab.Text = "Captured"
            task.delay(1, function() if grab.Parent then grab.Text = "Grab Current" end end)
        end
    end)
    go.MouseButton1Click:Connect(function()
        local text = box.Text:match("^%s*(.-)%s*$")
        local x, y, z = text:match("([%+%-]?%d*%.?%d+)%s*,%s*([%+%-]?%d*%.?%d+)%s*,%s*([%+%-]?%d*%.?%d+)")
        if not x then
            x, y, z = text:match("([%+%-]?%d*%.?%d+)%s+([%+%-]?%d*%.?%d+)%s+([%+%-]?%d*%.?%d+)")
        end
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root and x and y and z then
            root.CFrame = CFrame.new(tonumber(x), tonumber(y), tonumber(z))
            go.Text = "Done"
        else
            go.Text = "Invalid coords"
        end
        task.delay(1.2, function() if go.Parent then go.Text = "Teleport" end end)
    end)
end

createTeleportPreset("Point A")
createTeleportPreset("Point B")

-- ════════════════════════════════════════════════════════════
--  SECTION 5 ─ NOCLIP TOGGLE
-- ════════════════════════════════════════════════════════════
useCategory("Player")
sectionLabel("Noclip", nextOrder())

createToggle("Enable Noclip", nextOrder(), false, function(on)
    state.noclipEnabled = on
end)

sectionLabel("Anti-Fling", nextOrder())
createToggle("Enable Anti-Fling", nextOrder(), true, function(on)
    state.antiFlingEnabled = on
end)

-- ════════════════════════════════════════════════════════════
--  SECTION 5.5 ─ AIR WALK
-- ════════════════════════════════════════════════════════════
sectionLabel("Air Walk  (E ↑  Q ↓  Jump ↑)", nextOrder())

createToggle("Enable Air Walk", nextOrder(), false, function(on)
    state.airWalkEnabled = on
end)

-- ════════════════════════════════════════════════════════════
--  SECTION 6 ─ INFINITE JUMP
-- ════════════════════════════════════════════════════════════
sectionLabel("Infinite Jump", nextOrder())

createToggle("Enable Inf. Jump", nextOrder(), false, function(on)
    state.infJumpEnabled = on
end)

-- IY-style: hook into JumpRequest with debounce (matches IY source lines 9789-9796)
local infJumpDebounce = false
track(UserInputService.JumpRequest:Connect(function()
    if state.infJumpEnabled and not infJumpDebounce then
        infJumpDebounce = true
        local char = LocalPlayer.Character
        if char then
            local h = char:FindFirstChildWhichIsA("Humanoid")
            if h then
                h:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
        task.wait()
        infJumpDebounce = false
    end
end))

-- ════════════════════════════════════════════════════════════
--  SECTION 6.5 ─ MAX ZOOM DISTANCE
-- ════════════════════════════════════════════════════════════
sectionLabel("Max Zoom Distance", nextOrder())

local zoomRow = rowFrame(nextOrder())

create("TextLabel", {
    Size = UDim2.new(0, 48, 1, 0), BackgroundTransparency = 1,
    Text = "Zoom:", TextColor3 = Color3.fromRGB(210,210,220),
    TextSize = 13, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = zoomRow,
})

local zoomBox = styledBox(zoomRow, {
    Size     = UDim2.new(0, 90, 0, 24),
    Position = UDim2.new(0, 50, 0.5, -12),
    Text     = "128",
})

create("TextLabel", {
    Size = UDim2.new(0, 35, 1, 0), Position = UDim2.new(0, 150, 0, 0),
    BackgroundTransparency = 1, Text = "Lock:",
    TextColor3 = Color3.fromRGB(210,210,220), TextSize = 13,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    Parent = zoomRow,
})

local zoomToggle, zoomGetLocked = createInlineToggle(zoomRow, false)
zoomToggle(function(on)
    state.maxZoomLocked = on
    if on then
        local num = tonumber(zoomBox.Text)
        if num then
            state.maxZoomValue = num
            LocalPlayer.CameraMaxZoomDistance = num
        end
    end
end)

zoomBox.FocusLost:Connect(function()
    local num = tonumber(zoomBox.Text)
    if num then
        state.maxZoomValue = num
        if state.maxZoomLocked then
            LocalPlayer.CameraMaxZoomDistance = num
        end
    else
        zoomBox.Text = tostring(state.maxZoomValue)
    end
end)

-- IY enableshiftlock: keep the Roblox Shift Lock option available even when a
-- game attempts to turn it off.
sectionLabel("Shift Lock", nextOrder())
createToggle("Enable Shift Lock Option", nextOrder(), false, function(on)
    state.shiftLockEnabled = on
    if on then
        pcall(function() LocalPlayer.DevEnableMouseLock = true end)
    end
end)
track(LocalPlayer:GetPropertyChangedSignal("DevEnableMouseLock"):Connect(function()
    if state.shiftLockEnabled then
        pcall(function() LocalPlayer.DevEnableMouseLock = true end)
    end
end))

-- IY lighting commands, exposed as editable values instead of fixed toggles.
local originalFogEnd = Lighting.FogEnd

local function removePlayerLight()
    local char = LocalPlayer.Character
    if not char then return end
    for _, item in ipairs(char:GetDescendants()) do
        if item:IsA("PointLight") and item.Name == "LucidPlayerLight" then
            item:Destroy()
        end
    end
end

local function applyPlayerLight()
    removePlayerLight()
    if not state.playerLightEnabled then return end
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local light = create("PointLight", {
        Name = "LucidPlayerLight",
        Range = state.playerLightRange,
        Brightness = state.playerLightPower,
        Shadows = false,
        Parent = root,
    })
end

useCategory("Lighting")
sectionLabel("Fog End", nextOrder())
local fogRow = rowFrame(nextOrder(), 30)
local fogBox = styledBox(fogRow, {
    Size = UDim2.new(0, 105, 0, 24), Position = UDim2.new(0, 0, 0.5, -12),
    Text = tostring(Lighting.FogEnd), PlaceholderText = "FogEnd value",
})
local function lightingButton(parent, text, x, width, color)
    local button = create("TextButton", {
        Size = UDim2.new(0, width, 0, 24), Position = UDim2.new(0, x, 0.5, -12),
        BackgroundColor3 = color, BorderSizePixel = 0, Text = text,
        TextColor3 = Color3.fromRGB(240, 235, 255), TextSize = 11,
        Font = Enum.Font.GothamSemibold, Parent = parent,
    })
    create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = button })
    return button
end
local applyFogBtn = lightingButton(fogRow, "Apply", 113, 70, Color3.fromRGB(75, 50, 160))
local resetFogBtn = lightingButton(fogRow, "Reset", 191, 70, Color3.fromRGB(55, 50, 75))
applyFogBtn.MouseButton1Click:Connect(function()
    local value = tonumber(fogBox.Text)
    if value then
        Lighting.FogEnd = math.max(0, value)
        fogBox.Text = tostring(Lighting.FogEnd)
        applyFogBtn.Text = "Applied"
    else
        applyFogBtn.Text = "Invalid"
    end
    task.delay(1, function() if applyFogBtn.Parent then applyFogBtn.Text = "Apply" end end)
end)
resetFogBtn.MouseButton1Click:Connect(function()
    Lighting.FogEnd = originalFogEnd
    fogBox.Text = tostring(originalFogEnd)
end)

sectionLabel("Player Light", nextOrder())
local lightRow = rowFrame(nextOrder(), 32)
create("TextLabel", {
    Size = UDim2.new(0, 45, 1, 0), BackgroundTransparency = 1,
    Text = "Radius", TextColor3 = Color3.fromRGB(210, 210, 220),
    TextSize = 11, Font = Enum.Font.Gotham, Parent = lightRow,
})
local lightRangeBox = styledBox(lightRow, {
    Size = UDim2.new(0, 48, 0, 24), Position = UDim2.new(0, 48, 0.5, -12), Text = "30",
})
create("TextLabel", {
    Size = UDim2.new(0, 52, 1, 0), Position = UDim2.new(0, 102, 0, 0),
    BackgroundTransparency = 1, Text = "Intensity", TextColor3 = Color3.fromRGB(210, 210, 220),
    TextSize = 11, Font = Enum.Font.Gotham, Parent = lightRow,
})
local lightPowerBox = styledBox(lightRow, {
    Size = UDim2.new(0, 42, 0, 24), Position = UDim2.new(0, 157, 0.5, -12), Text = "5",
})
local function readLightSettings()
    local radius = tonumber(lightRangeBox.Text)
    local power = tonumber(lightPowerBox.Text)
    if radius then state.playerLightRange = math.max(radius, 0) end
    if power then state.playerLightPower = math.max(power, 0) end
    lightRangeBox.Text = tostring(state.playerLightRange)
    lightPowerBox.Text = tostring(state.playerLightPower)
end
local lightActions = rowFrame(nextOrder(), 30)
local applyLightBtn = lightingButton(lightActions, "Apply Light", 0, 128, Color3.fromRGB(75, 50, 160))
local removeLightBtn = lightingButton(lightActions, "Remove Light", 138, 128, Color3.fromRGB(70, 45, 60))
applyLightBtn.MouseButton1Click:Connect(function()
    readLightSettings()
    state.playerLightEnabled = true
    applyPlayerLight()
    applyLightBtn.Text = "Applied"
    task.delay(1, function() if applyLightBtn.Parent then applyLightBtn.Text = "Apply Light" end end)
end)
removeLightBtn.MouseButton1Click:Connect(function()
    state.playerLightEnabled = false
    removePlayerLight()
end)
lightRangeBox.FocusLost:Connect(readLightSettings)
lightPowerBox.FocusLost:Connect(readLightSettings)

addCleanup(function()
    Lighting.FogEnd = originalFogEnd
    state.playerLightEnabled = false
    removePlayerLight()
end)

-- ════════════════════════════════════════════════════════════
--  SECTION 7 ─ ANTI-AFK TOGGLE
-- ════════════════════════════════════════════════════════════
useCategory("Automation")
sectionLabel("Protection Status", nextOrder())
local antiAfkRow = rowFrame(nextOrder(), 24)
create("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Text = "Anti-AFK  ON", TextColor3 = Color3.fromRGB(80, 225, 125),
    TextSize = 13, Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = antiAfkRow,
})

-- ════════════════════════════════════════════════════════════
--  SECTION 7 ─ AUTOCLICK  (10ms interval) + Keybind
-- ════════════════════════════════════════════════════════════
sectionLabel("AutoClick (10ms)", nextOrder())

local _, acFireToggle = createToggle("Enable AutoClick", nextOrder(), false, function(on)
    state.autoclickEnabled = on
end)

-- Keybind row
local acBindRow = rowFrame(nextOrder())

create("TextLabel", {
    Size = UDim2.new(0, 55, 1, 0), BackgroundTransparency = 1,
    Text = "Keybind:", TextColor3 = Color3.fromRGB(210,210,220),
    TextSize = 13, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = acBindRow,
})

local acBindBtn = create("TextButton", {
    Size                   = UDim2.new(0, 110, 0, 24),
    Position               = UDim2.new(0, 60, 0.5, -12),
    BackgroundColor3       = Color3.fromRGB(55, 50, 80),
    BackgroundTransparency = 0.2,
    Text                   = "Click to bind",
    TextColor3             = Color3.fromRGB(200, 190, 240),
    TextSize               = 12,
    Font                   = Enum.Font.GothamSemibold,
    BorderSizePixel        = 0,
    Parent                 = acBindRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = acBindBtn })
create("UIStroke", { Color = Color3.fromRGB(90, 60, 180), Thickness = 1, Parent = acBindBtn })

-- Clear bind button
local acClearBtn = create("TextButton", {
    Size                   = UDim2.new(0, 50, 0, 24),
    Position               = UDim2.new(0, 178, 0.5, -12),
    BackgroundColor3       = Color3.fromRGB(80, 40, 40),
    BackgroundTransparency = 0.3,
    Text                   = "Clear",
    TextColor3             = Color3.fromRGB(220, 160, 160),
    TextSize               = 11,
    Font                   = Enum.Font.GothamSemibold,
    BorderSizePixel        = 0,
    Parent                 = acBindRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = acClearBtn })

local acBoundKey = nil         -- Enum.KeyCode or Enum.UserInputType value
local acBoundType = nil        -- "key" or "mouse"
local acListening = false      -- true while waiting for input

acBindBtn.MouseButton1Click:Connect(function()
    acListening = true
    acBindBtn.Text = "Press any key..."
    acBindBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 180)
end)

acClearBtn.MouseButton1Click:Connect(function()
    acBoundKey = nil
    acBoundType = nil
    acListening = false
    acBindBtn.Text = "Click to bind"
    acBindBtn.BackgroundColor3 = Color3.fromRGB(55, 50, 80)
end)

-- Listen for keybind assignment AND keybind press
-- Binding capture accepts focused input; an active bind ignores processed input.
track(UserInputService.InputBegan:Connect(function(input, processed)
    local isKey = input.UserInputType == Enum.UserInputType.Keyboard
    local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.MouseButton2
        or input.UserInputType == Enum.UserInputType.MouseButton3

    if not isKey and not isMouse then return end

    -- Binding capture is deliberate; normal binds should not fire while typing.
    if processed and not acListening then return end

    -- ── Listening mode: assign whatever was pressed ──
    if acListening then
        -- Don't let RightAlt be bound (used for GUI toggle)
        if isKey and input.KeyCode == Enum.KeyCode.RightAlt then return end

        if isKey then
            acBoundKey  = input.KeyCode
            acBoundType = "key"
            acBindBtn.Text = "[ " .. input.KeyCode.Name .. " ]"
        else
            acBoundKey  = input.UserInputType
            acBoundType = "mouse"
            local names = {
                [Enum.UserInputType.MouseButton1] = "Mouse1",
                [Enum.UserInputType.MouseButton2] = "Mouse2",
                [Enum.UserInputType.MouseButton3] = "Mouse3",
            }
            acBindBtn.Text = "[ " .. (names[input.UserInputType] or "Mouse") .. " ]"
        end

        acListening = false
        acBindBtn.BackgroundColor3 = Color3.fromRGB(55, 50, 80)
        return
    end

    -- ── Trigger mode: fire toggle when bound input is pressed ──
    if acBoundKey then
        if acBoundType == "key" and isKey and input.KeyCode == acBoundKey then
            acFireToggle()
        elseif acBoundType == "mouse" and isMouse and input.UserInputType == acBoundKey then
            acFireToggle()
        end
    end
end))

-- ════════════════════════════════════════════════════════════
--  REJOIN BUTTON
-- ════════════════════════════════════════════════════════════
useCategory("Servers")
local rejoinRow = rowFrame(nextOrder(), 32)

local rejoinBtn = create("TextButton", {
    Size                   = UDim2.new(1, 0, 0, 28),
    BackgroundColor3       = Color3.fromRGB(70, 40, 120),
    BackgroundTransparency = 0.2,
    Text                   = "Rejoin Server",
    TextColor3             = Color3.fromRGB(240, 240, 255),
    TextSize               = 13,
    Font                   = Enum.Font.GothamSemibold,
    BorderSizePixel        = 0,
    Parent                 = rejoinRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = rejoinBtn })
create("UIStroke", { Color = Color3.fromRGB(90, 60, 180), Thickness = 1, Parent = rejoinBtn })

-- IY-style rejoin (source: admin.lua lines 6876-6885)
rejoinBtn.MouseButton1Click:Connect(function()
    rejoinBtn.Text = "Rejoining..."
    local PlaceId = game.PlaceId
    local JobId = game.JobId
    if #Players:GetPlayers() <= 1 then
        -- Solo server: kick and teleport fresh
        LocalPlayer:Kick("\nRejoining...")
        task.wait()
        pcall(function()
            TeleportService:Teleport(PlaceId, LocalPlayer)
        end)
    else
        -- Multiplayer: rejoin same server instance
        pcall(function()
            TeleportService:TeleportToPlaceInstance(PlaceId, JobId, LocalPlayer)
        end)
    end
end)

-- ════════════════════════════════════════════════════════════
--  PRIVATE SERVER JOIN
-- ════════════════════════════════════════════════════════════
sectionLabel("Private Server", nextOrder())

local psRow = rowFrame(nextOrder(), 28)

local psBox = styledBox(psRow, {
    Size            = UDim2.new(1, -75, 0, 24),
    Position        = UDim2.new(0, 0, 0.5, -12),
    Text            = "",
    PlaceholderText = "Paste server link...",
})

local psBtn = create("TextButton", {
    Size                   = UDim2.new(0, 65, 0, 24),
    Position               = UDim2.new(1, -65, 0.5, -12),
    BackgroundColor3       = Color3.fromRGB(70, 40, 120),
    BackgroundTransparency = 0.2,
    Text                   = "Join",
    TextColor3             = Color3.fromRGB(240, 240, 255),
    TextSize               = 12,
    Font                   = Enum.Font.GothamSemibold,
    BorderSizePixel        = 0,
    Parent                 = psRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = psBtn })
create("UIStroke", { Color = Color3.fromRGB(90, 60, 180), Thickness = 1, Parent = psBtn })

psBtn.MouseButton1Click:Connect(function()
    local link = psBox.Text
    if link == "" then return end

    -- Extract the code from the share link
    -- Format: https://www.roblox.com/share?code=XXXXX&type=Server
    local code = link:match("code=([^&]+)")
    if not code then
        psBtn.Text = "Bad link"
        task.delay(1.5, function() psBtn.Text = "Join" end)
        return
    end

    psBtn.Text = "Joining..."
    local PlaceId = game.PlaceId

    -- Try TeleportToPrivateServer with the share code
    local success = pcall(function()
        TeleportService:TeleportToPrivateServer(PlaceId, code, {LocalPlayer})
    end)

    if not success then
        -- Fallback: try regular Teleport with code as teleportData
        local success2 = pcall(function()
            TeleportService:Teleport(PlaceId, LocalPlayer, { privateServerCode = code })
        end)

        if not success2 then
            psBtn.Text = "Failed"
            task.delay(1.5, function() psBtn.Text = "Join" end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════
--  CREDIT FOOTER
-- ════════════════════════════════════════════════════════════
create("TextLabel", {
    Size                   = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text                   = "Anti-AFK ON  |  Right Alt: toggle panel",
    TextColor3             = Color3.fromRGB(80, 225, 125),
    TextSize               = 10,
    Font                   = Enum.Font.Gotham,
    TextXAlignment         = Enum.TextXAlignment.Center,
    LayoutOrder            = 999,
    Parent                 = content,
})

-- ════════════════════════════════════════════════════════════
--  RUNTIME LOOPS (consolidated into single Heartbeat)
-- ════════════════════════════════════════════════════════════

-- Air Walk state
local airPlatform = nil
local airY = 0
local AIR_SPEED = 50
local JUMP_BOOST = 8
local airJumpDebounce = false

local function destroyPlatform()
    if airPlatform and airPlatform.Parent then
        airPlatform:Destroy()
    end
    airPlatform = nil
end
addCleanup(destroyPlatform)

local function ensurePlatform()
    if airPlatform and airPlatform.Parent then return end
    airPlatform = Instance.new("Part")
    airPlatform.Name = "AirWalkPlatform"
    airPlatform.Size = Vector3.new(6, 0.2, 6)
    airPlatform.Anchored = true
    airPlatform.CanCollide = true
    airPlatform.Transparency = 0.95
    airPlatform.Material = Enum.Material.ForceField
    airPlatform.Color = Color3.fromRGB(120, 100, 200)
    airPlatform.CastShadow = false
    airPlatform.Parent = workspace
end

-- Re-apply settings on respawn
local function onCharacterAdded(char)
    -- Wait for humanoid to load
    local h = char:WaitForChild("Humanoid", 10)
    if not h then return end

    -- Re-apply WalkSpeed
    if state.walkspeedLocked then
        h.WalkSpeed = state.walkspeedValue
    end

    -- Re-apply JumpHeight
    if state.jumpHeightLocked then
        h.UseJumpPower = false
        h.JumpHeight = state.jumpHeightValue
    end

    -- Re-apply Max Zoom
    if state.maxZoomLocked then
        LocalPlayer.CameraMaxZoomDistance = state.maxZoomValue
    end

    -- Destroy old air walk platform so it re-initializes at new position
    destroyPlatform()

    -- Recreate IY-style player light on the new character.
    if state.playerLightEnabled then
        task.spawn(function()
            char:WaitForChild("HumanoidRootPart", 10)
            if char == LocalPlayer.Character then applyPlayerLight() end
        end)
    end
end

track(LocalPlayer.CharacterAdded:Connect(onCharacterAdded))
-- Also apply to current character if already loaded
if LocalPlayer.Character then
    task.spawn(function() onCharacterAdded(LocalPlayer.Character) end)
end

-- Single consolidated Heartbeat for all per-frame logic
track(RunService.Heartbeat:Connect(function(dt)
    local char = LocalPlayer.Character
    if not char then
        destroyPlatform()
        return
    end

    local h = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")

    -- Anti-fling: suppress impossible momentum without interfering with normal
    -- running, jumping, vehicles, or deliberate teleports.
    if hrp and state.antiFlingEnabled then
        local linear = hrp.AssemblyLinearVelocity
        local angular = hrp.AssemblyAngularVelocity
        if linear.Magnitude > 250 then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        elseif linear.Magnitude > 100 then
            hrp.AssemblyLinearVelocity = linear.Unit * 100
        end
        if angular.Magnitude > 100 then
            hrp.AssemblyAngularVelocity = angular.Unit * 100
        end
    end

    -- WalkSpeed lock
    if h and state.walkspeedLocked then
        h.WalkSpeed = state.walkspeedValue
    end

    -- JumpHeight lock
    if h and state.jumpHeightLocked then
        h.UseJumpPower = false
        h.JumpHeight = state.jumpHeightValue
        pcall(function()
            h.JumpPower = state.jumpHeightValue * 10
        end)
    end

    -- Max Zoom lock
    if state.maxZoomLocked then
        LocalPlayer.CameraMaxZoomDistance = state.maxZoomValue
    end

    -- Noclip
    if state.noclipEnabled then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end

    -- Air Walk
    if state.airWalkEnabled then
        if not hrp or not h then
            destroyPlatform()
        else
            if not airPlatform or not airPlatform.Parent then
                airY = hrp.Position.Y - 3
            end

            if UserInputService:IsKeyDown(Enum.KeyCode.E) then
                airY = airY + AIR_SPEED * dt
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
                airY = airY - AIR_SPEED * dt
            end

            if h:GetState() == Enum.HumanoidStateType.Jumping then
                if not airJumpDebounce then
                    airJumpDebounce = true
                    airY = airY + JUMP_BOOST
                end
            else
                airJumpDebounce = false
            end

            ensurePlatform()
            airPlatform.CFrame = CFrame.new(hrp.Position.X, airY, hrp.Position.Z)
        end
    else
        destroyPlatform()
    end

    -- Coordinates live update
    if hrp then
        local pos = hrp.Position
        coordLiveLabel.Text = string.format(
            "X: %.1f   Y: %.1f   Z: %.1f", pos.X, pos.Y, pos.Z
        )
        if not coordBox:IsFocused() and not coordEdited then
            coordBox.Text = string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z)
        end
    end
end))

-- Anti-AFK (Idled event + periodic fallback)
track(LocalPlayer.Idled:Connect(function()
    if state.antiAfkEnabled then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

-- Periodic anti-AFK backup: simulates input every 60s in case Idled doesn't fire
task.spawn(function()
    while screenGui.Parent do
        if state.antiAfkEnabled then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
        task.wait(60)
    end
end)

-- AutoClick (10ms loop — works even when alt-tabbed)
task.spawn(function()
    while screenGui.Parent do
        if state.autoclickEnabled then
            local success = pcall(function()
                local camera = workspace.CurrentCamera
                if not camera then return end
                local vpSize = camera.ViewportSize
                local cx, cy = vpSize.X / 2, vpSize.Y / 2
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
            end)
            if not success and mouse1click then
                pcall(mouse1click)
            end
        end
        task.wait(state.autoclickInterval)
    end
end)

-- ════════════════════════════════════════════════════════════
--  TOGGLE GUI VISIBILITY — Right-Alt
-- ════════════════════════════════════════════════════════════
track(UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightAlt then
        mainFrame.Visible = not mainFrame.Visible
    end
end))

screenGui.Destroying:Connect(function()
    state.autoclickEnabled = false
    state.antiAfkEnabled = false
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    for _, callback in ipairs(cleanupActions) do
        pcall(callback)
    end
    table.clear(cleanupActions)
end)

print("[Lucid Panel v3.2] Loaded - Right-Alt to toggle | R to reload | X to close")
