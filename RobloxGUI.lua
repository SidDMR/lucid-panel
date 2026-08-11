--// Roblox GUI — Lucid Panel v3
--// Lucid Panel v4.1
--// Features: Opacity, Hip Height, WalkSpeed Lock, JumpHeight Lock,
--//           Coordinates (view/edit/copy), Noclip, Anti-AFK, AutoClick, Air Walk
--// Execute with any Roblox script executor

-- Script source URL for reload
local SCRIPT_URL = "https://raw.githubusercontent.com/SidDMR/lucid-panel/main/RobloxGUI.lua"

-- Singleton guard: double clicks/re-execution must not duplicate event loops.
local CoreGui = game:GetService("CoreGui")
local sharedEnvironment = (getgenv and getgenv()) or _G
local existingPanel = CoreGui:FindFirstChild("LucidPanel")
if existingPanel then
    warn("[Lucid Panel] Already running; duplicate execution ignored.")
    return
end
local previousToken = sharedEnvironment.__LUCID_PANEL_ACTIVE
if previousToken then
    if previousToken.PlaceId == game.PlaceId and previousToken.JobId == game.JobId then
        warn("[Lucid Panel] A load is already active; duplicate execution ignored.")
        return
    end
    -- A shared executor environment may survive teleport; the old token does not.
    sharedEnvironment.__LUCID_PANEL_ACTIVE = nil
end
local instanceToken = { PlaceId = game.PlaceId, JobId = game.JobId }
sharedEnvironment.__LUCID_PANEL_ACTIVE = instanceToken

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
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
    walkspeedLocked    = false,
    walkspeedValue     = 16,
    jumpHeightLocked   = false,
    jumpHeightValue    = 7.2,
    noclipEnabled      = false,
    airWalkEnabled     = false,
    freezeEnabled      = false,
    freezeRoot         = nil,
    freezeWasAnchored  = false,
    infJumpEnabled     = false,
    maxZoomLocked      = false,
    maxZoomValue       = 128, -- Roblox default
    antiAfkEnabled     = true,
    antiFlingEnabled   = false,
    shiftLockEnabled   = false,
    playerLightEnabled = false,
    playerLightRange   = 30,
    playerLightPower   = 5,
    nightLockEnabled   = false,
    nightClockTime     = 0,
    fogEndLocked       = false,
    fogEndValue        = Lighting.FogEnd,
    antiLagEnabled     = false,
    clickTpEnabled     = false,
    loopGotoEnabled    = false,
    spawnpointEnabled  = false,
    spawnpointDelay    = 0.1,
    flyEnabled         = false,
    flySpeed           = 50,
    freecamEnabled     = false,
    fovLocked          = false,
    fovValue           = 70,
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
    Text                   = ">>  Lucid Panel v4.1",
    TextColor3             = Color3.fromRGB(200, 180, 255),
    TextSize               = 16,
    Font                   = Enum.Font.GothamBold,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = titleBar,
})

-- Minimize button
local minimized = false
local minimizeBtn = create("TextButton", {
    Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -96, 0, 4),
    BackgroundColor3 = Color3.fromRGB(85, 75, 120), BackgroundTransparency = 0.35,
    Text = "-", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 17,
    Font = Enum.Font.GothamBold, BorderSizePixel = 0, Parent = titleBar,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = minimizeBtn })

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
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    mainFrame.Size = minimized and UDim2.new(0, 310, 0, 36) or UDim2.new(0, 310, 0, 520)
    minimizeBtn.Text = minimized and "+" or "-"
end)

create("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding   = UDim.new(0, 8),
    Parent    = content,
})

-- Collapsible top-level categories. Controls can select a category even when
-- their implementation appears later in this file.
local categories = {}
local categoryMeta = {}
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
    categoryMeta[name] = {
        wrapper = wrapper,
        body = body,
        header = header,
        setOpen = function(value)
            open = value
            refresh()
        end,
    }
end

createCategory("Favorites", 0, false)
createCategory("Player", 1, false)
createCategory("Teleport & Coordinates", 2, false)
createCategory("Automation", 3, false)
createCategory("Servers", 4, false)
createCategory("Lighting", 5, false)
createCategory("Camera", 6, false)
createCategory("Waypoints", 7, false)
createCategory("Diagnostics", 8, false)
createCategory("Misc", 9, false)
createCategory("Interface", 10, false)

local searchRow = create("Frame", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
    LayoutOrder = -20, Parent = content,
})
local searchBox = create("TextBox", {
    Size = UDim2.new(1, -94, 0, 26), BackgroundColor3 = Color3.fromRGB(38, 36, 52),
    BorderSizePixel = 0, Text = "", PlaceholderText = "Search tools...",
    TextColor3 = Color3.fromRGB(230, 225, 245), PlaceholderColor3 = Color3.fromRGB(120, 110, 150),
    TextSize = 12, Font = Enum.Font.Gotham, ClearTextOnFocus = false, Parent = searchRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = searchBox })
local collapseBtn = create("TextButton", {
    Size = UDim2.new(0, 86, 0, 26), Position = UDim2.new(1, -86, 0, 0),
    BackgroundColor3 = Color3.fromRGB(50, 45, 70), BorderSizePixel = 0,
    Text = "Expand all", TextColor3 = Color3.fromRGB(205, 195, 235),
    TextSize = 10, Font = Enum.Font.GothamSemibold, Parent = searchRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = collapseBtn })
local allExpanded = false
collapseBtn.MouseButton1Click:Connect(function()
    allExpanded = not allExpanded
    for _, meta in pairs(categoryMeta) do meta.setOpen(allExpanded) end
    collapseBtn.Text = allExpanded and "Collapse all" or "Expand all"
end)
local function categoryMatches(name, body, query)
    if name:lower():find(query, 1, true) then return true end
    for _, item in ipairs(body:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
            local searchable = (item.Text .. " " .. (item:IsA("TextBox") and item.PlaceholderText or "")):lower()
            if searchable:find(query, 1, true) then return true end
        end
    end
    return false
end
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local query = searchBox.Text:lower():match("^%s*(.-)%s*$")
    for name, meta in pairs(categoryMeta) do
        meta.wrapper.Visible = query == "" or categoryMatches(name, meta.body, query)
        if query ~= "" and meta.wrapper.Visible then meta.setOpen(true) end
    end
end)

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

local layoutOrder = 0
local function nextOrder()
    layoutOrder = layoutOrder + 1
    return layoutOrder
end

