--// Roblox GUI — Lucid Panel v5
--// Lucid Panel v5.2.6
--// Features: Opacity, Hip Height, WalkSpeed Lock, JumpHeight Lock,
--//           Coordinates (view/edit/copy), Noclip, Anti-AFK, AutoClick, Air Walk
--// Execute with any Roblox script executor

-- Script source URL for reload
local SCRIPT_URL = "https://raw.githubusercontent.com/SidDMR/lucid-panel/main/RobloxGUI.lua"
if not game:IsLoaded() then game.Loaded:Wait() end

-- Singleton guard: double clicks/re-execution must not duplicate event loops.
local CoreGui = game:GetService("CoreGui")
local sharedEnvironment = (getgenv and getgenv()) or _G
local existingPanel = CoreGui:FindFirstChild("LucidPanel")
if existingPanel then
    local samePlace = existingPanel:GetAttribute("LucidPlaceId") == game.PlaceId
    local sameJob = existingPanel:GetAttribute("LucidJobId") == game.JobId
    if samePlace and sameJob and not existingPanel:GetAttribute("LucidTeleporting") then
        existingPanel.Enabled = true
        local existingFrame = existingPanel:FindFirstChild("MainFrame")
        if existingFrame then existingFrame.Visible = true end
        warn("[Lucid Panel] Already running; existing panel shown.")
        return
    end
    existingPanel:Destroy()
end
local previousToken = sharedEnvironment.__LUCID_PANEL_ACTIVE
if previousToken then
    local previousGui = previousToken.Gui
    if previousGui and previousGui.Parent and previousToken.PlaceId == game.PlaceId and previousToken.JobId == game.JobId then
        previousGui.Enabled = true
        local previousFrame = previousGui:FindFirstChild("MainFrame")
        if previousFrame then previousFrame.Visible = true end
        warn("[Lucid Panel] Already running; existing panel shown.")
        return
    end
    -- Executor environments can outlive a destroyed GUI or a failed startup.
    -- With no live GUI behind it, the token is stale and must not block a rerun.
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
local detachableWindows = {}
local create
local track

local function registerDetachableWindow(window, isPinned, isDetached, setPinned, setDetached)
    table.insert(detachableWindows, {window=window, isPinned=isPinned, isDetached=isDetached,
        setPinned=setPinned,setDetached=setDetached})
end

local function makeResizableWindow(window, minimumWidth, minimumHeight)
    local handle=create("TextButton",{Name="ResizeHandle",Size=UDim2.new(0,20,0,20),
        Position=UDim2.new(1,-20,1,-20),BackgroundTransparency=1,BorderSizePixel=0,
        Text="◢",TextColor3=Color3.fromRGB(155,135,205),TextSize=16,
        Font=Enum.Font.GothamBold,ZIndex=100,Active=true,AutoButtonColor=false,Parent=window})
    local resizing=false
    local startPointer=nil
    local startSize=nil
    local resizeInput=nil
    local function pointerPosition()
        if resizeInput and resizeInput.UserInputType==Enum.UserInputType.Touch then
            return Vector2.new(resizeInput.Position.X,resizeInput.Position.Y)
        end
        return UserInputService:GetMouseLocation()
    end
    handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            resizeInput=input; startPointer=pointerPosition(); startSize=window.AbsoluteSize; resizing=true
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if resizing and startPointer and startSize
            and (input==resizeInput or input.UserInputType==Enum.UserInputType.MouseMovement
                or input.UserInputType==Enum.UserInputType.Touch) then
            local delta=pointerPosition()-startPointer
            window.Size=UDim2.new(0,math.max(minimumWidth or 220,startSize.X+delta.X),
                0,math.max(minimumHeight or 150,startSize.Y+delta.Y))
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input==resizeInput or input.UserInputType==Enum.UserInputType.MouseButton1 then
            resizing=false; resizeInput=nil; startPointer=nil; startSize=nil
        end
    end))
    return handle
end

track = function(connection)
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
    characterRecoveryLoopEnabled = false,
    freezeEnabled      = false,
    freezeRoot         = nil,
    freezeWasAnchored  = false,
    antiPushEnabled    = false,
    infJumpEnabled     = false,
    maxZoomLocked      = false,
    maxZoomValue       = 128, -- Roblox default
    antiAfkEnabled     = true,
    antiFlingEnabled   = false,
    antiFlingLinear    = 250,
    antiFlingAngular   = 100,
    antiPushStrength   = "Normal",
    physicsBypass      = false,
    shiftLockEnabled   = false,
    playerLightEnabled = false,
    playerLightRange   = 30,
    playerLightPower   = 5,
    comfortPreset      = "None",
    comfortLocked      = false,
    nightLockEnabled   = false,
    nightClockTime     = 0,
    fogEndLocked       = false,
    fogEndValue        = Lighting.FogEnd,
    antiLagEnabled     = false,
    clickTpEnabled     = true,
    loopGotoEnabled    = false,
    spawnpointEnabled  = false,
    spawnpointDelay    = 0.1,
    flyEnabled         = false,
    flySpeed           = 50,
    freecamEnabled     = false,
    freecamSpeed       = 50,
    photoModeEnabled   = false,
    noCameraShake      = false,
    cameraShakeStrength = "Strong",
    fovLocked          = false,
    fovValue           = 70,
    autoclickEnabled   = false,
    autoclickInterval  = 0.001, -- 1 ms requested; effective rate is scheduler-limited
    autoclickMode      = "Hybrid",
    autoclickToolOnly  = false, -- legacy profile compatibility
    autoclickAvoidGui  = true,
    espTransparency   = 0.78,
    espMaxDistance    = 5000,
    espHighlightStyle = "Hard",
    specialHighlightColor = "#FFE12D",
    superSpecialHighlightColor = "#FF9BCD",
    exploiterHighlightColor = "#CD234B",
    unavailableEmoteIds = {},
    namedHighlightsSuppressed = false,
    emoteSpeed        = 1,
    keepEmoteMoving   = true,
    emoteSyncTolerance = 0.05,
    emoteSyncMode     = "Precise",
    emoteSyncDelay    = 0,
    emoteLoopMode     = "Infinite",
    emoteLoopCount    = 3,
    emoteResultLimit  = 30,
    emoteAutoInterval = 8,
    emoteAutoMode     = "Off",
    emoteResumeRespawn = false,
    emoteAutoPlayJoin = false,
    emoteStopOnJump   = false,
    emoteStopOnSit    = false,
    emoteStopOnTool   = false,
    emoteAliases      = {},
    emoteHistory      = {},
    emotePlaylists    = {},
    emoteSpeeds       = {},
    emoteRecentSyncPlayers = {},
    emoteSearchCache = {},
    emoteCustoms     = {},
    emoteStateAnimations = {Idle="",Walk="",Run="",Jump="",Fall="",Climb="",Swim=""},
    emoteStateSpeeds = {Idle=1,Walk=1,Run=1,Jump=1,Fall=1,Climb=1,Swim=1},
    emoteStatePresets = {},
    emotePresetEnabled = false,
    lowPerformanceMode = false,
    fpsCapEnabled      = true,
    fpsCapValue        = 350,
    accentTheme       = "Midnight",
    rendering3dDisabled = false,
    gotoOffsetX       = 3,
    gotoOffsetY       = 1,
    gotoOffsetZ       = 0,
    favoriteNames     = {},
    emoteFavorites    = {},
}

-- ============================================================
-- UTILITY: create Instance with properties
-- ============================================================
create = function(className, props)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    if props.Parent then
        inst.Parent = props.Parent
    end
    if state.themeNewInstance then pcall(state.themeNewInstance,inst) end
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
instanceToken.Gui = screenGui
screenGui:SetAttribute("LucidPlaceId", game.PlaceId)
screenGui:SetAttribute("LucidJobId", game.JobId)
track(LocalPlayer.OnTeleport:Connect(function(teleportState)
    if teleportState == Enum.TeleportState.Started then
        screenGui:SetAttribute("LucidTeleporting", true)
    end
end))

local notificationHost=create("Frame",{Name="LucidNotifications",Size=UDim2.new(0,280,1,-20),
    Position=UDim2.new(1,-290,0,10),BackgroundTransparency=1,ZIndex=200,Parent=screenGui})
create("UIListLayout",{VerticalAlignment=Enum.VerticalAlignment.Bottom,HorizontalAlignment=Enum.HorizontalAlignment.Right,
    SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=notificationHost})
local notificationOrder=0
local function notifyLucid(title,message,color)
    notificationOrder=notificationOrder+1
    local notice=create("Frame",{Size=UDim2.new(1,0,0,54),BackgroundColor3=Color3.fromRGB(30,27,42),
        BackgroundTransparency=0.08,BorderSizePixel=0,LayoutOrder=notificationOrder,ZIndex=201,Parent=notificationHost})
    create("UICorner",{CornerRadius=UDim.new(0,7),Parent=notice})
    create("UIStroke",{Color=color or Color3.fromRGB(105,80,175),Thickness=1,Parent=notice})
    create("TextLabel",{Size=UDim2.new(1,-12,0,20),Position=UDim2.new(0,6,0,4),BackgroundTransparency=1,
        Text=tostring(title),TextColor3=color or Color3.fromRGB(205,190,250),TextSize=11,Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=202,Parent=notice})
    create("TextLabel",{Size=UDim2.new(1,-12,0,24),Position=UDim2.new(0,6,0,25),BackgroundTransparency=1,
        Text=tostring(message),TextWrapped=true,TextColor3=Color3.fromRGB(225,220,235),TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=202,Parent=notice})
    task.delay(3.5,function() if notice.Parent then notice:Destroy() end end)
end

-- ============================================================
-- SCROLLING MAIN FRAME  (taller content now needs scroll)
-- ============================================================
local mainFrame = create("Frame", {
    Name                   = "MainFrame",
    Size                   = UDim2.new(0, 310, 0, 520),
    Position               = UDim2.new(0.5, -155, 0.5, -260),
    BackgroundColor3       = Color3.fromRGB(22, 22, 30),
    BackgroundTransparency = 0.1,
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
    local panelWidth=math.max(1,mainFrame.Size.X.Offset)
    local panelHeight=math.max(1,mainFrame.Size.Y.Offset)
    panelScale.Scale = math.min(1, viewport.X / (panelWidth+30), viewport.Y / (panelHeight+30))
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

state.mainTitle=create("TextLabel", {
    Size                   = UDim2.new(1, -10, 1, 0),
    Position               = UDim2.new(0, 10, 0, 0),
    BackgroundTransparency = 1,
    Text                   = "LUCID PANEL  •  v5.2.6",
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
local mainExpandedSize=mainFrame.Size
local mainResizeHandle=makeResizableWindow(mainFrame,270,180)
track(mainFrame:GetPropertyChangedSignal("Size"):Connect(function()
    if not minimized then mainExpandedSize=mainFrame.Size end
    updatePanelScale()
end))
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    mainResizeHandle.Visible=not minimized
    mainFrame.Size = minimized and UDim2.new(0, mainExpandedSize.X.Offset, 0, 36) or mainExpandedSize
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
    local detached = false
    local pinned = false

    -- Huzuni-style modular category window. The original body is reparented,
    -- so controls retain their state and connections instead of being cloned.
    local detachButton = create("TextButton", {
        Size=UDim2.new(0,26,0,24), Position=UDim2.new(1,-30,0,4),
        BackgroundColor3=Color3.fromRGB(62,52,88), BorderSizePixel=0,
        Text="D", TextColor3=Color3.fromRGB(215,200,245), TextSize=10,
        Font=Enum.Font.GothamBold, ZIndex=5, Parent=header,
    })
    create("UICorner", { CornerRadius=UDim.new(0,5), Parent=detachButton })
    local dock = create("Frame", {
        Name="Lucid"..name:gsub("[^%w]","").."Window",
        Size=UDim2.new(0,285,0,340),
        Position=UDim2.new(0.5,-460+((order%4)*36),0.5,-170+((order%5)*24)),
        BackgroundColor3=Color3.fromRGB(24,22,34), BackgroundTransparency=0.12,
        BorderSizePixel=0, Active=true, Draggable=true, Visible=false, Parent=screenGui,
    })
    create("UICorner", { CornerRadius=UDim.new(0,9), Parent=dock })
    create("UIStroke", { Color=Color3.fromRGB(115,85,190), Thickness=1.3, Parent=dock })
    create("TextLabel", {
        Size=UDim2.new(1,-116,0,34), Position=UDim2.new(0,10,0,0), BackgroundTransparency=1,
        Text=name, TextColor3=Color3.fromRGB(210,190,255), TextSize=13,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=dock,
    })
    local pinButton=create("TextButton", {
        Size=UDim2.new(0,34,0,26), Position=UDim2.new(1,-106,0,4),
        BackgroundColor3=Color3.fromRGB(65,58,85), BorderSizePixel=0, Text="Pin",
        TextColor3=Color3.fromRGB(225,215,235), TextSize=9, Font=Enum.Font.GothamSemibold,
        Parent=dock,
    })
    local attachButton=create("TextButton", {
        Size=UDim2.new(0,28,0,26), Position=UDim2.new(1,-32,0,4),
        BackgroundColor3=Color3.fromRGB(105,65,75), BorderSizePixel=0, Text="X",
        TextColor3=Color3.new(1,1,1), TextSize=11, Font=Enum.Font.GothamBold, Parent=dock,
    })
    local collapseDockButton=create("TextButton",{Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-68,0,4),
        BackgroundColor3=Color3.fromRGB(65,58,85),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
        TextSize=14,Font=Enum.Font.GothamBold,Parent=dock})
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=pinButton })
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=attachButton })
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=collapseDockButton })
    local dockContent=create("ScrollingFrame", {
        Size=UDim2.new(1,-16,1,-44), Position=UDim2.new(0,8,0,38),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=3,
        AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(), Parent=dock,
    })
    makeResizableWindow(dock,220,120)

    local function refresh()
        header.Text = detached and ("[]  "..name) or ((open and "v  " or ">  ") .. name)
        body.Visible = detached or open
    end
    header.MouseButton1Click:Connect(function()
        if detached then dock.Visible=true; return end
        open = not open
        refresh()
    end)
    local function setDetached(value)
        detached=value
        if detached then
            body.Parent=dockContent
            body.Visible=true
            dock.Visible=true
        else
            body.Parent=wrapper
            body.LayoutOrder=1
            dock.Visible=false
        end
        refresh()
    end
    detachButton.MouseButton1Click:Connect(function() setDetached(not detached) end)
    attachButton.MouseButton1Click:Connect(function() setDetached(false) end)
    local function setPinned(value)
        pinned=value==true
        pinButton.Text=pinned and "ON" or "Pin"
        pinButton.BackgroundColor3=pinned and Color3.fromRGB(150,115,45) or Color3.fromRGB(65,58,85)
    end
    pinButton.MouseButton1Click:Connect(function() setPinned(not pinned) end)
    local dockExpanded=true
    local expandedSize=dock.Size
    collapseDockButton.MouseButton1Click:Connect(function()
        dockExpanded=not dockExpanded
        dockContent.Visible=dockExpanded
        dock.Size=dockExpanded and expandedSize or UDim2.new(0,expandedSize.X.Offset,0,34)
        collapseDockButton.Text=dockExpanded and "-" or "+"
    end)
    registerDetachableWindow(dock,function() return pinned end,function() return detached end,setPinned,setDetached)
    addCleanup(function() if dock.Parent then setDetached(false) end end)
    refresh()
    categories[name] = body
    categoryMeta[name] = {
        wrapper = wrapper,
        body = body,
        header = header,
        dock = dock,
        setDetached = setDetached,
        isOpen = function() return open end,
        setOpen = function(value)
            open = value
            refresh()
        end,
    }
end

createCategory("Home", -1, true)
createCategory("Favorites", 0, false)
createCategory("Player", 1, false)
createCategory("Teleport & Coordinates", 2, false)
createCategory("Automation", 3, false)
createCategory("Servers", 4, false)
createCategory("Lighting", 5, false)
createCategory("Camera", 6, false)
createCategory("Waypoints", 7, false)
createCategory("Emotes", 8, false)
createCategory("Misc", 9, false)
createCategory("Diagnostics", 10, false)
createCategory("Interface", 11, false)

state.mainNavigation={active="Home",groups={
    Home={Home=true,Favorites=true},
    Player={Player=true,Camera=true},
    World={["Teleport & Coordinates"]=true,Waypoints=true,Lighting=true,Servers=true},
    Tools={Automation=true,Emotes=true,Misc=true},
    Settings={Interface=true,Diagnostics=true},
},categoryGroup={}}
for group,names in pairs(state.mainNavigation.groups) do for name in pairs(names) do state.mainNavigation.categoryGroup[name]=group end end
state.mainNavigation.row=create("Frame",{Size=UDim2.new(1,0,0,30),BackgroundTransparency=1,LayoutOrder=-30,Parent=content})
state.mainNavigation.buttons={}
for index,name in ipairs({"Home","Player","World","Tools","Settings"}) do
    local button=create("TextButton",{Size=UDim2.new(0.19,0,0,27),Position=UDim2.new((index-1)*0.2025,0,0,0),
        BackgroundColor3=Color3.fromRGB(48,43,65),BorderSizePixel=0,Text=name,TextColor3=Color3.fromRGB(220,210,235),
        TextSize=9,Font=Enum.Font.GothamSemibold,Parent=state.mainNavigation.row})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=button}); state.mainNavigation.buttons[name]=button
end
state.mainNavigation.apply=function()
    local visible=state.mainNavigation.groups[state.mainNavigation.active] or {}
    for name,meta in pairs(categoryMeta) do meta.wrapper.Visible=visible[name]==true end
    for name,button in pairs(state.mainNavigation.buttons) do
        button.BackgroundColor3=name==state.mainNavigation.active
            and (state.currentThemePalette and state.currentThemePalette.selection or Color3.fromRGB(62,60,70))
            or (state.currentThemePalette and state.currentThemePalette.surface2 or Color3.fromRGB(48,43,65))
        button.TextColor3=name==state.mainNavigation.active and (state.currentThemePalette and state.currentThemePalette.text or Color3.new(1,1,1))
            or (state.currentThemePalette and state.currentThemePalette.muted or Color3.fromRGB(180,170,205))
    end
    content.CanvasPosition=Vector2.zero
end
state.mainNavigation.select=function(name)
    if state.mainNavigation.groups[name] then state.mainNavigation.active=name; state.mainNavigation.apply() end
end
for name,button in pairs(state.mainNavigation.buttons) do button.MouseButton1Click:Connect(function() state.mainNavigation.select(name) end) end
state.mainNavigation.apply()

-- Bottom launcher inspired by compact executor docks. It stays available
-- while the large window is hidden and every icon opens a real Lucid module.
state.initializeLucidDock=function()
    state.themePalettes={
        Midnight={background=Color3.fromRGB(8,8,10),panel=Color3.fromRGB(15,15,19),surface=Color3.fromRGB(25,25,31),surface2=Color3.fromRGB(39,39,47),selection=Color3.fromRGB(52,52,62),stroke=Color3.fromRGB(58,58,68),scrollbar=Color3.fromRGB(70,70,82),icon=Color3.fromRGB(225,225,232),accent=Color3.fromRGB(88,88,102),text=Color3.fromRGB(240,240,245),muted=Color3.fromRGB(155,155,168)},
        Ocean={background=Color3.fromRGB(7,17,28),panel=Color3.fromRGB(12,27,43),surface=Color3.fromRGB(18,43,67),surface2=Color3.fromRGB(28,62,92),accent=Color3.fromRGB(55,155,255),text=Color3.fromRGB(240,240,245),muted=Color3.fromRGB(165,165,175)},
        Crimson={background=Color3.fromRGB(25,7,11),panel=Color3.fromRGB(42,12,18),surface=Color3.fromRGB(62,18,27),surface2=Color3.fromRGB(86,27,39),accent=Color3.fromRGB(235,65,70),text=Color3.fromRGB(240,240,245),muted=Color3.fromRGB(165,165,175)},
        Forest={background=Color3.fromRGB(6,20,13),panel=Color3.fromRGB(10,35,22),surface=Color3.fromRGB(16,52,32),surface2=Color3.fromRGB(24,73,44),accent=Color3.fromRGB(50,195,100),text=Color3.fromRGB(240,240,245),muted=Color3.fromRGB(165,165,175)},
        Violet={background=Color3.fromRGB(16,14,23),panel=Color3.fromRGB(24,22,34),surface=Color3.fromRGB(38,34,56),surface2=Color3.fromRGB(54,46,76),accent=Color3.fromRGB(145,90,235),text=Color3.fromRGB(240,240,245),muted=Color3.fromRGB(165,165,175)},
        Amber={background=Color3.fromRGB(26,17,5),panel=Color3.fromRGB(43,29,9),surface=Color3.fromRGB(63,43,14),surface2=Color3.fromRGB(87,60,20),accent=Color3.fromRGB(245,165,25),text=Color3.fromRGB(240,240,245),muted=Color3.fromRGB(165,165,175)},
    }
    state.themeColors={}; for name,palette in pairs(state.themePalettes) do state.themeColors[name]=palette.accent end
    local dock=create("Frame",{Name="LucidBottomDock",Size=UDim2.new(0,400,0,38),
        AnchorPoint=Vector2.new(0.5,1),Position=UDim2.new(0.5,0,1,-10),
        BackgroundColor3=Color3.fromRGB(17,17,22),BackgroundTransparency=0.12,
        BorderSizePixel=0,Active=true,Draggable=true,ZIndex=150,Parent=screenGui})
    state.lucidDock=dock
    create("UICorner",{CornerRadius=UDim.new(0,11),Parent=dock})
    state.lucidDockStroke=create("UIStroke",{Color=Color3.fromRGB(145,90,235),Thickness=1.2,Transparency=0.35,Parent=dock})
    local dragHandle=create("TextButton",{Name="DockDragHandle",Size=UDim2.new(0,42,0,4),
        AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.new(0.5,0,0,0),
        BackgroundColor3=Color3.fromRGB(82,58,145),BackgroundTransparency=0.15,BorderSizePixel=0,
        Text="",AutoButtonColor=false,Active=true,ZIndex=153,Parent=dock})
    create("UICorner",{CornerRadius=UDim.new(1,0),Parent=dragHandle})
    local stats=create("TextLabel",{Size=UDim2.new(0,106,0,17),Position=UDim2.new(0,8,0,2),Active=true,
        BackgroundTransparency=1,Text="● FPS --    ● PING --ms",TextColor3=Color3.fromRGB(205,205,215),
        TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,RichText=true,ZIndex=151,Parent=dock})
    local executorLabel=create("TextLabel",{Size=UDim2.new(0,66,0,14),Position=UDim2.new(0,8,0,20),Active=true,
        BackgroundTransparency=1,BorderSizePixel=0,Text="● Potassium",TextColor3=Color3.fromRGB(95,225,165),
        TextSize=8,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=151,Parent=dock})
    local brand=create("TextLabel",{Size=UDim2.new(0,38,0,14),Position=UDim2.new(0,72,0,20),Active=true,
        BackgroundTransparency=1,BorderSizePixel=0,
        Text="LUCID",TextColor3=Color3.fromRGB(225,225,232),TextSize=8,Font=Enum.Font.GothamSemibold,
        ZIndex=151,Parent=dock})
    local buttonData={
        {"rbxassetid://7733960981","Home"},{"rbxassetid://7743875962","Player"},
        {"rbxassetid://7743878358","Tools"},{"rbxassetid://7733954760","World"},
        {"rbxassetid://7733970318","Panel"},{"rbxassetid://7743872929","Command"},
        {"rbxassetid://7734053495","Settings"},
    }
    state.lucidDockButtons={}
    state.lucidDockIcons={}
    for index,item in ipairs(buttonData) do
        local button=create("ImageButton",{Size=UDim2.new(0,34,0,30),Position=UDim2.new(0,110+(index-1)*40,0,4),
            BackgroundColor3=Color3.fromRGB(28,27,34),BackgroundTransparency=1,BorderSizePixel=0,
            Image="",AutoButtonColor=false,ZIndex=151,Parent=dock})
        create("UICorner",{CornerRadius=UDim.new(0,6),Parent=button})
        local icon=create("ImageLabel",{Size=UDim2.new(0,15,0,15),AnchorPoint=Vector2.new(0.5,0.5),
            Position=UDim2.new(0.5,0,0.5,0),BackgroundTransparency=1,Image=item[1],
            ImageColor3=Color3.fromRGB(210,210,220),ScaleType=Enum.ScaleType.Fit,ZIndex=152,Parent=button})
        local tooltip=create("TextLabel",{Size=UDim2.new(0,70,0,20),AnchorPoint=Vector2.new(0.5,1),
            Position=UDim2.new(0.5,0,0,-4),BackgroundColor3=Color3.fromRGB(12,12,15),
            BackgroundTransparency=0.06,BorderSizePixel=0,Text=item[2],TextColor3=Color3.fromRGB(240,240,245),
            TextSize=9,Font=Enum.Font.GothamSemibold,Visible=false,ZIndex=160,Parent=button})
        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=tooltip})
        button.MouseEnter:Connect(function() tooltip.Visible=true end)
        button.MouseLeave:Connect(function() tooltip.Visible=false end)
        state.lucidDockButtons[item[2]]=button
        state.lucidDockIcons[item[2]]=icon
        button.MouseButton1Click:Connect(function()
            if item[2]=="Command" then
                if state.toggleCommandConsole then state.toggleCommandConsole() end
            elseif item[2]=="Panel" then
                mainFrame.Visible=not mainFrame.Visible
            else
                mainFrame.Visible=true
                state.mainNavigation.select(item[2])
            end
            if state.refreshLucidDock then state.refreshLucidDock() end
        end)
    end
    state.refreshLucidDock=function()
        local accent=state.themeIconColor or state.accentColor or state.themeColors.Violet
        for name,button in pairs(state.lucidDockButtons) do
            local selected=(name~="Panel" and name~="Command" and name==state.mainNavigation.active and mainFrame.Visible)
                or (name=="Command" and state.commandConsole and state.commandConsole.Visible)
            button.BackgroundTransparency=selected and 0.15 or 1
            local icon=state.lucidDockIcons[name]
            if icon then icon.ImageColor3=(selected or (name=="Panel" and mainFrame.Visible)) and accent
                    or (state.currentThemePalette and state.currentThemePalette.muted or Color3.fromRGB(205,205,215)) end
        end
    end
    local dockDragging=false
    local dockDragStart
    local dockStart
    local function beginDockDrag(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dockDragging=true; dockDragStart=input.Position; dockStart=dock.Position
        end
    end
    stats.InputBegan:Connect(beginDockDrag); executorLabel.InputBegan:Connect(beginDockDrag)
    brand.InputBegan:Connect(beginDockDrag)
    dragHandle.InputBegan:Connect(beginDockDrag)
    track(UserInputService.InputChanged:Connect(function(input)
        if dockDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local delta=input.Position-dockDragStart
            dock.Position=UDim2.new(dockStart.X.Scale,dockStart.X.Offset+delta.X,dockStart.Y.Scale,dockStart.Y.Offset+delta.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dockDragging=false end
    end))
    state.themeNewInstance=function(instance)
        local palette=state.currentThemePalette
        if not palette then return end
        if instance:IsA("GuiObject") then
            local role=instance:GetAttribute("LucidThemeBackgroundRole")
            if not role and instance.BackgroundTransparency<1 then
                local c=instance.BackgroundColor3
                local semantic=(c.R>c.G*1.45 and c.R>c.B*1.25) or (c.G>c.R*1.35 and c.G>c.B*1.15)
                if not semantic then
                    local brightness=(c.R+c.G+c.B)/3
                    role=brightness<0.09 and "background" or (brightness<0.17 and "panel" or (brightness<0.27 and "surface" or "surface2"))
                    instance:SetAttribute("LucidThemeBackgroundRole",role)
                end
            end
            if role and palette[role] then instance.BackgroundColor3=palette[role] end
            if instance:IsA("TextBox") then
                instance:SetAttribute("LucidThemeBackgroundRole","input")
                instance.BackgroundColor3=Color3.fromRGB(18,18,22)
                instance.BackgroundTransparency=0.05
            end
            if instance:IsA("ScrollingFrame") then instance.ScrollBarImageColor3=palette.scrollbar or palette.accent end
            if instance:IsA("ImageButton") or instance:IsA("ImageLabel") then
                instance:SetAttribute("LucidThemeIcon",true); instance.ImageColor3=palette.muted
            end
            if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
                local textRole=instance:GetAttribute("LucidThemeTextRole")
                local interactive=instance:IsA("TextBox") or instance:IsA("TextButton")
                if interactive then textRole="text"; instance:SetAttribute("LucidThemeTextRole",textRole)
                elseif not textRole then
                    local c=instance.TextColor3
                    local semantic=(c.R>c.G*1.5 and c.R>c.B*1.3) or (c.G>c.R*1.35 and c.G>c.B*1.1)
                    if not semantic then
                        textRole=(c.R+c.G+c.B)/3>0.62 and "text" or "muted"
                        instance:SetAttribute("LucidThemeTextRole",textRole)
                    end
                end
                if textRole then instance.TextColor3=palette[textRole] end
                if instance:IsA("TextBox") then
                    -- Inputs use neutral high-contrast colors regardless of
                    -- accent theme; tinted placeholders became hard to read.
                    instance.TextColor3=Color3.fromRGB(240,240,244)
                    instance.PlaceholderColor3=Color3.fromRGB(180,180,188)
                    instance.TextTransparency=0
                    instance.TextStrokeTransparency=1
                    instance.TextStrokeColor3=Color3.fromRGB(0,0,0)
                    instance.TextScaled=false
                    instance.TextSize=math.max(instance.TextSize,14)
                    instance.Font=Enum.Font.SourceSans
                end
            end
        elseif instance:IsA("UIStroke") then
            if instance.Parent and instance.Parent:IsA("TextBox") then
                instance:SetAttribute("LucidInputStroke",true)
                instance.Color=Color3.fromRGB(52,52,60)
                instance.Transparency=0.25
                return
            end
            local c=instance.Color
            local semantic=(c.R>c.G*1.5 and c.R>c.B*1.3) or (c.G>c.R*1.35 and c.G>c.B*1.1)
            if not semantic then instance:SetAttribute("LucidThemeStroke",true) end
            if instance:GetAttribute("LucidThemeStroke") then instance.Color=palette.stroke or palette.accent end
        end
    end
    state.applyAccentTheme=function(name)
        if not state.themePalettes[name] then name="Midnight" end
        local palette=state.themePalettes[name]
        state.accentTheme=name; state.accentColor=palette.accent; state.themeIconColor=palette.icon or palette.accent; state.currentThemePalette=palette
        for _,instance in ipairs(screenGui:GetDescendants()) do state.themeNewInstance(instance) end
        mainFrame.BackgroundColor3=palette.background; dock.BackgroundColor3=palette.background
        mainStroke.Color=palette.stroke or palette.accent; state.lucidDockStroke.Color=palette.stroke or palette.accent
        if state.mainTitle then state.mainTitle.TextColor3=state.accentColor:Lerp(Color3.new(1,1,1),0.35) end
        if state.opacityFill then state.opacityFill.BackgroundColor3=state.accentColor end
        state.mainNavigation.apply(); state.refreshLucidDock()
        if state.accentThemeLabel then state.accentThemeLabel.Text="Theme: "..name end
    end
    local frames=0
    local elapsed=0
    local function metricHex(value,low,mid,high,higherIsBetter)
        local red=Color3.fromRGB(235,70,80)
        local yellow=Color3.fromRGB(235,190,65)
        local green=Color3.fromRGB(75,225,135)
        local color
        if higherIsBetter then
            if value<=low then color=red elseif value>=high then color=green
            elseif value<=mid then color=red:Lerp(yellow,(value-low)/(mid-low))
            else color=yellow:Lerp(green,(value-mid)/(high-mid)) end
        else
            if value<=low then color=green elseif value>=high then color=red
            elseif value<=mid then color=green:Lerp(yellow,(value-low)/(mid-low))
            else color=yellow:Lerp(red,(value-mid)/(high-mid)) end
        end
        return string.format("#%02X%02X%02X",math.floor(color.R*255+0.5),math.floor(color.G*255+0.5),math.floor(color.B*255+0.5))
    end
    track(RunService.RenderStepped:Connect(function(dt)
        frames=frames+1; elapsed=elapsed+dt
        if elapsed<0.5 then return end
        local fps=math.floor(frames/elapsed+0.5); frames=0; elapsed=0
        local ping=0
        pcall(function() ping=math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()+0.5) end)
        local fpsColor=metricHex(fps,60,180,300,true)
        local pingColor=metricHex(ping,1,150,300,false)
        stats.Text=string.format('<font color="%s">● FPS %d</font>    <font color="%s">● PING %dms</font>',fpsColor,fps,pingColor,ping)
    end))
    track(mainFrame:GetPropertyChangedSignal("Visible"):Connect(state.refreshLucidDock))
    state.applyAccentTheme(state.accentTheme)
end
state.initializeLucidDock()

local searchRow = create("Frame", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
    LayoutOrder = -20, Parent = content,
})
local searchBox = create("TextBox", {
    Size = UDim2.new(1, -94, 0, 26), BackgroundColor3 = Color3.fromRGB(38, 36, 52),
    BorderSizePixel = 0, Text = "", PlaceholderText = "Search tools...",
    TextColor3 = Color3.fromRGB(230, 225, 245), PlaceholderColor3 = Color3.fromRGB(120, 110, 150),
    TextSize = 12, Font = Enum.Font.Gotham, ClearTextOnFocus = true, Parent = searchRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = searchBox })