-- Favorites live in their own function scope to stay below executor register
-- limits. Only the registration closure remains in the root chunk.
local registerFavorite = (function()
    useCategory("Favorites")
    sectionLabel("Pinned Tools", nextOrder())

    local controlsRow = rowFrame(nextOrder(), 30)
    local detachButton = create("TextButton", {
        Size=UDim2.new(1,0,0,26), BackgroundColor3=Color3.fromRGB(65,52,95),
        BorderSizePixel=0, Text="Detach Favorites Window", TextColor3=Color3.fromRGB(235,225,250),
        TextSize=11, Font=Enum.Font.GothamSemibold, Parent=controlsRow,
    })
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=detachButton })

    local attachedHost = create("Frame", {
        Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1, LayoutOrder=nextOrder(), Parent=currentSection,
    })
    local favoritesList = create("Frame", {
        Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1, Parent=attachedHost,
    })
    create("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5), Parent=favoritesList })
    local emptyLabel = create("TextLabel", {
        Size=UDim2.new(1,0,0,24), BackgroundTransparency=1, Text="Star a tool to pin it here",
        TextColor3=Color3.fromRGB(135,125,155), TextSize=11, Font=Enum.Font.Gotham,
        LayoutOrder=-1, Parent=favoritesList,
    })

    local dock = create("Frame", {
        Name="LucidFavoritesWindow", Size=UDim2.new(0,250,0,300),
        Position=UDim2.new(0.5,170,0.5,-150), BackgroundColor3=Color3.fromRGB(24,22,34),
        BackgroundTransparency=0.15, BorderSizePixel=0, Active=true, Draggable=true,
        Visible=false, Parent=screenGui,
    })
    create("UICorner", { CornerRadius=UDim.new(0,9), Parent=dock })
    create("UIStroke", { Color=Color3.fromRGB(115,85,190), Thickness=1.3, Parent=dock })
    create("TextLabel", {
        Size=UDim2.new(1,-38,0,34), Position=UDim2.new(0,10,0,0), BackgroundTransparency=1,
        Text="★  Lucid Favorites", TextColor3=Color3.fromRGB(255,215,70), TextSize=14,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=dock,
    })
    local attachButton=create("TextButton", {
        Size=UDim2.new(0,28,0,26), Position=UDim2.new(1,-32,0,4), BackgroundColor3=Color3.fromRGB(105,65,75),
        BorderSizePixel=0, Text="X", TextColor3=Color3.fromRGB(255,240,245), TextSize=12,
        Font=Enum.Font.GothamBold, Parent=dock,
    })
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=attachButton })
    local dockContent=create("ScrollingFrame", {
        Size=UDim2.new(1,-16,1,-44), Position=UDim2.new(0,8,0,38), BackgroundTransparency=1,
        BorderSizePixel=0, ScrollBarThickness=3, AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.new(), Parent=dock,
    })

    local detached=false
    local favoriteCount=0
    local function setDetached(value)
        detached=value
        if detached then
            favoritesList.Parent=dockContent
            dock.Visible=true
            detachButton.Text="Favorites Detached"
        else
            favoritesList.Parent=attachedHost
            dock.Visible=false
            detachButton.Text="Detach Favorites Window"
        end
    end
    detachButton.MouseButton1Click:Connect(function() setDetached(not detached) end)
    attachButton.MouseButton1Click:Connect(function() setDetached(false) end)
    addCleanup(function() setDetached(false) end)

    return function(label, trigger, sourceRow)
        local starred=false
        local favoriteEntry=nil
        local star=create("TextButton", {
            Size=UDim2.new(0,24,0,24), Position=UDim2.new(1,-76,0.5,-12),
            BackgroundTransparency=1, BorderSizePixel=0, Text="☆",
            TextColor3=Color3.fromRGB(145,135,165), TextSize=18,
            Font=Enum.Font.GothamBold, ZIndex=8, Parent=sourceRow,
        })
        star.MouseButton1Click:Connect(function()
            starred=not starred
            star.Text=starred and "★" or "☆"
            star.TextColor3=starred and Color3.fromRGB(255,215,55) or Color3.fromRGB(145,135,165)
            if starred then
                favoriteCount=favoriteCount+1
                emptyLabel.Visible=false
                favoriteEntry=create("TextButton", {
                    Size=UDim2.new(1,0,0,28), BackgroundColor3=Color3.fromRGB(48,42,68),
                    BorderSizePixel=0, Text="★  "..label, TextColor3=Color3.fromRGB(245,230,170),
                    TextSize=11, Font=Enum.Font.GothamSemibold, LayoutOrder=favoriteCount,
                    Parent=favoritesList,
                })
                create("UICorner", { CornerRadius=UDim.new(0,6), Parent=favoriteEntry })
                favoriteEntry.MouseButton1Click:Connect(function()
                    -- Run after the GUI click releases so mouse-lock/shift-lock
                    -- input state is identical to using the original control.
                    task.defer(trigger)
                end)
            else
                favoriteCount=math.max(0,favoriteCount-1)
                if favoriteEntry then favoriteEntry:Destroy(); favoriteEntry=nil end
                emptyLabel.Visible=favoriteCount==0
            end
        end)
    end
end)()

local activeFeatures = {}
local toggleRegistry = {}
local statusLabelRef = nil
local function refreshFeatureStatus()
    if not statusLabelRef then return end
    local enabled = { "Anti-AFK" }
    for name, on in pairs(activeFeatures) do
        if on then table.insert(enabled, name) end
    end
    table.sort(enabled)
    statusLabelRef.Text = table.concat(enabled, "  •  ")
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

    local function setToggle(value)
        enabled = value == true
        toggleBg.BackgroundColor3 = enabled and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70)
        knob.Position = enabled and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        activeFeatures[labelText] = enabled
        refreshFeatureStatus()
        if callback then callback(enabled) end
    end

    local function fireToggle()
        setToggle(not enabled)
    end

    btn.MouseButton1Click:Connect(fireToggle)
    registerFavorite(labelText, fireToggle, row)

    toggleRegistry[labelText] = setToggle
    return function() return enabled end, fireToggle, setToggle
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

-- IY Anti-Lag, made reversible. We disable effects rather than deleting them
-- and retain only the original properties required for restoration.
sectionLabel("Performance", nextOrder())
local antiLagSnapshots = {}
local antiLagEnvironment = nil

local function optimizeInstance(item)
    if not state.antiLagEnabled or antiLagSnapshots[item] then return end
    if item:IsA("BasePart") then
        antiLagSnapshots[item] = { "BasePart", item.CastShadow, item.Material, item.Reflectance }
        item.CastShadow = false
        item.Material = Enum.Material.Plastic
        item.Reflectance = 0
    elseif item:IsA("Decal") or item:IsA("Texture") then
        antiLagSnapshots[item] = { "Visual", item.Transparency }
        item.Transparency = 1
    elseif item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam")
        or item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
        antiLagSnapshots[item] = { "Enabled", item.Enabled }
        item.Enabled = false
    elseif item:IsA("ForceField") then
        antiLagSnapshots[item] = { "Visible", item.Visible }
        item.Visible = false
    elseif item:IsA("PostEffect") then
        antiLagSnapshots[item] = { "Enabled", item.Enabled }
        item.Enabled = false
    end
end

local function enableAntiLag()
    if antiLagEnvironment then return end
    local terrain = workspace:FindFirstChildWhichIsA("Terrain")
    local originalQuality = nil
    pcall(function() originalQuality = settings().Rendering.QualityLevel end)
    antiLagEnvironment = {
        terrain = terrain,
        water = terrain and { terrain.WaterWaveSize, terrain.WaterWaveSpeed,
            terrain.WaterReflectance, terrain.WaterTransparency } or nil,
        globalShadows = Lighting.GlobalShadows,
        fogStart = Lighting.FogStart,
        fogEnd = Lighting.FogEnd,
        quality = originalQuality,
    }
    if terrain then
        terrain.WaterWaveSize = 0
        terrain.WaterWaveSpeed = 0
        terrain.WaterReflectance = 0
        terrain.WaterTransparency = 1
    end
    Lighting.GlobalShadows = false
    Lighting.FogStart = 9e9
    Lighting.FogEnd = 9e9
    pcall(function() settings().Rendering.QualityLevel = 1 end)
    task.spawn(function()
        local count = 0
        for _, root in ipairs({ workspace, Lighting }) do
            for _, item in ipairs(root:GetDescendants()) do
                if not state.antiLagEnabled then return end
                optimizeInstance(item)
                count = count + 1
                if count % 500 == 0 then task.wait() end
            end
        end
    end)
end

local function disableAntiLag()
    for item, values in pairs(antiLagSnapshots) do
        if item.Parent then
            pcall(function()
                if values[1] == "BasePart" then
                    item.CastShadow, item.Material, item.Reflectance = values[2], values[3], values[4]
                elseif values[1] == "Visual" then
                    item.Transparency = values[2]
                elseif values[1] == "Enabled" then
                    item.Enabled = values[2]
                elseif values[1] == "Visible" then
                    item.Visible = values[2]
                end
            end)
        end
    end
    table.clear(antiLagSnapshots)
    local saved = antiLagEnvironment
    antiLagEnvironment = nil
    if saved then
        if saved.terrain and saved.terrain.Parent and saved.water then
            saved.terrain.WaterWaveSize = saved.water[1]
            saved.terrain.WaterWaveSpeed = saved.water[2]
            saved.terrain.WaterReflectance = saved.water[3]
            saved.terrain.WaterTransparency = saved.water[4]
        end
        Lighting.GlobalShadows = saved.globalShadows
        Lighting.FogStart = saved.fogStart
        Lighting.FogEnd = saved.fogEnd
        if saved.quality ~= nil then
            pcall(function() settings().Rendering.QualityLevel = saved.quality end)
        end
    end