local collapseBtn = create("TextButton", {
    Size = UDim2.new(0, 86, 0, 26), Position = UDim2.new(1, -86, 0, 0),
    BackgroundColor3 = Color3.fromRGB(50, 45, 70), BorderSizePixel = 0,
    Text = "Expand all", TextColor3 = Color3.fromRGB(205, 195, 235),
    TextSize = 10, Font = Enum.Font.GothamSemibold, Parent = searchRow,
})
create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = collapseBtn })
local searchResults=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=false,LayoutOrder=-19,Parent=content})
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3),Parent=searchResults})
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
    for _,child in ipairs(searchResults:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    searchResults.Visible=query~=""
    local resultCount=0
    for name, meta in pairs(categoryMeta) do
        meta.wrapper.Visible = query == "" and (state.mainNavigation.groups[state.mainNavigation.active] or {})[name]==true
            or query~="" and categoryMatches(name, meta.body, query)
        if query ~= "" and meta.wrapper.Visible then meta.setOpen(true) end
        if query~="" and resultCount<8 then
            for _,item in ipairs(meta.body:GetDescendants()) do
                if resultCount>=8 then break end
                if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
                    local label=(item.Text~="" and item.Text or (item:IsA("TextBox") and item.PlaceholderText or ""))
                    if label~="" and label:lower():find(query,1,true) then
                        resultCount=resultCount+1
                        local resultMeta=meta
                        local resultCategory=name
                        local result=create("TextButton",{Size=UDim2.new(1,0,0,24),BackgroundColor3=Color3.fromRGB(46,40,64),
                            BorderSizePixel=0,Text="["..name.."]  "..label,TextColor3=Color3.fromRGB(225,215,240),
                            TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
                            LayoutOrder=resultCount,Parent=searchResults})
                        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=result})
                        create("UIPadding",{PaddingLeft=UDim.new(0,7),Parent=result})
                        result.MouseButton1Click:Connect(function()
                            state.mainNavigation.select(state.mainNavigation.categoryGroup[resultCategory] or "Home")
                            resultMeta.setOpen(true); searchBox.Text=""
                            task.defer(function()
                                local target=resultMeta.wrapper.AbsolutePosition.Y-content.AbsolutePosition.Y+content.CanvasPosition.Y
                                content.CanvasPosition=Vector2.new(0,math.max(0,target))
                            end)
                        end)
                    end
                end
            end
        end
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
    local palette=state.currentThemePalette
    local box = create("TextBox", {
        BackgroundColor3       = Color3.fromRGB(18,18,22),
        BackgroundTransparency = 0.05,
        TextColor3             = Color3.fromRGB(240,240,244),
        PlaceholderColor3      = Color3.fromRGB(180,180,188),
        TextSize               = 14,
        Font                   = Enum.Font.SourceSans,
        BorderSizePixel        = 0,
        ClearTextOnFocus       = true,
        Parent                 = parent,
    })
    for k, v in pairs(props) do box[k] = v end
    -- Keep every writable field readable even if a caller supplies legacy
    -- violet styling or the active theme changes later.
    box.BackgroundColor3=Color3.fromRGB(18,18,22)
    box.BackgroundTransparency=0.05
    box.TextColor3=Color3.fromRGB(240,240,244)
    box.PlaceholderColor3=Color3.fromRGB(180,180,188)
    box.TextTransparency=0
    box.TextStrokeTransparency=1
    box.TextStrokeColor3=Color3.fromRGB(0,0,0)
    box.TextScaled=false
    box.TextSize=math.max(box.TextSize,14)
    box.Font=Enum.Font.SourceSans
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
    box:SetAttribute("LucidThemeBackgroundRole","input")
    box:SetAttribute("LucidThemeTextRole","text")
    local inputStroke=create("UIStroke", { Color=Color3.fromRGB(52,52,60),Transparency=0.25,Thickness=1,Parent=box })
    inputStroke:SetAttribute("LucidInputStroke",true)
    return box
end

local layoutOrder = 0
local function nextOrder()
    layoutOrder = layoutOrder + 1
    return layoutOrder
end

-- Favorites live in their own function scope to stay below executor register
-- limits. Only the registration closure remains in the root chunk.
local favoriteRegistry = {}
local favoriteStatusRegistry = {}
local activeFeatures = {}
state.featureNavigationGroups={}
state.refreshNavigationCounts=function()
    local counts={Home=0,Player=0,World=0,Tools=0,Settings=0}
    for name,enabled in pairs(activeFeatures) do
        local group=state.featureNavigationGroups[name]
        if enabled and group then counts[group]=(counts[group] or 0)+1 end
    end
    for name,button in pairs(state.mainNavigation.buttons) do
        local count=counts[name] or 0; button.Text=name..(count>0 and (" · "..count) or "")
    end
end
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
        Name="LucidPinnedFavoritesWindow", Size=UDim2.new(0,250,0,300),
        Position=UDim2.new(0.5,170,0.5,-150), BackgroundColor3=Color3.fromRGB(24,22,34),
        BackgroundTransparency=0.15, BorderSizePixel=0, Active=true, Draggable=true,
        Visible=false, Parent=screenGui,
    })
    create("UICorner", { CornerRadius=UDim.new(0,9), Parent=dock })
    create("UIStroke", { Color=Color3.fromRGB(115,85,190), Thickness=1.3, Parent=dock })
    create("TextLabel", {
        Size=UDim2.new(1,-104,0,34), Position=UDim2.new(0,10,0,0), BackgroundTransparency=1,
        Text="★  Lucid Favorites", TextColor3=Color3.fromRGB(255,215,70), TextSize=14,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=dock,
    })
    local attachButton=create("TextButton", {
        Size=UDim2.new(0,28,0,26), Position=UDim2.new(1,-32,0,4), BackgroundColor3=Color3.fromRGB(105,65,75),
        BorderSizePixel=0, Text="X", TextColor3=Color3.fromRGB(255,240,245), TextSize=12,
        Font=Enum.Font.GothamBold, Parent=dock,
    })
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=attachButton })
    local pinned=false
    local pinButton=create("TextButton",{
        Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-96,0,4),BackgroundColor3=Color3.fromRGB(65,58,85),
        BorderSizePixel=0,Text="Pin",TextColor3=Color3.fromRGB(220,210,235),TextSize=9,
        Font=Enum.Font.GothamSemibold,Parent=dock,
    })
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=pinButton})
    local function setPinned(value)
        pinned=value==true; pinButton.Text=pinned and "ON" or "Pin"
        pinButton.BackgroundColor3=pinned and Color3.fromRGB(150,115,45) or Color3.fromRGB(65,58,85)
    end
    pinButton.MouseButton1Click:Connect(function() setPinned(not pinned) end)
    local dockCollapse=create("TextButton",{Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-64,0,4),
        BackgroundColor3=Color3.fromRGB(65,58,85),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
        TextSize=14,Font=Enum.Font.GothamBold,Parent=dock})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=dockCollapse})
    local dockContent=create("ScrollingFrame", {
        Size=UDim2.new(1,-16,1,-44), Position=UDim2.new(0,8,0,38), BackgroundTransparency=1,
        BorderSizePixel=0, ScrollBarThickness=3, AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.new(), Parent=dock,
    })
    makeResizableWindow(dock,210,120)

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
    local dockExpanded=true
    dockCollapse.MouseButton1Click:Connect(function()
        dockExpanded=not dockExpanded; dockContent.Visible=dockExpanded
        dock.Size=dockExpanded and UDim2.new(0,250,0,300) or UDim2.new(0,250,0,34)
        dockCollapse.Text=dockExpanded and "-" or "+"
    end)
    registerDetachableWindow(dock,function() return pinned end,function() return detached end,setPinned,setDetached)

    return function(label, trigger, sourceRow)
        local starred=false
        local favoriteEntry=nil
        local favoriteCheck=nil
        local function refreshFavoriteCheck(enabled)
            if favoriteCheck then favoriteCheck.Visible=enabled==true end
        end
        favoriteStatusRegistry[label]=refreshFavoriteCheck
        local starX=sourceRow:GetAttribute("LucidFavoriteStarX")
        if type(starX)~="number" then starX=math.min(190,8+#label*6.3) end
        local star=create("TextButton", {
            Size=UDim2.new(0,24,0,24), Position=UDim2.new(0,starX,0.5,-12),
            BackgroundTransparency=1, BorderSizePixel=0, Text="☆",
            TextColor3=Color3.fromRGB(145,135,165), TextSize=18,
            Font=Enum.Font.GothamBold, ZIndex=8, Parent=sourceRow,
        })
        local function setStar(value)
            if starred==value then return end
            starred=not starred
            state.favoriteNames[label]=starred or nil
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
                favoriteCheck=create("TextLabel",{Size=UDim2.new(0,24,1,0),Position=UDim2.new(1,-28,0,0),
                    BackgroundTransparency=1,Text="✓",TextColor3=Color3.fromRGB(75,225,120),
                    TextSize=17,Font=Enum.Font.GothamBold,ZIndex=3,Visible=activeFeatures[label]==true,
                    Parent=favoriteEntry})
                favoriteEntry.MouseButton1Click:Connect(function()
                    -- Run after the GUI click releases so mouse-lock/shift-lock
                    -- input state is identical to using the original control.
                    task.defer(trigger)
                end)
            else
                favoriteCount=math.max(0,favoriteCount-1)
                if favoriteEntry then favoriteEntry:Destroy(); favoriteEntry=nil end
                favoriteCheck=nil
                emptyLabel.Visible=favoriteCount==0
            end
        end
        star.MouseButton1Click:Connect(function() setStar(not starred) end)
        favoriteRegistry[label]=setStar
        if state.favoriteNames[label] then task.defer(function() setStar(true) end) end
    end
end)()

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
    row:SetAttribute("LucidFavoriteStarX",math.min(190,8+#labelText*6.3))
    for categoryName,body in pairs(categories) do
        if row:IsDescendantOf(body) then
            state.featureNavigationGroups[labelText]=state.mainNavigation.categoryGroup[categoryName]
            break
        end
    end

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
        state.refreshNavigationCounts()
        if favoriteStatusRegistry[labelText] then favoriteStatusRegistry[labelText](enabled) end
        refreshFeatureStatus()
        if callback then callback(enabled) end
    end

    local function fireToggle()
        setToggle(not enabled)
    end

    btn.MouseButton1Click:Connect(fireToggle)
    registerFavorite(labelText, fireToggle, row)

    toggleRegistry[labelText] = setToggle
    activeFeatures[labelText] = default == true
    state.refreshNavigationCounts()
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
    local changeCallback = nil
    local btn = create("TextButton", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = "",
        Parent                 = toggleBg,
    })

    local function toggle(callback)
        changeCallback = callback
        btn.MouseButton1Click:Connect(function()
            enabled = not enabled
            toggleBg.BackgroundColor3 = enabled and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70)
            knob.Position = enabled and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            if changeCallback then changeCallback(enabled) end
        end)
    end

    local function setInline(value)
        enabled=value==true
        toggleBg.BackgroundColor3=enabled and Color3.fromRGB(80,200,120) or Color3.fromRGB(60,60,70)
        knob.Position=enabled and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)
        if changeCallback then changeCallback(enabled) end
    end
    return toggle, function() return enabled end, setInline
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
    Size              = UDim2.new(0.9, 0, 1, 0),
    BackgroundColor3  = Color3.fromRGB(130, 90, 230),
    BorderSizePixel   = 0,
    Parent            = opacSlider,
})
state.opacityFill=opacFill
create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = opacFill })

local opacBox = styledBox(opacRow, {
    Size     = UDim2.new(0, 55, 0, 24),
    Position = UDim2.new(1, -55, 0.5, -12),
    Text     = "90%",
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
        setOpacity(90)
    end
end)

setOpacity(90) -- opaque black starter appearance from the v5 reference

sectionLabel("Interface Theme",nextOrder())
state.accentThemeLabel=create("TextLabel",{Size=UDim2.new(1,0,0,20),BackgroundTransparency=1,
    Text="Theme: "..tostring(state.accentTheme),TextColor3=Color3.fromRGB(210,205,225),
    TextSize=10,Font=Enum.Font.GothamSemibold,TextXAlignment=Enum.TextXAlignment.Left,
    LayoutOrder=nextOrder(),Parent=currentSection})
state.initializeAccentThemeControls=function()
    for rowIndex,names in ipairs({{"Midnight","Ocean","Crimson"},{"Forest","Violet","Amber"}}) do
        local row=rowFrame(nextOrder(),28)
        for index,name in ipairs(names) do
            local color=state.themeColors[name]
            local button=create("TextButton",{Size=UDim2.new(0.32,0,0,25),Position=UDim2.new((index-1)*0.34,0,0,1),
                BackgroundColor3=color,BackgroundTransparency=0.12,BorderSizePixel=0,Text=name,
                TextColor3=name=="Midnight" and Color3.fromRGB(30,30,36) or Color3.new(1,1,1),
                TextSize=9,Font=Enum.Font.GothamSemibold,Parent=row})
            create("UICorner",{CornerRadius=UDim.new(0,5),Parent=button})
            button.MouseButton1Click:Connect(function() state.applyAccentTheme(name) end)
        end
    end
    state.applyAccentTheme(state.accentTheme)
end
state.initializeAccentThemeControls()

sectionLabel("Frame Rate",nextOrder())
state.initializeFPSUnlock=function()
    local row=rowFrame(nextOrder(),30)
    create("TextLabel",{Size=UDim2.new(1,-80,1,0),BackgroundTransparency=1,Text="FPS limit",
        TextColor3=state.currentThemePalette and state.currentThemePalette.text or Color3.fromRGB(210,205,225),
        TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=row})
    local box=styledBox(row,{Size=UDim2.new(0,72,0,25),Position=UDim2.new(1,-72,0.5,-12),Text=tostring(state.fpsCapValue)})
    local status=create("TextLabel",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,
        Text="FPS cap ready",TextColor3=Color3.fromRGB(145,190,160),TextSize=10,
        Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=nextOrder(),Parent=currentSection})
    local function getSetter()
        local environment=(getgenv and getgenv()) or _G
        return environment.setfpscap or environment.set_fps_cap or environment.set_fpscap
    end
    local function applyCap(value)
        local setter=getSetter()
        if type(setter)~="function" then
            status.Text="FPS unlock unavailable in this executor"
            status.TextColor3=Color3.fromRGB(230,105,115)
            return false
        end
        local ok,err=pcall(setter,value)
        status.Text=ok and (value==240 and "Roblox 240 FPS cap restored" or ("FPS cap set to "..value))
            or ("FPS cap failed: "..tostring(err))
        status.TextColor3=ok and Color3.fromRGB(90,220,135) or Color3.fromRGB(230,105,115)
        return ok
    end
    local function readValue()
        state.fpsCapValue=math.clamp(math.floor((tonumber(box.Text) or state.fpsCapValue)+0.5),30,1000)
        box.Text=tostring(state.fpsCapValue)
        if state.fpsCapEnabled then applyCap(state.fpsCapValue) end
    end
    box.FocusLost:Connect(readValue)
    state.setFPSCapValue=function(value)
        state.fpsCapValue=math.clamp(math.floor((tonumber(value) or state.fpsCapValue)+0.5),30,1000)
        box.Text=tostring(state.fpsCapValue)
        if state.fpsCapEnabled then applyCap(state.fpsCapValue) end
    end
    local _,_,setter=createToggle("FPS Unlock / Custom Cap",nextOrder(),true,function(on)
        state.fpsCapEnabled=on
        if on then readValue() else applyCap(240) end
    end)
    state.setFPSCapEnabled=setter
    -- Apply the default immediately; createToggle reflects its default visually
    -- but intentionally does not invoke callbacks during construction.
    setter(true)
    addCleanup(function() if state.fpsCapEnabled then applyCap(240) end end)
end
state.initializeFPSUnlock()

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

local wsToggle, wsGetLocked, wsSetLocked = createInlineToggle(wsRow, false)
toggleRegistry["Lock WalkSpeed"]=wsSetLocked
activeFeatures["Lock WalkSpeed"]=false
wsToggle(function(on)
    state.walkspeedLocked = on
    activeFeatures["Lock WalkSpeed"]=on; refreshFeatureStatus()
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

local jhToggle, jhGetLocked, jhSetLocked = createInlineToggle(jhRow, false)
toggleRegistry["Lock Jump Height"]=jhSetLocked
activeFeatures["Lock Jump Height"]=false
jhToggle(function(on)
    activeFeatures["Lock Jump Height"]=on; refreshFeatureStatus()
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
local flingSettingsRow=rowFrame(nextOrder(),30)
local flingLinearBox=styledBox(flingSettingsRow,{Size=UDim2.new(0,112,0,24),Text="250",PlaceholderText="Linear limit"})
local flingAngularBox=styledBox(flingSettingsRow,{Size=UDim2.new(0,112,0,24),Position=UDim2.new(1,-112,0,0),Text="100",PlaceholderText="Angular limit"})
flingLinearBox.FocusLost:Connect(function()
    state.antiFlingLinear=math.clamp(tonumber(flingLinearBox.Text) or state.antiFlingLinear,25,1000)
    flingLinearBox.Text=tostring(state.antiFlingLinear)
end)
flingAngularBox.FocusLost:Connect(function()
    state.antiFlingAngular=math.clamp(tonumber(flingAngularBox.Text) or state.antiFlingAngular,10,1000)
    flingAngularBox.Text=tostring(state.antiFlingAngular)
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

createToggle("Mobile Freeze / Anti Push", nextOrder(), false, function(on)
    state.antiPushEnabled = on
    if on and state.freezeEnabled and toggleRegistry["Freeze Me"] then
        toggleRegistry["Freeze Me"](false)
        notifyLucid("Compatibility manager","Freeze Me suspended because Anti-Push was enabled",Color3.fromRGB(235,175,70))
    end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = false
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end)
local antiPushStrengthButton=create("TextButton",{
    Size=UDim2.new(1,0,0,26),BackgroundColor3=Color3.fromRGB(54,46,76),BorderSizePixel=0,
    Text="Anti Push Strength: Normal",TextColor3=Color3.fromRGB(225,215,240),TextSize=11,
    Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection,
})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=antiPushStrengthButton})
antiPushStrengthButton.MouseButton1Click:Connect(function()
    local nextStrength={Light="Normal",Normal="Strict",Strict="Light"}
    state.antiPushStrength=nextStrength[state.antiPushStrength]
    antiPushStrengthButton.Text="Anti Push Strength: "..state.antiPushStrength
end)
create("TextLabel",{Size=UDim2.new(1,0,0,18),BackgroundTransparency=1,
    Text="Hold B to temporarily bypass physics protection",TextColor3=Color3.fromRGB(155,145,175),
    TextSize=10,Font=Enum.Font.Gotham,LayoutOrder=nextOrder(),Parent=currentSection})
track(UserInputService.InputBegan:Connect(function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.B then state.physicsBypass=true end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode==Enum.KeyCode.B then state.physicsBypass=false end
end))

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

local zoomToggle, zoomGetLocked, zoomSetLocked = createInlineToggle(zoomRow, false)
toggleRegistry["Lock Max Zoom"]=zoomSetLocked
activeFeatures["Lock Max Zoom"]=false
zoomToggle(function(on)
    state.maxZoomLocked = on
    activeFeatures["Lock Max Zoom"]=on; refreshFeatureStatus()
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

useCategory("Teleport & Coordinates")
sectionLabel("Click Teleport", nextOrder())
createToggle("Left Alt + Click TP", nextOrder(), true, function(on)
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
--  SECTION 7 ─ AUTOCLICK modes + Keybind
-- ════════════════════════════════════════════════════════════
sectionLabel("AutoClick", nextOrder())

local _, acFireToggle = createToggle("Enable AutoClick", nextOrder(), false, function(on)
    state.autoclickEnabled = on
end)
local autoclickModeButton=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(54,46,76),
    BorderSizePixel=0,Text="AutoClick Mode: Hybrid",TextColor3=Color3.fromRGB(225,215,240),TextSize=11,
    Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=autoclickModeButton})
autoclickModeButton.MouseButton1Click:Connect(function()
    local nextMode={Hybrid="Mouse",Mouse="Tool",Tool="Center",Center="Hybrid"}
    state.autoclickMode=nextMode[state.autoclickMode] or "Hybrid"
    autoclickModeButton.Text="AutoClick Mode: "..state.autoclickMode
end)
createToggle("AutoClick Avoid GUI Buttons",nextOrder(),true,function(on)
    state.autoclickAvoidGui=on
end)
local autoclickIntervalRow=rowFrame(nextOrder(),28)
create("TextLabel",{Size=UDim2.new(1,-88,1,0),BackgroundTransparency=1,Text="Interval (ms, min 1)",
    TextColor3=Color3.fromRGB(190,180,205),TextSize=11,Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=autoclickIntervalRow})
local autoclickIntervalBox=styledBox(autoclickIntervalRow,{Size=UDim2.new(0,80,0,24),Position=UDim2.new(1,-80,0.5,-12),
    Text="1",PlaceholderText="1 ms"})
autoclickIntervalBox.FocusLost:Connect(function()
    local milliseconds=math.clamp(tonumber(autoclickIntervalBox.Text) or state.autoclickInterval*1000,1,60000)
    state.autoclickInterval=milliseconds/1000
    autoclickIntervalBox.Text=string.format("%.3g",milliseconds)
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

-- IY goto, grouped with Lucid's other character/location teleport tools.
local gotoApi={}
state.yellowHighlightApi={}
state.pinkHighlightApi={}
state.pinkHighlightNames={}
state.blackHighlightApi={}
state.blackHighlightNames={}
local function initializeTeleportAndESP()
useCategory("Teleport & Coordinates")
local teleportCategory=categories["Teleport & Coordinates"]
local detachGotoRow=rowFrame(nextOrder(),30)
local detachGotoButton=create("TextButton",{Size=UDim2.new(1,0,0,26),BackgroundColor3=Color3.fromRGB(65,52,95),
    BorderSizePixel=0,Text="Detach Go To Window",TextColor3=Color3.fromRGB(235,225,250),
    TextSize=11,Font=Enum.Font.GothamSemibold,Parent=detachGotoRow})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=detachGotoButton})
local gotoAttachedHost=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,LayoutOrder=nextOrder(),Parent=currentSection})
local gotoTools=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Parent=gotoAttachedHost})
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,7),Parent=gotoTools})
currentSection=gotoTools
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
gotoApi.find=findGotoPlayer
gotoApi.box=gotoBox

local gotoBusy = false
local gotoOffset=Vector3.new(state.gotoOffsetX,state.gotoOffsetY,state.gotoOffsetZ)
local previousTeleportCFrame=nil
local recentGotoPlayers={}
local gotoOffsetRow=rowFrame(nextOrder(),28)
create("TextLabel",{Size=UDim2.new(0,78,1,0),BackgroundTransparency=1,Text="Offset X,Y,Z",
    TextColor3=Color3.fromRGB(185,175,205),TextSize=10,Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=gotoOffsetRow})
local gotoOffsetBox=styledBox(gotoOffsetRow,{Size=UDim2.new(1,-84,0,24),Position=UDim2.new(0,84,0.5,-12),Text="3, 1, 0"})
gotoApi.setOffset=function(x,y,z)
    gotoOffset=Vector3.new(x,y,z)
    state.gotoOffsetX,state.gotoOffsetY,state.gotoOffsetZ=x,y,z
    gotoOffsetBox.Text=string.format("%g, %g, %g",x,y,z)
end
gotoOffsetBox.FocusLost:Connect(function()
    local x,y,z=gotoOffsetBox.Text:match("^%s*([%+%-%.%d]+)%s*,%s*([%+%-%.%d]+)%s*,%s*([%+%-%.%d]+)%s*$")
    if tonumber(x) and tonumber(y) and tonumber(z) then
        gotoApi.setOffset(tonumber(x),tonumber(y),tonumber(z))
    end
    gotoOffsetBox.Text=string.format("%g, %g, %g",gotoOffset.X,gotoOffset.Y,gotoOffset.Z)
end)
local function goToRequestedPlayer()
    if gotoBusy then return end
    local target = gotoApi.find(gotoApi.box.Text)
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
                previousTeleportCFrame=root.CFrame
                root.CFrame = targetRoot:GetPivot() + gotoOffset
                clearCharacterVelocity(character)
                table.insert(recentGotoPlayers,1,target.Name)
                while #recentGotoPlayers>5 do table.remove(recentGotoPlayers) end
                gotoBtn.Text = "Done"
            end
        end
        task.delay(1, function() if gotoBtn.Parent then gotoBtn.Text = "Go To" end end)
        gotoBusy = false
    end)
end

gotoBtn.MouseButton1Click:Connect(goToRequestedPlayer)
registerFavorite("Go To Player", goToRequestedPlayer, gotoRow)
gotoBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then goToRequestedPlayer() end
end)
local returnRow=rowFrame(nextOrder(),30)
local returnButtonWidth=math.min(260,math.max(58,24+#"Return to Previous Position"*6.6))
returnRow:SetAttribute("LucidFavoriteStarX",returnButtonWidth-27)
local returnButton=create("TextButton",{Size=UDim2.new(0,returnButtonWidth,0,26),BackgroundColor3=Color3.fromRGB(62,52,92),
    BorderSizePixel=0,Text="Return to Previous Position",TextColor3=Color3.fromRGB(235,230,245),
    TextSize=11,Font=Enum.Font.GothamSemibold,TextXAlignment=Enum.TextXAlignment.Left,Parent=returnRow})
create("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,30),Parent=returnButton})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=returnButton})
local function returnPreviousPosition()
    local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root and previousTeleportCFrame then
        local current=root.CFrame; root.CFrame=previousTeleportCFrame; previousTeleportCFrame=current
        clearCharacterVelocity(LocalPlayer.Character)
    else
        returnButton.Text="No previous position"; task.delay(1,function() if returnButton.Parent then returnButton.Text="Return to Previous Position" end end)
    end
end
returnButton.MouseButton1Click:Connect(returnPreviousPosition)
registerFavorite("Return Position",returnPreviousPosition,returnRow)
local recentGotoLabel=create("TextLabel",{Size=UDim2.new(1,0,0,18),BackgroundTransparency=1,
    Text="Recent players appear after Go To",TextColor3=Color3.fromRGB(145,135,165),TextSize=10,
    Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=nextOrder(),Parent=currentSection})
gotoBox:GetPropertyChangedSignal("Text"):Connect(function()
    if gotoBox.Text=="" and #recentGotoPlayers>0 then recentGotoLabel.Text="Recent: "..table.concat(recentGotoPlayers,", ") end
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
                    root.CFrame = targetRoot.CFrame + gotoOffset
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
gotoApi.go=function(name) gotoApi.box.Text=tostring(name or ""); goToRequestedPlayer() end
gotoApi.returnPrevious=returnPreviousPosition
gotoApi.setLoop=function(name,on)
    if name and tostring(name)~="" then gotoApi.box.Text=tostring(name) end
    local setter=toggleRegistry["Loop Go To (uses player above)"]
    if setter then setter(on==true) end
end
state.gotoApi=gotoApi
addCleanup(function()
    state.loopGotoEnabled = false
    loopGotoGeneration = loopGotoGeneration + 1
    loopGotoTarget = nil
end)

-- IY-style player ESP: BoxHandleAdornment per body part plus an always-on-top
-- name and distance label. Selected mode supports any number of chosen players.
currentSection=teleportCategory
local gotoDock=create("Frame",{Name="LucidGotoWindow",Size=UDim2.new(0,285,0,290),
    Position=UDim2.new(0.5,-460,0.5,-145),BackgroundColor3=Color3.fromRGB(24,22,34),
    BackgroundTransparency=0.12,BorderSizePixel=0,Active=true,Draggable=true,Visible=false,Parent=screenGui})
create("UICorner",{CornerRadius=UDim.new(0,9),Parent=gotoDock})
create("UIStroke",{Color=Color3.fromRGB(115,85,190),Thickness=1.3,Parent=gotoDock})
create("TextLabel",{Size=UDim2.new(1,-112,0,34),Position=UDim2.new(0,10,0,0),BackgroundTransparency=1,
    Text="Lucid Go To",TextColor3=Color3.fromRGB(210,190,255),TextSize=14,Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=gotoDock})
local gotoPin=false
local gotoPinButton=create("TextButton",{Size=UDim2.new(0,32,0,26),Position=UDim2.new(1,-104,0,4),
    BackgroundColor3=Color3.fromRGB(65,58,85),BorderSizePixel=0,Text="Pin",TextColor3=Color3.fromRGB(225,215,235),
    TextSize=9,Font=Enum.Font.GothamSemibold,Parent=gotoDock})
local gotoAttachButton=create("TextButton",{Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-32,0,4),
    BackgroundColor3=Color3.fromRGB(105,65,75),BorderSizePixel=0,Text="X",TextColor3=Color3.new(1,1,1),
    TextSize=11,Font=Enum.Font.GothamBold,Parent=gotoDock})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=gotoPinButton}); create("UICorner",{CornerRadius=UDim.new(0,6),Parent=gotoAttachButton})
local gotoCollapseButton=create("TextButton",{Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-68,0,4),
    BackgroundColor3=Color3.fromRGB(65,58,85),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
    TextSize=14,Font=Enum.Font.GothamBold,Parent=gotoDock})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=gotoCollapseButton})
local gotoDockContent=create("ScrollingFrame",{Size=UDim2.new(1,-16,1,-44),Position=UDim2.new(0,8,0,38),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(),Parent=gotoDock})
makeResizableWindow(gotoDock,235,140)
local gotoDetached=false
local function setGotoDetached(value)
    gotoDetached=value
    gotoTools.Parent=value and gotoDockContent or gotoAttachedHost
    gotoDock.Visible=value
    detachGotoButton.Text=value and "Go To Detached" or "Detach Go To Window"
end
detachGotoButton.MouseButton1Click:Connect(function() setGotoDetached(not gotoDetached) end)
gotoAttachButton.MouseButton1Click:Connect(function() setGotoDetached(false) end)
local function setGotoPinned(value)
    gotoPin=value==true; gotoPinButton.Text=gotoPin and "ON" or "Pin"
    gotoPinButton.BackgroundColor3=gotoPin and Color3.fromRGB(150,115,45) or Color3.fromRGB(65,58,85)
end
gotoPinButton.MouseButton1Click:Connect(function() setGotoPinned(not gotoPin) end)
local gotoDockExpanded=true
gotoCollapseButton.MouseButton1Click:Connect(function()
    gotoDockExpanded=not gotoDockExpanded; gotoDockContent.Visible=gotoDockExpanded
    gotoDock.Size=gotoDockExpanded and UDim2.new(0,285,0,290) or UDim2.new(0,285,0,34)
    gotoCollapseButton.Text=gotoDockExpanded and "-" or "+"
end)
registerDetachableWindow(gotoDock,function() return gotoPin end,function() return gotoDetached end,setGotoPinned,setGotoDetached)
addCleanup(function() setGotoDetached(false) end)