end

createToggle("Anti-Lag Mode", nextOrder(), false, function(on)
    state.antiLagEnabled = on
    if on then enableAntiLag() else disableAntiLag() end
end)
local antiLagInfo = rowFrame(nextOrder(), 26)
create("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Text = "Low quality, effects off, simpler materials",
    TextColor3 = Color3.fromRGB(125, 115, 155), TextSize = 10,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    TextWrapped = true, Parent = antiLagInfo,
})
track(workspace.DescendantAdded:Connect(function(item)
    if state.antiLagEnabled then task.defer(optimizeInstance, item) end
end))
track(Lighting.DescendantAdded:Connect(function(item)
    if state.antiLagEnabled then task.defer(optimizeInstance, item) end
end))
addCleanup(function()
    state.antiLagEnabled = false
    disableAntiLag()
end)

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

local function setHipHeight(value, applyToCharacter)
    value = math.clamp(value, HIP_MIN, HIP_MAX)
    hipBox.Text = string.format("%.2f", value):gsub("%.?0+$", "")
    hipFill.Size = UDim2.new((value - HIP_MIN) / (HIP_MAX - HIP_MIN), 0, 1, 0)
    if applyToCharacter == false then return end
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

-- Display the game's real value without mutating it during Lucid startup.
local initialCharacter = LocalPlayer.Character
local initialHumanoid = initialCharacter and initialCharacter:FindFirstChildOfClass("Humanoid")
local originalHipHeight = initialHumanoid and initialHumanoid.HipHeight or 0
setHipHeight(originalHipHeight, false)

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

local walkspeedConnection = nil
local applyingWalkspeed = false

local function applyWalkSpeed(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        wsBox.Text = tostring(state.walkspeedValue)
        return false
    end
    state.walkspeedValue = value
    wsBox.Text = tostring(value)
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        applyingWalkspeed = true
        pcall(function() humanoid.WalkSpeed = value end)
        applyingWalkspeed = false
    end
    return true
end

local function bindWalkSpeedHumanoid(humanoid)
    if walkspeedConnection then
        walkspeedConnection:Disconnect()
        walkspeedConnection = nil
    end
    if not humanoid then return end
    walkspeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if state.walkspeedLocked and not applyingWalkspeed
            and humanoid.WalkSpeed ~= state.walkspeedValue then
            applyingWalkspeed = true
            pcall(function() humanoid.WalkSpeed = state.walkspeedValue end)
            applyingWalkspeed = false
        end
    end)
end

addCleanup(function()
    if walkspeedConnection then walkspeedConnection:Disconnect() end
    walkspeedConnection = nil
end)

local wsToggle, wsGetLocked = createInlineToggle(wsRow, false)
wsToggle(function(on)
    state.walkspeedLocked = on
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    bindWalkSpeedHumanoid(humanoid)
    applyWalkSpeed(wsBox.Text)
end)