local function initializePlayerESP()
    useCategory("Player")
    sectionLabel("Player ESP", nextOrder())

    local function highlightColor(hex,fallback)
        local clean=tostring(hex or ""):gsub("#","")
        local value=#clean==6 and tonumber(clean,16) or nil
        if not value then return fallback end
        return Color3.fromRGB(math.floor(value/65536)%256,math.floor(value/256)%256,value%256)
    end

    local mode = "off"
    local holders = {}
    local selectedPlayers = {}
    local espTransparency = state.espTransparency
    local espMaxDistance=state.espMaxDistance
    local espShowDetails=true
    local espHideDead=true
    local espUseHighlight=false
    local yellowNames={}
    local running = true
    local setAll
    local setTarget
    local setEnemy
    local setHighlight
    local switchingEspMode=false
    local restoreHighlightAfterAll=false

    local selectRow = rowFrame(nextOrder(), 30)
    local selectBox = styledBox(selectRow, {
        Size=UDim2.new(1,-72,0,26), Position=UDim2.new(0,0,0.5,-13),
        Text="", PlaceholderText="Player name to ESP...",
    })
    local addSelectedButton = create("TextButton", {
        Size=UDim2.new(0,30,0,26), Position=UDim2.new(1,-64,0.5,-13),
        BackgroundColor3=Color3.fromRGB(70,120,80), BorderSizePixel=0, Text="+",
        TextColor3=Color3.fromRGB(245,255,245), TextSize=18, Font=Enum.Font.GothamBold,
        Parent=selectRow,
    })
    create("UICorner", { CornerRadius=UDim.new(0,6), Parent=addSelectedButton })
    local removeSelectedButton=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-30,0.5,-13),
        BackgroundColor3=Color3.fromRGB(120,65,70),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=selectRow})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=removeSelectedButton})
    local selectedStatus = create("TextLabel", {
        Size=UDim2.new(1,-58,0,24), BackgroundTransparency=1, Text="Selected: none",
        TextColor3=Color3.fromRGB(175,165,195), TextSize=10, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
        LayoutOrder=nextOrder(), Parent=currentSection,
    })
    local clearSelectedButton = create("TextButton", {
        Size=UDim2.new(0,52,0,22), Position=UDim2.new(1,-52,0,0),
        BackgroundColor3=Color3.fromRGB(75,48,62), BorderSizePixel=0, Text="Clear",
        TextColor3=Color3.fromRGB(235,215,225), TextSize=10, Font=Enum.Font.GothamSemibold,
        Parent=selectedStatus,
    })
    create("UICorner", { CornerRadius=UDim.new(0,5), Parent=clearSelectedButton })

    local transparencyRow = rowFrame(nextOrder(), 28)
    create("TextLabel", {
        Size=UDim2.new(1,-78,1,0), BackgroundTransparency=1,
        Text="ESP transparency (0-1)", TextColor3=Color3.fromRGB(185,175,205),
        TextSize=11, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left,
        Parent=transparencyRow,
    })
    local transparencyBox = styledBox(transparencyRow, {
        Size=UDim2.new(0,70,0,24), Position=UDim2.new(1,-70,0.5,-12), Text="0.78",
        PlaceholderText="0-1",
    })
    transparencyBox.FocusLost:Connect(function()
        espTransparency=math.clamp(tonumber(transparencyBox.Text) or espTransparency,0.05,1)
        state.espTransparency=espTransparency
        transparencyBox.Text=string.format("%.2f",espTransparency)
        for _, data in pairs(holders) do
            if data.folder then
                for _, item in ipairs(data.folder:GetChildren()) do
                    if item:IsA("BoxHandleAdornment") then item.Transparency=espTransparency end
                end
            end
        end
    end)
    local distanceRow=rowFrame(nextOrder(),28)
    create("TextLabel",{Size=UDim2.new(1,-78,1,0),BackgroundTransparency=1,Text="Maximum distance",
        TextColor3=Color3.fromRGB(185,175,205),TextSize=11,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,Parent=distanceRow})
    local distanceBox=styledBox(distanceRow,{Size=UDim2.new(0,70,0,24),Position=UDim2.new(1,-70,0.5,-12),Text="5000"})
    distanceBox.FocusLost:Connect(function()
        espMaxDistance=math.clamp(tonumber(distanceBox.Text) or espMaxDistance,25,100000)
        state.espMaxDistance=espMaxDistance
        distanceBox.Text=tostring(espMaxDistance)
    end)

    local function updateSelectedStatus()
        local names = {}
        for player in pairs(selectedPlayers) do table.insert(names, player.Name) end
        table.sort(names)
        selectedStatus.Text = #names > 0 and ("Selected: "..table.concat(names, ", ")) or "Selected: none"
    end

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

        local priorityYellow=yellowNames[player.Name]==true
        local priorityPink=not priorityYellow and state.pinkHighlightNames[player.Name]==true
        local priorityBlack=not priorityYellow and not priorityPink and state.blackHighlightNames[player.Name]==true
        local priorityColor=priorityYellow and highlightColor(state.specialHighlightColor,Color3.fromRGB(255,225,45))
            or (priorityPink and highlightColor(state.superSpecialHighlightColor,Color3.fromRGB(255,155,205))
            or (priorityBlack and highlightColor(state.exploiterHighlightColor,Color3.fromRGB(205,35,75)) or player.TeamColor.Color))
        if espUseHighlight then
            local highlight=Instance.new("Highlight"); highlight.Name=player.Name
            highlight.Adornee=character; highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor=priorityColor
            highlight.OutlineColor=(priorityYellow or priorityPink or priorityBlack)
                and priorityColor:Lerp(Color3.new(1,1,1),0.35) or Color3.new(1,1,1)
            highlight.FillTransparency=state.espHighlightStyle=="Hard" and 1
                or (priorityPink and math.clamp(espTransparency-0.08,0,0.88) or math.clamp(espTransparency+0.08,0,0.94))
            highlight.OutlineTransparency=state.espHighlightStyle=="Hard" and math.clamp(espTransparency-0.7,0,0.3) or 0.58
            highlight.Parent=folder
        end
        for _, part in ipairs(character:GetChildren()) do
            -- HumanoidRootPart is invisible and overlaps the torso, which made
            -- IY-style boxes appear nearly solid on compact R15 avatars.
            if not espUseHighlight and part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
                local adornment = Instance.new("BoxHandleAdornment")
                adornment.Name = player.Name
                adornment.Adornee = part
                adornment.AlwaysOnTop = true
                adornment.ZIndex = 10
                adornment.Size = part.Size
                adornment.Transparency = espTransparency
                if priorityYellow or priorityPink or priorityBlack then adornment.Color3=priorityColor else adornment.Color=player.TeamColor end
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
        local localRoot=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local function eligible(player)
            local char=player.Character; local root=char and char:FindFirstChild("HumanoidRootPart")
            local hum=char and char:FindFirstChildOfClass("Humanoid")
            if not root or (espHideDead and (not hum or hum.Health<=0)) then return false end
            return not localRoot or (localRoot.Position-root.Position).Magnitude<=espMaxDistance
        end
        if mode == "all" then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and eligible(player) then wanted[player] = true end
            end
        elseif mode == "enemy" then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Team ~= LocalPlayer.Team and eligible(player) then
                    wanted[player] = true
                end
            end
        elseif mode == "target" then
            for player in pairs(selectedPlayers) do
                if player.Parent == Players and eligible(player) then wanted[player] = true end
            end
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

    local function addSelectedPlayer()
        local target = findGotoPlayer(selectBox.Text)
        if not target then
            selectBox.Text="Player not found"
            task.delay(1,function() if selectBox.Parent and selectBox.Text=="Player not found" then selectBox.Text="" end end)
            return
        end
        selectedPlayers[target]=true
        selectBox.Text=""
        updateSelectedStatus()
        if mode=="target" then refreshESP() end
    end
    addSelectedButton.MouseButton1Click:Connect(addSelectedPlayer)
    removeSelectedButton.MouseButton1Click:Connect(function()
        local target=findGotoPlayer(selectBox.Text)
        if target then selectedPlayers[target]=nil; selectBox.Text=""; updateSelectedStatus(); refreshESP() end
    end)
    selectBox.FocusLost:Connect(function(enterPressed) if enterPressed then addSelectedPlayer() end end)
    clearSelectedButton.MouseButton1Click:Connect(function()
        table.clear(selectedPlayers)
        updateSelectedStatus()
        if mode=="target" then refreshESP() end
    end)

    local _, _, allSetter = createToggle("ESP All", nextOrder(), false, function(on)
        if on then
            if setTarget then setTarget(false) end
            if setEnemy then setEnemy(false) end
            mode = "all"
            state.namedHighlightsSuppressed=false
            if restoreHighlightAfterAll and setHighlight then
                setHighlight(true); restoreHighlightAfterAll=false
            end
            if state.yellowHighlightApi.refresh then state.yellowHighlightApi.refresh() end
            if state.pinkHighlightApi.refresh then state.pinkHighlightApi.refresh() end
            if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
        elseif mode == "all" then
            mode = "off"
            if not switchingEspMode then
                restoreHighlightAfterAll=espUseHighlight
                if setHighlight then setHighlight(false) end
                state.namedHighlightsSuppressed=true
                if state.yellowHighlightApi.refresh then state.yellowHighlightApi.refresh() end
                if state.pinkHighlightApi.refresh then state.pinkHighlightApi.refresh() end
                if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
            end
        end
        refreshESP()
    end)
    setAll = allSetter

    local _, _, targetSetter = createToggle("ESP Selected", nextOrder(), false, function(on)
        if on then
            if next(selectedPlayers) == nil then
                selectBox.Text = "Add a player first"
                task.delay(1.2, function() if selectBox.Parent and selectBox.Text=="Add a player first" then selectBox.Text="" end end)
                task.defer(function() if setTarget then setTarget(false) end end)
                return
            end
            if setAll then switchingEspMode=true; setAll(false); switchingEspMode=false end
            if setEnemy then setEnemy(false) end
            mode = "target"
        elseif mode == "target" then
            mode = "off"
        end
        refreshESP()
    end)
    setTarget = targetSetter

    local _, _, enemySetter = createToggle("ESP Enemy Team", nextOrder(), false, function(on)
        if on then
            if setAll then switchingEspMode=true; setAll(false); switchingEspMode=false end
            if setTarget then setTarget(false) end
            mode = "enemy"
        elseif mode == "enemy" then
            mode = "off"
        end
        refreshESP()
    end)
    setEnemy = enemySetter
    createToggle("ESP Show Health/Distance",nextOrder(),true,function(on) espShowDetails=on end)
    createToggle("ESP Hide Dead",nextOrder(),true,function(on) espHideDead=on; refreshESP() end)
    local _,_,highlightSetter=createToggle("ESP Highlight Mode",nextOrder(),false,function(on)
        espUseHighlight=on; clearESP(); refreshESP()
    end)
    setHighlight=highlightSetter
    local highlightStyleButton=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(54,46,76),
        BorderSizePixel=0,Text="Highlight Style: Hard",TextColor3=Color3.fromRGB(225,215,240),TextSize=11,
        Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=highlightStyleButton})
    highlightStyleButton.MouseButton1Click:Connect(function()
        state.espHighlightStyle=state.espHighlightStyle=="Hard" and "Soft" or "Hard"
        highlightStyleButton.Text="Highlight Style: "..state.espHighlightStyle
        clearESP(); refreshESP()
        if state.yellowHighlightApi.refresh then state.yellowHighlightApi.refresh() end
        if state.pinkHighlightApi.refresh then state.pinkHighlightApi.refresh() end
        if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
    end)

    sectionLabel("Special Player Highlights",nextOrder())
    local yellowHighlights={}
    local yellowCharacterConnections={}
    local specialColorRow=rowFrame(nextOrder(),28)
    local specialColorBox=styledBox(specialColorRow,{Size=UDim2.new(1,0,0,26),Text=state.specialHighlightColor,PlaceholderText="Special color — #RRGGBB"})
    local yellowRow=rowFrame(nextOrder(),30)
    local yellowBox=styledBox(yellowRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Special username/display name"})
    local yellowAdd=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-64,0,0),
        BackgroundColor3=Color3.fromRGB(125,105,38),BorderSizePixel=0,Text="+",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=yellowRow})
    local yellowRemove=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-30,0,0),
        BackgroundColor3=Color3.fromRGB(95,55,60),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=yellowRow})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=yellowAdd}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=yellowRemove})
    local yellowStatus=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Text="Highlighted: none",
        TextColor3=Color3.fromRGB(220,205,120),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=nextOrder(),Parent=currentSection})

    local function refreshYellowStatus()
        local names={}; for name in pairs(yellowNames) do table.insert(names,name) end
        table.sort(names,function(a,b) return a:lower()<b:lower() end)
        yellowStatus.Text=#names>0 and ("Highlighted: "..table.concat(names,", ")) or "Highlighted: none"
    end
    local function removeYellowHighlight(player)
        local highlight=yellowHighlights[player]
        if highlight and highlight.Parent then highlight:Destroy() end
        yellowHighlights[player]=nil
    end
    local function applyYellowHighlight(player)
        removeYellowHighlight(player)
        if state.namedHighlightsSuppressed or not player or not yellowNames[player.Name] or not player.Character then return end
        local highlight=Instance.new("Highlight")
        highlight.Name="LucidYellowPlayerHighlight"; highlight.Adornee=player.Character
        local color=highlightColor(state.specialHighlightColor,Color3.fromRGB(255,225,45))
        highlight.FillColor=color
        highlight.FillTransparency=state.espHighlightStyle=="Hard" and 1 or math.clamp(espTransparency+0.08,0,0.94)
        highlight.OutlineColor=color:Lerp(Color3.new(1,1,1),0.35)
        highlight.OutlineTransparency=state.espHighlightStyle=="Hard" and math.clamp(espTransparency-0.7,0,0.3) or 0.58
        highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; highlight.Parent=player.Character
        yellowHighlights[player]=highlight
    end
    local function watchYellowPlayer(player)
        if player==LocalPlayer or yellowCharacterConnections[player] then return end
        yellowCharacterConnections[player]=track(player.CharacterAdded:Connect(function()
            task.defer(function() applyYellowHighlight(player) end)
        end))
        applyYellowHighlight(player)
    end
    local function addYellowPlayer()
        local player=findGotoPlayer(yellowBox.Text)
        if not player then yellowBox.Text="Player not found"; return end
        yellowNames[player.Name]=true; yellowBox.Text=""; watchYellowPlayer(player); applyYellowHighlight(player); refreshYellowStatus(); refreshESP()
        if state.pinkHighlightApi.refresh then state.pinkHighlightApi.refresh() end
        if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
    end
    local function removeYellowPlayer()
        local query=yellowBox.Text:match("^%s*(.-)%s*$"):lower(); local removedName=nil
        if query=="" then yellowBox.Text="Enter a player name"; return end
        local player=findGotoPlayer(query)
        if player and yellowNames[player.Name] then removedName=player.Name end
        if not removedName then
            for name in pairs(yellowNames) do if name:lower():sub(1,#query)==query then removedName=name; break end end
        end
        if removedName then
            yellowNames[removedName]=nil
            for playerKey in pairs(yellowHighlights) do if playerKey.Name==removedName then removeYellowHighlight(playerKey) end end
        end
        yellowBox.Text=""; refreshYellowStatus(); refreshESP()
        if state.pinkHighlightApi.refresh then state.pinkHighlightApi.refresh() end
        if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
    end
    yellowAdd.MouseButton1Click:Connect(addYellowPlayer); yellowRemove.MouseButton1Click:Connect(removeYellowPlayer)
    yellowBox.FocusLost:Connect(function(enterPressed) if enterPressed then addYellowPlayer() end end)
    track(Players.PlayerAdded:Connect(watchYellowPlayer))
    track(Players.PlayerRemoving:Connect(removeYellowHighlight))
    for _,player in ipairs(Players:GetPlayers()) do watchYellowPlayer(player) end
    state.yellowHighlightApi.getNames=function()
        local names={}; for name in pairs(yellowNames) do table.insert(names,name) end; return names
    end
    state.yellowHighlightApi.setNames=function(names)
        table.clear(yellowNames)
        if type(names)=="table" then for _,name in ipairs(names) do if type(name)=="string" then yellowNames[name]=true end end end
        for player in pairs(yellowHighlights) do removeYellowHighlight(player) end
        for _,player in ipairs(Players:GetPlayers()) do watchYellowPlayer(player); applyYellowHighlight(player) end
        refreshYellowStatus(); refreshESP()
        if state.pinkHighlightApi.refresh then state.pinkHighlightApi.refresh() end
        if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
    end
    state.yellowHighlightApi.refresh=function()
        for _,player in ipairs(Players:GetPlayers()) do applyYellowHighlight(player) end
    end
    specialColorBox.FocusLost:Connect(function()
        local clean=specialColorBox.Text:gsub("#",""):upper()
        if #clean==6 and tonumber(clean,16) then state.specialHighlightColor="#"..clean end
        specialColorBox.Text=state.specialHighlightColor; clearESP(); refreshESP(); state.yellowHighlightApi.refresh()
    end)
    state.yellowHighlightApi.refreshColor=function() specialColorBox.Text=state.specialHighlightColor end
    local clearYellowButton=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(105,82,34),
        BorderSizePixel=0,Text="Clear Special Highlights",TextColor3=Color3.fromRGB(240,235,245),TextSize=11,
        Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=clearYellowButton})
    clearYellowButton.MouseButton1Click:Connect(function()
        state.yellowHighlightApi.setNames({}); clearYellowButton.Text="Yellow highlights cleared"
        task.delay(1,function() if clearYellowButton.Parent then clearYellowButton.Text="Clear Special Highlights" end end)
    end)

    sectionLabel("Super Special Player Highlights",nextOrder())
    do
        local pinkHighlights={}
        local pinkConnections={}
        local superColorRow=rowFrame(nextOrder(),28)
        local superColorBox=styledBox(superColorRow,{Size=UDim2.new(1,0,0,26),Text=state.superSpecialHighlightColor,PlaceholderText="Super Special color — #RRGGBB"})
        local pinkRow=rowFrame(nextOrder(),30)
        local pinkBox=styledBox(pinkRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Super Special username/display name"})
        local pinkAdd=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-64,0,0),
            BackgroundColor3=Color3.fromRGB(184,103,143),BorderSizePixel=0,Text="+",TextColor3=Color3.new(1,1,1),
            TextSize=18,Font=Enum.Font.GothamBold,Parent=pinkRow})
        local pinkRemove=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-30,0,0),
            BackgroundColor3=Color3.fromRGB(95,55,70),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
            TextSize=18,Font=Enum.Font.GothamBold,Parent=pinkRow})
        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=pinkAdd}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=pinkRemove})
        local pinkStatus=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Text="Highlighted: none",
            TextColor3=Color3.fromRGB(255,190,220),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
            TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=nextOrder(),Parent=currentSection})
        local function refreshPinkStatus()
            local names={}; for name in pairs(state.pinkHighlightNames) do table.insert(names,name) end
            table.sort(names,function(a,b) return a:lower()<b:lower() end)
            pinkStatus.Text=#names>0 and ("Highlighted: "..table.concat(names,", ")) or "Highlighted: none"
        end
        local function removePinkHighlight(player)
            local highlight=pinkHighlights[player]
            if highlight and highlight.Parent then highlight:Destroy() end
            pinkHighlights[player]=nil
        end
        local function applyPinkHighlight(player)
            removePinkHighlight(player)
            if state.namedHighlightsSuppressed or not player or not state.pinkHighlightNames[player.Name] or yellowNames[player.Name] or not player.Character then return end
            local highlight=Instance.new("Highlight")
            highlight.Name="LucidPinkPlayerHighlight"; highlight.Adornee=player.Character
            local color=highlightColor(state.superSpecialHighlightColor,Color3.fromRGB(255,155,205))
            highlight.FillColor=color
            highlight.FillTransparency=state.espHighlightStyle=="Hard" and 1 or math.clamp(espTransparency-0.08,0,0.88)
            highlight.OutlineColor=color:Lerp(Color3.new(1,1,1),0.35)
            highlight.OutlineTransparency=state.espHighlightStyle=="Hard" and math.clamp(espTransparency-0.7,0,0.3) or 0.48
            highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; highlight.Parent=player.Character
            pinkHighlights[player]=highlight
        end
        local function watchPinkPlayer(player)
            if player==LocalPlayer or pinkConnections[player] then return end
            pinkConnections[player]=track(player.CharacterAdded:Connect(function() task.defer(function() applyPinkHighlight(player) end) end))
            applyPinkHighlight(player)
        end
        local function setPinkNames(names)
            table.clear(state.pinkHighlightNames)
            if type(names)=="table" then for _,name in ipairs(names) do if type(name)=="string" then state.pinkHighlightNames[name]=true end end end
            for player in pairs(pinkHighlights) do removePinkHighlight(player) end
            for _,player in ipairs(Players:GetPlayers()) do watchPinkPlayer(player); applyPinkHighlight(player) end
            refreshPinkStatus(); refreshESP()
        end
        local function addPinkPlayer()
            local player=findGotoPlayer(pinkBox.Text)
            if not player then pinkBox.Text="Player not found"; return end
            state.pinkHighlightNames[player.Name]=true; pinkBox.Text=""; watchPinkPlayer(player); applyPinkHighlight(player); refreshPinkStatus(); refreshESP()
            if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
        end
        pinkAdd.MouseButton1Click:Connect(addPinkPlayer)
        pinkRemove.MouseButton1Click:Connect(function()
            local query=pinkBox.Text:match("^%s*(.-)%s*$"):lower(); local removedName=nil
            if query=="" then pinkBox.Text="Enter a player name"; return end
            local player=findGotoPlayer(query)
            if player and state.pinkHighlightNames[player.Name] then removedName=player.Name end
            if not removedName then for name in pairs(state.pinkHighlightNames) do if name:lower():sub(1,#query)==query then removedName=name; break end end end
            if removedName then
                state.pinkHighlightNames[removedName]=nil
                for playerKey in pairs(pinkHighlights) do if playerKey.Name==removedName then removePinkHighlight(playerKey) end end
            end
            pinkBox.Text=""; refreshPinkStatus(); refreshESP()
            if state.blackHighlightApi.refresh then state.blackHighlightApi.refresh() end
        end)
        pinkBox.FocusLost:Connect(function(enterPressed) if enterPressed then addPinkPlayer() end end)
        track(Players.PlayerAdded:Connect(watchPinkPlayer)); track(Players.PlayerRemoving:Connect(removePinkHighlight))
        for _,player in ipairs(Players:GetPlayers()) do watchPinkPlayer(player) end
        state.pinkHighlightApi.getNames=function()
            local names={}; for name in pairs(state.pinkHighlightNames) do table.insert(names,name) end; return names
        end
        state.pinkHighlightApi.setNames=setPinkNames
        state.pinkHighlightApi.refresh=function()
            for _,player in ipairs(Players:GetPlayers()) do applyPinkHighlight(player) end
        end
        superColorBox.FocusLost:Connect(function()
            local clean=superColorBox.Text:gsub("#",""):upper()
            if #clean==6 and tonumber(clean,16) then state.superSpecialHighlightColor="#"..clean end
            superColorBox.Text=state.superSpecialHighlightColor; clearESP(); refreshESP(); state.pinkHighlightApi.refresh()
        end)
        state.pinkHighlightApi.refreshColor=function() superColorBox.Text=state.superSpecialHighlightColor end
        local clearPinkButton=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(120,65,92),
            BorderSizePixel=0,Text="Clear Super Special Highlights",TextColor3=Color3.fromRGB(240,235,245),TextSize=11,
            Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
        create("UICorner",{CornerRadius=UDim.new(0,6),Parent=clearPinkButton})
        clearPinkButton.MouseButton1Click:Connect(function()
            setPinkNames({}); clearPinkButton.Text="Pink highlights cleared"
            task.delay(1,function() if clearPinkButton.Parent then clearPinkButton.Text="Clear Super Special Highlights" end end)
        end)
        addCleanup(function() for player in pairs(pinkHighlights) do removePinkHighlight(player) end end)
    end

    sectionLabel("Exploiter Player Highlights",nextOrder())
    do
        local blackHighlights={}
        local blackConnections={}
        local exploiterColorRow=rowFrame(nextOrder(),28)
        local exploiterColorBox=styledBox(exploiterColorRow,{Size=UDim2.new(1,0,0,26),Text=state.exploiterHighlightColor,PlaceholderText="Exploiter color — #RRGGBB"})
        local blackRow=rowFrame(nextOrder(),30)
        local blackBox=styledBox(blackRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Exploiter username/display name"})
        local blackAdd=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-64,0,0),
            BackgroundColor3=Color3.fromRGB(145,38,62),BorderSizePixel=0,Text="+",TextColor3=Color3.new(1,1,1),TextSize=18,Font=Enum.Font.GothamBold,Parent=blackRow})
        local blackRemove=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-30,0,0),
            BackgroundColor3=Color3.fromRGB(95,55,60),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),TextSize=18,Font=Enum.Font.GothamBold,Parent=blackRow})
        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=blackAdd}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=blackRemove})
        local blackStatus=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Text="Marked: none",
            TextColor3=Color3.fromRGB(235,120,145),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
            TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=nextOrder(),Parent=currentSection})
        local function refreshBlackStatus()
            local names={}; for name in pairs(state.blackHighlightNames) do table.insert(names,name) end
            table.sort(names,function(a,b) return a:lower()<b:lower() end)
            blackStatus.Text=#names>0 and ("Marked: "..table.concat(names,", ")) or "Marked: none"
        end
        local function removeBlackHighlight(player)
            local highlight=blackHighlights[player]; if highlight and highlight.Parent then highlight:Destroy() end; blackHighlights[player]=nil
        end
        local function applyBlackHighlight(player)
            removeBlackHighlight(player)
            if state.namedHighlightsSuppressed or not player or not state.blackHighlightNames[player.Name] or yellowNames[player.Name]
                or state.pinkHighlightNames[player.Name] or not player.Character then return end
            local highlight=Instance.new("Highlight")
            highlight.Name="LucidBlackPlayerHighlight"; highlight.Adornee=player.Character
            local color=highlightColor(state.exploiterHighlightColor,Color3.fromRGB(205,35,75))
            highlight.FillColor=color
            highlight.FillTransparency=state.espHighlightStyle=="Hard" and 1 or math.clamp(espTransparency,0,0.9)
            highlight.OutlineColor=color:Lerp(Color3.new(1,1,1),0.35)
            highlight.OutlineTransparency=state.espHighlightStyle=="Hard" and math.clamp(espTransparency-0.7,0,0.3) or 0.5
            highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; highlight.Parent=player.Character; blackHighlights[player]=highlight
        end
        local function watchBlackPlayer(player)
            if player==LocalPlayer or blackConnections[player] then return end
            blackConnections[player]=track(player.CharacterAdded:Connect(function() task.defer(function() applyBlackHighlight(player) end) end)); applyBlackHighlight(player)
        end
        local function setBlackNames(names)
            table.clear(state.blackHighlightNames)
            if type(names)=="table" then for _,name in ipairs(names) do if type(name)=="string" then state.blackHighlightNames[name]=true end end end
            for player in pairs(blackHighlights) do removeBlackHighlight(player) end
            for _,player in ipairs(Players:GetPlayers()) do watchBlackPlayer(player); applyBlackHighlight(player) end
            refreshBlackStatus(); refreshESP()
        end
        local function addBlackPlayer()
            local player=findGotoPlayer(blackBox.Text)
            if not player then blackBox.Text="Player not found"; return end
            state.blackHighlightNames[player.Name]=true; blackBox.Text=""; watchBlackPlayer(player); applyBlackHighlight(player); refreshBlackStatus(); refreshESP()
        end
        blackAdd.MouseButton1Click:Connect(addBlackPlayer)
        blackRemove.MouseButton1Click:Connect(function()
            local query=blackBox.Text:match("^%s*(.-)%s*$"):lower(); local removedName=nil
            if query=="" then blackBox.Text="Enter a player name"; return end
            local player=findGotoPlayer(query); if player and state.blackHighlightNames[player.Name] then removedName=player.Name end
            if not removedName then for name in pairs(state.blackHighlightNames) do if name:lower():sub(1,#query)==query then removedName=name; break end end end
            if removedName then state.blackHighlightNames[removedName]=nil; for playerKey in pairs(blackHighlights) do if playerKey.Name==removedName then removeBlackHighlight(playerKey) end end end
            blackBox.Text=""; refreshBlackStatus(); refreshESP()
        end)
        blackBox.FocusLost:Connect(function(enterPressed) if enterPressed then addBlackPlayer() end end)
        track(Players.PlayerAdded:Connect(watchBlackPlayer)); track(Players.PlayerRemoving:Connect(removeBlackHighlight))
        for _,player in ipairs(Players:GetPlayers()) do watchBlackPlayer(player) end
        state.blackHighlightApi.getNames=function() local names={}; for name in pairs(state.blackHighlightNames) do table.insert(names,name) end; return names end
        state.blackHighlightApi.setNames=setBlackNames
        state.blackHighlightApi.refresh=function() for _,player in ipairs(Players:GetPlayers()) do applyBlackHighlight(player) end end
        exploiterColorBox.FocusLost:Connect(function()
            local clean=exploiterColorBox.Text:gsub("#",""):upper()
            if #clean==6 and tonumber(clean,16) then state.exploiterHighlightColor="#"..clean end
            exploiterColorBox.Text=state.exploiterHighlightColor; clearESP(); refreshESP(); state.blackHighlightApi.refresh()
        end)
        state.blackHighlightApi.refreshColor=function() exploiterColorBox.Text=state.exploiterHighlightColor end
        local clearBlackButton=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(105,35,52),BorderSizePixel=0,
            Text="Clear Exploiter Highlights",TextColor3=Color3.fromRGB(240,220,225),TextSize=11,Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
        create("UICorner",{CornerRadius=UDim.new(0,6),Parent=clearBlackButton})
        clearBlackButton.MouseButton1Click:Connect(function() setBlackNames({}); clearBlackButton.Text="Exploiter highlights cleared"; task.delay(1,function() if clearBlackButton.Parent then clearBlackButton.Text="Clear Exploiter Highlights" end end) end)
        addCleanup(function() for player in pairs(blackHighlights) do removeBlackHighlight(player) end end)
    end

    task.spawn(function()
        while running and screenGui.Parent do
            if mode ~= "off" then
                refreshESP()
                local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                for player, data in pairs(holders) do
                    if data.label and data.root and data.root.Parent then
                        local distance = localRoot and math.floor((localRoot.Position-data.root.Position).Magnitude) or 0
                        local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                        local health=humanoid and math.floor(humanoid.Health+0.5) or 0
                        data.label.Text=espShowDetails and (player.Name.." | "..distance.." studs | HP "..health) or player.Name
                    end
                end
            end
            task.wait(state.lowPerformanceMode and 0.8 or 0.35)
        end
    end)

    addCleanup(function()
        running=false
        mode="off"
        clearESP()
        for player in pairs(yellowHighlights) do removeYellowHighlight(player) end
    end)
end

initializePlayerESP()
end

initializeTeleportAndESP()

useCategory("Teleport & Coordinates")
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

-- Noclip is enforced by the consolidated Heartbeat below. Keeping a second
-- Stepped scan doubled all character-descendant work without changing state.

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
state.recoverCharacter=function()
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
end
recoveryBtn.MouseButton1Click:Connect(state.recoverCharacter)
do
    local _,_,setRecoveryLoop=createToggle("Character Recovery Loop",nextOrder(),false,function(on)
        state.characterRecoveryLoopEnabled=on
        if on then state.recoverCharacter() end
    end)
    state.setCharacterRecoveryLoop=setRecoveryLoop
end
task.spawn(function()
    while screenGui.Parent do
        if state.characterRecoveryLoopEnabled then
            local character=LocalPlayer.Character
            local humanoid=character and character:FindFirstChildOfClass("Humanoid")
            local root=character and character:FindFirstChild("HumanoidRootPart")
            if root then
                if root.Anchored then root.Anchored=false end
                if root.AssemblyAngularVelocity.Magnitude>8 then root.AssemblyAngularVelocity=Vector3.zero end
                if root.AssemblyLinearVelocity.Magnitude>300 then root.AssemblyLinearVelocity=Vector3.zero end
            end
            if humanoid then
                if humanoid.PlatformStand then humanoid.PlatformStand=false end
                local current=humanoid:GetState()
                if current==Enum.HumanoidStateType.FallingDown
                    or current==Enum.HumanoidStateType.Ragdoll
                    or current==Enum.HumanoidStateType.Physics then
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end
        task.wait(state.characterRecoveryLoopEnabled and 0.35 or 1)
    end
end)

-- ============================================================
-- V4 GENERAL TOOLKIT
-- ============================================================
-- Keep the large optional toolkit in its own function scope. Many executor
-- compilers retain Lua's per-function local/register limit; putting every UI
-- control in the root chunk makes loadstring return nil before Lucid starts.
local function initializeV4Toolkit()
local AvatarEditorService=game:GetService("AvatarEditorService")
local shortcutKeys = { Migraine=Enum.KeyCode.F8 }
local shortcutBoxes = {}
local setPhotoModeToggle
local function actionButton(textValue, callback, color)
    local row = rowFrame(nextOrder(), 32)
    local compactWidth=math.min(260,math.max(58,24+#textValue*6.6))
    row:SetAttribute("LucidFavoriteStarX",compactWidth-27)
    local button = create("TextButton", {
        Size = UDim2.new(0, compactWidth, 0, 28), BackgroundColor3 = color or Color3.fromRGB(62, 52, 92),
        BorderSizePixel = 0, Text = textValue, TextColor3 = Color3.fromRGB(235, 230, 245),
        TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment=Enum.TextXAlignment.Left, Parent = row,
    })
    create("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,30),Parent=button})
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })
    local function runAction() callback(button) end
    button.MouseButton1Click:Connect(runAction)
    registerFavorite(textValue, runAction, row)
    state.commandActions=state.commandActions or {}
    state.commandActions[textValue]=runAction
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
    local target = gotoApi.find(gotoApi.box.Text)
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
    local target=gotoApi.find(gotoApi.box.Text)
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
local freecamSpeedRow=rowFrame(nextOrder())
create("TextLabel",{Size=UDim2.new(0.65,0,1,0),BackgroundTransparency=1,Text="Freecam speed",
    TextColor3=Color3.fromRGB(210,210,220),TextSize=13,Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=freecamSpeedRow})
local freecamSpeedBox=styledBox(freecamSpeedRow,{Size=UDim2.new(0,70,0,24),Position=UDim2.new(1,-70,0.5,-12),Text="50"})
freecamSpeedBox.FocusLost:Connect(function()
    state.freecamSpeed=math.clamp(tonumber(freecamSpeedBox.Text) or state.freecamSpeed,1,500)
    freecamSpeedBox.Text=tostring(state.freecamSpeed)
end)
local function setNoCameraShake(on)
    state.noCameraShake=on
    pcall(function() RunService:UnbindFromRenderStep("LucidNoCameraShake") end)
    if on then
        RunService:BindToRenderStep("LucidNoCameraShake",Enum.RenderPriority.Last.Value,function()
            local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.CameraOffset~=Vector3.zero then
                local strength=state.cameraShakeStrength
                local removal=strength=="Light" and 0.35 or (strength=="Medium" and 0.7 or 1)
                humanoid.CameraOffset=humanoid.CameraOffset*(1-removal)
            end
        end)
    else
        local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.CameraOffset=Vector3.zero end
    end
end
local shakeStrengthButton=actionButton("Camera Shake Strength: Strong",function(button)
    local current=state.cameraShakeStrength
    state.cameraShakeStrength=current=="Light" and "Medium" or (current=="Medium" and "Strong" or "Light")
    button.Text="Camera Shake Strength: "..state.cameraShakeStrength
end)
createToggle("Remove Camera Shake",nextOrder(),false,setNoCameraShake)
local savedCamera = nil
local freecamCFrame = nil
local freecamYaw = 0
local freecamPitch = 0
local function releaseFreecamMouse()
    UserInputService.MouseBehavior=Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled=true
    -- Potassium/Roblox may apply the previous frame's LockCenter after this
    -- callback. Release it again after that frame has completed.
    task.defer(function()
        if not state.freecamEnabled then
            UserInputService.MouseBehavior=Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled=true
        end
    end)
    task.delay(0.08,function()
        if not state.freecamEnabled then
            UserInputService.MouseBehavior=Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled=true
        end
    end)
end
local _, fireFreecam, setFreecam = createToggle("Freecam", nextOrder(), false, function(on)
    state.freecamEnabled = on
    local camera = workspace.CurrentCamera
    if not camera then if not on then releaseFreecamMouse() end; return end
    if on then
        if state.flyEnabled then
            setFly(false)
            notifyLucid("Compatibility manager","Fly suspended while Freecam is active",Color3.fromRGB(235,175,70))
        end
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
        savedCamera, freecamCFrame = nil, nil
        releaseFreecamMouse()
    elseif not on then
        releaseFreecamMouse()
    end
end)
addCleanup(function()
    pcall(function() RunService:UnbindFromRenderStep("LucidNoCameraShake") end)
    ContextActionService:UnbindAction("LucidFreecamSink")
    if state.freecamEnabled and savedCamera and workspace.CurrentCamera then
        local camera=workspace.CurrentCamera
        camera.CameraType=savedCamera.Type; camera.CameraSubject=savedCamera.Subject
        camera.CFrame=savedCamera.CFrame; camera.FieldOfView=savedCamera.FOV
    end
    state.freecamEnabled=false; releaseFreecamMouse()
end)
actionButton("First Person", function() LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson end)
actionButton("Third Person / Restore", function()
    LocalPlayer.CameraMode = Enum.CameraMode.Classic
    if state.freecamEnabled then setFreecam(false) end
    local camera = workspace.CurrentCamera
    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if camera and h then camera.CameraType = Enum.CameraType.Custom; camera.CameraSubject = h end
    releaseFreecamMouse()
end)

sectionLabel("Clean Photo Mode",nextOrder())
do
    local hiddenVisuals={}
    local hiddenWindows={}
    local savedMainVisible=true
    local savedBackpackEnabled=true
    local photoStartedFreecam=false
    local function rememberVisual(instance,property)
        if hiddenVisuals[instance] then return end
        local ok,value=pcall(function() return instance[property] end)
        if ok then hiddenVisuals[instance]={property=property,value=value}; pcall(function() instance[property]=false end) end
    end
    local function lucidEspVisual(instance)
        local ancestor=instance.Parent
        while ancestor and ancestor~=game do
            if ancestor.Name:match("_LucidESP$") or ancestor.Name=="LucidHazardGhost"
                or ancestor.Name:match("^LucidWaypoint_") then return true end
            ancestor=ancestor.Parent
        end
        return instance.Name:match("^Lucid.*ESP")~=nil
            or instance.Name:match("^Lucid.*PlayerHighlight$")~=nil
            or instance.Name=="GhostOutline" or instance.Name=="GhostLabel"
    end
    local function hideEspVisual(instance)
        if not lucidEspVisual(instance) then return end
        if instance:IsA("Highlight") or instance:IsA("BillboardGui") then rememberVisual(instance,"Enabled")
        elseif instance:IsA("BoxHandleAdornment") then rememberVisual(instance,"Visible") end
    end
    local function hideCustomBackpack(instance)
        local lower=instance.Name:lower()
        if not (lower:find("backpack",1,true) or lower:find("hotbar",1,true)) then return end
        if instance:IsA("ScreenGui") then rememberVisual(instance,"Enabled")
        elseif instance:IsA("GuiObject") then rememberVisual(instance,"Visible") end
    end
    local function scanPhotoVisuals()
        for _,instance in ipairs(screenGui:GetDescendants()) do hideEspVisual(instance) end
        for _,instance in ipairs(workspace:GetDescendants()) do hideEspVisual(instance) end
        local playerGui=LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then for _,instance in ipairs(playerGui:GetDescendants()) do hideCustomBackpack(instance) end end
    end
    local function restorePhotoVisuals()
        for instance,record in pairs(hiddenVisuals) do
            if instance and instance.Parent then pcall(function() instance[record.property]=record.value end) end
        end
        table.clear(hiddenVisuals)
    end
    local function setPhotoMode(on)
        if state.photoModeEnabled==on then return end
        state.photoModeEnabled=on
        if on then
            savedMainVisible=mainFrame.Visible
            table.clear(hiddenWindows)
            if notificationHost and notificationHost.Parent then
                hiddenWindows[notificationHost]=notificationHost.Visible; notificationHost.Visible=false
            end
            if state.lucidDock and state.lucidDock.Parent then
                hiddenWindows[state.lucidDock]=state.lucidDock.Visible; state.lucidDock.Visible=false
            end
            for _,item in ipairs(detachableWindows) do
                if item.window and item.window.Parent then hiddenWindows[item.window]=item.window.Visible; item.window.Visible=false end
            end
            local starterGui=game:GetService("StarterGui")
            pcall(function() savedBackpackEnabled=starterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) end)
            pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false) end)
            scanPhotoVisuals()
            photoStartedFreecam=not state.freecamEnabled
            if photoStartedFreecam then setFreecam(true) end
            mainFrame.Visible=false
        else
            restorePhotoVisuals()
            pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,savedBackpackEnabled) end)
            for window,wasVisible in pairs(hiddenWindows) do if window and window.Parent then window.Visible=wasVisible end end
            table.clear(hiddenWindows)
            if photoStartedFreecam and state.freecamEnabled then setFreecam(false) end
            photoStartedFreecam=false; mainFrame.Visible=savedMainVisible
            notifyLucid("Photo Mode disabled","Backpack, ESP and Lucid windows restored",Color3.fromRGB(75,210,120))
        end
    end
    local _,_,photoModeSetter=createToggle("Photo Mode — Clean Freecam",nextOrder(),false,setPhotoMode)
    setPhotoModeToggle=photoModeSetter
    track(screenGui.DescendantAdded:Connect(function(instance) if state.photoModeEnabled then task.defer(hideEspVisual,instance) end end))
    track(workspace.DescendantAdded:Connect(function(instance) if state.photoModeEnabled then task.defer(hideEspVisual,instance) end end))
    local playerGui=LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then track(playerGui.DescendantAdded:Connect(function(instance) if state.photoModeEnabled then task.defer(hideCustomBackpack,instance) end end)) end
    addCleanup(function() if state.photoModeEnabled then setPhotoMode(false) end end)
end

sectionLabel("Photo Isolation",nextOrder())
state.initializePhotoIsolation=function()
    local exceptions={}
    local originals={}
    local characterConnections={}
    local isolationEnabled=false
    local inputRow=rowFrame(nextOrder(),30)
    local inputBox=styledBox(inputRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Player username/display name"})
    local addButton=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-64,0,0),
        BackgroundColor3=Color3.fromRGB(48,105,67),BorderSizePixel=0,Text="+",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=inputRow})
    local removeButton=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-30,0,0),
        BackgroundColor3=Color3.fromRGB(95,55,60),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=inputRow})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=addButton}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=removeButton})
    local status=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Text="Visible with you: nobody",
        TextColor3=Color3.fromRGB(155,190,165),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=nextOrder(),Parent=currentSection})

    local function remember(instance,property,value)
        local record=originals[instance]
        if not record then record={}; originals[instance]=record end
        if record[property]==nil then record[property]=value end
    end
    local function hideObject(object)
        if object:IsA("BasePart") then
            remember(object,"LocalTransparencyModifier",object.LocalTransparencyModifier); object.LocalTransparencyModifier=1
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("Highlight") then
            remember(object,"Enabled",object.Enabled); object.Enabled=false
        elseif object:IsA("Humanoid") then
            remember(object,"DisplayDistanceType",object.DisplayDistanceType); object.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
        end
    end
    local function shouldHide(player)
        return isolationEnabled and player~=LocalPlayer and not exceptions[player.Name]
    end
    local function applyPlayer(player)
        local character=player.Character
        if not character or not shouldHide(player) then return end
        hideObject(character)
        for _,object in ipairs(character:GetDescendants()) do hideObject(object) end
    end
    local function restoreAll()
        for object,properties in pairs(originals) do
            if object and object.Parent then
                for property,value in pairs(properties) do pcall(function() object[property]=value end) end
            end
        end
        table.clear(originals)
    end
    local function refresh()
        restoreAll()
        if isolationEnabled then for _,player in ipairs(Players:GetPlayers()) do applyPlayer(player) end end
    end
    local function updateStatus()
        local names={}; for name in pairs(exceptions) do table.insert(names,name) end
        table.sort(names,function(a,b) return a:lower()<b:lower() end)
        status.Text=#names>0 and ("Visible with you: "..table.concat(names,", ")) or "Visible with you: nobody"
    end
    local function watchPlayer(player)
        if player==LocalPlayer or characterConnections[player] then return end
        characterConnections[player]=track(player.CharacterAdded:Connect(function(character)
            if shouldHide(player) then
                task.defer(function() if character.Parent then applyPlayer(player) end end)
            end
        end))
    end
    local function addException()
        local player=gotoApi.find(inputBox.Text)
        if not player or player==LocalPlayer then inputBox.Text="Player not found"; return end
        exceptions[player.Name]=true; inputBox.Text=""; updateStatus(); refresh()
    end
    local function removeException()
        local query=inputBox.Text:match("^%s*(.-)%s*$"):lower()
        if query=="" then inputBox.Text="Enter a player name"; return end
        local removed=nil
        for name in pairs(exceptions) do if name:lower():sub(1,#query)==query then removed=name; break end end
        if removed then exceptions[removed]=nil end
        inputBox.Text=""; updateStatus(); refresh()
    end
    addButton.MouseButton1Click:Connect(addException); removeButton.MouseButton1Click:Connect(removeException)
    inputBox.FocusLost:Connect(function(enterPressed) if enterPressed then addException() end end)
    createToggle("Photo Isolation — Hide Other Players",nextOrder(),false,function(on)
        isolationEnabled=on; state.photoIsolationEnabled=on; refresh()
    end)
    track(Players.PlayerAdded:Connect(function(player) watchPlayer(player); if isolationEnabled then task.defer(function() applyPlayer(player) end) end end))
    track(workspace.DescendantAdded:Connect(function(object)
        if not isolationEnabled then return end
        local character=object:FindFirstAncestorOfClass("Model")
        local player=character and Players:GetPlayerFromCharacter(character)
        if player and shouldHide(player) then hideObject(object) end
    end))
    for _,player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
    addCleanup(function() isolationEnabled=false; restoreAll() end)
end
state.initializePhotoIsolation()

sectionLabel("Hide Named Players",nextOrder())
state.initializeNamedPlayerHider=function()
    local hiddenNames={}
    local originals={}
    local characterConnections={}
    local enabled=false
    local inputRow=rowFrame(nextOrder(),30)
    local inputBox=styledBox(inputRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Player to hide from screen"})
    local addButton=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-64,0,0),
        BackgroundColor3=Color3.fromRGB(70,78,115),BorderSizePixel=0,Text="+",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=inputRow})
    local removeButton=create("TextButton",{Size=UDim2.new(0,30,0,26),Position=UDim2.new(1,-30,0,0),
        BackgroundColor3=Color3.fromRGB(95,55,60),BorderSizePixel=0,Text="-",TextColor3=Color3.new(1,1,1),
        TextSize=18,Font=Enum.Font.GothamBold,Parent=inputRow})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=addButton}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=removeButton})
    local status=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Text="Hidden list: nobody",
        TextColor3=Color3.fromRGB(180,175,210),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=nextOrder(),Parent=currentSection})
    local function remember(instance,property,value)
        local record=originals[instance]
        if not record then record={}; originals[instance]=record end
        if record[property]==nil then record[property]=value end
    end
    local function hideObject(object)
        if object:IsA("BasePart") then
            remember(object,"LocalTransparencyModifier",object.LocalTransparencyModifier); object.LocalTransparencyModifier=1
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("Highlight") then
            remember(object,"Enabled",object.Enabled); object.Enabled=false
        elseif object:IsA("Humanoid") then
            remember(object,"DisplayDistanceType",object.DisplayDistanceType); object.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
        end
    end
    local function shouldHide(player)
        return enabled and player~=LocalPlayer and hiddenNames[player.Name]==true
    end
    local function applyPlayer(player)
        local character=player.Character
        if not character or not shouldHide(player) then return end
        for _,object in ipairs(character:GetDescendants()) do hideObject(object) end
    end
    local function restoreAll()
        for object,properties in pairs(originals) do
            if object and object.Parent then for property,value in pairs(properties) do pcall(function() object[property]=value end) end end
        end
        table.clear(originals)
    end
    local function refresh()
        restoreAll()
        if enabled then for _,player in ipairs(Players:GetPlayers()) do applyPlayer(player) end end
    end
    local function updateStatus()
        local names={}; for name in pairs(hiddenNames) do table.insert(names,name) end
        table.sort(names,function(a,b) return a:lower()<b:lower() end)
        status.Text=#names>0 and ("Hidden list: "..table.concat(names,", ")) or "Hidden list: nobody"
    end
    local function watchPlayer(player)
        if player==LocalPlayer or characterConnections[player] then return end
        characterConnections[player]=track(player.CharacterAdded:Connect(function(character)
            if shouldHide(player) then task.defer(function() if character.Parent then applyPlayer(player) end end) end
        end))
    end
    local function addPlayer()
        local player=gotoApi.find(inputBox.Text)
        if not player or player==LocalPlayer then inputBox.Text="Player not found"; return end
        hiddenNames[player.Name]=true; inputBox.Text=""; watchPlayer(player); updateStatus(); refresh()
    end
    local function removePlayer()
        local query=inputBox.Text:match("^%s*(.-)%s*$"):lower()
        if query=="" then inputBox.Text="Enter a player name"; return end
        local removed=nil
        for name in pairs(hiddenNames) do if name:lower():sub(1,#query)==query then removed=name; break end end
        if removed then hiddenNames[removed]=nil end
        inputBox.Text=""; updateStatus(); refresh()
    end
    addButton.MouseButton1Click:Connect(addPlayer); removeButton.MouseButton1Click:Connect(removePlayer)
    inputBox.FocusLost:Connect(function(enterPressed) if enterPressed then addPlayer() end end)
    createToggle("Hide Named Players",nextOrder(),false,function(on) enabled=on; refresh() end)
    local clearButton=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(85,48,62),BorderSizePixel=0,
        Text="Clear Hidden Player List",TextColor3=Color3.fromRGB(235,225,240),TextSize=11,Font=Enum.Font.GothamSemibold,
        LayoutOrder=nextOrder(),Parent=currentSection})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=clearButton})
    clearButton.MouseButton1Click:Connect(function()
        table.clear(hiddenNames); updateStatus(); refresh(); clearButton.Text="Hidden list cleared"
        task.delay(1,function() if clearButton.Parent then clearButton.Text="Clear Hidden Player List" end end)
    end)
    track(Players.PlayerAdded:Connect(function(player) watchPlayer(player); if shouldHide(player) then task.defer(function() applyPlayer(player) end) end end))
    track(workspace.DescendantAdded:Connect(function(object)
        if not enabled then return end
        local character=object:FindFirstAncestorOfClass("Model")
        local player=character and Players:GetPlayerFromCharacter(character)
        if player and shouldHide(player) then hideObject(object) end
    end))
    for _,player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
    state.namedPlayerHiderApi={
        getNames=function() local names={}; for name in pairs(hiddenNames) do table.insert(names,name) end; return names end,
        setNames=function(names)
            table.clear(hiddenNames)
            if type(names)=="table" then for _,name in ipairs(names) do if type(name)=="string" then hiddenNames[name]=true end end end
            updateStatus(); refresh()
        end,
    }
    addCleanup(function() enabled=false; restoreAll() end)
end
state.initializeNamedPlayerHider()

-- In-memory waypoints are intentionally per-place and do not move between games.
useCategory("Waypoints")
sectionLabel("Named Waypoints", nextOrder())
local waypointRow = rowFrame(nextOrder())
local waypointBox = styledBox(waypointRow, { Size=UDim2.new(1,0,0,26), Text="Home", PlaceholderText="Waypoint name" })
local waypoints = {}
local waypointMarkers={}
local waypointMarkersEnabled=false
local waypointSortNearest=false
local lastSelectedWaypoint=nil
local pendingOverwrite=nil
local refreshWaypointDropdown = function() end
actionButton("Save / Update Waypoint", function(button)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local name = waypointBox.Text:match("^%s*(.-)%s*$")
    if root and name ~= "" then
        if waypoints[name] and pendingOverwrite~=name then
            pendingOverwrite=name; button.Text="Click again to overwrite: "..name
            task.delay(2.5,function() if pendingOverwrite==name then pendingOverwrite=nil end end)
            return
        end
        pendingOverwrite=nil; waypoints[name] = root.CFrame; refreshWaypointDropdown(); button.Text = "Saved: "..name
        task.delay(1, function() if button.Parent then button.Text="Save / Update Waypoint" end end) end
end)
actionButton("Go To Waypoint", function(button)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local point = waypoints[waypointBox.Text:match("^%s*(.-)%s*$")]
    if root and point then root.CFrame = point; clearCharacterVelocity(LocalPlayer.Character)
    else button.Text="Waypoint not found"; task.delay(1, function() if button.Parent then button.Text="Go To Waypoint" end end) end
end)
local waypointDropdownRow = rowFrame(nextOrder(), 30)
local waypointDropdownButton = create("TextButton", {
    Size=UDim2.new(1,0,0,26), BackgroundColor3=Color3.fromRGB(54,46,76),
    BorderSizePixel=0, Text=">  Quick Waypoint List", TextColor3=Color3.fromRGB(225,215,240),
    TextSize=11, Font=Enum.Font.GothamSemibold, Parent=waypointDropdownRow,
})
create("UICorner", { CornerRadius=UDim.new(0,6), Parent=waypointDropdownButton })
local waypointDropdown = create("Frame", {
    Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1, Visible=false, LayoutOrder=nextOrder(), Parent=currentSection,
})
create("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,4), Parent=waypointDropdown })
local waypointDropdownOpen=false
local function setWaypointDropdownOpen(value)
    waypointDropdownOpen=value
    waypointDropdown.Visible=value
    waypointDropdownButton.Text=(value and "v  " or ">  ").."Quick Waypoint List"
end
waypointDropdownButton.MouseButton1Click:Connect(function() setWaypointDropdownOpen(not waypointDropdownOpen) end)
registerFavorite("Quick Waypoint List", function()
    categoryMeta["Waypoints"].setOpen(true)
    setWaypointDropdownOpen(true)
end, waypointDropdownRow)
refreshWaypointDropdown=function()
    for _,marker in pairs(waypointMarkers) do marker:Destroy() end
    table.clear(waypointMarkers)
    for _, child in ipairs(waypointDropdown:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    local names={}
    for name in pairs(waypoints) do table.insert(names,name) end
    local sortRoot=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    table.sort(names,function(a,b)
        if waypointSortNearest and sortRoot then
            return (sortRoot.Position-waypoints[a].Position).Magnitude < (sortRoot.Position-waypoints[b].Position).Magnitude
        end
        return a:lower()<b:lower()
    end)
    if #names==0 then
        create("TextLabel", { Size=UDim2.new(1,0,0,24), BackgroundTransparency=1,
            Text="No saved waypoints", TextColor3=Color3.fromRGB(140,130,155), TextSize=10,
            Font=Enum.Font.Gotham, Parent=waypointDropdown })
        return
    end
    for index,name in ipairs(names) do
        local entry=create("Frame",{Name="WaypointEntry_"..name,Size=UDim2.new(1,0,0,28),
            BackgroundTransparency=1,LayoutOrder=index,Parent=waypointDropdown})
        local rootNow=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local distance=rootNow and math.floor((rootNow.Position-waypoints[name].Position).Magnitude) or 0
        local go=create("TextButton", { Size=UDim2.new(1,-34,0,26), BackgroundColor3=Color3.fromRGB(44,39,60),
            BorderSizePixel=0, Text=name.."  ("..distance.." studs)", TextColor3=Color3.fromRGB(225,220,235),
            TextSize=11, Font=Enum.Font.Gotham, Parent=entry })
        create("UICorner", { CornerRadius=UDim.new(0,5), Parent=go })
        local remove=create("TextButton",{Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-28,0,0),
            BackgroundColor3=Color3.fromRGB(85,45,55),BorderSizePixel=0,Text="X",TextColor3=Color3.fromRGB(255,225,230),
            TextSize=11,Font=Enum.Font.GothamBold,Parent=entry})
        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=remove})
        go.MouseButton1Click:Connect(function()
            local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local point=waypoints[name]
            if root and point then
                lastSelectedWaypoint=name
                waypointBox.Text=name
                root.CFrame=point
                clearCharacterVelocity(LocalPlayer.Character)
            end
        end)
        remove.MouseButton1Click:Connect(function() waypoints[name]=nil; refreshWaypointDropdown() end)
        if waypointMarkersEnabled then
            local marker=Instance.new("Part"); marker.Name="LucidWaypoint_"..name; marker.Anchored=true
            marker.CanCollide=false; marker.CanTouch=false; marker.CanQuery=false; marker.Transparency=1
            marker.Size=Vector3.new(1,1,1); marker.CFrame=waypoints[name]; marker.Parent=workspace
            local bill=Instance.new("BillboardGui"); bill.AlwaysOnTop=true; bill.Size=UDim2.new(0,150,0,30); bill.Adornee=marker; bill.Parent=marker
            local textLabel=Instance.new("TextLabel"); textLabel.Size=UDim2.new(1,0,1,0); textLabel.BackgroundTransparency=1
            textLabel.Text="◆ "..name; textLabel.TextColor3=Color3.fromRGB(255,215,70); textLabel.TextStrokeTransparency=0
            textLabel.TextSize=14; textLabel.Font=Enum.Font.GothamBold; textLabel.Parent=bill
            waypointMarkers[name]=marker
        end
    end
end
refreshWaypointDropdown()
actionButton("Sort Waypoints: Alphabetical",function(button)
    waypointSortNearest=not waypointSortNearest
    button.Text="Sort Waypoints: "..(waypointSortNearest and "Nearest" or "Alphabetical")
    refreshWaypointDropdown()
end)
actionButton("Rename Last Selected",function(button)
    local newName=waypointBox.Text:match("^%s*(.-)%s*$")
    if lastSelectedWaypoint and waypoints[lastSelectedWaypoint] and newName~="" then
        if newName~=lastSelectedWaypoint and waypoints[newName] then button.Text="Name already exists"; return end
        waypoints[newName]=waypoints[lastSelectedWaypoint]
        if newName~=lastSelectedWaypoint then waypoints[lastSelectedWaypoint]=nil end
        lastSelectedWaypoint=newName; refreshWaypointDropdown(); button.Text="Renamed to "..newName
    else button.Text="Select a quick waypoint first" end
end)
createToggle("Show Waypoint Markers",nextOrder(),false,function(on)
    waypointMarkersEnabled=on; refreshWaypointDropdown()
end)
addCleanup(function() for _,marker in pairs(waypointMarkers) do marker:Destroy() end end)
actionButton("Delete Waypoint", function(button)
    waypoints[waypointBox.Text:match("^%s*(.-)%s*$")] = nil
    refreshWaypointDropdown()
    button.Text="Deleted"; task.delay(1, function() if button.Parent then button.Text="Delete Waypoint" end end)
end)
state.waypointApi={
    save=function(name)
        name=tostring(name or ""):match("^%s*(.-)%s*$")
        local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root or name=="" then return false,"Character or name unavailable" end
        waypoints[name]=root.CFrame; waypointBox.Text=name; refreshWaypointDropdown(); return true,"Saved waypoint "..name
    end,
    go=function(name)
        name=tostring(name or ""):match("^%s*(.-)%s*$")
        local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local point=waypoints[name]
        if not root or not point then return false,"Waypoint not found: "..name end
        root.CFrame=point; clearCharacterVelocity(LocalPlayer.Character); waypointBox.Text=name; return true,"Teleported to "..name
    end,
    delete=function(name)
        name=tostring(name or ""):match("^%s*(.-)%s*$")
        if not waypoints[name] then return false,"Waypoint not found: "..name end
        waypoints[name]=nil; refreshWaypointDropdown(); return true,"Deleted waypoint "..name
    end,
    list=function()
        local names={}; for name in pairs(waypoints) do table.insert(names,name) end
        table.sort(names); return names
    end,
}

-- Lighting presets remain fully editable through the existing lighting values.
useCategory("Lighting")
sectionLabel("Comfort Presets", nextOrder())
local originalComfort = { Brightness=Lighting.Brightness, Exposure=Lighting.ExposureCompensation,
    Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient, ClockTime=Lighting.ClockTime }
local function setComfort(clock, brightness, exposure, ambient)
    Lighting.ClockTime=clock; Lighting.Brightness=brightness; Lighting.ExposureCompensation=exposure
    Lighting.Ambient=ambient; Lighting.OutdoorAmbient=ambient
end
local function applySavedComfortPreset()
    if state.comfortPreset=="Migraine" then setComfort(0,1,-1,Color3.fromRGB(55,55,75))
    elseif state.comfortPreset=="Evening" then setComfort(19,1.5,-0.35,Color3.fromRGB(85,70,85))
    elseif state.comfortPreset=="Overcast" then setComfort(12,1,-0.5,Color3.fromRGB(90,90,95)) end
end
local function triggerMigraineComfort()
    state.comfortPreset="Migraine"; applySavedComfortPreset()
end
actionButton("Migraine Comfort", function(button)
    triggerMigraineComfort(); button.Text="Migraine Comfort applied"
end)
actionButton("Evening", function(button)
    state.comfortPreset="Evening"; applySavedComfortPreset(); button.Text="Evening applied"
end)
actionButton("Overcast", function(button)
    state.comfortPreset="Overcast"; applySavedComfortPreset(); button.Text="Overcast applied"
end)
actionButton("Restore Lighting", function()
    state.comfortPreset="None"
    for property, value in pairs(originalComfort) do Lighting[property] = value end
end)
createToggle("Lock Comfort Preset",nextOrder(),false,function(on)
    state.comfortLocked=on
    if on then applySavedComfortPreset() end
end)
local comfortLockElapsed=0
track(RunService.Heartbeat:Connect(function(dt)
    if not state.comfortLocked or state.comfortPreset=="None" then return end
    comfortLockElapsed=comfortLockElapsed+dt
    if comfortLockElapsed>=0.25 then comfortLockElapsed=0; applySavedComfortPreset() end
end))
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

-- Marketplace emote browser. Roblox's catalog API identifies emote
-- animations as asset type 61; only currently on-sale results are requested.
useCategory("Emotes")
state.emoteModuleTabs={root=currentSection}
state.emoteModuleTabs.row=rowFrame(nextOrder(),30)
local emoteTabNames={"All","Favs","Player","Custom","States","Presets"}
for index,name in ipairs(emoteTabNames) do
    local button=create("TextButton",{Size=UDim2.new(0.158,0,0,28),Position=UDim2.new((index-1)*0.168,0,0,0),
        BackgroundColor3=index==1 and Color3.fromRGB(78,55,135) or Color3.fromRGB(48,43,65),BorderSizePixel=0,
        Text=name,TextColor3=Color3.fromRGB(235,230,245),TextSize=10,Font=Enum.Font.GothamSemibold,Parent=state.emoteModuleTabs.row})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=button}); state.emoteModuleTabs[name.."Button"]=button
end
state.emoteModuleTabs.mainButton=state.emoteModuleTabs.AllButton
state.emoteModuleTabs.favoritesButton=state.emoteModuleTabs.FavsButton
state.emoteModuleTabs.main=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=true,LayoutOrder=nextOrder(),Parent=state.emoteModuleTabs.root})
state.emoteModuleTabs.favorites=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=false,LayoutOrder=nextOrder(),Parent=state.emoteModuleTabs.root})
for _,name in ipairs({"player","custom","states","presets","legacy"}) do
    state.emoteModuleTabs[name]=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,Visible=false,LayoutOrder=nextOrder(),Parent=state.emoteModuleTabs.root})
end
state.emoteModuleTabs.new=state.emoteModuleTabs.legacy
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=state.emoteModuleTabs.main})
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=state.emoteModuleTabs.favorites})
for _,name in ipairs({"player","custom","states","presets","legacy"}) do create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=state.emoteModuleTabs[name]}) end
state.emoteModuleTabs.set=function(tab)
    state.emoteModuleTabs.active=tab
    state.emoteModuleTabs.main.Visible=tab=="All"; state.emoteModuleTabs.favorites.Visible=tab=="Favs"
    state.emoteModuleTabs.player.Visible=tab=="Player"
    state.emoteModuleTabs.custom.Visible=tab=="Custom"; state.emoteModuleTabs.states.Visible=tab=="States"
    state.emoteModuleTabs.presets.Visible=tab=="Presets"; state.emoteModuleTabs.legacy.Visible=tab=="Legacy"
    for _,name in ipairs(emoteTabNames) do state.emoteModuleTabs[name.."Button"].BackgroundColor3=tab==name and Color3.fromRGB(78,55,135) or Color3.fromRGB(48,43,65) end
    if state.updateEmoteResultsHeight then task.defer(state.updateEmoteResultsHeight) end
end
state.emoteModuleTabs.mainButton.MouseButton1Click:Connect(function()
    if state.emoteModuleTabs.showMain then state.emoteModuleTabs.showMain(true) else state.emoteModuleTabs.set("All") end
end)
state.emoteModuleTabs.CustomButton.MouseButton1Click:Connect(function() state.emoteModuleTabs.set("Custom") end)
state.emoteModuleTabs.StatesButton.MouseButton1Click:Connect(function() state.emoteModuleTabs.set("States") end)
state.emoteModuleTabs.PresetsButton.MouseButton1Click:Connect(function() state.emoteModuleTabs.set("Presets") end)
currentSection=state.emoteModuleTabs.main
sectionLabel("Marketplace Emote Browser", nextOrder())
local EMOTE_FAVORITES_PATH="LucidPanel/emote_favorites.json"
local function saveGlobalEmoteFavorites()
    if not writefile then return false end
    pcall(function()
        if makefolder and (not isfolder or not isfolder("LucidPanel")) then makefolder("LucidPanel") end
    end)
    local payload={version=3,favorites=state.emoteFavorites or {},aliases=state.emoteAliases or {},
        history=state.emoteHistory or {},playlists=state.emotePlaylists or {},speeds=state.emoteSpeeds or {},
        recentSyncPlayers=state.emoteRecentSyncPlayers or {},lastEmote=state.emoteLast,searchCache=state.emoteSearchCache or {},
        customs=state.emoteCustoms or {},stateAnimations=state.emoteStateAnimations or {},
        stateSpeeds=state.emoteStateSpeeds or {},statePresets=state.emoteStatePresets or {}}
    local encodedOk,encoded=pcall(function() return HttpService:JSONEncode(payload) end)
    return encodedOk and pcall(writefile,EMOTE_FAVORITES_PATH,encoded)
end
local function loadGlobalEmoteFavorites()
    if not readfile or (isfile and not isfile(EMOTE_FAVORITES_PATH)) then return end
    local ok,decoded=pcall(function() return HttpService:JSONDecode(readfile(EMOTE_FAVORITES_PATH)) end)
    if ok and type(decoded)=="table" then
        if type(decoded.favorites)=="table" then
            state.emoteFavorites=decoded.favorites
            state.emoteAliases=type(decoded.aliases)=="table" and decoded.aliases or {}
            state.emoteHistory=type(decoded.history)=="table" and decoded.history or {}
            state.emotePlaylists=type(decoded.playlists)=="table" and decoded.playlists or {}
            state.emoteSpeeds=type(decoded.speeds)=="table" and decoded.speeds or {}
            state.emoteRecentSyncPlayers=type(decoded.recentSyncPlayers)=="table" and decoded.recentSyncPlayers or {}
            state.emoteLast=type(decoded.lastEmote)=="table" and decoded.lastEmote or nil
            state.emoteSearchCache=type(decoded.searchCache)=="table" and decoded.searchCache or {}
            state.emoteCustoms=type(decoded.customs)=="table" and decoded.customs or {}
            state.emoteStateAnimations=type(decoded.stateAnimations)=="table" and decoded.stateAnimations or state.emoteStateAnimations
            state.emoteStateSpeeds=type(decoded.stateSpeeds)=="table" and decoded.stateSpeeds or state.emoteStateSpeeds
            state.emoteStatePresets=type(decoded.statePresets)=="table" and decoded.statePresets or {}
        else
            -- Version 1 stored the favorites table directly.
            state.emoteFavorites=decoded
        end
    end
end
local function mergeLegacyEmoteFavorites(legacyFavorites)
    if type(legacyFavorites)~="table" then return end
    local changed=false
    for id,info in pairs(legacyFavorites) do
        if state.emoteFavorites[tostring(id)]==nil and type(info)=="table" then
            state.emoteFavorites[tostring(id)]=info; changed=true
        end
    end
    if changed then saveGlobalEmoteFavorites() end
end
loadGlobalEmoteFavorites()
local emoteSearchRow=rowFrame(nextOrder(),30)
local emoteSearchBox=styledBox(emoteSearchRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Search on-sale emotes..."})
local emoteSearchButton=create("TextButton",{Size=UDim2.new(0,64,0,26),Position=UDim2.new(1,-64,0,0),
    BackgroundColor3=Color3.fromRGB(75,50,160),BorderSizePixel=0,Text="Search",TextColor3=Color3.new(1,1,1),
    TextSize=10,Font=Enum.Font.GothamSemibold,Parent=emoteSearchRow})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=emoteSearchButton})
local emoteSpeedRow=rowFrame(nextOrder(),28)
create("TextLabel",{Size=UDim2.new(1,-78,1,0),BackgroundTransparency=1,Text="Playback speed (0.1-5)",
    TextColor3=Color3.fromRGB(195,185,215),TextSize=11,Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=emoteSpeedRow})
local emoteSpeedBox=styledBox(emoteSpeedRow,{Size=UDim2.new(0,70,0,24),Position=UDim2.new(1,-70,0.5,-12),Text="1"})
local emoteSpeed=state.emoteSpeed
local emoteTrack=nil
local emoteAnimation=nil
local currentEmoteName=nil
local emoteResumeBusy=false
local emoteSyncPlayer=nil
local emoteSyncActive=false
local emoteSyncAnimationId=nil
local emoteSyncElapsed=0
createToggle("Keep Emote While Moving",nextOrder(),true,function(on)
    state.keepEmoteMoving=on
end)
emoteSpeedBox.FocusLost:Connect(function()
    emoteSpeed=math.clamp(tonumber(emoteSpeedBox.Text) or emoteSpeed,0.1,5)
    state.emoteSpeed=emoteSpeed
    emoteSpeedBox.Text=string.format("%.1f",emoteSpeed)
    if emoteTrack then pcall(function() emoteTrack:AdjustSpeed(emoteSpeed) end) end
end)
local emoteStatus=create("TextLabel",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,
    Text="Search to load emotes",TextColor3=Color3.fromRGB(160,150,180),TextSize=10,
    Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=nextOrder(),Parent=currentSection})
local emoteTabRow=rowFrame(nextOrder(),28)
local browseEmotesButton=create("TextButton",{Size=UDim2.new(0.49,0,0,26),BackgroundColor3=Color3.fromRGB(78,55,135),
    BorderSizePixel=0,Text="Browse",TextColor3=Color3.new(1,1,1),TextSize=11,Font=Enum.Font.GothamSemibold,Parent=emoteTabRow})
local favoriteEmotesButton=create("TextButton",{Size=UDim2.new(0.49,0,0,26),Position=UDim2.new(0.51,0,0,0),
    BackgroundColor3=Color3.fromRGB(48,43,65),BorderSizePixel=0,Text="Favorites",
    TextColor3=Color3.fromRGB(225,215,235),TextSize=11,Font=Enum.Font.GothamSemibold,Parent=emoteTabRow})
create("UICorner",{CornerRadius=UDim.new(0,5),Parent=browseEmotesButton}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=favoriteEmotesButton})
emoteTabRow.Visible=false
local mainFavoriteSearchRow=rowFrame(nextOrder(),30)
mainFavoriteSearchRow.Parent=state.emoteModuleTabs.favorites
mainFavoriteSearchRow.Visible=false
local mainFavoriteSearchBox=styledBox(mainFavoriteSearchRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Search favorite emotes/aliases..."})
local mainFavoriteSearchButton=create("TextButton",{Size=UDim2.new(0,64,0,26),Position=UDim2.new(1,-64,0,0),
    BackgroundColor3=Color3.fromRGB(75,50,160),BorderSizePixel=0,Text="Search",TextColor3=Color3.new(1,1,1),
    TextSize=10,Font=Enum.Font.GothamSemibold,Parent=mainFavoriteSearchRow})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=mainFavoriteSearchButton})
local emoteResults=create("ScrollingFrame",{Size=UDim2.new(1,0,0,190),CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(29,27,39),
    BackgroundTransparency=0.2,BorderSizePixel=0,ScrollBarThickness=3,LayoutOrder=nextOrder(),Parent=currentSection})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=emoteResults})
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=emoteResults})
local emoteView="browse"
local emoteCursor=nil
local emotePages=nil
local emoteQuery=""
local emoteLoading=false
local emoteRequestGeneration=0
local function stopEmote()
    emoteSyncActive=false; emoteSyncPlayer=nil; emoteSyncAnimationId=nil; emoteSyncElapsed=0
    if emoteTrack then pcall(function() emoteTrack:Stop(0.15) end) end
    if emoteAnimation then emoteAnimation:Destroy() end
    emoteTrack=nil; emoteAnimation=nil; currentEmoteName=nil
    emoteResumeBusy=false
    emoteStatus.Text="Emote stopped"
end
local stopEmoteButton=actionButton("Stop Emote",function() stopEmote() end,Color3.fromRGB(85,48,62))
stopEmoteButton.Size=UDim2.new(0,76,0,24); stopEmoteButton.Position=UDim2.new(1,-76,0,0)
state.emoteModuleTabs.favoriteStopRow=create("Frame",{Size=UDim2.new(1,0,0,32),BackgroundTransparency=1,
    LayoutOrder=nextOrder(),Parent=state.emoteModuleTabs.favorites})
state.emoteModuleTabs.favoriteStopButton=create("TextButton",{Size=UDim2.new(0,76,0,24),Position=UDim2.new(1,-76,0,2),
    BackgroundColor3=Color3.fromRGB(85,48,62),BorderSizePixel=0,Text="Stop Emote",
    TextColor3=Color3.fromRGB(235,230,245),TextSize=12,Font=Enum.Font.GothamSemibold,
    Parent=state.emoteModuleTabs.favoriteStopRow})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=state.emoteModuleTabs.favoriteStopButton})
state.emoteModuleTabs.favoriteStopButton.MouseButton1Click:Connect(stopEmote)
emoteResults.LayoutOrder=nextOrder()
local function playEmote(assetId,name)
    emoteSyncActive=false; emoteSyncPlayer=nil; emoteSyncAnimationId=nil
    stopEmote()
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator and humanoid then animator=Instance.new("Animator"); animator.Parent=humanoid end
    if not animator then emoteStatus.Text="Character Animator unavailable"; return false end
    local savedSpeed=tonumber((state.emoteSpeeds or {})[tostring(assetId)])
    if savedSpeed then
        emoteSpeed=math.clamp(savedSpeed,0.1,5); state.emoteSpeed=emoteSpeed
        emoteSpeedBox.Text=string.format("%.1f",emoteSpeed)
    end
    local emoteKey="Lucid_"..tostring(assetId)
    local track=nil
    local tracksBefore={}
    for _,playing in ipairs(animator:GetPlayingAnimationTracks()) do tracksBefore[playing]=true end
    local nativeOk=pcall(function()
        local description=humanoid:FindFirstChildOfClass("HumanoidDescription") or humanoid.HumanoidDescription
        description:AddEmote(emoteKey,tonumber(assetId))
        humanoid:PlayEmote(emoteKey)
    end)
    if nativeOk then
        task.wait(0.15)
        local newest=nil
        for _,playing in ipairs(animator:GetPlayingAnimationTracks()) do
            if not tracksBefore[playing] and (not newest or playing.Priority.Value>=newest.Priority.Value) then newest=playing end
        end
        track=newest
    end
    if not track then
        local animation=Instance.new("Animation"); animation.AnimationId="rbxassetid://"..tostring(assetId)
        local ok,loaded=pcall(function() return animator:LoadAnimation(animation) end)
        if not ok or not loaded then
            animation:Destroy(); state.unavailableEmoteIds[tostring(assetId)]=true
            emoteStatus.Text="Unavailable/private emote: "..tostring(name)
            notifyLucid("Emote unavailable",tostring(name).." was denied by Roblox",Color3.fromRGB(230,90,105))
            return false
        end
        emoteAnimation=animation; track=loaded; track:Play(0.15,1,emoteSpeed)
    end
    emoteTrack=track; currentEmoteName=name
    state.emoteCurrent={id=tonumber(assetId) or assetId,name=name}; state.emoteLast=state.emoteCurrent
    track.Priority=Enum.AnimationPriority.Action4; track.Looped=state.emoteLoopMode~="Once"; track:AdjustSpeed(emoteSpeed)
    emoteStatus.Text="Playing: "..name.."  |  "..string.format("%.1fx",emoteSpeed)
    if state.emoteAdvancedOnPlayed then task.defer(state.emoteAdvancedOnPlayed,state.emoteCurrent,track) end
    return true