wsBox.FocusLost:Connect(function(_enterPressed)
    applyWalkSpeed(wsBox.Text)
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

local jhToggle, jhGetLocked = createInlineToggle(jhRow, false)
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

local noclipCollisionState = {}
local function restoreNoclipCollisions()
    for part, canCollide in pairs(noclipCollisionState) do
        if part.Parent then part.CanCollide = canCollide end
    end
    table.clear(noclipCollisionState)
end

local _, fireNoclip = createToggle("Enable Noclip", nextOrder(), false, function(on)
    state.noclipEnabled = on
    if not on then restoreNoclipCollisions() end
end)
addCleanup(restoreNoclipCollisions)

sectionLabel("Anti-Fling", nextOrder())
createToggle("Enable Anti-Fling", nextOrder(), false, function(on)
    state.antiFlingEnabled = on
end)

-- ════════════════════════════════════════════════════════════
--  SECTION 5.5 ─ AIR WALK
-- ════════════════════════════════════════════════════════════
sectionLabel("Air Walk  (E up, Q down)", nextOrder())

local _, fireAirWalk = createToggle("Enable Air Walk", nextOrder(), false, function(on)
    state.airWalkEnabled = on
end)

-- IY freeze used on self: anchor the character root and restore its prior
-- anchored state when disabled instead of blindly forcing it false.
sectionLabel("Freeze Self", nextOrder())
local function setSelfFrozen(on)
    if not on then
        local previousRoot = state.freezeRoot
        if previousRoot and previousRoot.Parent then
            previousRoot.Anchored = state.freezeWasAnchored
        end
        state.freezeEnabled = false
        state.freezeRoot = nil
        state.freezeWasAnchored = false
        return
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if state.freezeRoot ~= root then
        state.freezeRoot = root
        state.freezeWasAnchored = root.Anchored
    end
    state.freezeEnabled = true
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    root.Anchored = true
end

createToggle("Freeze Me", nextOrder(), false, setSelfFrozen)
addCleanup(function() setSelfFrozen(false) end)

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

sectionLabel("Click Teleport", nextOrder())
createToggle("Left Alt + Click TP", nextOrder(), false, function(on)
    state.clickTpEnabled = on
end)

local clickTpBusy = false
local function pointerInsidePanel()
    if not mainFrame.Visible then return false end
    local pointer = UserInputService:GetMouseLocation()
    local topLeft = mainFrame.AbsolutePosition
    local size = mainFrame.AbsoluteSize
    return pointer.X >= topLeft.X and pointer.X <= topLeft.X + size.X
        and pointer.Y >= topLeft.Y and pointer.Y <= topLeft.Y + size.Y
end

local function clearCharacterVelocity(character)
    for _, item in ipairs(character:GetDescendants()) do
        if item:IsA("BasePart") then
            pcall(function()
                item.AssemblyLinearVelocity = Vector3.zero
                item.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

track(mouse.Button1Down:Connect(function()
    if not state.clickTpEnabled or clickTpBusy then return end
    if not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then return end
    if UserInputService:GetFocusedTextBox() or pointerInsidePanel() then return end
    if not mouse.Target then return end

    clickTpBusy = true
    task.spawn(function()
        pcall(function()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not character or not root then return end

            if humanoid and humanoid.SeatPart then
                humanoid.Sit = false
                task.wait(0.1)
                if character ~= LocalPlayer.Character or not root.Parent then return end
            end

            local hitPosition = mouse.Hit.Position
            local previous = root.Position
            local height = humanoid and humanoid.HipHeight > 0 and (humanoid.HipHeight + 1) or 4
            local facing = CFrame.new(hitPosition, Vector3.new(previous.X, hitPosition.Y, previous.Z))
                * CFrame.Angles(0, math.pi, 0)
            root.CFrame = facing + Vector3.new(0, height, 0)
            clearCharacterVelocity(character)
        end)
        clickTpBusy = false
    end)
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
        state.fogEndValue = Lighting.FogEnd
        fogBox.Text = tostring(Lighting.FogEnd)
        applyFogBtn.Text = "Applied"
    else
        applyFogBtn.Text = "Invalid"
    end
    task.delay(1, function() if applyFogBtn.Parent then applyFogBtn.Text = "Apply" end end)
end)
resetFogBtn.MouseButton1Click:Connect(function()
    Lighting.FogEnd = originalFogEnd
    state.fogEndValue = originalFogEnd
    fogBox.Text = tostring(originalFogEnd)
end)
createToggle("Lock FogEnd", nextOrder(), false, function(on)
    state.fogEndLocked = on
    if on then
        local value = tonumber(fogBox.Text)
        if value then state.fogEndValue = math.max(0, value) end
        Lighting.FogEnd = state.fogEndValue
        fogBox.Text = tostring(state.fogEndValue)
    end
end)

-- IY night sets ClockTime to 0. Lucid also offers a guarded lock so games that
-- continuously write daytime cannot immediately undo the client-side setting.
local originalClockTime = Lighting.ClockTime
local enforcingNight = false
local function applyNightTime()
    if enforcingNight then return end
    enforcingNight = true
    Lighting.ClockTime = state.nightClockTime
    enforcingNight = false
end

sectionLabel("Night / Clock Time", nextOrder())
local nightRow = rowFrame(nextOrder(), 30)
local clockBox = styledBox(nightRow, {
    Size = UDim2.new(0, 72, 0, 24), Position = UDim2.new(0, 0, 0.5, -12),
    Text = "0", PlaceholderText = "0-24",
})
local applyNightBtn = lightingButton(nightRow, "Apply", 80, 82, Color3.fromRGB(75, 50, 160))
local resetNightBtn = lightingButton(nightRow, "Reset", 170, 82, Color3.fromRGB(55, 50, 75))

applyNightBtn.MouseButton1Click:Connect(function()
    local value = tonumber(clockBox.Text)
    if value then
        -- ClockTime naturally wraps at 24; explicit modulo keeps the UI clear.
        state.nightClockTime = value % 24
        clockBox.Text = string.format("%.2f", state.nightClockTime)
        applyNightTime()
        applyNightBtn.Text = "Applied"
    else
        applyNightBtn.Text = "Invalid"
    end
    task.delay(1, function() if applyNightBtn.Parent then applyNightBtn.Text = "Apply" end end)
end)
resetNightBtn.MouseButton1Click:Connect(function()
    state.nightClockTime = originalClockTime
    clockBox.Text = string.format("%.2f", originalClockTime)
    applyNightTime()
end)

createToggle("Lock Selected Night Time", nextOrder(), false, function(on)
    state.nightLockEnabled = on
    if on then
        local value = tonumber(clockBox.Text)
        if value then state.nightClockTime = value % 24 end
        clockBox.Text = string.format("%.2f", state.nightClockTime)
        applyNightTime()
    end
end)

track(Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
    if state.nightLockEnabled and not enforcingNight
        and math.abs(Lighting.ClockTime - state.nightClockTime) > 0.001 then
        applyNightTime()
    end
end))

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
    state.nightLockEnabled = false
    Lighting.ClockTime = originalClockTime
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

-- IY goto, exposed in a small Misc section for future general utilities.
useCategory("Misc")
sectionLabel("Go To Player", nextOrder())
local gotoRow = rowFrame(nextOrder(), 30)
local gotoBox = styledBox(gotoRow, {
    Size = UDim2.new(1, -82, 0, 24), Position = UDim2.new(0, 0, 0.5, -12),
    Text = "", PlaceholderText = "Username or display name",
})
local gotoBtn = create("TextButton", {
    Size = UDim2.new(0, 72, 0, 24), Position = UDim2.new(1, -72, 0.5, -12),
    BackgroundColor3 = Color3.fromRGB(75, 50, 160), BorderSizePixel = 0,
    Text = "Go To", TextColor3 = Color3.fromRGB(240, 235, 255),
    TextSize = 11, Font = Enum.Font.GothamSemibold, Parent = gotoRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = gotoBtn })

local function findGotoPlayer(query)
    query = query:match("^%s*(.-)%s*$"):lower()
    if query == "" then return nil end
    local candidates = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then table.insert(candidates, player) end
    end
    for _, player in ipairs(candidates) do
        if player.Name:lower() == query or player.DisplayName:lower() == query then return player end
    end
    for _, player in ipairs(candidates) do
        if player.Name:lower():sub(1, #query) == query
            or player.DisplayName:lower():sub(1, #query) == query then return player end
    end
    for _, player in ipairs(candidates) do
        if player.Name:lower():find(query, 1, true)
            or player.DisplayName:lower():find(query, 1, true) then return player end
    end
    return nil
end

local gotoBusy = false
local function goToRequestedPlayer()
    if gotoBusy then return end
    local target = findGotoPlayer(gotoBox.Text)
    local targetCharacter = target and target.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        gotoBtn.Text = "Not found"
        task.delay(1.2, function() if gotoBtn.Parent then gotoBtn.Text = "Go To" end end)
        return
    end
    gotoBusy = true
    task.spawn(function()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            if humanoid and humanoid.SeatPart then
                humanoid.Sit = false
                task.wait(0.1)
            end
            if root.Parent and targetRoot.Parent then
                root.CFrame = targetRoot:GetPivot() + Vector3.new(3, 1, 0)
                clearCharacterVelocity(character)
                gotoBtn.Text = "Done"
            end
        end
        task.delay(1, function() if gotoBtn.Parent then gotoBtn.Text = "Go To" end end)
        gotoBusy = false
    end)
end

gotoBtn.MouseButton1Click:Connect(goToRequestedPlayer)
gotoBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then goToRequestedPlayer() end
end)

local loopGotoTarget = nil
local loopGotoGeneration = 0
local fireLoopGoto
local _, loopGotoToggle = createToggle("Loop Go To (uses player above)", nextOrder(), false, function(on)
    if on then
        local target = findGotoPlayer(gotoBox.Text)
        if not target then
            gotoBtn.Text = "Not found"
            task.delay(1.2, function() if gotoBtn.Parent then gotoBtn.Text = "Go To" end end)
            task.defer(function() if fireLoopGoto then fireLoopGoto() end end)
            return
        end
        loopGotoTarget = target
        state.loopGotoEnabled = true
        loopGotoGeneration = loopGotoGeneration + 1
        local generation = loopGotoGeneration
        task.spawn(function()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.SeatPart then
                humanoid.Sit = false
                task.wait(0.1)
            end
            while state.loopGotoEnabled and generation == loopGotoGeneration and screenGui.Parent do
                character = LocalPlayer.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                local targetCharacter = loopGotoTarget and loopGotoTarget.Character
                local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
                if root and targetRoot then
                    root.CFrame = targetRoot.CFrame + Vector3.new(3, 1, 0)
                end
                RunService.Heartbeat:Wait()
            end
        end)
    else
        state.loopGotoEnabled = false
        loopGotoTarget = nil
        loopGotoGeneration = loopGotoGeneration + 1
    end
end)
fireLoopGoto = loopGotoToggle
addCleanup(function()
    state.loopGotoEnabled = false
    loopGotoGeneration = loopGotoGeneration + 1
    loopGotoTarget = nil
end)

-- IY-style player ESP: BoxHandleAdornment per body part plus an always-on-top
-- name and distance label. The targeted mode reuses Lucid's Go To resolver.
local function initializePlayerESP()
    useCategory("Player")
    sectionLabel("Player ESP", nextOrder())

    local mode = "off"
    local holders = {}
    local running = true
    local setAll
    local setTarget

    local function removeESP(player)
        local data = holders[player]
        if data and data.folder then data.folder:Destroy() end
        holders[player] = nil
    end

    local function clearESP()
        for player in pairs(holders) do removeESP(player) end
    end

    local function addESP(player)
        if player == LocalPlayer then return end
        local character = player.Character
        local head = character and character:FindFirstChild("Head")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not head or not root or not humanoid then return end

        removeESP(player)
        local folder = Instance.new("Folder")
        folder.Name = player.Name.."_LucidESP"
        folder.Parent = screenGui

        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                local adornment = Instance.new("BoxHandleAdornment")
                adornment.Name = player.Name
                adornment.Adornee = part
                adornment.AlwaysOnTop = true
                adornment.ZIndex = 10
                adornment.Size = part.Size
                adornment.Transparency = 0.3
                adornment.Color = player.TeamColor
                adornment.Parent = folder
            end
        end

        local billboard = Instance.new("BillboardGui")
        billboard.Name = player.Name
        billboard.Adornee = head
        billboard.Size = UDim2.new(0,180,0,60)
        billboard.StudsOffset = Vector3.new(0,2.5,0)
        billboard.AlwaysOnTop = true
        billboard.Parent = folder
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1,0,1,0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.SourceSansSemibold
        label.TextSize = 17
        label.TextColor3 = Color3.new(1,1,1)
        label.TextStrokeTransparency = 0
        label.TextYAlignment = Enum.TextYAlignment.Bottom
        label.Parent = billboard
        holders[player] = { folder=folder, character=character, root=root, label=label }
    end

    local function wantedPlayers()
        local wanted = {}
        if mode == "all" then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then wanted[player] = true end
            end
        elseif mode == "target" then
            local target = findGotoPlayer(gotoBox.Text)
            if target then wanted[target] = true end
        end
        return wanted
    end

    local function refreshESP()
        local wanted = wantedPlayers()
        for player in pairs(holders) do
            if not wanted[player] then removeESP(player) end
        end
        for player in pairs(wanted) do
            local data = holders[player]
            if not data or data.character ~= player.Character or not data.folder.Parent then
                addESP(player)
            end
        end
    end

    local _, _, allSetter = createToggle("ESP All", nextOrder(), false, function(on)
        if on then
            if setTarget then setTarget(false) end
            mode = "all"
        elseif mode == "all" then
            mode = "off"
        end
        refreshESP()
    end)
    setAll = allSetter

    local _, _, targetSetter = createToggle("ESP GoTo Player", nextOrder(), false, function(on)
        if on then
            local target = findGotoPlayer(gotoBox.Text)
            if not target then
                gotoBtn.Text = "ESP target not found"
                task.delay(1.2, function() if gotoBtn.Parent then gotoBtn.Text="Go To" end end)
                task.defer(function() if setTarget then setTarget(false) end end)
                return
            end
            if setAll then setAll(false) end
            mode = "target"
        elseif mode == "target" then
            mode = "off"
        end
        refreshESP()
    end)
    setTarget = targetSetter

    task.spawn(function()
        while running and screenGui.Parent do
            if mode ~= "off" then
                refreshESP()
                local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                for player, data in pairs(holders) do
                    if data.label and data.root and data.root.Parent then
                        local distance = localRoot and math.floor((localRoot.Position-data.root.Position).Magnitude) or 0
                        data.label.Text = "Name: "..player.Name.." | Distance: "..distance
                    end
                end
            end
            task.wait(0.35)
        end
    end)

    addCleanup(function()
        running=false
        mode="off"
        clearESP()
    end)
end

initializePlayerESP()

sectionLabel("Custom Spawn Point", nextOrder())
local spawnDelayRow = rowFrame(nextOrder(), 30)
create("TextLabel", {
    Size = UDim2.new(0, 92, 1, 0), BackgroundTransparency = 1,
    Text = "Respawn delay:", TextColor3 = Color3.fromRGB(210, 210, 220),
    TextSize = 11, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = spawnDelayRow,
})
local spawnDelayBox = styledBox(spawnDelayRow, {
    Size = UDim2.new(0, 70, 0, 24), Position = UDim2.new(0, 98, 0.5, -12),
    Text = "0.1", PlaceholderText = "seconds",
})

local spawnpointCFrame = nil
local fireSpawnpoint
local _, spawnpointToggle = createToggle("Enable at current position", nextOrder(), false, function(on)
    if on then
        local delayValue = tonumber(spawnDelayBox.Text)
        if not delayValue or delayValue < 0 then delayValue = 0.1 end
        state.spawnpointDelay = delayValue
        spawnDelayBox.Text = tostring(delayValue)
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            task.defer(function() if fireSpawnpoint then fireSpawnpoint() end end)
            return
        end
        spawnpointCFrame = root.CFrame
        state.spawnpointEnabled = true
    else
        state.spawnpointEnabled = false
        spawnpointCFrame = nil
    end
end)
fireSpawnpoint = spawnpointToggle
spawnDelayBox.FocusLost:Connect(function()
    local value = tonumber(spawnDelayBox.Text)
    if value and value >= 0 then state.spawnpointDelay = value end
    spawnDelayBox.Text = tostring(state.spawnpointDelay)
end)
addCleanup(function()
    state.spawnpointEnabled = false
    spawnpointCFrame = nil
end)

-- ════════════════════════════════════════════════════════════
--  CREDIT FOOTER
-- ════════════════════════════════════════════════════════════
statusLabelRef = create("TextLabel", {
    Size                   = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text                   = "Anti-AFK",
    TextColor3             = Color3.fromRGB(80, 225, 125),
    TextSize               = 10,
    Font                   = Enum.Font.Gotham,
    TextXAlignment         = Enum.TextXAlignment.Center,
    LayoutOrder            = 999,
    Parent                 = content,
})
refreshFeatureStatus()

-- ════════════════════════════════════════════════════════════
--  RUNTIME LOOPS (consolidated into single Heartbeat)
-- ════════════════════════════════════════════════════════════

-- IY float/platform implementation adapted for Lucid lifecycle management.
local airPlatform = nil
local AIR_BASE_OFFSET = -3.1
local airPlatformY = nil
local airQDown = false
local airEDown = false

local function removeStaleFloatPads()
    local char = LocalPlayer.Character
    if char then
        for _, name in ipairs({ "LucidFloatPlatform", "AirWalkPlatform" }) do
            local stale = char:FindFirstChild(name)
            if stale and stale ~= airPlatform then stale:Destroy() end
        end
    end
    local oldWorkspacePad = workspace:FindFirstChild("AirWalkPlatform")
    if oldWorkspacePad and oldWorkspacePad ~= airPlatform then oldWorkspacePad:Destroy() end
    local oldLucidPad = workspace:FindFirstChild("LucidFloatPlatform")
    if oldLucidPad and oldLucidPad ~= airPlatform then oldLucidPad:Destroy() end
end
removeStaleFloatPads()

local function destroyPlatform()
    if airPlatform and airPlatform.Parent then
        airPlatform:Destroy()
    end
    airPlatform = nil
    airPlatformY = nil
    removeStaleFloatPads()
    airQDown, airEDown = false, false
end
addCleanup(destroyPlatform)

local function ensurePlatform()
    if airPlatform and airPlatform.Parent then return end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local old = char:FindFirstChild("LucidFloatPlatform")
    if old then old:Destroy() end
    airPlatform = Instance.new("Part")
    airPlatform.Name = "LucidFloatPlatform"
    airPlatform.Size = Vector3.new(2, 0.2, 1.5)
    airPlatform.Anchored = true
    airPlatform.CanCollide = false
    airPlatform.CanTouch = false
    airPlatform.CanQuery = false
    airPlatform.Massless = true
    airPlatform.Transparency = 1
    airPlatform.CastShadow = false
    -- Keep the pad outside the character model. Character controllers and
    -- noclip scripts commonly rewrite or move descendants of the character.
    airPlatform.Parent = workspace
    airPlatformY = root.Position.Y + AIR_BASE_OFFSET
end

local function repairPlatform()
    if not state.airWalkEnabled then return end
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not root then return end

    if not airPlatform or airPlatform.Parent ~= workspace then
        destroyPlatform()
        ensurePlatform()
    end
    if not airPlatform then return end

    -- Character controllers and Lucid Noclip may rewrite descendant collision
    -- properties. Restore the float pad immediately before physics simulation.
    airPlatform.Anchored = true
    -- The pad is now a position marker only. Collidable client parts can create
    -- enormous R15 solver impulses, so AirWalk no longer relies on collision.
    airPlatform.CanCollide = false
    airPlatform.Transparency = 1
    pcall(function() airPlatform.CollisionGroup = "Default" end)
    if not airPlatformY then airPlatformY = root.Position.Y + AIR_BASE_OFFSET end
    airPlatform.CFrame = CFrame.new(root.Position.X, airPlatformY, root.Position.Z)
end

track(RunService.Stepped:Connect(repairPlatform))

local function enforceNoclip()
    if not state.noclipEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part ~= airPlatform then
            if noclipCollisionState[part] == nil then
                noclipCollisionState[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

-- IY-style pre-physics enforcement, plus the existing Heartbeat second pass.
track(RunService.Stepped:Connect(enforceNoclip))

track(UserInputService.InputBegan:Connect(function(input, processed)
    if not state.airWalkEnabled or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.Q then airQDown = true end
    if input.KeyCode == Enum.KeyCode.E then airEDown = true end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Q then airQDown = false end
    if input.KeyCode == Enum.KeyCode.E then airEDown = false end
end))

useCategory("Player")
sectionLabel("Character Recovery", nextOrder())
local recoveryRow = rowFrame(nextOrder(), 32)
local recoveryBtn = create("TextButton", {
    Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromRGB(85, 50, 65),
    BorderSizePixel = 0, Text = "Recover Character",
    TextColor3 = Color3.fromRGB(245, 225, 235), TextSize = 12,
    Font = Enum.Font.GothamSemibold, Parent = recoveryRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = recoveryBtn })
recoveryBtn.MouseButton1Click:Connect(function()
    if state.airWalkEnabled then fireAirWalk() end
    if state.noclipEnabled then fireNoclip() end
    restoreNoclipCollisions()
    destroyPlatform()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if humanoid then
        humanoid.Sit = false
        humanoid.PlatformStand = false
        humanoid.HipHeight = originalHipHeight
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    recoveryBtn.Text = "Recovered"
    task.delay(1.2, function() if recoveryBtn.Parent then recoveryBtn.Text = "Recover Character" end end)
end)

-- ============================================================
-- V4 GENERAL TOOLKIT
-- ============================================================
-- Keep the large optional toolkit in its own function scope. Many executor
-- compilers retain Lua's per-function local/register limit; putting every UI
-- control in the root chunk makes loadstring return nil before Lucid starts.
local function initializeV4Toolkit()
local function actionButton(textValue, callback, color)
    local row = rowFrame(nextOrder(), 32)
    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = color or Color3.fromRGB(62, 52, 92),
        BorderSizePixel = 0, Text = textValue, TextColor3 = Color3.fromRGB(235, 230, 245),
        TextSize = 12, Font = Enum.Font.GothamSemibold, Parent = row,
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })
    local function runAction() callback(button) end
    button.MouseButton1Click:Connect(runAction)
    registerFavorite(textValue, runAction, row)
    return button
end

-- Fly uses camera-relative movement without inserting permanent character parts.
useCategory("Player")
sectionLabel("Movement+", nextOrder())
local flySpeedRow = rowFrame(nextOrder())
create("TextLabel", { Size = UDim2.new(0.65, 0, 1, 0), BackgroundTransparency = 1,
    Text = "Fly speed", TextColor3 = Color3.fromRGB(210,210,220), TextSize = 13,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Parent = flySpeedRow })
local flySpeedBox = styledBox(flySpeedRow, { Size = UDim2.new(0,70,0,24), Position = UDim2.new(1,-70,0.5,-12), Text = "50" })
flySpeedBox.FocusLost:Connect(function()
    state.flySpeed = math.clamp(tonumber(flySpeedBox.Text) or state.flySpeed, 1, 500)
    flySpeedBox.Text = tostring(state.flySpeed)
end)
local _, fireFly, setFly = createToggle("Fly", nextOrder(), false, function(on)
    state.flyEnabled = on
    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if h and not on then h.PlatformStand = false end
end)
sectionLabel("Player Utilities", nextOrder())
local spectatingPlayer = nil
actionButton("Spectate GoTo Player", function(button)
    local target = findGotoPlayer(gotoBox.Text)
    local camera = workspace.CurrentCamera
    local humanoid = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    if camera and humanoid then camera.CameraSubject=humanoid; spectatingPlayer=target; button.Text="Watching "..target.Name
    else button.Text="Player not found" end
end)
actionButton("Stop Spectating", function()
    spectatingPlayer=nil
    local camera=workspace.CurrentCamera; local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if camera and humanoid then camera.CameraSubject=humanoid; camera.CameraType=Enum.CameraType.Custom end
end)
actionButton("Copy GoTo Player ID", function(button)
    local target=findGotoPlayer(gotoBox.Text)
    if target and setclipboard then setclipboard(tostring(target.UserId)); button.Text="Copied "..target.Name.." ID"
    else button.Text="Player/clipboard unavailable" end
end)

-- Camera controls preserve the previous camera before Freecam takes ownership.
useCategory("Camera")
sectionLabel("Camera Tools", nextOrder())
local fovRow = rowFrame(nextOrder())
create("TextLabel", { Size=UDim2.new(0.55,0,1,0), BackgroundTransparency=1, Text="Field of view",
    TextColor3=Color3.fromRGB(210,210,220), TextSize=13, Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=fovRow })
local fovBox = styledBox(fovRow, { Size=UDim2.new(0,70,0,24), Position=UDim2.new(1,-70,0.5,-12), Text="70" })
fovBox.FocusLost:Connect(function()
    state.fovValue = math.clamp(tonumber(fovBox.Text) or state.fovValue, 1, 120)
    fovBox.Text = tostring(state.fovValue)
    if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = state.fovValue end
end)
createToggle("Lock FOV", nextOrder(), false, function(on) state.fovLocked = on end)
local savedCamera = nil
local freecamCFrame = nil
local freecamYaw = 0
local freecamPitch = 0
local _, fireFreecam, setFreecam = createToggle("Freecam", nextOrder(), false, function(on)
    state.freecamEnabled = on
    local camera = workspace.CurrentCamera
    if not camera then return end
    if on then
        if state.flyEnabled then setFly(false) end
        savedCamera = {
            Type=camera.CameraType, Subject=camera.CameraSubject,
            CFrame=camera.CFrame, FOV=camera.FieldOfView,
            MouseBehavior=UserInputService.MouseBehavior,
            MouseIconEnabled=UserInputService.MouseIconEnabled,
        }
        freecamCFrame = camera.CFrame
        local pitch, yaw = freecamCFrame:ToOrientation()
        freecamPitch, freecamYaw = pitch, yaw
        camera.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
        ContextActionService:BindActionAtPriority(
            "LucidFreecamSink",
            function() return Enum.ContextActionResult.Sink end,
            false,
            Enum.ContextActionPriority.High.Value + 100,
            Enum.PlayerActions.CharacterForward,
            Enum.PlayerActions.CharacterBackward,
            Enum.PlayerActions.CharacterLeft,
            Enum.PlayerActions.CharacterRight,
            Enum.PlayerActions.CharacterJump
        )
    elseif savedCamera then
        ContextActionService:UnbindAction("LucidFreecamSink")
        camera.CameraType = savedCamera.Type
        camera.CameraSubject = savedCamera.Subject
        camera.CFrame = savedCamera.CFrame
        if not state.fovLocked then camera.FieldOfView = savedCamera.FOV end
        UserInputService.MouseBehavior = savedCamera.MouseBehavior
        UserInputService.MouseIconEnabled = savedCamera.MouseIconEnabled
        savedCamera, freecamCFrame = nil, nil
    end
end)
addCleanup(function()
    ContextActionService:UnbindAction("LucidFreecamSink")
    if state.freecamEnabled and savedCamera and workspace.CurrentCamera then
        local camera=workspace.CurrentCamera
        camera.CameraType=savedCamera.Type; camera.CameraSubject=savedCamera.Subject
        camera.CFrame=savedCamera.CFrame; camera.FieldOfView=savedCamera.FOV
        UserInputService.MouseBehavior=savedCamera.MouseBehavior
        UserInputService.MouseIconEnabled=savedCamera.MouseIconEnabled
    end
end)
actionButton("First Person", function() LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson end)
actionButton("Third Person / Restore", function()
    LocalPlayer.CameraMode = Enum.CameraMode.Classic
    if state.freecamEnabled then setFreecam(false) end
    local camera = workspace.CurrentCamera
    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if camera and h then camera.CameraType = Enum.CameraType.Custom; camera.CameraSubject = h end
end)

-- In-memory waypoints are intentionally per-place and do not move between games.
useCategory("Waypoints")
sectionLabel("Named Waypoints", nextOrder())
local waypointRow = rowFrame(nextOrder())
local waypointBox = styledBox(waypointRow, { Size=UDim2.new(1,0,0,26), Text="Home", PlaceholderText="Waypoint name" })
local waypoints = {}
actionButton("Save / Update Waypoint", function(button)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local name = waypointBox.Text:match("^%s*(.-)%s*$")
    if root and name ~= "" then waypoints[name] = root.CFrame; button.Text = "Saved: "..name
        task.delay(1, function() if button.Parent then button.Text="Save / Update Waypoint" end end) end
end)
actionButton("Go To Waypoint", function(button)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local point = waypoints[waypointBox.Text:match("^%s*(.-)%s*$")]
    if root and point then root.CFrame = point; clearCharacterVelocity(LocalPlayer.Character)
    else button.Text="Waypoint not found"; task.delay(1, function() if button.Parent then button.Text="Go To Waypoint" end end) end
end)
actionButton("Delete Waypoint", function(button)
    waypoints[waypointBox.Text:match("^%s*(.-)%s*$")] = nil
    button.Text="Deleted"; task.delay(1, function() if button.Parent then button.Text="Delete Waypoint" end end)
end)

-- Lighting presets remain fully editable through the existing lighting values.
useCategory("Lighting")
sectionLabel("Comfort Presets", nextOrder())
local originalComfort = { Brightness=Lighting.Brightness, Exposure=Lighting.ExposureCompensation,
    Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient, ClockTime=Lighting.ClockTime }
local function setComfort(clock, brightness, exposure, ambient)
    Lighting.ClockTime=clock; Lighting.Brightness=brightness; Lighting.ExposureCompensation=exposure
    Lighting.Ambient=ambient; Lighting.OutdoorAmbient=ambient
end
actionButton("Migraine Comfort", function() setComfort(0, 1, -1, Color3.fromRGB(55,55,75)) end)
actionButton("Evening", function() setComfort(19, 1.5, -0.35, Color3.fromRGB(85,70,85)) end)
actionButton("Overcast", function() setComfort(12, 1, -0.5, Color3.fromRGB(90,90,95)) end)
actionButton("Restore Lighting", function()
    for property, value in pairs(originalComfort) do Lighting[property] = value end
end)
local brightEffectState = {}
createToggle("Disable Bright Effects", nextOrder(), false, function(on)
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("BloomEffect") or effect:IsA("SunRaysEffect") or effect:IsA("ColorCorrectionEffect")
            or effect:IsA("DepthOfFieldEffect") or effect:IsA("BlurEffect") then
            if on then
                if brightEffectState[effect] == nil then brightEffectState[effect]=effect.Enabled end
                effect.Enabled=false
            elseif brightEffectState[effect] ~= nil then
                effect.Enabled=brightEffectState[effect]; brightEffectState[effect]=nil
            end
        end
    end
end)
addCleanup(function()
    for effect, enabled in pairs(brightEffectState) do
        if effect and effect.Parent then effect.Enabled=enabled end
    end
end)

-- Server utilities.
useCategory("Servers")
sectionLabel("Server Utilities", nextOrder())
local jobRow = rowFrame(nextOrder())
local jobIdBox = styledBox(jobRow, { Size=UDim2.new(1,0,0,26), Text="", PlaceholderText="Paste Job ID..." })
actionButton("Copy Job ID", function(button)
    if setclipboard then setclipboard(game.JobId); button.Text="Copied Job ID" else button.Text=game.JobId end
end)
actionButton("Join Job ID", function(button)
    local id = jobIdBox.Text:match("^%s*(.-)%s*$")
    if id == "" then button.Text="Paste a Job ID above"; return end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
end)
actionButton("Server Hop", function(button)
    button.Text = "Finding server..."
    task.spawn(function()
        local ok, data = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
        end)
        if ok and data and data.data then
            for _, server in ipairs(data.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer); return
                end
            end
        end
        button.Text="No server found"; task.delay(1.5,function() if button.Parent then button.Text="Server Hop" end end)
    end)
end)

-- Profiles save only portable settings; character positions are deliberately excluded.
useCategory("Interface")
sectionLabel("Profile & Safety", nextOrder())
local profilePath = "LucidPanel/profile.json"
actionButton("Save Default Profile", function(button)
    if not writefile then button.Text="File API unavailable"; return end
    pcall(function() if makefolder and (not isfolder or not isfolder("LucidPanel")) then makefolder("LucidPanel") end end)
    local payload = { values={ walkspeedValue=state.walkspeedValue, jumpHeightValue=state.jumpHeightValue,
        maxZoomValue=state.maxZoomValue, flySpeed=state.flySpeed, fovValue=state.fovValue }, toggles={} }
    for name, enabled in pairs(activeFeatures) do payload.toggles[name]=enabled end
    local ok = pcall(writefile, profilePath, HttpService:JSONEncode(payload))
    button.Text = ok and "Profile saved" or "Save failed"
end)
actionButton("Load Default Profile", function(button)
    if not readfile or (isfile and not isfile(profilePath)) then button.Text="No saved profile"; return end
    local ok, payload = pcall(function() return HttpService:JSONDecode(readfile(profilePath)) end)
    if not ok then button.Text="Profile invalid"; return end
    for key,value in pairs(payload.values or {}) do if state[key] ~= nil then state[key]=value end end
    flySpeedBox.Text=tostring(state.flySpeed); fovBox.Text=tostring(state.fovValue)
    for name,value in pairs(payload.toggles or {}) do if toggleRegistry[name] then toggleRegistry[name](value) end end
    button.Text="Profile loaded"
end)

-- Panic is also bound to End. It turns off intrusive features and repairs physics.
local function panicReset()
    for name, setter in pairs(toggleRegistry) do
        if name ~= "Enable at current position" then pcall(setter, false) end
    end
    state.flyEnabled=false; state.freecamEnabled=false; state.noclipEnabled=false; state.airWalkEnabled=false
    restoreNoclipCollisions(); destroyPlatform()
    local char=LocalPlayer.Character; local h=char and char:FindFirstChildOfClass("Humanoid")
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if h then h.PlatformStand=false; h.Sit=false; h:ChangeState(Enum.HumanoidStateType.GettingUp) end
    if root then root.Anchored=false; root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
end
actionButton("PANIC / Reset Features [End]", function(button)
    panicReset(); button.Text="Reset complete"; task.delay(1,function() if button.Parent then button.Text="PANIC / Reset Features [End]" end end)
end, Color3.fromRGB(145,50,65))
sectionLabel("Quick Keybinds", nextOrder())
local shortcutKeys = { Fly=Enum.KeyCode.F, Noclip=Enum.KeyCode.N, Freecam=Enum.KeyCode.P }
local shortcutRow = rowFrame(nextOrder(), 32)
local shortcutBoxes = {}
for index, name in ipairs({"Fly","Noclip","Freecam"}) do
    local box = styledBox(shortcutRow, { Size=UDim2.new(0.31,0,0,26), Position=UDim2.new((index-1)*0.345,0,0,0),
        Text=name..":"..shortcutKeys[name].Name, PlaceholderText=name.." key" })
    shortcutBoxes[name]=box
    box.FocusLost:Connect(function()
        local requested=box.Text:match(":?(%w+)$")
        local key=requested and Enum.KeyCode[requested]
        if key and key ~= Enum.KeyCode.Unknown and key ~= Enum.KeyCode.RightAlt and key ~= Enum.KeyCode.End then
            shortcutKeys[name]=key
        end
        box.Text=name..":"..shortcutKeys[name].Name
    end)
end

-- Live diagnostics and a copyable report.
useCategory("Diagnostics")
sectionLabel("Live Character Report", nextOrder())
local diagnosticsLabel = create("TextLabel", { Size=UDim2.new(1,0,0,82), BackgroundColor3=Color3.fromRGB(35,33,48),
    BorderSizePixel=0, Text="Waiting for character...", TextColor3=Color3.fromRGB(205,205,220), TextSize=11,
    Font=Enum.Font.Code, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top, LayoutOrder=nextOrder(), Parent=currentSection })
create("UICorner", { CornerRadius=UDim.new(0,6), Parent=diagnosticsLabel })
actionButton("Copy Diagnostic Report", function(button)
    if setclipboard then setclipboard(diagnosticsLabel.Text); button.Text="Report copied" else button.Text="Clipboard unavailable" end
end)

local flyKeys = { W=false, A=false, S=false, D=false, Space=false, LeftControl=false }
track(UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.End and not processed then panicReset(); return end
    if not processed and UserInputService:GetFocusedTextBox() == nil then
        if input.KeyCode == shortcutKeys.Fly then
            if state.freecamEnabled then setFreecam(false) end
            fireFly()
        elseif input.KeyCode == shortcutKeys.Noclip then fireNoclip()
        elseif input.KeyCode == shortcutKeys.Freecam then fireFreecam() end
    end
    if flyKeys[input.KeyCode.Name] ~= nil and (not processed or state.freecamEnabled) then
        flyKeys[input.KeyCode.Name]=true
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if flyKeys[input.KeyCode.Name] ~= nil then flyKeys[input.KeyCode.Name]=false end
end))