end
track(RunService.Heartbeat:Connect(function(dt)
    if emoteSyncActive or not state.keepEmoteMoving or not currentEmoteName or not emoteTrack or emoteResumeBusy then return end
    state.emoteResumeElapsed=(state.emoteResumeElapsed or 0)+dt
    if state.emoteResumeElapsed<(state.lowPerformanceMode and 0.25 or 0.1) then return end
    state.emoteResumeElapsed=0
    if not emoteTrack.IsPlaying then
        emoteResumeBusy=true
        task.defer(function()
            if state.keepEmoteMoving and currentEmoteName and emoteTrack then
                pcall(function()
                    emoteTrack.Priority=Enum.AnimationPriority.Action4
                    emoteTrack.Looped=true
                    emoteTrack:Play(0.05,1,emoteSpeed)
                    emoteTrack:AdjustSpeed(emoteSpeed)
                end)
            end
            emoteResumeBusy=false
        end)
    end
end))
sectionLabel("Player Emote Sync",nextOrder())
local emoteSyncSettingsRow=rowFrame(nextOrder(),28)
create("TextLabel",{Size=UDim2.new(1,-78,1,0),BackgroundTransparency=1,Text="Sync tolerance (seconds)",
    TextColor3=Color3.fromRGB(195,185,215),TextSize=11,Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=emoteSyncSettingsRow})
local emoteSyncToleranceBox=styledBox(emoteSyncSettingsRow,{Size=UDim2.new(0,70,0,24),
    Position=UDim2.new(1,-70,0.5,-12),Text=tostring(state.emoteSyncTolerance)})
emoteSyncToleranceBox.FocusLost:Connect(function()
    state.emoteSyncTolerance=math.clamp(tonumber(emoteSyncToleranceBox.Text) or state.emoteSyncTolerance,0.01,2)
    emoteSyncToleranceBox.Text=string.format("%.2f",state.emoteSyncTolerance)
end)
local emoteSyncRow=rowFrame(nextOrder(),30)
local emoteSyncBox=styledBox(emoteSyncRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Username or display name"})
local emoteSyncButton=create("TextButton",{Size=UDim2.new(0,64,0,26),Position=UDim2.new(1,-64,0,0),
    BackgroundColor3=Color3.fromRGB(58,120,88),BorderSizePixel=0,Text="Sync",TextColor3=Color3.new(1,1,1),
    TextSize=10,Font=Enum.Font.GothamSemibold,Parent=emoteSyncRow})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=emoteSyncButton})

local function findEmoteSyncPlayer(query)
    query=tostring(query or ""):match("^%s*(.-)%s*$"):lower()
    if query=="" then return nil end
    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LocalPlayer and (player.Name:lower()==query or player.DisplayName:lower()==query) then return player end
    end
    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LocalPlayer and (player.Name:lower():sub(1,#query)==query
            or player.DisplayName:lower():sub(1,#query)==query) then return player end
    end
end

local function getSyncSourceTrack(player)
    local humanoid=player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end
    local best=nil
    for _,playing in ipairs(animator:GetPlayingAnimationTracks()) do
        local animation=playing.Animation
        local animationId=animation and animation.AnimationId
        if playing.IsPlaying and animationId and animationId~=""
            and playing.Priority.Value>=Enum.AnimationPriority.Action.Value then
            if animationId==emoteSyncAnimationId then return playing end
            if not best or playing.Priority.Value>best.Priority.Value
                or (playing.Priority==best.Priority and playing.WeightCurrent>best.WeightCurrent) then best=playing end
        end
    end
    return best
end

local function loadSyncedTrack(sourceTrack)
    local animationId=sourceTrack.Animation and sourceTrack.Animation.AnimationId
    if not animationId or animationId=="" then return false end
    if emoteTrack then pcall(function() emoteTrack:Stop(0.05) end) end
    if emoteAnimation then emoteAnimation:Destroy() end
    local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator and humanoid then animator=Instance.new("Animator"); animator.Parent=humanoid end
    if not animator then return false end
    local animation=Instance.new("Animation"); animation.AnimationId=animationId
    local ok,loaded=pcall(function() return animator:LoadAnimation(animation) end)
    if not ok or not loaded then animation:Destroy(); return false end
    emoteAnimation=animation; emoteTrack=loaded; emoteSyncAnimationId=animationId
    currentEmoteName="Synced with "..emoteSyncPlayer.Name
    loaded.Priority=Enum.AnimationPriority.Action4; loaded.Looped=sourceTrack.Looped
    loaded:Play(0.05,1,sourceTrack.Speed)
    loaded:AdjustWeight(1,0.05)
    pcall(function() loaded.TimePosition=sourceTrack.TimePosition end)
    return true
end

local function stopEmoteSync(stopPlayback)
    emoteSyncActive=false; emoteSyncPlayer=nil; emoteSyncAnimationId=nil; emoteSyncElapsed=0
    if stopPlayback then stopEmote() end
end

local function beginEmoteSync()
    local player=findEmoteSyncPlayer(emoteSyncBox.Text)
    if not player then emoteStatus.Text="Sync player not found"; return end
    stopEmote()
    emoteSyncPlayer=player; emoteSyncActive=true; emoteSyncElapsed=1
    table.insert(state.emoteRecentSyncPlayers,1,player.Name)
    for index=#state.emoteRecentSyncPlayers,2,-1 do
        if state.emoteRecentSyncPlayers[index]==player.Name then table.remove(state.emoteRecentSyncPlayers,index) end
    end
    while #state.emoteRecentSyncPlayers>6 do table.remove(state.emoteRecentSyncPlayers) end
    saveGlobalEmoteFavorites()
    local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local targetHumanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid and targetHumanoid and humanoid.RigType~=targetHumanoid.RigType then
        notifyLucid("Emote rig mismatch","Your rig and "..player.Name.." use different rig types; some poses may distort.",Color3.fromRGB(235,175,70))
    end
    emoteStatus.Text="Waiting for "..player.Name.." to emote..."
end
emoteSyncButton.MouseButton1Click:Connect(beginEmoteSync)
emoteSyncBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then beginEmoteSync() end
end)
local stopSyncButton=actionButton("Stop Sync",function(button)
    stopEmoteSync(true); button.Text="Emote sync stopped"
    task.delay(1,function() if button.Parent then button.Text="Stop Sync" end end)
end,Color3.fromRGB(85,48,62))
stopSyncButton.Size=UDim2.new(0,68,0,24); stopSyncButton.Position=UDim2.new(1,-68,0,0)

track(RunService.Heartbeat:Connect(function(dt)
    if not emoteSyncActive then return end
    emoteSyncElapsed=emoteSyncElapsed+dt
    if emoteSyncElapsed<(state.lowPerformanceMode and 0.25 or 0.12) then return end
    emoteSyncElapsed=0
    if not emoteSyncPlayer or emoteSyncPlayer.Parent~=Players then
        emoteStatus.Text="Sync player left the server"; stopEmoteSync(true); return
    end
    local sourceTrack=getSyncSourceTrack(emoteSyncPlayer)
    if not sourceTrack then
        if emoteTrack and emoteTrack.IsPlaying then pcall(function() emoteTrack:Stop(0.1) end) end
        emoteStatus.Text="Waiting for "..emoteSyncPlayer.Name.." to emote..."
        return
    end
    local sourceId=sourceTrack.Animation and sourceTrack.Animation.AnimationId
    if not emoteTrack or sourceId~=emoteSyncAnimationId then
        if not loadSyncedTrack(sourceTrack) then emoteStatus.Text="Could not load target emote"; return end
    end
    if state.emotePoseHeld then
        pcall(function() emoteTrack:AdjustSpeed(0) end)
        emoteStatus.Text="Synced pose held with "..emoteSyncPlayer.Name
        return
    end
    pcall(function()
        if not emoteTrack.IsPlaying then emoteTrack:Play(0.05,1,sourceTrack.Speed) end
        local syncMode=state.emoteSyncMode
        if syncMode=="Animation" then emoteTrack:AdjustSpeed(emoteSpeed) else emoteTrack:AdjustSpeed(sourceTrack.Speed) end
        local drift=math.abs(emoteTrack.TimePosition-sourceTrack.TimePosition)
        local trackLength=math.max(emoteTrack.Length,sourceTrack.Length)
        if trackLength>0 then drift=math.min(drift,math.abs(trackLength-drift)) end
        local desired=math.max(0,sourceTrack.TimePosition+(tonumber(state.emoteSyncDelay) or 0))
        if syncMode=="Precise" and drift>state.emoteSyncTolerance then
            emoteTrack.TimePosition=desired
        elseif syncMode=="Smooth" then
            local signedDrift=desired-emoteTrack.TimePosition
            if math.abs(signedDrift)>state.emoteSyncTolerance*3 then emoteTrack.TimePosition=desired
            else emoteTrack:AdjustSpeed(math.clamp(sourceTrack.Speed+signedDrift*0.35,0.1,5)) end
        end
    end)
    emoteStatus.Text="Synced with "..emoteSyncPlayer.Name.." | "..tostring(state.emoteSyncMode).." | "..tostring(sourceId)
end))
local function clearEmoteResults()
    for _,child in ipairs(emoteResults:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
end
local loadEmoteResults
local function createEmoteResult(id,name,badge)
    local row=create("Frame",{Size=UDim2.new(1,-4,0,30),BackgroundTransparency=1,Parent=emoteResults})
    local unavailable=state.unavailableEmoteIds[tostring(id)]==true
    local button=create("TextButton",{Size=UDim2.new(1,-36,0,28),BackgroundColor3=Color3.fromRGB(45,40,62),
        BorderSizePixel=0,Text=unavailable and ("Unavailable — "..name)
            or ((badge and (badge.."  ") or "")..(state.emoteAliases[tostring(id)] or name)),
        TextColor3=unavailable and Color3.fromRGB(220,120,135) or Color3.fromRGB(230,225,240),TextSize=11,
        Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=row})
    create("UIPadding",{PaddingLeft=UDim.new(0,8),Parent=button})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=button})
    local star=create("TextButton",{Size=UDim2.new(0,30,0,28),Position=UDim2.new(1,-30,0,0),
        BackgroundColor3=Color3.fromRGB(55,48,70),BorderSizePixel=0,
        Text=state.emoteFavorites[tostring(id)] and "★" or "☆",
        TextColor3=state.emoteFavorites[tostring(id)] and Color3.fromRGB(255,215,55) or Color3.fromRGB(155,145,175),
        TextSize=17,Font=Enum.Font.GothamBold,Parent=row})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=star})
    button.MouseButton1Click:Connect(function()
        if state.unavailableEmoteIds[tostring(id)] then
            button.Text="Unavailable — "..name; button.TextColor3=Color3.fromRGB(220,120,135); return
        end
        if playEmote(id,name)==false then
            button.Text="Unavailable — "..name; button.TextColor3=Color3.fromRGB(220,120,135)
        end
    end)
    star.MouseButton1Click:Connect(function()
        local key=tostring(id)
        if state.emoteFavorites[key] then state.emoteFavorites[key]=nil else state.emoteFavorites[key]={id=id,name=name} end
        saveGlobalEmoteFavorites()
        star.Text=state.emoteFavorites[key] and "★" or "☆"
        star.TextColor3=state.emoteFavorites[key] and Color3.fromRGB(255,215,55) or Color3.fromRGB(155,145,175)
        if emoteView=="favorites" then row:Destroy() end
    end)
end

-- Browse emotes belonging to any player currently in this server. Equipped
-- emotes come from HumanoidDescription; unequipped ownership is supplemented
-- from the public Roblox inventory API when the player's inventory is open.
state.initializePlayerEmoteBrowser=function()
    local previousSection=currentSection
    currentSection=state.emoteModuleTabs.player
    sectionLabel("Player Emote Library",nextOrder())
    local playerRow=rowFrame(nextOrder(),30)
    local playerBox=styledBox(playerRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="In-game username/display name"})
    local loadButton=create("TextButton",{Size=UDim2.new(0,64,0,26),Position=UDim2.new(1,-64,0,0),
        BackgroundColor3=Color3.fromRGB(58,120,88),BorderSizePixel=0,Text="Load",
        TextColor3=Color3.new(1,1,1),TextSize=10,Font=Enum.Font.GothamSemibold,Parent=playerRow})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=loadButton})
    local playerStopRow=rowFrame(nextOrder(),24)
    local playerStopButton=create("TextButton",{Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-44,0,0),
        BackgroundColor3=Color3.fromRGB(85,48,62),BorderSizePixel=0,Text="Stop",
        TextColor3=Color3.fromRGB(235,230,245),TextSize=11,Font=Enum.Font.GothamSemibold,
        Parent=playerStopRow})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=playerStopButton})
    playerStopButton.MouseButton1Click:Connect(function()
        stopEmote(); playerStopButton.Text="Stopped"
        task.delay(1,function() if playerStopButton.Parent then playerStopButton.Text="Stop" end end)
    end)
    local filterRow=rowFrame(nextOrder(),30)
    local filterBox=styledBox(filterRow,{Size=UDim2.new(1,0,0,26),Text="",PlaceholderText="Filter this player's emotes..."})
    local status=create("TextLabel",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,
        Text="Enter yourself or another player currently in this server.",TextWrapped=true,
        TextColor3=Color3.fromRGB(165,155,185),TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        LayoutOrder=nextOrder(),Parent=currentSection})
    local function findPlayer(query)
        query=tostring(query or ""):match("^%s*(.-)%s*$"):lower()
        if query=="" then return LocalPlayer end
        for _,player in ipairs(Players:GetPlayers()) do
            if player.Name:lower()==query or player.DisplayName:lower()==query then return player end
        end
        for _,player in ipairs(Players:GetPlayers()) do
            if player.Name:lower():sub(1,#query)==query or player.DisplayName:lower():sub(1,#query)==query then return player end
        end
    end
    local function renderPlayerEmotes()
        emoteView="player"; clearEmoteResults(); emoteResults.Parent=state.emoteModuleTabs.player
        local query=filterBox.Text:match("^%s*(.-)%s*$"):lower()
        local shown=0
        for _,item in ipairs(state.playerEmoteBrowserResults or {}) do
            if query=="" or item.name:lower():find(query,1,true) then
                createEmoteResult(item.id,item.name,item.equipped and "[Equipped]" or "[Owned]")
                shown=shown+1
            end
        end
        if shown==0 and state.playerEmoteBrowserResults then status.Text="No emotes match this filter." end
    end
    local function loadPlayerEmotes()
        local player=findPlayer(playerBox.Text)
        if not player then status.Text="Player not found in this server."; return end
        playerBox.Text=player.Name; loadButton.Text="Loading..."; status.Text="Loading "..player.Name.."'s emotes..."
        task.spawn(function()
            local results={}
            local byId={}
            local equippedNames={}
            local descriptionOk,description=pcall(function()
                return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
            end)
            if descriptionOk and description then
                pcall(function()
                    for _,entry in ipairs(description:GetEquippedEmotes()) do equippedNames[tostring(entry.Name):lower()]=true end
                    for emoteName,ids in pairs(description:GetEmotes()) do
                        for _,id in ipairs(ids) do
                            local key=tostring(id)
                            if not byId[key] then
                                local item={id=id,name=tostring(emoteName),equipped=equippedNames[tostring(emoteName):lower()]==true}
                                byId[key]=item; table.insert(results,item)
                            end
                        end
                    end
                end)
            end
            local inventoryOpen=true
            local cursor=nil
            local pages=0
            repeat
                pages=pages+1
                local url="https://inventory.roblox.com/v2/users/"..player.UserId.."/inventory/61?limit=100&sortOrder=Asc"
                if cursor then url=url.."&cursor="..HttpService:UrlEncode(cursor) end
                local ok,body=pcall(function() return game:HttpGet(url,true) end)
                if not ok or type(body)~="string" or body:sub(1,1)~="{" then inventoryOpen=false; break end
                local decodedOk,decoded=pcall(function() return HttpService:JSONDecode(body) end)
                if not decodedOk or type(decoded)~="table" then inventoryOpen=false; break end
                for _,entry in ipairs(decoded.data or {}) do
                    local id=entry.assetId or entry.AssetId or (type(entry.asset)=="table" and (entry.asset.id or entry.asset.assetId))
                    if id and not byId[tostring(id)] then
                        local item={id=id,name=tostring(entry.name or entry.Name or (type(entry.asset)=="table" and entry.asset.name) or ("Emote "..id)),equipped=false}
                        byId[tostring(id)]=item; table.insert(results,item)
                    end
                end
                cursor=decoded.nextPageCursor
            until not cursor or cursor=="" or pages>=20
            table.sort(results,function(a,b)
                if a.equipped~=b.equipped then return a.equipped end
                return a.name:lower()<b.name:lower()
            end)
            state.playerEmoteBrowserResults=results
            local equippedCount=0
            for _,item in ipairs(results) do if item.equipped then equippedCount=equippedCount+1 end end
            local ownedCount=#results-equippedCount
            loadButton.Text="Load"
            status.Text=string.format("%s — %d equipped, %d unequipped%s",player.Name,equippedCount,ownedCount,
                inventoryOpen and "" or " | inventory private/unavailable")
            renderPlayerEmotes()
        end)
    end
    state.emoteModuleTabs.PlayerButton.MouseButton1Click:Connect(function()
        state.emoteModuleTabs.set("Player"); emoteResults.Parent=state.emoteModuleTabs.player
        if state.playerEmoteBrowserResults then renderPlayerEmotes() end
    end)
    loadButton.MouseButton1Click:Connect(loadPlayerEmotes)
    playerBox.FocusLost:Connect(function(enterPressed) if enterPressed then loadPlayerEmotes() end end)
    filterBox:GetPropertyChangedSignal("Text"):Connect(function()
        if state.emoteModuleTabs.active=="Player" and state.playerEmoteBrowserResults then renderPlayerEmotes() end
    end)
    currentSection=previousSection
end
state.initializePlayerEmoteBrowser()

local function showFavoriteEmotes()
    emoteView="favorites"; clearEmoteResults()
    state.emoteModuleTabs.set("Favs"); emoteResults.Parent=state.emoteModuleTabs.favorites
    mainFavoriteSearchRow.Visible=true; mainFavoriteSearchBox.Text=tostring(state.emoteFavoriteQuery or "")
    browseEmotesButton.BackgroundColor3=Color3.fromRGB(48,43,65)
    favoriteEmotesButton.BackgroundColor3=Color3.fromRGB(78,55,135)
    local favorites={}
    local query=tostring(state.emoteFavoriteQuery or ""):lower()
    for id,info in pairs(state.emoteFavorites or {}) do
        local shown=tostring(state.emoteAliases[tostring(id)] or info.name)
        if query=="" or shown:lower():find(query,1,true) or tostring(info.name):lower():find(query,1,true) then table.insert(favorites,info) end
    end
    table.sort(favorites,function(a,b)
        return tostring(state.emoteAliases[tostring(a.id)] or a.name):lower()<tostring(state.emoteAliases[tostring(b.id)] or b.name):lower()
    end)
    for _,info in ipairs(favorites) do createEmoteResult(info.id,info.name) end
    emoteStatus.Text=#favorites>0 and ("Favorite emotes: "..#favorites) or "No favorite emotes yet"
end
state.emoteModuleTabs.showMain=function(refreshContents)
    state.emoteModuleTabs.set("All"); emoteResults.Parent=state.emoteModuleTabs.main
    mainFavoriteSearchRow.Visible=false
    if refreshContents and emoteView~="browse" then
        emoteView="browse"; emoteQuery=emoteSearchBox.Text:match("^%s*(.-)%s*$")
        task.defer(function() if loadEmoteResults then loadEmoteResults(false) end end)
    end
end
browseEmotesButton.MouseButton1Click:Connect(function()
    state.emoteModuleTabs.showMain(false)
    emoteView="browse"; browseEmotesButton.BackgroundColor3=Color3.fromRGB(78,55,135)
    favoriteEmotesButton.BackgroundColor3=Color3.fromRGB(48,43,65)
    mainFavoriteSearchRow.Visible=false
    emoteQuery=emoteSearchBox.Text:match("^%s*(.-)%s*$"); loadEmoteResults(false)
end)
favoriteEmotesButton.MouseButton1Click:Connect(showFavoriteEmotes)
state.emoteModuleTabs.favoritesButton.MouseButton1Click:Connect(showFavoriteEmotes)
mainFavoriteSearchButton.MouseButton1Click:Connect(function()
    state.emoteFavoriteQuery=mainFavoriteSearchBox.Text:match("^%s*(.-)%s*$"); showFavoriteEmotes()
end)
mainFavoriteSearchBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then state.emoteFavoriteQuery=mainFavoriteSearchBox.Text:match("^%s*(.-)%s*$"); showFavoriteEmotes() end
end)
loadEmoteResults=function(append)
    state.emoteModuleTabs.showMain(false)
    emoteView="browse"
    mainFavoriteSearchRow.Visible=false
    browseEmotesButton.BackgroundColor3=Color3.fromRGB(78,55,135)
    favoriteEmotesButton.BackgroundColor3=Color3.fromRGB(48,43,65)
    emoteLoading=true; emoteSearchButton.Text="Loading..."
    emoteRequestGeneration=emoteRequestGeneration+1
    local generation=emoteRequestGeneration
    if not append then emoteCursor=nil; emotePages=nil; clearEmoteResults() end
    local completed=false
    local ok=false
    local data=nil
    local cacheKey=emoteQuery:lower()
    local cached=not append and state.emoteSearchCache[cacheKey]
    if cached and type(cached.items)=="table" and os.time()-(tonumber(cached.savedAt) or 0)<604800 then
        ok=true; data=cached.items; completed=true
    else task.spawn(function()
        ok,data=pcall(function()
            if append and emotePages then
                if emotePages.IsFinished then return {} end
                emotePages:AdvanceToNextPageAsync()
                return emotePages:GetCurrentPage()
            end
            if append and emoteCursor and not emotePages then error("Continue HTTP catalog cursor") end
            local params=CatalogSearchParams.new()
            params.SearchKeyword=emoteQuery
            params.AssetTypes={Enum.AvatarAssetType.EmoteAnimation}
            params.IncludeOffSale=false
            params.SalesTypeFilter=Enum.SalesTypeFilter.All
            params.SortType=Enum.CatalogSortType.Relevance
            params.Limit=math.clamp(tonumber(state.emoteResultLimit) or 30,10,30)
            emotePages=AvatarEditorService:SearchCatalogAsync(params)
            return emotePages:GetCurrentPage()
        end)
        if not ok then
            local url="https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=39&IncludeNotForSale=false&salesTypeFilter=1&Limit="..math.clamp(tonumber(state.emoteResultLimit) or 30,10,30).."&SortType=0&SortAggregation=5"
            if emoteQuery~="" then url=url.."&Keyword="..HttpService:UrlEncode(emoteQuery) end
            if append and emoteCursor then url=url.."&Cursor="..HttpService:UrlEncode(emoteCursor) end
            local httpOk,body=pcall(function() return game:HttpGet(url,true) end)
            if httpOk and type(body)=="string" and body:sub(1,1)=="{" then
                local decoded=HttpService:JSONDecode(body)
                data=decoded.data; emoteCursor=decoded.nextPageCursor; ok=type(data)=="table"
            end
        end
        completed=true
    end) end
    local started=os.clock()
    while not completed and os.clock()-started<12 and generation==emoteRequestGeneration do task.wait(0.1) end
    if generation~=emoteRequestGeneration then return end
    if not completed then
        emoteLoading=false; emoteSearchButton.Text="Search"
        emoteStatus.Text="Catalog request timed out — try again"
        return
    end
    if ok and type(data)=="table" then
        local filtered={}
        local cacheItems={}
        for _,item in ipairs(data) do
            local id=item.Id or item.id or item.AssetId or item.assetId
            if id then
                local name=tostring(item.Name or item.name or ("Emote "..id))
                table.insert(cacheItems,{id=id,name=name})
                local category=state.emoteCategoryFilter or "All"
                local lower=name:lower()
                local matches=category=="All"
                    or (category=="Dance" and (lower:find("dance",1,true) or lower:find("shuffle",1,true)))
                    or (category=="Pose" and (lower:find("pose",1,true) or lower:find("stance",1,true)))
                    or (category=="Idle" and (lower:find("idle",1,true) or lower:find("sit",1,true)))
                    or (category=="Movement" and (lower:find("walk",1,true) or lower:find("run",1,true) or lower:find("move",1,true)))
                if matches then table.insert(filtered,{id=id,name=name}) end
            end
        end
        table.sort(filtered,function(a,b) return a.name:lower()<b.name:lower() end)
        for _,item in ipairs(filtered) do createEmoteResult(item.id,item.name) end
        if not append and not cached then
            state.emoteSearchCache[cacheKey]={savedAt=os.time(),items=cacheItems}
            local cacheKeys={}; for key,entry in pairs(state.emoteSearchCache) do table.insert(cacheKeys,{key=key,time=tonumber(entry.savedAt) or 0}) end
            table.sort(cacheKeys,function(a,b) return a.time>b.time end)
            for index=13,#cacheKeys do state.emoteSearchCache[cacheKeys[index].key]=nil end
            saveGlobalEmoteFavorites()
        end
        emoteStatus.Text=#filtered>0 and ("Found "..#filtered.." — click a name to play") or "No emotes matched this search/filter"
    else
        emoteStatus.Text="Catalog search unavailable: "..tostring(data or "unknown error")
    end
    emoteLoading=false; emoteSearchButton.Text="Search"
end
emoteSearchButton.MouseButton1Click:Connect(function()
    emoteQuery=emoteSearchBox.Text:match("^%s*(.-)%s*$"); loadEmoteResults(false)
end)
emoteSearchBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then emoteQuery=emoteSearchBox.Text:match("^%s*(.-)%s*$"); loadEmoteResults(false) end
end)
local loadMoreEmotesButton=actionButton("Load More Emotes",function(button)
    if (emotePages and not emotePages.IsFinished) or emoteCursor then loadEmoteResults(true)
    else button.Text="No more results"; task.delay(1,function() if button.Parent then button.Text="Load More Emotes" end end) end
end)
loadMoreEmotesButton.Parent.LayoutOrder=emoteResults.LayoutOrder
emoteResults.LayoutOrder=nextOrder()
emoteSpeedRow.LayoutOrder=100000

state.initializeEmoteStudio=function(api)
    local stateOriginals={}
    local selectedPreset=nil
    local function smallButton(parent,textValue,callback,color)
        local button=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=color or Color3.fromRGB(52,47,70),
            BorderSizePixel=0,Text=textValue,TextColor3=Color3.fromRGB(235,230,245),TextSize=10,Font=Enum.Font.GothamSemibold,
            LayoutOrder=nextOrder(),Parent=parent})
        create("UICorner",{CornerRadius=UDim.new(0,6),Parent=button}); button.MouseButton1Click:Connect(function() callback(button) end); return button
    end
    local function speedControl(parent)
        local row=create("Frame",{Size=UDim2.new(1,0,0,30),BackgroundTransparency=1,LayoutOrder=nextOrder(),Parent=parent})
        create("TextLabel",{Size=UDim2.new(1,-78,1,0),BackgroundTransparency=1,Text="Animation Speed",
            TextColor3=Color3.fromRGB(210,205,220),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=row})
        local box=styledBox(row,{Size=UDim2.new(0,70,0,24),Position=UDim2.new(1,-70,0.5,-12),Text=string.format("%.1f",state.emoteSpeed),PlaceholderText="0.1-5"})
        box.FocusLost:Connect(function()
            state.emoteSpeed=math.clamp(tonumber(box.Text) or state.emoteSpeed,0.1,5); box.Text=string.format("%.1f",state.emoteSpeed)
            emoteSpeed=state.emoteSpeed; emoteSpeedBox.Text=box.Text; local track=api.getTrack(); if track then pcall(function() track:AdjustSpeed(emoteSpeed) end) end
        end)
    end

    -- CUSTOM
    currentSection=state.emoteModuleTabs.custom
    local customSearchRow=rowFrame(nextOrder(),28)
    local customSearch=styledBox(customSearchRow,{Size=UDim2.new(1,0,0,26),Text="",PlaceholderText="Search custom animations..."})
    local customNameRow=rowFrame(nextOrder(),28)
    local customName=styledBox(customNameRow,{Size=UDim2.new(1,0,0,26),Text="",PlaceholderText="Animation name..."})
    local customIdRow=rowFrame(nextOrder(),28)
    local customId=styledBox(customIdRow,{Size=UDim2.new(1,-72,0,26),Text="",PlaceholderText="Animation ID..."})
    local customAdd=create("TextButton",{Size=UDim2.new(0,64,0,26),Position=UDim2.new(1,-64,0,0),BackgroundColor3=Color3.fromRGB(48,115,62),
        BorderSizePixel=0,Text="Add",TextColor3=Color3.new(1,1,1),TextSize=10,Font=Enum.Font.GothamSemibold,Parent=customIdRow})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=customAdd})
    local customList=create("ScrollingFrame",{Size=UDim2.new(1,0,0,180),CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=0.35,BackgroundColor3=Color3.fromRGB(25,24,34),BorderSizePixel=0,ScrollBarThickness=3,
        LayoutOrder=nextOrder(),Parent=currentSection})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=customList}); create("UIListLayout",{Padding=UDim.new(0,4),Parent=customList})
    local function refreshCustom()
        for _,child in ipairs(customList:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local query=customSearch.Text:lower(); local items={}
        for _,item in pairs(state.emoteCustoms) do if query=="" or tostring(item.name):lower():find(query,1,true) then table.insert(items,item) end end
        table.sort(items,function(a,b) return tostring(a.name):lower()<tostring(b.name):lower() end)
        for _,item in ipairs(items) do
            local row=create("Frame",{Size=UDim2.new(1,-4,0,30),BackgroundTransparency=1,Parent=customList})
            local play=create("TextButton",{Size=UDim2.new(1,-38,0,28),BackgroundColor3=Color3.fromRGB(43,39,57),BorderSizePixel=0,
                Text=tostring(item.name),TextColor3=Color3.fromRGB(230,225,240),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=row})
            local remove=create("TextButton",{Size=UDim2.new(0,32,0,28),Position=UDim2.new(1,-32,0,0),BackgroundColor3=Color3.fromRGB(85,45,55),
                BorderSizePixel=0,Text="X",TextColor3=Color3.fromRGB(240,180,190),TextSize=11,Font=Enum.Font.GothamBold,Parent=row})
            create("UICorner",{CornerRadius=UDim.new(0,5),Parent=play}); create("UICorner",{CornerRadius=UDim.new(0,5),Parent=remove})
            play.MouseButton1Click:Connect(function() api.play(item.id,item.name) end)
            remove.MouseButton1Click:Connect(function() state.emoteCustoms[tostring(item.id)]=nil; saveGlobalEmoteFavorites(); refreshCustom() end)
        end
    end
    customAdd.MouseButton1Click:Connect(function()
        local id=tonumber(customId.Text:match("(%d+)") or "")
        local name=customName.Text:match("^%s*(.-)%s*$")
        if not id or name=="" then customId.Text="Valid name + ID required"; return end
        state.emoteCustoms[tostring(id)]={id=id,name=name}; customName.Text=""; customId.Text=""; saveGlobalEmoteFavorites(); refreshCustom()
    end)
    customSearch:GetPropertyChangedSignal("Text"):Connect(refreshCustom); refreshCustom(); speedControl(currentSection)

    -- STATES
    currentSection=state.emoteModuleTabs.states
    local statesStatus=create("TextLabel",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,Text="Custom states ready",
        TextColor3=Color3.fromRGB(155,190,165),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
        LayoutOrder=nextOrder(),Parent=currentSection})
    local stateLabels={}
    local function restoreStates()
        for animation,id in pairs(stateOriginals) do if animation and animation.Parent then animation.AnimationId=id end end; table.clear(stateOriginals)
    end
    local function applyStates()
        restoreStates(); if not state.emotePresetEnabled then return end
        local animate=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Animate"); if not animate then statesStatus.Text="Animate script unavailable"; return end
        for stateName,id in pairs(state.emoteStateAnimations) do
            if tostring(id)~="" then
                local folder=animate:FindFirstChild(stateName:lower())
                local animation=folder and folder:FindFirstChildWhichIsA("Animation",true)
                if animation then stateOriginals[animation]=animation.AnimationId; animation.AnimationId="rbxassetid://"..tostring(id) end
            end
        end
        statesStatus.Text="State animations applied"
    end
    local function bindStateSpeeds(character)
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local animator=humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator",3))
        if animator then track(animator.AnimationPlayed:Connect(function(animationTrack)
            local id=animationTrack.Animation and animationTrack.Animation.AnimationId:match("(%d+)")
            for stateName,stateId in pairs(state.emoteStateAnimations) do
                if id and tostring(stateId)==id then pcall(function() animationTrack:AdjustSpeed(tonumber(state.emoteStateSpeeds[stateName]) or 1) end); break end
            end
        end)) end
    end
    for _,stateName in ipairs({"Idle","Walk","Run","Jump","Fall","Climb","Swim"}) do
        if state.emoteStateAnimations[stateName]==nil then state.emoteStateAnimations[stateName]="" end
        if state.emoteStateSpeeds[stateName]==nil then state.emoteStateSpeeds[stateName]=1 end
        local label=create("TextLabel",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,Text=stateName..": "..(state.emoteStateAnimations[stateName]~="" and state.emoteStateAnimations[stateName] or "None"),
            TextColor3=Color3.fromRGB(210,205,220),TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
            LayoutOrder=nextOrder(),Parent=currentSection})
        stateLabels[stateName]=label
        local speedRow=rowFrame(nextOrder(),26)
        create("TextLabel",{Size=UDim2.new(0,38,1,0),BackgroundTransparency=1,Text="Spd:",TextColor3=Color3.fromRGB(170,165,185),
            TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=speedRow})
        local stateSpeedBox=styledBox(speedRow,{Size=UDim2.new(0,62,0,22),Position=UDim2.new(1,-62,0.5,-11),
            Text=string.format("%.1f",tonumber(state.emoteStateSpeeds[stateName]) or 1),PlaceholderText="0.1-5"})
        stateSpeedBox.FocusLost:Connect(function()
            state.emoteStateSpeeds[stateName]=math.clamp(tonumber(stateSpeedBox.Text) or 1,0.1,5)
            stateSpeedBox.Text=string.format("%.1f",state.emoteStateSpeeds[stateName]); saveGlobalEmoteFavorites()
        end)
        local row=rowFrame(nextOrder(),28)
        local idBox=styledBox(row,{Size=UDim2.new(1,-52,0,26),Text="",PlaceholderText="Paste "..stateName.." ID..."})
        local setButton=create("TextButton",{Size=UDim2.new(0,46,0,26),Position=UDim2.new(1,-46,0,0),BackgroundColor3=Color3.fromRGB(48,105,62),BorderSizePixel=0,
            Text="Set",TextColor3=Color3.new(1,1,1),TextSize=10,Font=Enum.Font.GothamSemibold,Parent=row})
        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=setButton})
        setButton.MouseButton1Click:Connect(function()
            local id=tonumber(idBox.Text:match("(%d+)") or "")
            if not id then idBox.Text="Invalid ID"; return end
            state.emoteStateAnimations[stateName]=tostring(id); label.Text=stateName..": "..id; idBox.Text=""; saveGlobalEmoteFavorites(); applyStates()
        end)
    end
    createToggle("Enable Preset Animations",nextOrder(),false,function(on) state.emotePresetEnabled=on; applyStates() end)
    speedControl(currentSection)

    -- PRESETS
    currentSection=state.emoteModuleTabs.presets
    local presetNameRow=rowFrame(nextOrder(),28)
    local presetName=styledBox(presetNameRow,{Size=UDim2.new(1,-104,0,26),Text="",PlaceholderText="Preset name..."})
    local savePreset=create("TextButton",{Size=UDim2.new(0,98,0,26),Position=UDim2.new(1,-98,0,0),BackgroundColor3=Color3.fromRGB(48,105,62),
        BorderSizePixel=0,Text="Save Current",TextColor3=Color3.new(1,1,1),TextSize=10,Font=Enum.Font.GothamSemibold,Parent=presetNameRow})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=savePreset})
    local presetSelect=smallButton(currentSection,"Preset: Select...",function(button)
        local names={}; for name in pairs(state.emoteStatePresets) do table.insert(names,name) end; table.sort(names)
        if #names==0 then button.Text="No presets saved"; return end
        local index=table.find(names,selectedPreset) or 0; selectedPreset=names[index%#names+1]; button.Text="Preset: "..selectedPreset
    end)
    smallButton(currentSection,"Load Selected Preset",function(button)
        local preset=selectedPreset and state.emoteStatePresets[selectedPreset]
        if not preset then button.Text="Select a preset first"; return end
        state.emoteStateAnimations=table.clone(preset.animations or {}); state.emoteStateSpeeds=table.clone(preset.speeds or {})
        for stateName,label in pairs(stateLabels) do label.Text=stateName..": "..tostring(state.emoteStateAnimations[stateName] or "None") end
        applyStates(); button.Text="Loaded: "..selectedPreset
    end,Color3.fromRGB(55,75,105))
    savePreset.MouseButton1Click:Connect(function()
        local name=presetName.Text:match("^%s*(.-)%s*$"); if name=="" then presetName.Text="Name required"; return end
        state.emoteStatePresets[name]={animations=table.clone(state.emoteStateAnimations),speeds=table.clone(state.emoteStateSpeeds)}
        selectedPreset=name; presetSelect.Text="Preset: "..name; presetName.Text=""; saveGlobalEmoteFavorites()
    end)
    smallButton(currentSection,"Advanced / Sync Tools",function() state.emoteModuleTabs.set("Legacy") end,Color3.fromRGB(65,52,95))
    speedControl(currentSection); speedControl(state.emoteModuleTabs.favorites)
    if LocalPlayer.Character then bindStateSpeeds(LocalPlayer.Character) end
    track(LocalPlayer.CharacterAdded:Connect(function(character)
        task.defer(bindStateSpeeds,character); if state.emotePresetEnabled then task.delay(1,applyStates) end
    end))
    addCleanup(restoreStates)
end
state.initializeEmoteStudio({play=playEmote,getTrack=function() return emoteTrack end})

-- Advanced emote tools live in their own closure so Potassium does not add
-- their locals to initializeV4Toolkit's register frame.
currentSection=state.emoteModuleTabs.new
local legacyBack=create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Color3.fromRGB(65,52,95),BorderSizePixel=0,
    Text="< Back to Presets",TextColor3=Color3.fromRGB(235,225,250),TextSize=11,Font=Enum.Font.GothamSemibold,
    LayoutOrder=nextOrder(),Parent=currentSection})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=legacyBack})
legacyBack.MouseButton1Click:Connect(function() state.emoteModuleTabs.set("Presets") end)
state.initializeAdvancedEmotes=function(api)
    local paused=false
    local loopConnection=nil
    local playlistGeneration=0
    local poseHeld=false
    local posePercent=0
    state.emoteCategoryFilter=state.emoteCategoryFilter or "All"
    state.emoteSortMode="Name"
    state.emoteFavoriteQuery=state.emoteFavoriteQuery or ""
    state.emoteHotkeyName=state.emoteHotkeyName or "H"

    sectionLabel("Playback Controls",nextOrder())
    local advancedStopButton=actionButton("Stop Emote",function() api.stop() end,Color3.fromRGB(85,48,62))
    advancedStopButton.Size=UDim2.new(0,76,0,24); advancedStopButton.Position=UDim2.new(1,-76,0,0)
    actionButton("Pause / Resume Emote",function(button)
        local track=api.getTrack()
        if not track then button.Text="No emote playing"; return end
        paused=not paused
        if paused then track:AdjustSpeed(0); button.Text="Resume Emote"
        else track:AdjustSpeed(api.getSpeed()); button.Text="Pause Emote" end
    end)
    actionButton("Restart Current Emote",function(button)
        local track=api.getTrack()
        if track then track.TimePosition=0; track:AdjustSpeed(api.getSpeed()); paused=false; button.Text="Emote restarted"
        else button.Text="No emote playing" end
    end)
    actionButton("Repeat Last Emote",function(button)
        local last=state.emoteLast
        if last then api.play(last.id,last.name); button.Text="Repeating "..last.name else button.Text="No recent emote" end
    end)
    local loopButton=actionButton("Loop Mode: "..state.emoteLoopMode,function(button)
        local current=state.emoteLoopMode
        state.emoteLoopMode=current=="Infinite" and "Once" or (current=="Once" and "Counted" or "Infinite")
        button.Text="Loop Mode: "..state.emoteLoopMode
        local track=api.getTrack(); if track then track.Looped=state.emoteLoopMode~="Once" end
    end)
    local loopCountRow=rowFrame(nextOrder(),28)
    local loopCountBox=styledBox(loopCountRow,{Size=UDim2.new(1,0,0,24),Text=tostring(state.emoteLoopCount),PlaceholderText="Counted loop plays (2-100)"})
    loopCountBox.FocusLost:Connect(function()
        state.emoteLoopCount=math.clamp(math.floor(tonumber(loopCountBox.Text) or 3),2,100); loopCountBox.Text=tostring(state.emoteLoopCount)
    end)
    actionButton("Save Speed for Current Emote",function(button)
        local current=state.emoteCurrent
        if not current then button.Text="No emote playing"; return end
        state.emoteSpeeds[tostring(current.id)]=api.getSpeed(); saveGlobalEmoteFavorites()
        button.Text="Saved "..string.format("%.1fx",api.getSpeed()).." for "..current.name
    end)

    sectionLabel("Pose Hold / Timeline",nextOrder())
    local poseRow=rowFrame(nextOrder(),28)
    local poseBox=styledBox(poseRow,{Size=UDim2.new(1,0,0,24),Text="0",PlaceholderText="Timeline percent (0-100)"})
    local function applyPose()
        local track=api.getTrack(); if not track or track.Length<=0 then return end
        posePercent=math.clamp(tonumber(poseBox.Text) or posePercent,0,100); poseBox.Text=tostring(math.floor(posePercent+0.5))
        track.TimePosition=track.Length*(posePercent/100)
        if poseHeld then track:AdjustSpeed(0) end
    end
    poseBox.FocusLost:Connect(applyPose)
    createToggle("Pose Hold",nextOrder(),false,function(on)
        poseHeld=on; state.emotePoseHeld=on; local track=api.getTrack()
        if track then if on then applyPose(); track:AdjustSpeed(0) else track:AdjustSpeed(api.getSpeed()) end end
    end)
    actionButton("Timeline -5%",function() posePercent=math.max(0,posePercent-5); poseBox.Text=tostring(posePercent); applyPose() end)
    actionButton("Timeline +5%",function() posePercent=math.min(100,posePercent+5); poseBox.Text=tostring(posePercent); applyPose() end)

    sectionLabel("History, Aliases & Favorites",nextOrder())
    local aliasRow=rowFrame(nextOrder(),28)
    local aliasBox=styledBox(aliasRow,{Size=UDim2.new(1,0,0,24),Text="",PlaceholderText="Alias for current emote"})
    actionButton("Save Alias for Current Emote",function(button)
        local current=state.emoteCurrent; local alias=aliasBox.Text:match("^%s*(.-)%s*$")
        if not current or alias=="" then button.Text="Play an emote and enter an alias"; return end
        state.emoteAliases[tostring(current.id)]=alias; saveGlobalEmoteFavorites(); button.Text="Alias saved: "..alias
    end)
    local favoriteSearchRow=rowFrame(nextOrder(),28)
    local favoriteSearchBox=styledBox(favoriteSearchRow,{Size=UDim2.new(1,0,0,24),Text=state.emoteFavoriteQuery,PlaceholderText="Search favorites/aliases"})
    favoriteSearchBox.FocusLost:Connect(function(enter)
        state.emoteFavoriteQuery=favoriteSearchBox.Text:match("^%s*(.-)%s*$"); if enter then api.showFavorites() end
    end)
    local sortButton=actionButton("Favorite Sort: Alphabetical",function(button)
        state.emoteSortMode="Name"; button.Text="Favorite Sort: Alphabetical"; api.showFavorites()
    end)
    actionButton("Show Emote History",function()
        api.showItems(state.emoteHistory,"History is empty")
    end)
    actionButton("Clear Emote History",function(button)
        table.clear(state.emoteHistory); saveGlobalEmoteFavorites(); button.Text="History cleared"
    end,Color3.fromRGB(85,48,62))
    local categoryButton=actionButton("Catalog Filter: "..state.emoteCategoryFilter,function(button)
        local nextCategory={All="Dance",Dance="Pose",Pose="Idle",Idle="Movement",Movement="All"}
        state.emoteCategoryFilter=nextCategory[state.emoteCategoryFilter] or "All"; button.Text="Catalog Filter: "..state.emoteCategoryFilter
    end)
    local resultLimitRow=rowFrame(nextOrder(),28)
    local resultLimitBox=styledBox(resultLimitRow,{Size=UDim2.new(1,0,0,24),Text=tostring(state.emoteResultLimit),PlaceholderText="Catalog results (10-30)"})
    resultLimitBox.FocusLost:Connect(function()
        state.emoteResultLimit=math.clamp(math.floor(tonumber(resultLimitBox.Text) or 30),10,30); resultLimitBox.Text=tostring(state.emoteResultLimit)
    end)
    actionButton("Cancel Catalog Search",function(button) api.cancelSearch(); button.Text="Search cancelled" end,Color3.fromRGB(85,48,62))

    sectionLabel("Playlists",nextOrder())
    local playlistRow=rowFrame(nextOrder(),28)
    local playlistBox=styledBox(playlistRow,{Size=UDim2.new(1,0,0,24),Text="default",PlaceholderText="Playlist name"})
    actionButton("Add Current Emote to Playlist",function(button)
        local current=state.emoteCurrent; local name=playlistBox.Text:match("^%s*(.-)%s*$")
        if not current or name=="" then button.Text="Play an emote and name the playlist"; return end
        state.emotePlaylists[name]=state.emotePlaylists[name] or {}
        table.insert(state.emotePlaylists[name],{id=current.id,name=current.name}); saveGlobalEmoteFavorites(); button.Text="Added to "..name
    end)
    actionButton("Remove Current Emote from Playlist",function(button)
        local current=state.emoteCurrent; local name=playlistBox.Text:match("^%s*(.-)%s*$"); local list=state.emotePlaylists[name]
        if not current or type(list)~="table" then button.Text="Current emote/playlist unavailable"; return end
        local removed=0
        for index=#list,1,-1 do if tostring(list[index].id)==tostring(current.id) then table.remove(list,index); removed=removed+1 end end
        saveGlobalEmoteFavorites(); button.Text=removed>0 and ("Removed from "..name) or "Emote not in playlist"
    end)
    actionButton("Show Selected Playlist",function(button)
        local list=state.emotePlaylists[playlistBox.Text:match("^%s*(.-)%s*$")]
        if list then api.showItems(list,"Playlist is empty") else button.Text="Playlist not found" end
    end)
    local function playPlaylist(randomize)
        local list=state.emotePlaylists[playlistBox.Text:match("^%s*(.-)%s*$")]
        if type(list)~="table" or #list==0 then return false end
        playlistGeneration=playlistGeneration+1; local generation=playlistGeneration
        task.spawn(function()
            local index=1
            while generation==playlistGeneration and screenGui.Parent do
                local item=randomize and list[math.random(1,#list)] or list[index]
                api.play(item.id,item.name); task.wait(math.max(1,tonumber(state.emoteAutoInterval) or 8))
                index=index%#list+1
            end
        end)
        return true
    end
    actionButton("Play Selected Playlist",function(button) if not playPlaylist(false) then button.Text="Playlist not found/empty" end end)
    actionButton("List Playlist Names",function(button)
        local names={}; for name in pairs(state.emotePlaylists) do table.insert(names,name) end; table.sort(names)
        button.Text=#names>0 and table.concat(names," | ") or "No playlists"
    end)
    actionButton("Delete Selected Playlist",function(button)
        local name=playlistBox.Text:match("^%s*(.-)%s*$")
        if state.emotePlaylists[name] then state.emotePlaylists[name]=nil; saveGlobalEmoteFavorites(); button.Text="Deleted "..name else button.Text="Playlist not found" end
    end,Color3.fromRGB(85,48,62))
    actionButton("Stop Playlist / Automation",function(button) playlistGeneration=playlistGeneration+1; state.emoteAutoMode="Off"; button.Text="Automation stopped" end,Color3.fromRGB(85,48,62))

    sectionLabel("Automation",nextOrder())
    local intervalRow=rowFrame(nextOrder(),28)
    local intervalBox=styledBox(intervalRow,{Size=UDim2.new(1,0,0,24),Text=tostring(state.emoteAutoInterval),PlaceholderText="Seconds between emotes"})
    intervalBox.FocusLost:Connect(function() state.emoteAutoInterval=math.clamp(tonumber(intervalBox.Text) or 8,1,300); intervalBox.Text=tostring(state.emoteAutoInterval) end)
    actionButton("Random Favorite Automation",function(button)
        local favorites={}; for _,item in pairs(state.emoteFavorites) do table.insert(favorites,item) end
        if #favorites==0 then button.Text="No favorites"; return end
        playlistGeneration=playlistGeneration+1; local generation=playlistGeneration; state.emoteAutoMode="Random Favorites"
        task.spawn(function()
            while generation==playlistGeneration and screenGui.Parent do
                local item=favorites[math.random(1,#favorites)]; api.play(item.id,item.name)
                task.wait(math.max(1,tonumber(state.emoteAutoInterval) or 8))
            end
        end)
    end)
    createToggle("Resume Last Emote After Respawn",nextOrder(),state.emoteResumeRespawn,function(on) state.emoteResumeRespawn=on end)
    createToggle("Auto-play Last Emote On Join",nextOrder(),state.emoteAutoPlayJoin,function(on) state.emoteAutoPlayJoin=on end)
    createToggle("Stop Emote When Jumping",nextOrder(),state.emoteStopOnJump,function(on) state.emoteStopOnJump=on end)
    createToggle("Stop Emote When Sitting",nextOrder(),state.emoteStopOnSit,function(on) state.emoteStopOnSit=on end)
    createToggle("Stop Emote When Equipping Tool",nextOrder(),state.emoteStopOnTool,function(on) state.emoteStopOnTool=on end)
    local hotkeyRow=rowFrame(nextOrder(),28)
    local hotkeyBox=styledBox(hotkeyRow,{Size=UDim2.new(1,0,0,24),Text=state.emoteHotkeyName,PlaceholderText="Repeat-last key (example: H)"})
    hotkeyBox.FocusLost:Connect(function()
        local name=hotkeyBox.Text:match("^%s*(.-)%s*$"); if Enum.KeyCode[name] then state.emoteHotkeyName=name else hotkeyBox.Text=state.emoteHotkeyName end
    end)
    actionButton("Clear Repeat-Emote Hotkey",function(button)
        state.emoteHotkeyName="Unbound"; hotkeyBox.Text="Unbound"; button.Text="Emote hotkey cleared"
    end,Color3.fromRGB(85,48,62))

    sectionLabel("Advanced Sync",nextOrder())
    local syncModeButton=actionButton("Sync Mode: "..state.emoteSyncMode,function(button)
        local nextMode={Animation="Speed",Speed="Precise",Precise="Smooth",Smooth="Animation"}
        state.emoteSyncMode=nextMode[state.emoteSyncMode] or "Precise"; button.Text="Sync Mode: "..state.emoteSyncMode
    end)
    local delayRow=rowFrame(nextOrder(),28)
    local delayBox=styledBox(delayRow,{Size=UDim2.new(1,0,0,24),Text=tostring(state.emoteSyncDelay),PlaceholderText="Sync delay, seconds (-2 to 2)"})
    delayBox.FocusLost:Connect(function() state.emoteSyncDelay=math.clamp(tonumber(delayBox.Text) or 0,-2,2); delayBox.Text=string.format("%.2f",state.emoteSyncDelay) end)
    actionButton("Use Most Recent Sync Player",function(button)
        local name=state.emoteRecentSyncPlayers[1]
        if name then api.setSyncName(name); api.beginSync(); button.Text="Syncing "..name else button.Text="No recent sync player" end
    end)

    sectionLabel("Backup / Transfer",nextOrder())
    local transferRow=rowFrame(nextOrder(),52)
    local transferBox=styledBox(transferRow,{Size=UDim2.new(1,0,0,48),Text="",PlaceholderText="Favorites JSON for import/export",MultiLine=true,TextWrapped=true})
    actionButton("Export Emote Library",function(button)
        local ok,text=pcall(function() return HttpService:JSONEncode({favorites=state.emoteFavorites,aliases=state.emoteAliases,playlists=state.emotePlaylists,speeds=state.emoteSpeeds}) end)
        if ok then transferBox.Text=text; if setclipboard then setclipboard(text) end; button.Text="Library exported" else button.Text="Export failed" end
    end)
    actionButton("Import Emote Library",function(button)
        local ok,data=pcall(function() return HttpService:JSONDecode(transferBox.Text) end)
        if not ok or type(data)~="table" then button.Text="Invalid JSON"; return end
        if type(data.favorites)=="table" then for id,item in pairs(data.favorites) do state.emoteFavorites[id]=item end end
        if type(data.aliases)=="table" then for id,value in pairs(data.aliases) do state.emoteAliases[id]=value end end
        if type(data.playlists)=="table" then for name,list in pairs(data.playlists) do state.emotePlaylists[name]=list end end
        if type(data.speeds)=="table" then for id,value in pairs(data.speeds) do state.emoteSpeeds[id]=value end end
        saveGlobalEmoteFavorites(); button.Text="Library imported"
    end)

    state.emoteAdvancedOnPlayed=function(item,track)
        item.lastUsed=os.time()
        local favorite=state.emoteFavorites[tostring(item.id)]; if favorite then favorite.lastUsed=item.lastUsed end
        for index=#state.emoteHistory,1,-1 do if tostring(state.emoteHistory[index].id)==tostring(item.id) then table.remove(state.emoteHistory,index) end end
        table.insert(state.emoteHistory,1,{id=item.id,name=item.name,lastUsed=item.lastUsed})
        while #state.emoteHistory>20 do table.remove(state.emoteHistory) end
        if loopConnection then loopConnection:Disconnect(); loopConnection=nil end
        if state.emoteLoopMode=="Counted" then
            local loops=0; track.Looped=true
            loopConnection=track.DidLoop:Connect(function()
                loops=loops+1
                if loops>=math.max(1,(tonumber(state.emoteLoopCount) or 3)-1) then track.Looped=false; loopConnection:Disconnect(); loopConnection=nil end
            end)
        end
        saveGlobalEmoteFavorites()
    end
    state.emoteAdvancedRefresh=function()
        loopButton.Text="Loop Mode: "..tostring(state.emoteLoopMode)
        sortButton.Text="Favorite Sort: Alphabetical"
        categoryButton.Text="Catalog Filter: "..tostring(state.emoteCategoryFilter)
        syncModeButton.Text="Sync Mode: "..tostring(state.emoteSyncMode)
        intervalBox.Text=tostring(state.emoteAutoInterval); resultLimitBox.Text=tostring(state.emoteResultLimit)
        loopCountBox.Text=tostring(state.emoteLoopCount)
        delayBox.Text=string.format("%.2f",tonumber(state.emoteSyncDelay) or 0); hotkeyBox.Text=tostring(state.emoteHotkeyName)
    end
    track(UserInputService.InputBegan:Connect(function(input,processed)
        if state.emoteHotkeyName~="Unbound" and not processed and UserInputService:GetFocusedTextBox()==nil
            and input.KeyCode==Enum.KeyCode[state.emoteHotkeyName] then
            local last=state.emoteLast; if last then api.play(last.id,last.name) end
        end
    end))
    local function bindJumpStop(character)
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then track(humanoid.StateChanged:Connect(function(_,newState)
            if state.emoteStopOnJump and (newState==Enum.HumanoidStateType.Jumping or newState==Enum.HumanoidStateType.Freefall) then api.stop() end
            if state.emoteStopOnSit and newState==Enum.HumanoidStateType.Seated then api.stop() end
        end)) end
        if character then track(character.ChildAdded:Connect(function(child)
            if state.emoteStopOnTool and child:IsA("Tool") then api.stop() end
        end)) end
    end
    if LocalPlayer.Character then bindJumpStop(LocalPlayer.Character) end
    track(LocalPlayer.CharacterAdded:Connect(function(character) task.defer(bindJumpStop,character) end))
    addCleanup(function() playlistGeneration=playlistGeneration+1; if loopConnection then loopConnection:Disconnect() end end)
    if state.emoteAutoPlayJoin and state.emoteLast then
        task.delay(1,function() if screenGui.Parent and state.emoteLast then api.play(state.emoteLast.id,state.emoteLast.name) end end)
    end
end
state.emoteCommandApi={
    play=playEmote,stop=stopEmote,getTrack=function() return emoteTrack end,getSpeed=function() return emoteSpeed end,
    showFavorites=showFavoriteEmotes,showItems=function(items,emptyText)
        emoteView="advanced"; emoteResults.Parent=state.emoteModuleTabs.new; clearEmoteResults()
        for _,item in ipairs(items or {}) do if item.id then createEmoteResult(item.id,item.name or ("Emote "..item.id)) end end
        emoteStatus.Text=#(items or {})>0 and ("Showing "..#items.." emotes") or emptyText
    end,
    setSyncName=function(name) emoteSyncBox.Text=name end,beginSync=beginEmoteSync,
    cancelSearch=function()
        emoteRequestGeneration=emoteRequestGeneration+1; emoteLoading=false; emoteSearchButton.Text="Search"; emoteStatus.Text="Catalog search cancelled"
    end,
}
state.initializeAdvancedEmotes(state.emoteCommandApi)
currentSection=state.emoteModuleTabs.root
local emotesDock=categoryMeta["Emotes"] and categoryMeta["Emotes"].dock
if emotesDock then
    state.updateEmoteResultsHeight=function()
        if emotesDock.Visible then
            local active=state.emoteModuleTabs.active or "All"
            local reserved=active=="Favs" and 125 or 255
            local minimum=active=="Favs" and 190 or 100
            emoteResults.Size=UDim2.new(1,-4,0,math.max(minimum,emotesDock.AbsoluteSize.Y-reserved))
        else
            emoteResults.Size=UDim2.new(1,0,0,190)
        end
    end
    track(emotesDock:GetPropertyChangedSignal("AbsoluteSize"):Connect(state.updateEmoteResultsHeight))
    task.defer(state.updateEmoteResultsHeight)
end
track(LocalPlayer.CharacterAdded:Connect(function()
    local syncTarget=emoteSyncActive and emoteSyncPlayer or nil
    local resumeItem=state.emoteResumeRespawn and state.emoteLast or nil
    if currentEmoteName or emoteTrack then stopEmote() end
    if syncTarget and syncTarget.Parent==Players then
        emoteSyncPlayer=syncTarget; emoteSyncActive=true; emoteSyncElapsed=1
        emoteStatus.Text="Resuming sync with "..syncTarget.Name.."..."
    elseif resumeItem then
        task.delay(1,function()
            if screenGui.Parent and LocalPlayer.Character and state.emoteResumeRespawn then playEmote(resumeItem.id,resumeItem.name) end
        end)
    end
end))
addCleanup(stopEmote)

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
do
useCategory("Interface")
sectionLabel("Profile & Safety", nextOrder())
local compactMode=false
createToggle("Compact Panel",nextOrder(),false,function(on)
    compactMode=on
    if not minimized then mainFrame.Size=on and UDim2.new(0,310,0,410) or UDim2.new(0,310,0,520) end
    searchRow.Visible=not on
    if statusLabelRef then statusLabelRef.Visible=not on end
end)
create("TextLabel",{Size=UDim2.new(1,0,0,32),BackgroundTransparency=1,
    Text="Safety: intrusive toggles never auto-enable when a profile loads.",
    TextWrapped=true,TextColor3=Color3.fromRGB(145,180,155),TextSize=10,Font=Enum.Font.Gotham,
    LayoutOrder=nextOrder(),Parent=currentSection})
local profileNameRow=rowFrame(nextOrder(),28)
local profileNameBox=styledBox(profileNameRow,{Size=UDim2.new(1,0,0,26),Text="default",PlaceholderText="Profile name"})
local profileListOpen=false
local profileListButton=create("TextButton",{Size=UDim2.new(1,0,0,26),BackgroundColor3=Color3.fromRGB(54,46,76),
    BorderSizePixel=0,Text=">  Saved Profiles",TextColor3=Color3.fromRGB(225,215,240),TextSize=11,
    Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=profileListButton})
local profileList=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=false,LayoutOrder=nextOrder(),Parent=currentSection})
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=profileList})
local loadNamedProfile
local function refreshProfileList()
    for _,child in ipairs(profileList:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    local names={}
    if listfiles then
        local ok,files=pcall(listfiles,"LucidPanel")
        if ok and type(files)=="table" then
            for _,path in ipairs(files) do
                local normalized=tostring(path):gsub("\\","/")
                local name=normalized:match("/profile_([%w_%-]+)%.json$") or normalized:match("^profile_([%w_%-]+)%.json$")
                if name and not name:match("_backup$") then table.insert(names,name) end
            end
        end
    end
    table.sort(names,function(a,b) return a:lower()<b:lower() end)
    if #names==0 then
        create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,
            Text=listfiles and "No saved profiles found" or "Executor cannot list files",
            TextColor3=Color3.fromRGB(145,135,160),TextSize=10,Font=Enum.Font.Gotham,Parent=profileList})
    else
        for index,name in ipairs(names) do
            local entry=create("TextButton",{Size=UDim2.new(1,0,0,26),BackgroundColor3=Color3.fromRGB(44,39,60),
                BorderSizePixel=0,Text=name,TextColor3=Color3.fromRGB(225,220,235),TextSize=11,
                Font=Enum.Font.Gotham,LayoutOrder=index,Parent=profileList})
            create("UICorner",{CornerRadius=UDim.new(0,5),Parent=entry})
            entry.MouseButton1Click:Connect(function()
                profileNameBox.Text=name; profileListOpen=false; profileList.Visible=false
                profileListButton.Text=">  Saved Profiles: "..name
                if loadNamedProfile then task.defer(function() loadNamedProfile(entry) end) end
            end)
        end
    end
end
profileListButton.MouseButton1Click:Connect(function()
    profileListOpen=not profileListOpen; profileList.Visible=profileListOpen
    profileListButton.Text=(profileListOpen and "v  " or ">  ").."Saved Profiles"
    if profileListOpen then refreshProfileList() end
end)
local function getProfilePath()
    local safeName=profileNameBox.Text:gsub("[^%w_%-]","")
    if safeName=="" then safeName="default" end
    profileNameBox.Text=safeName
    return "LucidPanel/profile_"..safeName..".json"