local renderWarningShown = false
track(RunService.RenderStepped:Connect(function(dt)
    -- Keep the v4 render path completely dormant until a camera/movement
    -- feature is explicitly enabled. This avoids permanent per-frame work.
    if not state.flyEnabled and not state.freecamEnabled and not state.fovLocked then return end
    local ok, err = pcall(function()
    local camera=workspace.CurrentCamera
    local direction=Vector3.new(0,0,0)
    if state.freecamEnabled and camera and freecamCFrame then
        local mouseDelta = UserInputService:GetMouseDelta()
        freecamYaw = freecamYaw - mouseDelta.X * 0.0025
        freecamPitch = math.clamp(freecamPitch - mouseDelta.Y * 0.0025, math.rad(-89), math.rad(89))
        freecamCFrame = CFrame.new(freecamCFrame.Position)
            * CFrame.fromOrientation(freecamPitch, freecamYaw, 0)
        camera.CFrame = freecamCFrame
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    end
    if camera then
        direction = direction + camera.CFrame.LookVector*((flyKeys.W and 1 or 0)-(flyKeys.S and 1 or 0))
        direction = direction + camera.CFrame.RightVector*((flyKeys.D and 1 or 0)-(flyKeys.A and 1 or 0))
        direction = direction + Vector3.new(0,1,0)*((flyKeys.Space and 1 or 0)-(flyKeys.LeftControl and 1 or 0))
    end
    if state.flyEnabled then
        local char=LocalPlayer.Character; local root=char and char:FindFirstChild("HumanoidRootPart")
        local h=char and char:FindFirstChildOfClass("Humanoid")
        if root then root.AssemblyLinearVelocity=Vector3.zero; root.CFrame=root.CFrame + direction*state.flySpeed*dt end
        if h then h.PlatformStand=true end
    elseif state.freecamEnabled and camera and freecamCFrame then
        freecamCFrame = freecamCFrame + direction*state.flySpeed*dt
        camera.CFrame=freecamCFrame
    end
    if state.fovLocked and camera then camera.FieldOfView=state.fovValue end
    end)
    if not ok and not renderWarningShown then
        renderWarningShown=true
        warn("[Lucid v4 / Render] "..tostring(err))
    end
end))

task.spawn(function()
    local diagnosticsFailed=false
    while screenGui.Parent do
        if diagnosticsFailed then break end
        local ok, err=pcall(function()
            local char=LocalPlayer.Character; local h=char and char:FindFirstChildOfClass("Humanoid")
            local root=char and char:FindFirstChild("HumanoidRootPart")
            local rig=h and tostring(h.RigType):gsub("Enum.HumanoidRigType.","") or "None"
            local humanoidState=h and tostring(h:GetState()):gsub("Enum.HumanoidStateType.","") or "None"
            local speed=root and math.floor(root.AssemblyLinearVelocity.Magnitude+0.5) or 0
            diagnosticsLabel.Text=string.format("Place: %s\nRig: %s | State: %s\nWalkSpeed: %s | HipHeight: %s | Velocity: %s\nActive: %s",
                tostring(game.PlaceId), rig, humanoidState, h and tostring(h.WalkSpeed) or "-",
                h and string.format("%.2f",h.HipHeight) or "-", speed, statusLabelRef and statusLabelRef.Text or "Anti-AFK")
        end)
        if not ok then
            diagnosticsLabel.Text="Diagnostics unavailable\n"..tostring(err)
            warn("[Lucid v4 / Diagnostics] "..tostring(err))
            diagnosticsFailed=true
        end
        task.wait(1)
    end
end)
end