end
actionButton("Save Named Profile", function(button)
    if not writefile then button.Text="File API unavailable"; return end
    pcall(function() if makefolder and (not isfolder or not isfolder("LucidPanel")) then makefolder("LucidPanel") end end)
    -- Preserve waypoint groups belonging to other places when this profile is
    -- updated. PlaceId isolation prevents coordinates leaking across games.
    local payload = {}
    local profilePath=getProfilePath()
    if readfile and (not isfile or isfile(profilePath)) then
        pcall(function() payload=HttpService:JSONDecode(readfile(profilePath)) end)
    end
    if type(payload)~="table" then payload={} end
    payload.version=5
    payload.savedAt=os.time()
    payload.values={}
    for key,value in pairs(state) do
        if type(value)=="number" or type(value)=="string" then payload.values[key]=value end
    end
    payload.toggles={}
    payload.favorites={}
    for name in pairs(state.favoriteNames or {}) do payload.favorites[name]=true end
    payload.yellowHighlights=state.yellowHighlightApi.getNames and state.yellowHighlightApi.getNames() or {}
    payload.pinkHighlights=state.pinkHighlightApi.getNames and state.pinkHighlightApi.getNames() or {}
    payload.blackHighlights=state.blackHighlightApi.getNames and state.blackHighlightApi.getNames() or {}
    payload.hiddenNamedPlayers=state.namedPlayerHiderApi and state.namedPlayerHiderApi.getNames and state.namedPlayerHiderApi.getNames() or {}
    -- Emote favorites are global and saved independently of named profiles.
    payload.keybinds={}
    for name,key in pairs(shortcutKeys or {}) do payload.keybinds[name]=key and key.Name or "Unbound" end
    for _,name in ipairs({"Fly","Noclip","Freecam","Migraine","Photo Mode","Character Recovery"}) do
        if not shortcutKeys[name] then payload.keybinds[name]="Unbound" end
    end
    payload.interface={opacity=1-mainFrame.BackgroundTransparency,
        xScale=mainFrame.Position.X.Scale,xOffset=mainFrame.Position.X.Offset,
        yScale=mainFrame.Position.Y.Scale,yOffset=mainFrame.Position.Y.Offset,
        width=mainExpandedSize.X.Offset,height=mainExpandedSize.Y.Offset,minimized=minimized,
        dockXScale=state.lucidDock and state.lucidDock.Position.X.Scale or 0.5,
        dockXOffset=state.lucidDock and state.lucidDock.Position.X.Offset or 0,
        dockYScale=state.lucidDock and state.lucidDock.Position.Y.Scale or 1,
        dockYOffset=state.lucidDock and state.lucidDock.Position.Y.Offset or -10}
    payload.lighting={playerLightEnabled=state.playerLightEnabled==true,
        brightness=Lighting.Brightness,exposure=Lighting.ExposureCompensation,
        clockTime=Lighting.ClockTime,fogStart=Lighting.FogStart,fogEnd=Lighting.FogEnd,
        ambient={Lighting.Ambient.R,Lighting.Ambient.G,Lighting.Ambient.B},
        outdoorAmbient={Lighting.OutdoorAmbient.R,Lighting.OutdoorAmbient.G,Lighting.OutdoorAmbient.B}}
    payload.windows={}
    for _,detachable in ipairs(detachableWindows) do
        local window=detachable.window
        payload.windows[window.Name]={xScale=window.Position.X.Scale,xOffset=window.Position.X.Offset,
            yScale=window.Position.Y.Scale,yOffset=window.Position.Y.Offset,
            width=window.Size.X.Offset,height=window.Size.Y.Offset,
            pinned=detachable.isPinned(),detached=detachable.isDetached()}
    end
    payload.categories={}
    for name,meta in pairs(categoryMeta) do
        if meta.isOpen then payload.categories[name]=meta.isOpen() end
    end
    payload.waypointsByPlace=payload.waypointsByPlace or {}
    local savedWaypoints={}
    for name, point in pairs(waypoints) do
        savedWaypoints[name]={point:GetComponents()}
    end
    payload.waypointsByPlace[tostring(game.PlaceId)]=savedWaypoints
    for name, enabled in pairs(activeFeatures) do payload.toggles[name]=enabled end
    local encodedOk, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
    if encodedOk and readfile and (not isfile or isfile(profilePath)) then
        local backupPath=profilePath:gsub("%.json$","_backup.json")
        pcall(function()
            local existing=readfile(profilePath)
            local decoded=HttpService:JSONDecode(existing)
            if type(decoded)=="table" then writefile(backupPath,existing) end
        end)
    end
    local ok = encodedOk and pcall(writefile, profilePath, encoded)
    button.Text = ok and "Profile saved" or (encodedOk and "Write failed" or "Profile data invalid")
    notifyLucid(ok and "Profile saved" or "Profile save failed",
        ok and profileNameBox.Text or button.Text,ok and Color3.fromRGB(75,210,120) or Color3.fromRGB(230,90,105))
    if ok and profileListOpen then refreshProfileList() end
    task.delay(1.5,function() if button.Parent then button.Text="Save Named Profile" end end)
end)
loadNamedProfile = function(button)
    local profilePath=getProfilePath()
    if not readfile then button.Text="File API unavailable"; return end
    local function decodeProfile(path)
        if isfile and not isfile(path) then return false,nil end
        return pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    end
    local ok,payload=decodeProfile(profilePath)
    local recovered=false
    if not ok or type(payload)~="table" then
        ok,payload=decodeProfile(profilePath:gsub("%.json$","_backup.json")); recovered=ok and type(payload)=="table"
    end
    if not ok or type(payload)~="table" then button.Text="Profile invalid/missing"; notifyLucid("Profile load failed",profileNameBox.Text,Color3.fromRGB(230,90,105)); return end
    for key,value in pairs(payload.values or {}) do
        if state[key]~=nil and not (key=="accentTheme" and tonumber(payload.version or 0)<5) then state[key]=value end
    end
    if state.applyAccentTheme then state.applyAccentTheme(state.accentTheme) end
    if state.yellowHighlightApi.refreshColor then state.yellowHighlightApi.refreshColor() end
    if state.pinkHighlightApi.refreshColor then state.pinkHighlightApi.refreshColor() end
    if state.blackHighlightApi.refreshColor then state.blackHighlightApi.refreshColor() end
    if type(payload.lighting)=="table" and type(payload.lighting.playerLightEnabled)=="boolean" then
        state.playerLightEnabled=payload.lighting.playerLightEnabled
    end
    local function updateText(control,value)
        if control and control.Parent then control.Text=tostring(value) end
    end
    updateText(wsBox,state.walkspeedValue); updateText(jhBox,state.jumpHeightValue)
    updateText(autoclickIntervalBox,string.format("%.3g",math.max(1,(tonumber(state.autoclickInterval) or 0.001)*1000)))
    if state.autoclickMode~="Mouse" and state.autoclickMode~="Tool" and state.autoclickMode~="Center" then
        state.autoclickMode="Hybrid"
    end
    if autoclickModeButton and autoclickModeButton.Parent then autoclickModeButton.Text="AutoClick Mode: "..state.autoclickMode end
    updateText(zoomBox,state.maxZoomValue); updateText(flySpeedBox,state.flySpeed); updateText(freecamSpeedBox,state.freecamSpeed)
    if state.cameraShakeStrength~="Light" and state.cameraShakeStrength~="Medium" and state.cameraShakeStrength~="Strong" then
        state.cameraShakeStrength="Strong"
    end
    if shakeStrengthButton and shakeStrengthButton.Parent then shakeStrengthButton.Text="Camera Shake Strength: "..state.cameraShakeStrength end
    if state.emoteAdvancedRefresh then state.emoteAdvancedRefresh() end
    updateText(fovBox,state.fovValue); updateText(flingLinearBox,state.antiFlingLinear)
    updateText(flingAngularBox,state.antiFlingAngular); updateText(fogBox,state.fogEndValue)
    updateText(clockBox,state.nightClockTime); updateText(lightRangeBox,state.playerLightRange)
    updateText(lightPowerBox,state.playerLightPower); updateText(spawnDelayBox,state.spawnpointDelay)
    if antiPushStrengthButton and antiPushStrengthButton.Parent then
        antiPushStrengthButton.Text="Anti Push Strength: "..tostring(state.antiPushStrength)
    end
    if highlightStyleButton and highlightStyleButton.Parent then
        if state.espHighlightStyle~="Soft" then state.espHighlightStyle="Hard" end
        highlightStyleButton.Text="Highlight Style: "..state.espHighlightStyle
    end
    emoteSpeed=state.emoteSpeed; updateText(emoteSpeedBox,string.format("%.1f",emoteSpeed))
    updateText(emoteSyncToleranceBox,string.format("%.2f",state.emoteSyncTolerance))
    if gotoApi.setOffset then gotoApi.setOffset(state.gotoOffsetX,state.gotoOffsetY,state.gotoOffsetZ) end
    -- Safe startup: remembered toggle states are intentionally not activated.
    -- Import favorites from older profile files once, without replacing the
    -- global collection or tying it to this profile/place.
    mergeLegacyEmoteFavorites(payload.emoteFavorites)
    if state.yellowHighlightApi.setNames then state.yellowHighlightApi.setNames(payload.yellowHighlights or {}) end
    if state.pinkHighlightApi.setNames then state.pinkHighlightApi.setNames(payload.pinkHighlights or {}) end
    if state.blackHighlightApi.setNames then state.blackHighlightApi.setNames(payload.blackHighlights or {}) end
    if state.namedPlayerHiderApi and state.namedPlayerHiderApi.setNames then state.namedPlayerHiderApi.setNames(payload.hiddenNamedPlayers or {}) end
    for name,setter in pairs(favoriteRegistry or {}) do setter((payload.favorites or {})[name]==true) end
    for name,value in pairs(payload.keybinds or {}) do
        local legacyDefault=tonumber(payload.version or 0)<4 and ((name=="Fly" and value=="F")
            or (name=="Noclip" and value=="N") or (name=="Freecam" and value=="P"))
        local key=not legacyDefault and value~="Unbound" and Enum.KeyCode[value] or nil
        shortcutKeys[name]=key
        if shortcutBoxes and shortcutBoxes[name] then shortcutBoxes[name].Text=key and key.Name or "" end
    end
    local interface=payload.interface or {}
    if type(interface.opacity)=="number" then setOpacity(math.floor(math.clamp(interface.opacity,0,1)*100+0.5)) end
    if type(interface.xScale)=="number" and type(interface.xOffset)=="number"
        and type(interface.yScale)=="number" and type(interface.yOffset)=="number" then
        mainFrame.Position=UDim2.new(interface.xScale,interface.xOffset,interface.yScale,interface.yOffset)
    end
    if state.lucidDock and type(interface.dockXScale)=="number" and type(interface.dockXOffset)=="number"
        and type(interface.dockYScale)=="number" and type(interface.dockYOffset)=="number" then
        state.lucidDock.Position=UDim2.new(interface.dockXScale,interface.dockXOffset,interface.dockYScale,interface.dockYOffset)
    end
    if type(interface.width)=="number" and type(interface.height)=="number" then
        mainExpandedSize=UDim2.new(0,math.max(270,interface.width),0,math.max(180,interface.height))
        if not minimized then mainFrame.Size=mainExpandedSize end
    end
    if type(interface.minimized)=="boolean" then
        minimized=interface.minimized; content.Visible=not minimized; mainResizeHandle.Visible=not minimized
        mainFrame.Size=minimized and UDim2.new(0,mainExpandedSize.X.Offset,0,36) or mainExpandedSize
        minimizeBtn.Text=minimized and "+" or "-"
    end
    for name,isOpen in pairs(payload.categories or {}) do
        local meta=categoryMeta[name]
        if meta and meta.setOpen and type(isOpen)=="boolean" then meta.setOpen(isOpen) end
    end
    for _,detachable in ipairs(detachableWindows or {}) do
        local saved=(payload.windows or {})[detachable.window.Name]
        if type(saved)=="table" then
            if type(saved.xScale)=="number" and type(saved.xOffset)=="number"
                and type(saved.yScale)=="number" and type(saved.yOffset)=="number" then
                detachable.window.Position=UDim2.new(saved.xScale,saved.xOffset,saved.yScale,saved.yOffset)
            end
            if type(saved.width)=="number" and type(saved.height)=="number" then
                detachable.window.Size=UDim2.new(0,math.max(210,saved.width),0,math.max(34,saved.height))
            end
            if detachable.setPinned then detachable.setPinned(saved.pinned==true) end
            if detachable.setDetached then detachable.setDetached(saved.detached==true) end
        end
    end
    table.clear(waypoints)
    local savedWaypoints=(payload.waypointsByPlace or {})[tostring(game.PlaceId)] or {}
    for name, components in pairs(savedWaypoints) do
        if type(name)=="string" and type(components)=="table" and #components==12 then
            local valid=true
            for index=1,12 do
                if type(components[index])~="number" then valid=false; break end
            end
            if valid then waypoints[name]=CFrame.new(unpack(components)) end
        end
    end
    refreshWaypointDropdown()
    -- Apply only changed feature states. Replaying every callback (especially
    -- ESP, lighting and physics features) causes a large load-time stall.
    local toggleNames={}
    for name in pairs(toggleRegistry or {}) do table.insert(toggleNames,name) end
    table.sort(toggleNames)
    for _,name in ipairs(toggleNames) do
        local savedToggle=(payload.toggles or {})[name]
        if savedToggle~=nil then
            local desired=savedToggle==true
            if activeFeatures[name]~=desired then pcall(toggleRegistry[name],desired) end
        end
    end
    local savedLighting=payload.lighting
    if type(savedLighting)=="table" then pcall(function()
        if type(savedLighting.brightness)=="number" then Lighting.Brightness=savedLighting.brightness end
        if type(savedLighting.exposure)=="number" then Lighting.ExposureCompensation=savedLighting.exposure end
        if type(savedLighting.clockTime)=="number" then Lighting.ClockTime=savedLighting.clockTime end
        if type(savedLighting.fogStart)=="number" then Lighting.FogStart=savedLighting.fogStart end
        if type(savedLighting.fogEnd)=="number" then Lighting.FogEnd=savedLighting.fogEnd end
        if type(savedLighting.ambient)=="table" and #savedLighting.ambient==3 then
            Lighting.Ambient=Color3.new(unpack(savedLighting.ambient))
        end
        if type(savedLighting.outdoorAmbient)=="table" and #savedLighting.outdoorAmbient==3 then
            Lighting.OutdoorAmbient=Color3.new(unpack(savedLighting.outdoorAmbient))
        end
    end) end
    applySavedComfortPreset()
    if state.playerLightEnabled then applyPlayerLight() else removePlayerLight() end
    button.Text="Profile loaded — settings restored"
    notifyLucid(recovered and "Profile recovered from backup" or "Profile loaded",profileNameBox.Text,
        recovered and Color3.fromRGB(235,175,70) or Color3.fromRGB(75,210,120))
end
local loadProfileButton=actionButton("Load Named Profile", function(button) loadNamedProfile(button) end)
loadProfileButton.Name="LoadNamedProfileButton"
local AUTO_PROFILE_PATH="LucidPanel/auto_profiles.json"
local autoProfileStatus=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,
    Text="Auto profile: none",TextColor3=Color3.fromRGB(155,145,175),TextSize=10,Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=nextOrder(),Parent=currentSection})
local function readAutoProfiles()
    if not readfile or (isfile and not isfile(AUTO_PROFILE_PATH)) then return {byPlace={}} end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(AUTO_PROFILE_PATH)) end)
    if not ok or type(data)~="table" then return {byPlace={}} end
    data.byPlace=type(data.byPlace)=="table" and data.byPlace or {}
    return data
end
local function writeAutoProfiles(data)
    if not writefile then return false end
    pcall(function() if makefolder and (not isfolder or not isfolder("LucidPanel")) then makefolder("LucidPanel") end end)
    local ok,encoded=pcall(function() return HttpService:JSONEncode(data) end)
    return ok and pcall(writefile,AUTO_PROFILE_PATH,encoded)
end
local function refreshAutoProfileStatus()
    local data=readAutoProfiles()
    local assigned=data.byPlace[tostring(game.PlaceId)]
    autoProfileStatus.Text="Auto profile: "..tostring(assigned or data.fallback or "none")..(assigned and " (this game)" or (data.fallback and " (fallback)" or ""))
end
actionButton("Auto-load Selected Profile for This Game",function(button)
    local selected=profileNameBox.Text:gsub("[^%w_%-]","")
    if selected=="" then selected="default" end
    profileNameBox.Text=selected
    local data=readAutoProfiles(); data.byPlace[tostring(game.PlaceId)]=selected
    local ok=writeAutoProfiles(data); refreshAutoProfileStatus(); button.Text=ok and "Game auto profile assigned" or "Assignment failed"
end)
actionButton("Set Selected as Global Fallback",function(button)
    local selected=profileNameBox.Text:gsub("[^%w_%-]","")
    if selected=="" then selected="default" end
    profileNameBox.Text=selected
    local data=readAutoProfiles(); data.fallback=selected
    local ok=writeAutoProfiles(data); refreshAutoProfileStatus(); button.Text=ok and "Global fallback assigned" or "Assignment failed"
end)
actionButton("Clear This Game Auto Profile",function(button)
    local data=readAutoProfiles(); data.byPlace[tostring(game.PlaceId)]=nil
    local ok=writeAutoProfiles(data); refreshAutoProfileStatus(); button.Text=ok and "Game assignment cleared" or "Clear failed"
end,Color3.fromRGB(85,48,62))
refreshAutoProfileStatus()
state.autoLoadAssignedProfile=function()
    local data=readAutoProfiles()
    local assigned=data.byPlace[tostring(game.PlaceId)] or data.fallback
    if assigned and tostring(assigned)~="" then
        profileNameBox.Text=tostring(assigned)
        loadNamedProfile(loadProfileButton)
    end
end
actionButton("Export Profile to Clipboard",function(button)
    local path=getProfilePath()
    if readfile and setclipboard and (not isfile or isfile(path)) then
        local ok,data=pcall(readfile,path)
        if ok then setclipboard(data); button.Text="Profile exported" else button.Text="Export failed" end
    else button.Text="Save profile first" end
end)
actionButton("Import Profile from Text Box",function(button)
    if not writefile then button.Text="File API unavailable"; return end
    local text=profileNameBox.Text
    local ok=pcall(function() HttpService:JSONDecode(text) end)
    if not ok then button.Text="Paste JSON in name box"; return end
    pcall(function() if makefolder and (not isfolder or not isfolder("LucidPanel")) then makefolder("LucidPanel") end end)
    local path="LucidPanel/profile_imported.json"
    local wrote=pcall(writefile,path,text)
    if wrote then profileNameBox.Text="imported"; button.Text="Imported; press Load" else button.Text="Import failed" end
end)
actionButton("Delete Selected Profile",function(button)
    local path=getProfilePath()
    if delfile and (not isfile or isfile(path)) then
        local ok=pcall(delfile,path); button.Text=ok and "Profile deleted" or "Delete failed"
        if ok then refreshProfileList() end
    else button.Text="Delete API/file unavailable" end
end,Color3.fromRGB(90,48,60))

sectionLabel("Window & Performance Manager",nextOrder())
createToggle("Low Performance Mode",nextOrder(),false,function(on)
    state.lowPerformanceMode=on
    notifyLucid("Performance mode",on and "Reduced update frequency enabled" or "Normal update frequency restored",
        on and Color3.fromRGB(235,175,70) or Color3.fromRGB(75,210,120))
end)
createToggle("Disable 3D Rendering",nextOrder(),false,function(on)
    local ok=pcall(function() RunService:Set3dRenderingEnabled(not on) end)
    state.rendering3dDisabled=ok and on or false
    if ok then
        notifyLucid("3D rendering",on and "World rendering disabled; scripts remain active" or "World rendering restored",
            on and Color3.fromRGB(235,175,70) or Color3.fromRGB(75,210,120))
    else
        notifyLucid("3D rendering unavailable","This executor cannot control 3D rendering",Color3.fromRGB(230,90,105))
    end
end)
addCleanup(function()
    state.rendering3dDisabled=false
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
end)
actionButton("Show All Detached Windows",function(button)
    local shown=0
    for _,item in ipairs(detachableWindows) do
        if item.isDetached() and item.window and item.window.Parent then item.window.Visible=true; shown=shown+1 end
    end
    button.Text="Shown: "..shown
end)
actionButton("Reset Off-screen Windows",function(button)
    local camera=workspace.CurrentCamera; local viewport=camera and camera.ViewportSize or Vector2.new(1280,720)
    mainFrame.Position=UDim2.new(0.5,-mainFrame.AbsoluteSize.X/2,0.5,-mainFrame.AbsoluteSize.Y/2)
    local index=0
    for _,item in ipairs(detachableWindows) do
        local window=item.window
        if window and window.Parent then
            local p=window.AbsolutePosition; local s=window.AbsoluteSize
            if p.X+s.X<20 or p.Y+s.Y<20 or p.X>viewport.X-20 or p.Y>viewport.Y-20 then
                index=index+1; window.Position=UDim2.new(0,20+((index-1)%4)*35,0,50+((index-1)%6)*30)
            end
        end
    end
    button.Text="Off-screen windows recovered"
end)
actionButton("Snap Detached Windows to Edges",function(button)
    local camera=workspace.CurrentCamera; local viewport=camera and camera.ViewportSize or Vector2.new(1280,720)
    for _,item in ipairs(detachableWindows) do
        local window=item.window
        if item.isDetached() and window and window.Visible then
            local p=window.AbsolutePosition; local s=window.AbsoluteSize
            local x=(p.X+s.X/2)<viewport.X/2 and 8 or math.max(8,viewport.X-s.X-8)
            local y=math.clamp(p.Y,8,math.max(8,viewport.Y-s.Y-8))
            window.Position=UDim2.new(0,x,0,y)
        end
    end
    button.Text="Detached windows snapped"
end)
end

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
local function findShortcutKey(text)
    local requested=tostring(text or ""):match("^%s*(.-)%s*$"):lower():gsub("[%s_%-]","")
    if requested=="" then return nil end
    local aliases={pgup="pageup",pgdn="pagedown",del="delete",ins="insert",
        back="browserback",backwards="browserback",forward="browserforward",forwards="browserforward"}
    requested=aliases[requested] or requested
    for _,keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
        if keyCode.Name:lower():gsub("[%s_%-]","")==requested then return keyCode end
    end
    if requested=="browserback" then return Enum.KeyCode.Backspace end
    return nil
end
for _, name in ipairs({"Fly","Noclip","Freecam","Migraine","Photo Mode","Character Recovery"}) do
    local shortcutRow = rowFrame(nextOrder(), 30)
    create("TextLabel", {
        Size=UDim2.new(0,72,1,0), BackgroundTransparency=1, Text=name,
        TextColor3=Color3.fromRGB(205,200,215), TextSize=11, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=shortcutRow,
    })
    local box = styledBox(shortcutRow, { Size=UDim2.new(0,100,0,26), Position=UDim2.new(0,76,0.5,-13),
        Text=shortcutKeys[name] and shortcutKeys[name].Name or "", PlaceholderText="Unbound" })
    shortcutBoxes[name]=box
    local clearButton=create("TextButton", {
        Size=UDim2.new(0,60,0,24), Position=UDim2.new(1,-60,0.5,-12),
        BackgroundColor3=Color3.fromRGB(75,48,62), BorderSizePixel=0, Text="Clear",
        TextColor3=Color3.fromRGB(235,215,225), TextSize=10, Font=Enum.Font.GothamSemibold,
        Parent=shortcutRow,
    })
    create("UICorner", { CornerRadius=UDim.new(0,5), Parent=clearButton })
    clearButton.MouseButton1Click:Connect(function()
        shortcutKeys[name]=nil
        box.Text=""
    end)
    box.Focused:Connect(function()
        state.shortcutListeningName=name
        state.shortcutListeningBox=box
        box.Text="Press a key..."
    end)
    box.FocusLost:Connect(function()
        if state.shortcutListeningName==name then
            state.shortcutListeningName=nil
            state.shortcutListeningBox=nil
        end
        local key=findShortcutKey(box.Text)
        if key and key ~= Enum.KeyCode.Unknown and key ~= Enum.KeyCode.RightAlt and key ~= Enum.KeyCode.End then
            shortcutKeys[name]=key
        end
        box.Text=shortcutKeys[name] and shortcutKeys[name].Name or ""
    end)
end
track(UserInputService.InputBegan:Connect(function(input)
    if not state.shortcutListeningName or not state.shortcutListeningBox then return end
    if input.UserInputType~=Enum.UserInputType.Keyboard then return end
    local key=input.KeyCode
    if key==Enum.KeyCode.Unknown then return end
    if key==Enum.KeyCode.Escape then
        state.shortcutListeningBox.Text=shortcutKeys[state.shortcutListeningName] and shortcutKeys[state.shortcutListeningName].Name or ""
    elseif key~=Enum.KeyCode.RightAlt and key~=Enum.KeyCode.End then
        shortcutKeys[state.shortcutListeningName]=key
        state.shortcutListeningBox.Text=key.Name
        state.shortcutCaptureUntil=os.clock()+0.25
    end
    local capturedBox=state.shortcutListeningBox
    state.shortcutListeningName=nil
    state.shortcutListeningBox=nil
    task.defer(function() if capturedBox and capturedBox.Parent then capturedBox:ReleaseFocus() end end)
end))

-- General dynamic backpack cleaner. Tools are discovered from the live
-- Backpack/Character, so users never need to type internal tool names.
do
useCategory("Misc")
sectionLabel("Dynamic Backpack Cleaner",nextOrder())
local backpackCleanerSelections={}
local backpackCleanerDiscovered={}
local backpackCleanerOrder={}
local backpackCleanerAutoArrange=false
local backpackArrangeGeneration=0
local backpackArranging=false
local backpackRespawnGeneration=0
local backpackWaitingForRespawnTools=false
local backpackLastRespawnToolArrival=0
local BACKPACK_CLEANER_PATH="LucidPanel/backpack_cleaner.json"
local function readBackpackCleanerData()
    if not readfile or (isfile and not isfile(BACKPACK_CLEANER_PATH)) then return {byPlace={}} end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(BACKPACK_CLEANER_PATH)) end)
    if not ok or type(data)~="table" then return {byPlace={}} end
    data.byPlace=type(data.byPlace)=="table" and data.byPlace or {}; return data
end
local function saveBackpackCleanerSelections()
    if not writefile then return end
    local data=readBackpackCleanerData(); data.byPlace[tostring(game.PlaceId)]={remove=backpackCleanerSelections,
        order=backpackCleanerOrder,autoArrange=backpackCleanerAutoArrange}
    pcall(function() if makefolder and (not isfolder or not isfolder("LucidPanel")) then makefolder("LucidPanel") end end)
    pcall(function() writefile(BACKPACK_CLEANER_PATH,HttpService:JSONEncode(data)) end)
end
do
    local saved=(readBackpackCleanerData().byPlace or {})[tostring(game.PlaceId)]
    if type(saved)=="table" and type(saved.remove)=="table" then
        for name,enabled in pairs(saved.remove) do if enabled==true then backpackCleanerSelections[name]=true end end
        if type(saved.order)=="table" then backpackCleanerOrder=saved.order end
        backpackCleanerAutoArrange=saved.autoArrange==true
    end
end
local backpackCleanerList=create("ScrollingFrame",{Size=UDim2.new(1,0,0,150),CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(29,27,39),
    BackgroundTransparency=0.2,BorderSizePixel=0,ScrollBarThickness=3,LayoutOrder=nextOrder(),Parent=currentSection})
create("UICorner",{CornerRadius=UDim.new(0,6),Parent=backpackCleanerList})
create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=backpackCleanerList})

local function removeSelectedBackpackTool(object)
    if object and object:IsA("Tool") and backpackCleanerSelections[object.Name] then
        pcall(function() object:Destroy() end)
    end
end
local function discoverBackpackTools()
    local function inspect(container)
        if not container then return end
        for _,object in ipairs(container:GetChildren()) do
            if object:IsA("Tool") then backpackCleanerDiscovered[object.Name]=true end
        end
    end
    inspect(LocalPlayer:FindFirstChildOfClass("Backpack")); inspect(LocalPlayer.Character)
end
local function sweepSelectedBackpackTools()
    local function inspect(container)
        if not container then return end
        for _,object in ipairs(container:GetChildren()) do removeSelectedBackpackTool(object) end
    end
    inspect(LocalPlayer:FindFirstChildOfClass("Backpack")); inspect(LocalPlayer.Character)
end
local function arrangeBackpackTools()
    if not backpackCleanerAutoArrange or backpackArranging or #backpackCleanerOrder==0 then return end
    local backpack=LocalPlayer:FindFirstChildOfClass("Backpack"); if not backpack then return end
    backpackArranging=true
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local originallyEquipped=character and character:FindFirstChildOfClass("Tool")
    if humanoid and originallyEquipped then humanoid:UnequipTools(); RunService.Heartbeat:Wait() end
    local rank={}; for index,name in ipairs(backpackCleanerOrder) do if rank[name]==nil then rank[name]=index end end
    local tools={}; for _,tool in ipairs(backpack:GetChildren()) do if tool:IsA("Tool") then table.insert(tools,tool) end end
    local originalTools={}; for index,tool in ipairs(tools) do originalTools[index]=tool end
    table.sort(tools,function(a,b)
        local ar,br=rank[a.Name] or math.huge,rank[b.Name] or math.huge
        return ar==br and a.Name:lower()<b.Name:lower() or ar<br
    end)
    local alreadyOrdered=true
    for index,tool in ipairs(tools) do
        if originalTools[index]~=tool then alreadyOrdered=false; break end
    end
    if alreadyOrdered then
        if humanoid and originallyEquipped and originallyEquipped.Parent==backpack then pcall(function() humanoid:EquipTool(originallyEquipped) end) end
        backpackArranging=false; return
    end
    for _,tool in ipairs(tools) do tool.Parent=nil end
    -- Core Backpack batches same-frame changes and can retain its old Slot
    -- table. Wait, then insert one Tool per frame to force deterministic slots.
    task.wait(0.12)
    for _,tool in ipairs(tools) do tool.Parent=backpack; RunService.Heartbeat:Wait() end
    if humanoid and originallyEquipped and originallyEquipped.Parent==backpack then pcall(function() humanoid:EquipTool(originallyEquipped) end) end
    backpackArranging=false
end
local function scheduleBackpackArrange()
    if not backpackCleanerAutoArrange or backpackArranging then return end
    backpackArrangeGeneration=backpackArrangeGeneration+1; local generation=backpackArrangeGeneration
    task.delay(0.45,function()
        if generation==backpackArrangeGeneration and screenGui.Parent then arrangeBackpackTools() end
    end)
end
local refreshBackpackCleanerList
refreshBackpackCleanerList=function()
    discoverBackpackTools()
    for _,child in ipairs(backpackCleanerList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    local names={}
    for name in pairs(backpackCleanerDiscovered) do table.insert(names,name) end
    table.sort(names,function(a,b) return a:lower()<b:lower() end)
    if #names==0 then
        create("TextLabel",{Size=UDim2.new(1,-4,0,28),BackgroundTransparency=1,Text="No tools detected yet",
            TextColor3=Color3.fromRGB(150,140,170),TextSize=11,Font=Enum.Font.Gotham,Parent=backpackCleanerList})
        return
    end
    for index,name in ipairs(names) do
        local selected=backpackCleanerSelections[name]==true
        local button=create("TextButton",{Size=UDim2.new(1,-4,0,30),BackgroundColor3=selected and Color3.fromRGB(55,135,82) or Color3.fromRGB(48,42,65),
            BorderSizePixel=0,Text=name..(selected and "  |  AUTO-REMOVE ON" or "  |  Keep"),
            TextColor3=selected and Color3.fromRGB(225,255,232) or Color3.fromRGB(225,220,235),
            TextSize=11,Font=Enum.Font.GothamSemibold,LayoutOrder=index,Parent=backpackCleanerList})
        create("UICorner",{CornerRadius=UDim.new(0,5),Parent=button})
        button.MouseButton1Click:Connect(function()
            backpackCleanerSelections[name]=not backpackCleanerSelections[name] or nil
            saveBackpackCleanerSelections()
            refreshBackpackCleanerList()
            task.defer(sweepSelectedBackpackTools)
        end)
    end
end
actionButton("Refresh Detected Backpack Tools",function(button)
    refreshBackpackCleanerList(); button.Text="Tool list refreshed"
    task.delay(1,function() if button.Parent then button.Text="Refresh Detected Backpack Tools" end end)
end)
actionButton("Clear Backpack Auto-Remove List",function(button)
    table.clear(backpackCleanerSelections); saveBackpackCleanerSelections(); refreshBackpackCleanerList(); button.Text="Auto-remove list cleared"
    task.delay(1,function() if button.Parent then button.Text="Clear Backpack Auto-Remove List" end end)
end,Color3.fromRGB(85,48,62))
createToggle("Auto-arrange Saved Backpack Order",nextOrder(),backpackCleanerAutoArrange,function(on)
    backpackCleanerAutoArrange=on; saveBackpackCleanerSelections(); if on then scheduleBackpackArrange() end
end)
actionButton("Save Current Backpack Order",function(button)
    table.clear(backpackCleanerOrder)
    local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not backpack or not character or not humanoid then button.Text="Character/Backpack unavailable"; return end
    local originalEquipped=character:FindFirstChildOfClass("Tool")
    local slotKeys={Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five,
        Enum.KeyCode.Six,Enum.KeyCode.Seven,Enum.KeyCode.Eight,Enum.KeyCode.Nine,Enum.KeyCode.Zero}
    local recorded={}
    button.Text="Reading hotbar slots 1-0..."
    backpackArranging=true
    humanoid:UnequipTools(); RunService.Heartbeat:Wait()
    for _,keyCode in ipairs(slotKeys) do
        VirtualInputManager:SendKeyEvent(true,keyCode,false,game)
        VirtualInputManager:SendKeyEvent(false,keyCode,false,game)
        task.wait(0.08)
        local equipped=character:FindFirstChildOfClass("Tool")
        if equipped and not recorded[equipped.Name] then
            table.insert(backpackCleanerOrder,equipped.Name); recorded[equipped.Name]=true
        end
        humanoid:UnequipTools(); task.wait(0.03)
    end
    backpackArranging=false
    if backpack then
        for _,tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and not recorded[tool.Name] then table.insert(backpackCleanerOrder,tool.Name); recorded[tool.Name]=true end
        end
    end
    if originalEquipped and originalEquipped.Parent==backpack then
        pcall(function() humanoid:EquipTool(originalEquipped) end)
    end
    saveBackpackCleanerSelections()
    button.Text=#backpackCleanerOrder>0 and ("Saved: "..table.concat(backpackCleanerOrder," > ")) or "No tools to order"
end)
track(LocalPlayer.DescendantAdded:Connect(function(object)
    if not object:IsA("Tool") then return end
    backpackCleanerDiscovered[object.Name]=true
    if backpackWaitingForRespawnTools then backpackLastRespawnToolArrival=os.clock() end
    if backpackArranging then return end
    task.defer(function()
        removeSelectedBackpackTool(object)
        if backpackCleanerList.Parent then refreshBackpackCleanerList() end
    end)
end))
track(LocalPlayer.CharacterAdded:Connect(function()
    -- Persistent inventories arrive in waves. Wait until Tool arrivals have
    -- been quiet, then arrange exactly once for this respawn.
    backpackRespawnGeneration=backpackRespawnGeneration+1
    local generation=backpackRespawnGeneration
    backpackWaitingForRespawnTools=true; backpackLastRespawnToolArrival=os.clock()
    task.spawn(function()
        local started=os.clock()
        while generation==backpackRespawnGeneration and screenGui.Parent do
            if os.clock()-started>=1.5 and os.clock()-backpackLastRespawnToolArrival>=1 then
                backpackWaitingForRespawnTools=false
                arrangeBackpackTools()
                return
            end
            if os.clock()-started>=7 then
                backpackWaitingForRespawnTools=false
                arrangeBackpackTools()
                return
            end
            task.wait(0.2)
        end
    end)
end))
refreshBackpackCleanerList()
end

-- Place-specific obstacle cleanup for Climb Scary Worm Tower 3.
if game.PlaceId==136070094363960 then
    useCategory("Misc")
    sectionLabel("Climb Scary Worm Tower 3",nextOrder())
    local removeBananaPeels=false
    local removeLandmines=false
    local removeAllObstacles=false
    local scaryWormEspEnabled=false
    local scaryWormHighlights=setmetatable({},{__mode="k"})
    local hazardEspEnabled={banana=false,mine=false}
    local hazardHighlights=setmetatable({},{__mode="k"})
    local hazardGhosts={}
    local preserveHazardGhost=function() end

    local function isInsideObstacles(object)
        local obstacles=workspace:FindFirstChild("Obstacles")
        return obstacles and object~=obstacles and object:IsDescendantOf(obstacles)
    end
    local function shouldRemoveObstacle(object)
        if removeAllObstacles and isInsideObstacles(object) then return true end
        local lowerName=object.Name:lower()
        if removeBananaPeels and lowerName:find("banana peel",1,true) then
            -- Equipped tools live under a player's Character, which is itself
            -- inside workspace. Preserve that tool so it can still activate;
            -- only remove the deployed peel after it leaves the character.
            local tool=object:IsA("Tool") and object or object:FindFirstAncestorOfClass("Tool")
            local holder=tool and tool.Parent
            if holder and Players:GetPlayerFromCharacter(holder) then return false end
            local character=object:FindFirstAncestorOfClass("Model")
            if character and Players:GetPlayerFromCharacter(character) then return false end
            return true
        end
        if removeLandmines and (lowerName:find("landmine",1,true) or lowerName:find("land mine",1,true)) then return true end
        return false
    end
    local function removeMatchingObstacle(object)
        if object and object.Parent and shouldRemoveObstacle(object) then
            preserveHazardGhost(object)
            pcall(function() object:Destroy() end)
        end
    end
    local function sweepObstacles()
        for _,object in ipairs(workspace:GetDescendants()) do removeMatchingObstacle(object) end
    end
    local function heldByPlayer(object)
        local tool=object:IsA("Tool") and object or object:FindFirstAncestorOfClass("Tool")
        if tool and tool.Parent and Players:GetPlayerFromCharacter(tool.Parent) then return true end
        local character=object:FindFirstAncestorOfClass("Model")
        return character and Players:GetPlayerFromCharacter(character)~=nil
    end
    local function hazardKind(object)
        if heldByPlayer(object) then return nil end
        local name=object.Name:lower()
        if name:find("banana peel",1,true) then return "banana" end
        if name:find("landmine",1,true) or name:find("land mine",1,true) then return "mine" end
        return nil
    end
    local function hazardTransform(object)
        if object:IsA("BasePart") then return object.CFrame,object.Size end
        if object:IsA("Model") then
            local ok,cframe,size=pcall(object.GetBoundingBox,object)
            if ok then return cframe,size end
        end
        return nil,nil
    end
    local function clearHazardGhosts()
        for key,marker in pairs(hazardGhosts) do
            if marker and marker.Parent then marker:Destroy() end
            hazardGhosts[key]=nil
        end
    end
    preserveHazardGhost=function(object)
        local kind=hazardKind(object)
        if not kind or not hazardEspEnabled[kind] then return end
        local cframe,size=hazardTransform(object)
        if not cframe then return end
        local position=cframe.Position
        local key=string.format("%s:%d:%d:%d",kind,math.floor(position.X/2+0.5),math.floor(position.Y/2+0.5),math.floor(position.Z/2+0.5))
        if hazardGhosts[key] and hazardGhosts[key].Parent then return end
        local marker=Instance.new("Part")
        marker.Name="LucidHazardGhost"; marker.Anchored=true; marker.CanCollide=false; marker.CanTouch=false; marker.CanQuery=false
        marker.Transparency=1; marker.Size=Vector3.new(math.max(1,size.X),math.max(0.5,size.Y),math.max(1,size.Z)); marker.CFrame=cframe
        marker.Parent=workspace
        local box=Instance.new("BoxHandleAdornment")
        box.Name="GhostOutline"; box.Adornee=marker; box.AlwaysOnTop=true; box.ZIndex=10; box.Size=marker.Size
        box.Color3=kind=="banana" and Color3.fromRGB(255,220,35) or Color3.fromRGB(255,75,35)
        box.Transparency=0.35; box.Parent=marker
        local tag=Instance.new("BillboardGui")
        tag.Name="GhostLabel"; tag.Adornee=marker; tag.AlwaysOnTop=true; tag.Size=UDim2.new(0,110,0,24); tag.StudsOffset=Vector3.new(0,marker.Size.Y/2+0.8,0); tag.Parent=marker
        local label=Instance.new("TextLabel")
        label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=1; label.Text=kind=="banana" and "Banana (removed)" or "Mine (removed)"
        label.TextColor3=box.Color3; label.TextStrokeTransparency=0.25; label.Font=Enum.Font.GothamBold; label.TextSize=12; label.Parent=tag
        hazardGhosts[key]=marker
    end
    local function addHazardHighlight(object)
        local kind=hazardKind(object)
        if not kind or not hazardEspEnabled[kind] or hazardHighlights[object] or not (object:IsA("Model") or object:IsA("BasePart")) then return end
        local highlight=Instance.new("Highlight")
        highlight.Name="LucidHazardESP_"..kind; highlight.Adornee=object
        highlight.FillColor=kind=="banana" and Color3.fromRGB(255,220,35) or Color3.fromRGB(255,75,35)
        highlight.OutlineColor=kind=="banana" and Color3.fromRGB(255,245,110) or Color3.fromRGB(255,155,70)
        highlight.FillTransparency=0.82; highlight.OutlineTransparency=0.1
        highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; highlight.Parent=object
        hazardHighlights[object]=highlight
    end
    local function clearHazardHighlights(kind)
        for object,highlight in pairs(hazardHighlights) do
            if not kind or highlight.Name=="LucidHazardESP_"..kind then
                if highlight.Parent then highlight:Destroy() end; hazardHighlights[object]=nil
            end
        end
    end
    local function scanHazards()
        for _,object in ipairs(workspace:GetDescendants()) do addHazardHighlight(object) end
    end
    local function isScaryWorm(object)
        return object and object.Name:lower():find("scary worm",1,true)~=nil
    end
    local function addScaryWormHighlight(object)
        if not scaryWormEspEnabled or not object or not object.Parent or not isScaryWorm(object) then return end
        if scaryWormHighlights[object] and scaryWormHighlights[object].Parent then return end
        local target=(object:IsA("Model") or object:IsA("BasePart")) and object
            or object:FindFirstChildWhichIsA("Model",true) or object:FindFirstChildWhichIsA("BasePart",true)
        if not target then return end
        local highlight=Instance.new("Highlight")
        highlight.Name="LucidScaryWormESP"
        highlight.Adornee=target
        highlight.FillColor=Color3.fromRGB(255,35,35)
        highlight.FillTransparency=0.9
        highlight.OutlineColor=Color3.fromRGB(255,45,45)
        highlight.OutlineTransparency=0.35
        highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent=object
        scaryWormHighlights[object]=highlight
    end
    local function clearScaryWormHighlights()
        for object,highlight in pairs(scaryWormHighlights) do
            if highlight and highlight.Parent then highlight:Destroy() end
            scaryWormHighlights[object]=nil
        end
        for _,highlight in ipairs(workspace:GetDescendants()) do
            if highlight:IsA("Highlight") and highlight.Name=="LucidScaryWormESP" then highlight:Destroy() end
        end
    end
    local function scanScaryWorms()
        for _,object in ipairs(workspace:GetDescendants()) do
            if isScaryWorm(object) then addScaryWormHighlight(object) end
        end
    end

    createToggle("Remove Banana Peels",nextOrder(),false,function(on)
        removeBananaPeels=on
        if on then task.defer(sweepObstacles) end
    end)
    createToggle("Remove Landmines",nextOrder(),false,function(on)
        removeLandmines=on
        if on then task.defer(sweepObstacles) end
    end)
    createToggle("Banana Peel ESP (Yellow)",nextOrder(),false,function(on)
        hazardEspEnabled.banana=on
        if on then task.defer(scanHazards) else clearHazardHighlights("banana") end
    end)
    createToggle("Landmine ESP (Red)",nextOrder(),false,function(on)
        hazardEspEnabled.mine=on
        if on then task.defer(scanHazards) else clearHazardHighlights("mine") end
    end)
    actionButton("Clear Hazard Ghost ESP",function(button)
        clearHazardGhosts(); button.Text="Hazard ghosts cleared"
        task.delay(1.2,function() if button.Parent then button.Text="Clear Hazard Ghost ESP" end end)
    end,Color3.fromRGB(85,55,62))
    createToggle("Remove All Workspace Obstacles",nextOrder(),false,function(on)
        removeAllObstacles=on
        if on then task.defer(sweepObstacles) end
    end)
    createToggle("Scary Worm ESP (Red 90% Transparent)",nextOrder(),false,function(on)
        scaryWormEspEnabled=on
        if on then task.defer(scanScaryWorms) else clearScaryWormHighlights() end
    end)
    track(workspace.DescendantAdded:Connect(function(object)
        if removeBananaPeels or removeLandmines or removeAllObstacles then
            task.defer(removeMatchingObstacle,object)
        end
        if hazardEspEnabled.banana or hazardEspEnabled.mine then task.defer(addHazardHighlight,object) end
        if scaryWormEspEnabled and isScaryWorm(object) then task.defer(addScaryWormHighlight,object) end
    end))
    addCleanup(function()
        scaryWormEspEnabled=false; hazardEspEnabled.banana=false; hazardEspEnabled.mine=false
        clearScaryWormHighlights(); clearHazardHighlights(); clearHazardGhosts()
    end)
end

-- Live diagnostics and a copyable report.
useCategory("Diagnostics")
sectionLabel("Explorer", nextOrder())
local function unloadDexPlusPlus()
    local containers={CoreGui,LocalPlayer:FindFirstChildOfClass("PlayerGui")}
    if type(gethui)=="function" then
        local ok,hiddenUi=pcall(gethui)
        if ok and hiddenUi then table.insert(containers,hiddenUi) end
    end
    local removed=0
    local visited={}
    for _,container in ipairs(containers) do
        if container and not visited[container] then
            visited[container]=true
            for _,gui in ipairs(container:GetChildren()) do
                if gui.Name:sub(1,5)=="_DPP_" then
                    removed=removed+1
                    pcall(function() gui:Destroy() end)
                end
            end
        end
    end
    sharedEnvironment.__LUCID_DEX_LOADING=nil
    return removed
end
actionButton("Launch Dex++ Explorer", function(button)
    if sharedEnvironment.__LUCID_DEX_LOADING then
        button.Text="Dex++ is already loading"
        task.delay(1.5,function() if button.Parent then button.Text="Launch Dex++ Explorer" end end)
        return
    end
    if type(loadstring)~="function" then
        button.Text="Executor has no loadstring"
        return
    end
    local loadToken={}
    sharedEnvironment.__LUCID_DEX_LOADING=loadToken
    button.Text="Loading Dex++..."
    task.spawn(function()
        local fetched, source=pcall(function()
            return game:HttpGet("https://github.com/AZYsGithub/DexPlusPlus/releases/latest/download/out.lua")
        end)
        local launched=false
        if sharedEnvironment.__LUCID_DEX_LOADING==loadToken and fetched and type(source)=="string" and #source>0 then
            local compiled, dexChunk=pcall(loadstring,source)
            if compiled and type(dexChunk)=="function" then launched=pcall(dexChunk) end
        end
        if sharedEnvironment.__LUCID_DEX_LOADING==loadToken then
            sharedEnvironment.__LUCID_DEX_LOADING=nil
        end
        if button.Parent then
            button.Text=launched and "Dex++ launched" or "Dex++ failed to load"
            task.delay(1.5,function() if button.Parent then button.Text="Launch Dex++ Explorer" end end)
        end
    end)
end,Color3.fromRGB(70,52,115))
actionButton("Unload Dex++",function(button)
    local removed=unloadDexPlusPlus()
    button.Text=removed>0 and ("Dex++ unloaded ("..removed..")") or "Dex++ is not running"
    task.delay(1.5,function() if button.Parent then button.Text="Unload Dex++" end end)
end,Color3.fromRGB(105,48,62))
sectionLabel("Live Character Report", nextOrder())
create("TextLabel",{Size=UDim2.new(1,0,0,18),BackgroundTransparency=1,
    Text="Lucid Panel v5.2.6 | Modular UI",TextColor3=Color3.fromRGB(170,155,220),
    TextSize=10,Font=Enum.Font.GothamSemibold,LayoutOrder=nextOrder(),Parent=currentSection})
local diagnosticsLabel = create("TextLabel", { Size=UDim2.new(1,0,0,108), BackgroundColor3=Color3.fromRGB(35,33,48),
    BorderSizePixel=0, Text="Waiting for character...", TextColor3=Color3.fromRGB(205,205,220), TextSize=11,
    Font=Enum.Font.Code, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top, LayoutOrder=nextOrder(), Parent=currentSection })
create("UICorner", { CornerRadius=UDim.new(0,6), Parent=diagnosticsLabel })
actionButton("Copy Diagnostic Report", function(button)
    if setclipboard then setclipboard(diagnosticsLabel.Text); button.Text="Report copied" else button.Text="Clipboard unavailable" end
end)
actionButton("Emergency Cleanup Only",function(button)
    ContextActionService:UnbindAction("LucidFreecamSink")
    state.freecamEnabled=false; releaseFreecamMouse()
    state.rendering3dDisabled=false; pcall(function() RunService:Set3dRenderingEnabled(true) end)
    restoreNoclipCollisions(); destroyPlatform(); removePlayerLight()
    for _,item in ipairs(workspace:GetChildren()) do
        if item.Name:match("^LucidWaypoint_") or item.Name=="LucidFloatPlatform" then item:Destroy() end
    end
    local camera=workspace.CurrentCamera
    local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if camera and humanoid then camera.CameraType=Enum.CameraType.Custom; camera.CameraSubject=humanoid end
    button.Text="Cleanup complete"; task.delay(1,function() if button.Parent then button.Text="Emergency Cleanup Only" end end)
end,Color3.fromRGB(95,60,65))

local flyKeys = { W=false, A=false, S=false, D=false, Space=false, LeftControl=false }
track(UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.End and not processed then panicReset(); return end
    if not processed and UserInputService:GetFocusedTextBox() == nil
        and os.clock()>=(state.shortcutCaptureUntil or 0) then
        if input.KeyCode == shortcutKeys.Fly then
            if state.freecamEnabled then setFreecam(false) end
            fireFly()
        elseif input.KeyCode == shortcutKeys.Noclip then fireNoclip()
        elseif input.KeyCode == shortcutKeys.Freecam then fireFreecam()
        elseif input.KeyCode == shortcutKeys["Photo Mode"] and setPhotoModeToggle then
            setPhotoModeToggle(not state.photoModeEnabled)
        elseif input.KeyCode == shortcutKeys["Character Recovery"] and state.setCharacterRecoveryLoop then
            state.setCharacterRecoveryLoop(not state.characterRecoveryLoopEnabled)
        elseif input.KeyCode == shortcutKeys.Migraine then
            triggerMigraineComfort()
            notifyLucid("Migraine Comfort","Emergency lighting preset applied",Color3.fromRGB(105,180,220))
        end
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
        freecamCFrame = freecamCFrame + direction*state.freecamSpeed*dt
        camera.CFrame=freecamCFrame
    end
    if state.fovLocked and camera then camera.FieldOfView=state.fovValue end
    end)
    if not ok and not renderWarningShown then
        renderWarningShown=true
        warn("[Lucid v4 / Render] "..tostring(err))
    end
end))

state.initializeHomeDashboard=function()
    useCategory("Home")
    sectionLabel("Overview",nextOrder())
    local profileSummary=create("TextLabel",{Size=UDim2.new(1,0,0,24),BackgroundColor3=Color3.fromRGB(35,32,48),
        BackgroundTransparency=0.15,BorderSizePixel=0,Text="Profile: default",TextColor3=Color3.fromRGB(215,205,235),
        TextSize=11,Font=Enum.Font.GothamSemibold,TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=nextOrder(),Parent=currentSection})
    local activeSummary=create("TextLabel",{Size=UDim2.new(1,0,0,48),BackgroundColor3=Color3.fromRGB(35,32,48),
        BackgroundTransparency=0.15,BorderSizePixel=0,Text="No optional features enabled",TextWrapped=true,
        TextColor3=Color3.fromRGB(145,205,160),TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,LayoutOrder=nextOrder(),Parent=currentSection})
    create("UICorner",{CornerRadius=UDim.new(0,6),Parent=profileSummary}); create("UICorner",{CornerRadius=UDim.new(0,6),Parent=activeSummary})
    create("UIPadding",{PaddingLeft=UDim.new(0,8),Parent=profileSummary}); create("UIPadding",{PaddingLeft=UDim.new(0,8),PaddingTop=UDim.new(0,5),Parent=activeSummary})
    sectionLabel("Quick Actions",nextOrder())
    actionButton("Open Favorites",function(button)
        state.mainNavigation.select("Home"); categoryMeta.Home.setOpen(false); categoryMeta.Favorites.setOpen(true)
        button.Text="Favorites opened"
    end)
    actionButton("Apply Migraine Comfort",function(button)
        triggerMigraineComfort(); button.Text="Migraine Comfort applied"
    end,Color3.fromRGB(48,88,105))
    actionButton("Load Selected Profile",function(button) loadNamedProfile(button) end)
    actionButton("Disable All Active Features",function(button)
        for name,enabled in pairs(activeFeatures) do
            if enabled and toggleRegistry[name] then pcall(toggleRegistry[name],false) end
        end
        button.Text="Active features disabled"
    end,Color3.fromRGB(115,55,65))
    actionButton("PANIC / Repair Character [End]",function(button)
        panicReset(); button.Text="Character repaired"
    end,Color3.fromRGB(145,50,65))
    create("TextLabel",{Size=UDim2.new(1,0,0,40),BackgroundTransparency=1,
        Text="Tip: use the top navigation to show only related modules. Search still checks every tool.",
        TextWrapped=true,TextColor3=Color3.fromRGB(145,135,165),TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=nextOrder(),Parent=currentSection})
    task.spawn(function()
        while screenGui.Parent do
            local names={}; for name,enabled in pairs(activeFeatures) do if enabled then table.insert(names,name) end end
            table.sort(names)
            if profileSummary and profileSummary.Parent then
                profileSummary.Text="Profile: "..tostring(profileNameBox and profileNameBox.Text or "unknown").."  |  Place: "..tostring(game.PlaceId)
            end
            if activeSummary and activeSummary.Parent then
                activeSummary.Text=#names==0 and "No optional features enabled" or ("ON ("..#names.."): "..table.concat(names,", "))
            end
            task.wait(state.lowPerformanceMode and 2 or 0.75)
        end
    end)
end
state.initializeHomeDashboard()

state.initializeCommandConsole=function()
    local console=create("Frame",{Name="LucidCommandConsole",Size=UDim2.new(0,350,0,60),
        AnchorPoint=Vector2.new(0.5,1),Position=UDim2.new(0.5,0,0,-8),
        BackgroundColor3=Color3.fromRGB(10,10,13),BackgroundTransparency=0.04,
        BorderSizePixel=0,Visible=false,ZIndex=170,Parent=state.lucidDock})
    state.commandConsole=console
    create("UICorner",{CornerRadius=UDim.new(0,8),Parent=console})
    create("UIStroke",{Color=state.currentThemePalette and state.currentThemePalette.stroke or Color3.fromRGB(58,58,68),
        Thickness=1,Transparency=0.2,Parent=console})
    local input=styledBox(console,{Size=UDim2.new(1,-58,0,28),Position=UDim2.new(0,7,0,7),
        Text="",PlaceholderText="> type a command...",ClearTextOnFocus=false,ZIndex=171})
    local keyLabel=create("TextLabel",{Size=UDim2.new(0,43,0,28),Position=UDim2.new(1,-50,0,7),
        BackgroundColor3=Color3.fromRGB(30,30,36),BorderSizePixel=0,Text="F6",
        TextColor3=Color3.fromRGB(190,190,200),TextSize=10,Font=Enum.Font.GothamSemibold,
        ZIndex=171,Parent=console})
    create("UICorner",{CornerRadius=UDim.new(0,5),Parent=keyLabel})
    local commandListButton=create("TextButton",{Size=UDim2.new(0,72,0,18),Position=UDim2.new(0,7,0,39),
        BackgroundColor3=Color3.fromRGB(30,30,36),BorderSizePixel=0,Text="Commands",
        TextColor3=Color3.fromRGB(235,235,240),TextSize=10,Font=Enum.Font.GothamSemibold,
        ZIndex=171,Parent=console})
    create("UICorner",{CornerRadius=UDim.new(0,4),Parent=commandListButton})
    local status=create("TextLabel",{Size=UDim2.new(1,-90,0,17),Position=UDim2.new(0,84,0,39),
        BackgroundTransparency=1,Text="!help for commands",TextColor3=Color3.fromRGB(145,145,158),
        TextSize=10,Font=Enum.Font.SourceSans,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=171,Parent=console})
    local browser=create("Frame",{Name="CommandBrowser",Size=UDim2.new(0,330,0,350),
        AnchorPoint=Vector2.new(0.5,1),Position=UDim2.new(0.5,0,0,-68),
        BackgroundColor3=Color3.fromRGB(9,9,12),BackgroundTransparency=0.03,
        BorderSizePixel=0,Visible=false,ZIndex=180,Parent=state.lucidDock})
    create("UICorner",{CornerRadius=UDim.new(0,8),Parent=browser})
    create("UIStroke",{Color=state.currentThemePalette and state.currentThemePalette.stroke or Color3.fromRGB(58,58,68),
        Thickness=1,Transparency=0.15,Parent=browser})
    create("TextLabel",{Size=UDim2.new(1,-42,0,28),Position=UDim2.new(0,10,0,4),BackgroundTransparency=1,
        Text="COMMANDS",TextColor3=Color3.fromRGB(240,240,245),TextSize=11,Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=181,Parent=browser})
    local closeBrowser=create("TextButton",{Size=UDim2.new(0,24,0,22),Position=UDim2.new(1,-28,0,6),
        BackgroundColor3=Color3.fromRGB(38,38,45),BorderSizePixel=0,Text="X",TextColor3=Color3.fromRGB(210,210,218),
        TextSize=10,Font=Enum.Font.GothamBold,ZIndex=181,Parent=browser})
    create("UICorner",{CornerRadius=UDim.new(0,4),Parent=closeBrowser})
    local browserSearch=styledBox(browser,{Size=UDim2.new(1,-16,0,28),Position=UDim2.new(0,8,0,34),
        Text="",PlaceholderText="Search commands...",ClearTextOnFocus=false,ZIndex=181})
    local commandList=create("ScrollingFrame",{Size=UDim2.new(1,-16,1,-72),Position=UDim2.new(0,8,0,66),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.new(),ZIndex=181,Parent=browser})
    create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=commandList})
    local function normalize(value) return tostring(value or ""):lower():gsub("%b()",""):gsub("[^%w]","") end
    local function buildCommandCatalog()
        local catalog={
            {command="!emote <animationId> [name]",description="Play an animation by asset ID"},
            {command="!fogend <value>",description="Set and lock the lighting FogEnd"},
            {command="!fov <20-120>",description="Set and lock the camera field of view"},
            {command="!fps <30-1000>",description="Set the client FPS cap"},
            {command="!goto <player>",description="Teleport to an in-game player"},
            {command="!help",description="Show a compact command summary"},
            {command="!jumpheight <value>",description="Set and lock jump height"},
            {command="!loopgoto <player>",description="Continuously follow a player"},
            {command="!migraine",description="Apply Migraine Comfort lighting"},
            {command="!open <section>",description="Open Home, Player, World, Tools or Settings"},
            {command="!panel",description="Show or hide the main Lucid panel"},
            {command="!return",description="Return to the previous teleport position"},
            {command="!showwaypoints <on|off>",description="Show or hide waypoint markers"},
            {command="!stopemote",description="Stop current emote playback or sync"},
            {command="!stopsync",description="Stop player emote synchronization"},
            {command="!sync <player>",description="Synchronize with a player's current emote"},
            {command="!unloopgoto",description="Disable loop goto"},
            {command="!walkspeed <value>",description="Set and lock WalkSpeed"},
            {command="!waypoint delete <name>",description="Delete a named waypoint"},
            {command="!waypoint goto <name>",description="Teleport to a named waypoint"},
            {command="!waypoint list",description="List saved waypoints"},
            {command="!waypoint save <name>",description="Save your current position"},
            {command="!waypoint show <on|off>",description="Control waypoint markers"},
        }
        local known={}
        for _,entry in ipairs(catalog) do known[normalize(entry.command:match("^!?([^%s<]+)"))]=true end
        for label in pairs(toggleRegistry) do
            local command=normalize(label)
            if command~="" and not known[command] then
                table.insert(catalog,{command="!"..command.." [on|off]",description="Toggle: "..label}); known[command]=true
            end
        end
        for label in pairs(state.commandActions or {}) do
            local command=normalize(label)
            if command~="" and not known[command] then
                table.insert(catalog,{command="!"..command,description="Action: "..label}); known[command]=true
            end
        end
        table.sort(catalog,function(a,b) return a.command:lower()<b.command:lower() end)
        return catalog
    end
    local function refreshCommandBrowser()
        for _,child in ipairs(commandList:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local query=browserSearch.Text:match("^%s*(.-)%s*$"):lower()
        local shown=0
        for _,entry in ipairs(buildCommandCatalog()) do
            if query=="" or entry.command:lower():find(query,1,true) or entry.description:lower():find(query,1,true) then
                shown=shown+1
                local button=create("TextButton",{Size=UDim2.new(1,-4,0,42),BackgroundColor3=Color3.fromRGB(20,20,25),
                    BackgroundTransparency=0.05,BorderSizePixel=0,Text="",LayoutOrder=shown,ZIndex=182,Parent=commandList})
                create("UICorner",{CornerRadius=UDim.new(0,5),Parent=button})
                create("TextLabel",{Size=UDim2.new(1,-12,0,18),Position=UDim2.new(0,7,0,3),BackgroundTransparency=1,
                    Text=entry.command,TextColor3=Color3.fromRGB(240,240,245),TextSize=11,Font=Enum.Font.SourceSansSemibold,
                    TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=183,Parent=button})
                create("TextLabel",{Size=UDim2.new(1,-12,0,16),Position=UDim2.new(0,7,0,21),BackgroundTransparency=1,
                    Text=entry.description,TextColor3=Color3.fromRGB(155,155,168),TextSize=10,Font=Enum.Font.SourceSans,
                    TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=183,Parent=button})
                button.MouseButton1Click:Connect(function()
                    input.Text=entry.command:gsub("<[^>]+>",""):gsub("%[[^%]]+%]",""):match("^%s*(.-)%s*$").." "
                    browser.Visible=false; task.defer(function() input:CaptureFocus(); input.CursorPosition=#input.Text+1 end)
                end)
            end
        end
    end
    commandListButton.MouseButton1Click:Connect(function()
        browser.Visible=not browser.Visible
        if browser.Visible then refreshCommandBrowser(); task.defer(function() browserSearch:CaptureFocus() end) end
    end)
    closeBrowser.MouseButton1Click:Connect(function() browser.Visible=false end)
    browserSearch:GetPropertyChangedSignal("Text"):Connect(refreshCommandBrowser)
    local function boolArgument(value,current)
        value=tostring(value or ""):lower()
        if value=="on" or value=="true" or value=="1" or value=="enable" then return true end
        if value=="off" or value=="false" or value=="0" or value=="disable" then return false end
        return not current
    end
    local function finish(ok,message)
        status.Text=tostring(message or (ok and "Command complete" or "Command failed"))
        status.TextColor3=ok and Color3.fromRGB(105,220,145) or Color3.fromRGB(235,105,115)
    end
    local function runCommand(text)
        local raw=tostring(text or ""):match("^%s*(.-)%s*$"):gsub("^!","")
        local command,rest=raw:match("^(%S+)%s*(.-)%s*$")
        command=normalize(command)
        if command=="" then return end
        if command=="help" or command=="commands" then
            finish(true,"!goto !loopgoto !sync !waypoint !espall !noclip !fly !freecam !walkspeed !fogend …")
            return
        elseif command=="open" then
            local target=rest:sub(1,1):upper()..rest:sub(2):lower()
            if state.mainNavigation.groups[target] then mainFrame.Visible=true; state.mainNavigation.select(target); finish(true,"Opened "..target)
            else finish(false,"Use: !open home/player/world/tools/settings") end
            return
        elseif command=="panel" then mainFrame.Visible=not mainFrame.Visible; finish(true,"Panel "..(mainFrame.Visible and "shown" or "hidden")); return
        elseif command=="goto" then
            if rest=="" then finish(false,"Use: !goto <player>") else state.gotoApi.go(rest); finish(true,"Going to "..rest) end
            return
        elseif command=="loopgoto" then
            if rest=="" then finish(false,"Use: !loopgoto <player>") else state.gotoApi.setLoop(rest,true); finish(true,"Loop goto: "..rest) end
            return
        elseif command=="unloopgoto" or command=="stopgoto" then state.gotoApi.setLoop(nil,false); finish(true,"Loop goto disabled"); return
        elseif command=="return" or command=="returnposition" then state.gotoApi.returnPrevious(); finish(true,"Returned to previous position"); return
        elseif command=="sync" then
            if rest=="" then finish(false,"Use: !sync <player>")
            else state.emoteCommandApi.setSyncName(rest); state.emoteCommandApi.beginSync(); finish(true,"Syncing with "..rest) end
            return
        elseif command=="stopsync" or command=="stopemote" then state.emoteCommandApi.stop(); finish(true,"Emote playback/sync stopped"); return
        elseif command=="emote" then
            local id,name=rest:match("^(%d+)%s*(.*)$")
            if id then state.emoteCommandApi.play(tonumber(id),name~="" and name or ("Emote "..id)); finish(true,"Playing emote "..id)
            else finish(false,"Use: !emote <animationId> [name]") end
            return
        elseif command=="waypoint" or command=="wp" then
            local operation,name=rest:match("^(%S+)%s*(.-)%s*$"); operation=normalize(operation)
            if operation=="save" then local ok,msg=state.waypointApi.save(name); finish(ok,msg)
            elseif operation=="goto" or operation=="go" then local ok,msg=state.waypointApi.go(name); finish(ok,msg)
            elseif operation=="delete" or operation=="remove" then local ok,msg=state.waypointApi.delete(name); finish(ok,msg)
            elseif operation=="list" then local names=state.waypointApi.list(); finish(true,#names>0 and table.concat(names,", ") or "No waypoints saved")
            elseif operation=="show" then local setter=toggleRegistry["Show Waypoint Markers"]; if setter then setter(boolArgument(name,activeFeatures["Show Waypoint Markers"])); finish(true,"Waypoint markers updated") end
            else finish(false,"!waypoint save/goto/delete/list/show <name|on|off>") end
            return
        elseif command=="showwaypoints" or command=="waypointmarkers" then
            local setter=toggleRegistry["Show Waypoint Markers"]; setter(boolArgument(rest,activeFeatures["Show Waypoint Markers"])); finish(true,"Waypoint markers updated"); return
        elseif command=="walkspeed" or command=="ws" then
            local value=tonumber(rest); if value then state.walkspeedValue=math.clamp(value,0,500); wsBox.Text=tostring(state.walkspeedValue); wsSetLocked(true); finish(true,"WalkSpeed locked at "..state.walkspeedValue) else finish(false,"Use: !walkspeed <value>") end; return
        elseif command=="jumpheight" or command=="jh" then
            local value=tonumber(rest); if value then state.jumpHeightValue=math.clamp(value,0,100); jhBox.Text=tostring(state.jumpHeightValue); jhSetLocked(true); finish(true,"Jump height locked at "..state.jumpHeightValue) else finish(false,"Use: !jumpheight <value>") end; return
        elseif command=="fov" then
            local value=tonumber(rest); if value then state.fovValue=math.clamp(value,20,120); fovBox.Text=tostring(state.fovValue); toggleRegistry["Lock FOV"](true); finish(true,"FOV locked at "..state.fovValue) else finish(false,"Use: !fov <20-120>") end; return
        elseif command=="fogend" then
            local value=tonumber(rest); if value then state.fogEndValue=math.max(0,value); fogBox.Text=tostring(state.fogEndValue); toggleRegistry["Lock FogEnd"](true); finish(true,"FogEnd locked at "..state.fogEndValue) else finish(false,"Use: !fogend <value>") end; return
        elseif command=="fps" or command=="fpscap" then
            local value=tonumber(rest); if value then state.setFPSCapValue(value); state.setFPSCapEnabled(true); finish(true,"FPS cap set to "..state.fpsCapValue) else finish(false,"Use: !fps <30-1000>") end; return
        elseif command=="migraine" then triggerMigraineComfort(); finish(true,"Migraine comfort applied"); return end

        for label,setter in pairs(toggleRegistry) do
            if normalize(label)==command then
                local desired=boolArgument(rest,activeFeatures[label]); setter(desired)
                finish(true,label..": "..(desired and "ON" or "OFF")); return
            end
        end
        for label,action in pairs(state.commandActions or {}) do
            if normalize(label)==command then action(); finish(true,label); return end
        end
        finish(false,"Unknown command: !"..command.." | use !help")
    end
    input.FocusLost:Connect(function(enterPressed)
        if enterPressed then local text=input.Text; input.Text=""; runCommand(text); task.defer(function() if console.Visible then input:CaptureFocus() end end) end
    end)
    state.toggleCommandConsole=function(force)
        console.Visible=force==nil and not console.Visible or force==true
        if console.Visible then state.lucidDock.Visible=true; task.defer(function() input:CaptureFocus() end)
        else browser.Visible=false; input:ReleaseFocus(); browserSearch:ReleaseFocus() end
        if state.refreshLucidDock then state.refreshLucidDock() end
    end
    track(UserInputService.InputBegan:Connect(function(event,processed)
        if event.KeyCode==Enum.KeyCode.F6 and (not processed or UserInputService:GetFocusedTextBox()==input) then state.toggleCommandConsole() end
    end))
end
state.initializeCommandConsole()

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
            local activeCount=0; for _,enabled in pairs(activeFeatures) do if enabled then activeCount=activeCount+1 end end
            local detachedCount=0; for _,item in ipairs(detachableWindows) do if item.isDetached() then detachedCount=detachedCount+1 end end
            diagnosticsLabel.Text=string.format("Place: %s\nRig: %s | State: %s\nWalkSpeed: %s | HipHeight: %s | Velocity: %s\nLucid: %d connections | %d active | %d detached | %s\nActive: %s",
                tostring(game.PlaceId), rig, humanoidState, h and tostring(h.WalkSpeed) or "-",
                h and string.format("%.2f",h.HipHeight) or "-", speed,#connections,activeCount,detachedCount,
                state.lowPerformanceMode and "LOW PERF" or "NORMAL",statusLabelRef and statusLabelRef.Text or "Anti-AFK")
        end)
        if not ok then
            diagnosticsLabel.Text="Diagnostics unavailable\n"..tostring(err)
            warn("[Lucid v4 / Diagnostics] "..tostring(err))
            diagnosticsFailed=true
        end
        task.wait(state.lowPerformanceMode and 2.5 or 1)
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

    -- Movable freeze: reject external horizontal/rotational impulses while
    -- preserving player-directed movement at the humanoid's current speed.
    if state.antiPushEnabled and hrp and h and not state.freezeEnabled and not state.physicsBypass
        and not h.SeatPart then
        hrp.Anchored = false
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        local currentVelocity = hrp.AssemblyLinearVelocity
        local moveDirection = h.MoveDirection
        local intendedSpeed = state.walkspeedLocked and state.walkspeedValue or h.WalkSpeed
        local intendedHorizontal = moveDirection.Magnitude > 0.01 and moveDirection.Unit * intendedSpeed or Vector3.new(0,0,0)
        if state.antiPushStrength=="Light" then
            intendedHorizontal=Vector3.new(currentVelocity.X,0,currentVelocity.Z):Lerp(intendedHorizontal,0.45)
        elseif state.antiPushStrength=="Normal" then
            intendedHorizontal=Vector3.new(currentVelocity.X,0,currentVelocity.Z):Lerp(intendedHorizontal,0.8)
        end
        -- Keep ordinary jump/fall motion. Strict rejects upward/downward tool
        -- impulses much sooner while retaining enough range for normal jumps.
        local vertical
        if state.antiPushStrength=="Strict" then
            local humanoidState=h:GetState()
            if humanoidState==Enum.HumanoidStateType.Jumping
                or humanoidState==Enum.HumanoidStateType.Freefall then
                vertical=math.clamp(currentVelocity.Y,-45,45)
            else
                vertical=math.clamp(currentVelocity.Y,-20,12)
            end
        else
            local verticalLimit=state.antiPushStrength=="Normal" and 85 or 130
            vertical=math.clamp(currentVelocity.Y,-verticalLimit,verticalLimit)
        end
        hrp.AssemblyLinearVelocity = Vector3.new(
            intendedHorizontal.X,
            vertical,
            intendedHorizontal.Z
        )
    end

    -- Anti-fling: suppress impossible momentum without interfering with normal
    -- running, jumping, vehicles, or deliberate teleports.
    if hrp and state.antiFlingEnabled and not state.physicsBypass then
        local linear = hrp.AssemblyLinearVelocity
        local angular = hrp.AssemblyAngularVelocity
        if linear.Magnitude > state.antiFlingLinear then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        elseif linear.Magnitude > state.antiFlingLinear*0.6 then
            hrp.AssemblyLinearVelocity = linear.Unit * (state.antiFlingLinear*0.6)
        end
        if angular.Magnitude > state.antiFlingAngular then
            hrp.AssemblyAngularVelocity = angular.Unit * state.antiFlingAngular
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

    -- Coordinate labels do not need a physics-frame refresh. Limiting UI text
    -- invalidation substantially reduces layout/render work while moving.
    state.coordUpdateElapsed=(state.coordUpdateElapsed or 0)+dt
    if hrp and state.coordUpdateElapsed>=(state.lowPerformanceMode and 0.25 or 0.1) then
        state.coordUpdateElapsed=0
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

-- AutoClick modes. Requested intervals below one frame remain scheduler-limited.
local function hasInteractiveGuiAt(x,y)
    if not state.autoclickAvoidGui then return false end
    for _,container in ipairs({LocalPlayer:FindFirstChildOfClass("PlayerGui"),CoreGui}) do
        if container then
            local ok,objects=pcall(function() return container:GetGuiObjectsAtPosition(x,y) end)
            if ok then
                for _,object in ipairs(objects) do
                    if object:IsA("GuiButton") or object:IsA("TextBox") then return true end
                end
            end
        end
    end
    return false
end
state.sendAutoMouseClick=function(x,y,useExecutorCursor)
    if useExecutorCursor and type(mouse1click)=="function" then
        local ok=pcall(mouse1click)
        if ok then return true end
    end
    local ok=pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x,y,0,true,game,0)
        VirtualInputManager:SendMouseButtonEvent(x,y,0,false,game,0)
    end)
    if ok then return true end
    return pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(x,y),workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
        VirtualUser:Button1Up(Vector2.new(x,y),workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
    end)
end
task.spawn(function()
    while screenGui.Parent do
        if state.autoclickEnabled then
            local mode=state.autoclickMode or "Hybrid"
            if mode=="Tool" or mode=="Hybrid" then
                local character=LocalPlayer.Character
                local tool=character and character:FindFirstChildOfClass("Tool")
                if tool then pcall(function() tool:Activate() end) end
            end
            if mode=="Mouse" or mode=="Hybrid" or mode=="Center" then
                local camera=workspace.CurrentCamera
                if camera then
                    local x,y
                    if mode=="Center" then
                        local viewport=camera.ViewportSize; x,y=viewport.X/2,viewport.Y/2
                    else
                        local pointer=UserInputService:GetMouseLocation(); x,y=pointer.X,pointer.Y
                    end
                    if not hasInteractiveGuiAt(x,y) then state.sendAutoMouseClick(x,y,mode~="Center") end
                end
            end
        end
        -- Stay dormant while disabled instead of waking at the configured
        -- 1 ms active interval for the entire lifetime of the panel.
        task.wait(state.autoclickEnabled and state.autoclickInterval or 0.25)
    end
end)

-- ════════════════════════════════════════════════════════════
--  TOGGLE GUI VISIBILITY — Right-Alt
-- ════════════════════════════════════════════════════════════
track(UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightAlt then
        mainFrame.Visible = not mainFrame.Visible
        for _,detachable in ipairs(detachableWindows) do
            if detachable.window and detachable.window.Parent and detachable.isDetached() then
                detachable.window.Visible=not state.photoModeEnabled and (detachable.isPinned() or mainFrame.Visible)
            end
        end
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

-- Load the PlaceId-assigned profile only after every category, toggle and
-- detachable window has registered. Loading earlier produced partial configs.
task.defer(state.autoLoadAssignedProfile)

-- Executor-supported teleport persistence. The newly loaded copy queues itself
-- again, so this also works across multi-place teleport chains.
state.queueTeleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
state.teleportBootstrap = string.format(
    "loadstring(game:HttpGet(%q, true))()",
    SCRIPT_URL
)
state.teleportQueueReady = false
if type(state.queueTeleport) == "function" then
    state.teleportQueueReady = pcall(state.queueTeleport, state.teleportBootstrap)
end

if state.teleportQueueReady then
    print("[Lucid Panel v5.2.6] Loaded - teleport auto-execute queued | Right-Alt to toggle")
else
    warn("[Lucid Panel v5.2.6] Loaded, but this executor does not expose queue_on_teleport")
end