initializeV4Toolkit()

-- Re-apply settings on respawn
local function onCharacterAdded(char)
    -- Wait for humanoid to load
    local h = char:WaitForChild("Humanoid", 10)
    if not h then return end
    restoreNoclipCollisions()
    removeStaleFloatPads()
    originalHipHeight = h.HipHeight
    bindWalkSpeedHumanoid(h)

    -- A new root replaces the old anchored instance after respawn.
    if state.freezeEnabled then
        state.freezeRoot = nil
        state.freezeWasAnchored = false
        task.spawn(function()
            local root = char:WaitForChild("HumanoidRootPart", 10)
            if root and char == LocalPlayer.Character and state.freezeEnabled then
                setSelfFrozen(true)
            end
        end)
    end

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

    -- IY spawnpoint: wait the configured delay after a new root exists, then
    -- restore the saved CFrame if the toggle is still active.
    if state.spawnpointEnabled and spawnpointCFrame then
        local savedPosition = spawnpointCFrame
        local savedDelay = state.spawnpointDelay
        task.spawn(function()
            local root = char:WaitForChild("HumanoidRootPart", 10)
            if not root then return end
            task.wait(savedDelay)
            if state.spawnpointEnabled and spawnpointCFrame == savedPosition
                and char == LocalPlayer.Character and root.Parent then
                root.CFrame = savedPosition
                clearCharacterVelocity(char)
            end
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

    -- IY-style freeze enforcement. Some games attempt to unanchor the root.
    if state.freezeEnabled and hrp then
        if state.freezeRoot ~= hrp then
            state.freezeRoot = hrp
            state.freezeWasAnchored = hrp.Anchored
        end
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        hrp.Anchored = true
        -- Anchored humanoids cannot use AutoRotate. Mirror the camera's flat
        -- yaw while Roblox Shift Lock owns the mouse so facing still changes.
        local camera = workspace.CurrentCamera
        if camera and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
            and not state.freecamEnabled then
            local look = camera.CFrame.LookVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            if flatLook.Magnitude > 0.001 then
                hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
            end
        end
    end

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

    -- Client-side FogEnd lock for games that continuously overwrite Lighting.
    if state.fogEndLocked and Lighting.FogEnd ~= state.fogEndValue then
        Lighting.FogEnd = state.fogEndValue
    end

    -- Noclip
    enforceNoclip()

    -- Air Walk
    if state.airWalkEnabled then
        if not hrp or not h then
            destroyPlatform()
        else
            ensurePlatform()
            if airPlatform then
                if not airPlatformY then airPlatformY = hrp.Position.Y + AIR_BASE_OFFSET end
                local verticalDirection = (airEDown and 1 or 0) - (airQDown and 1 or 0)
                if verticalDirection ~= 0 then
                    local verticalStep = verticalDirection * 10 * dt
                    airPlatformY = airPlatformY + verticalStep
                end
                -- Hold the root at a deterministic height. Horizontal Roblox
                -- movement remains untouched, while jump/gravity impulses are
                -- removed instead of being resolved against a physical pad.
                local heldY = airPlatformY - AIR_BASE_OFFSET
                local currentCFrame = hrp.CFrame
                hrp.CFrame = CFrame.new(currentCFrame.Position.X, heldY, currentCFrame.Position.Z)
                    * currentCFrame.Rotation
                local currentVelocity = hrp.AssemblyLinearVelocity
                hrp.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                airPlatform.CFrame = CFrame.new(hrp.Position.X, airPlatformY, hrp.Position.Z)
            end
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
    if sharedEnvironment.__LUCID_PANEL_ACTIVE == instanceToken then
        sharedEnvironment.__LUCID_PANEL_ACTIVE = nil
    end
end)

-- Executor-supported teleport persistence. The newly loaded copy queues itself
-- again, so this also works across multi-place teleport chains.
local queueTeleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
local teleportBootstrap = string.format(
    "loadstring(game:HttpGet(%q, true))()",
    SCRIPT_URL
)
local teleportQueueReady = false
if type(queueTeleport) == "function" then
    teleportQueueReady = pcall(queueTeleport, teleportBootstrap)
end

if teleportQueueReady then
    print("[Lucid Panel v4.1] Loaded - teleport auto-execute queued | Right-Alt to toggle")
else
    warn("[Lucid Panel v4.1] Loaded, but this executor does not expose queue_on_teleport")
end
