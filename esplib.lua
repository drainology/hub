-- // table
local esplib = getgenv().esplib
if not esplib then
    esplib = {
        box = {
            enabled = false,
            type = "normal",
            padding = 1.15,
            fill = Color3.new(1,1,1),
            fill_transparency = 0,
            outline = Color3.new(0,0,0),
            outline_transparency = 0,
        },
        healthbar = {
            enabled = false,
            fill = Color3.new(0,1,0),
            fill_transparency = 0,
            outline = Color3.new(0,0,0),
            outline_transparency = 0,
        },
        name = {
            enabled = false,
            fill = Color3.new(1,1,1),
            transparency = 0,
            size = 13,
        },
        distance = {
            enabled = false,
            fill = Color3.new(1,1,1),
            transparency = 0,
            size = 13,
        },
        tracer = {
            enabled = false,
            fill = Color3.new(1,1,1),
            fill_transparency = 0,
            outline = Color3.new(0,0,0),
            outline_transparency = 0,
            from = "mouse",
        },
        skeleton = {
            enabled = false,
            fill = Color3.new(1,1,1),
            fill_transparency = 0,
            outline = Color3.new(0,0,0),
            outline_transparency = 0,
        },
        highlight = {
            enabled = false,
            depth_mode = "Always", -- "Always", "Occluded", or "Both"
            fill = Color3.new(1, 0, 0),
            fill_transparency = 0.5,
            outline = Color3.new(1, 1, 1),
            outline_transparency = 0,
            occ_fill = Color3.new(1, 0.5, 0),
            occ_fill_transparency = 0.5,
            occ_outline = Color3.new(1, 0.5, 0),
            occ_outline_transparency = 0,
        },
    }
    getgenv().esplib = esplib
end

local espinstances = {}
local espfunctions = {}

-- // services
local run_service        = game:GetService("RunService")
local players            = game:GetService("Players")
local user_input_service = game:GetService("UserInputService")
local camera             = workspace.CurrentCamera
local local_player       = players.LocalPlayer

-- // ScreenGui container
local screen_gui = local_player:WaitForChild("PlayerGui"):FindFirstChild("_ESPLib")
if not screen_gui then
    screen_gui = Instance.new("ScreenGui")
    screen_gui.Name           = "_ESPLib"
    screen_gui.ResetOnSpawn   = false
    screen_gui.IgnoreGuiInset = true
    screen_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen_gui.Parent         = local_player:WaitForChild("PlayerGui")
end

-- // helpers

local function make_frame(z)
    local f = Instance.new("Frame")
    f.BorderSizePixel      = 0
    f.BackgroundTransparency = 1
    f.Visible              = false
    f.ZIndex               = z or 1
    f.Parent               = screen_gui
    return f
end

local function make_stroke(parent, thickness)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Thickness       = thickness
    s.Color           = Color3.new(1, 1, 1)
    s.Parent          = parent
    return s
end

-- line = rotated frame, anchor at center
local function make_line(thickness, z)
    local f = Instance.new("Frame")
    f.BorderSizePixel    = 0
    f.AnchorPoint        = Vector2.new(0.5, 0.5)
    f.BackgroundColor3   = Color3.new(1, 1, 1)
    f.Size               = UDim2.fromOffset(0, thickness)
    f.Visible            = false
    f.ZIndex             = z or 1
    f.Parent             = screen_gui
    return f
end

local function set_line(frame, from, to, color, thickness, transparency)
    local diff   = to - from
    local length = diff.Magnitude
    frame.BackgroundColor3    = color
    frame.BackgroundTransparency = transparency or 0
    if length < 0.5 then
        frame.Size = UDim2.fromOffset(0, thickness)
        return
    end
    frame.Size     = UDim2.fromOffset(math.ceil(length), thickness)
    frame.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
    frame.Rotation = math.deg(math.atan2(diff.Y, diff.X))
end

local function make_label(z)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.TextColor3             = Color3.new(1, 1, 1)
    t.TextStrokeTransparency = 0
    t.TextStrokeColor3       = Color3.new(0, 0, 0)
    t.Font                   = Enum.Font.Gotham
    t.TextSize               = 13
    t.Text                   = ""
    t.AnchorPoint            = Vector2.new(0.5, 0)
    t.Size                   = UDim2.fromOffset(0, 18)
    t.AutomaticSize          = Enum.AutomaticSize.X
    t.Visible                = false
    t.ZIndex                 = z or 3
    t.Parent                 = screen_gui
    return t
end

-- // bounding box
local function get_bounding_box(instance)
    local min, max = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
    local onscreen = false

    local function process_part(p)
        local size = (p.Size / 2) * esplib.box.padding
        local cf   = p.CFrame
        for _, off in ipairs({
            Vector3.new( size.X,  size.Y,  size.Z), Vector3.new(-size.X,  size.Y,  size.Z),
            Vector3.new( size.X, -size.Y,  size.Z), Vector3.new(-size.X, -size.Y,  size.Z),
            Vector3.new( size.X,  size.Y, -size.Z), Vector3.new(-size.X,  size.Y, -size.Z),
            Vector3.new( size.X, -size.Y, -size.Z), Vector3.new(-size.X, -size.Y, -size.Z),
        }) do
            local pos, vis = camera:WorldToViewportPoint(cf:PointToWorldSpace(off))
            if vis then
                local v2 = Vector2.new(pos.X, pos.Y)
                min = min:Min(v2); max = max:Max(v2); onscreen = true
            end
        end
    end

    if instance:IsA("Model") then
        for _, p in ipairs(instance:GetChildren()) do
            if p:IsA("BasePart") then
                process_part(p)
            elseif p:IsA("Accessory") then
                local h = p:FindFirstChild("Handle")
                if h and h:IsA("BasePart") then process_part(h) end
            end
        end
    elseif instance:IsA("BasePart") then
        local size = instance.Size / 2
        local cf   = instance.CFrame
        for _, off in ipairs({
            Vector3.new( size.X,  size.Y,  size.Z), Vector3.new(-size.X,  size.Y,  size.Z),
            Vector3.new( size.X, -size.Y,  size.Z), Vector3.new(-size.X, -size.Y,  size.Z),
            Vector3.new( size.X,  size.Y, -size.Z), Vector3.new(-size.X,  size.Y, -size.Z),
            Vector3.new( size.X, -size.Y, -size.Z), Vector3.new(-size.X, -size.Y, -size.Z),
        }) do
            local pos, vis = camera:WorldToViewportPoint(cf:PointToWorldSpace(off))
            if vis then
                local v2 = Vector2.new(pos.X, pos.Y)
                min = min:Min(v2); max = max:Max(v2); onscreen = true
            end
        end
    end
    return min, max, onscreen
end

-- // add functions

function espfunctions.add_box(instance)
    if not instance or espinstances[instance] and espinstances[instance].box then return end
    local box = {}

    -- normal box
    box.side_outline = {}
    box.side_fill    = {}
    for _ = 1, 4 do
        table.insert(box.side_outline, make_line(2, 1))
        table.insert(box.side_fill,    make_line(1, 2))
    end

    -- corner box
    box.corner_outline = {}
    box.corner_fill    = {}
    for _ = 1, 8 do
        table.insert(box.corner_outline, make_line(2, 1))
        table.insert(box.corner_fill,    make_line(1, 2))
    end

    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].box = box
end

function espfunctions.add_healthbar(instance)
    if not instance or espinstances[instance] and espinstances[instance].healthbar then return end
    local outline = make_frame(1); outline.BackgroundTransparency = 0
    local fill    = make_frame(2); fill.BackgroundTransparency    = 0
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].healthbar = { outline = outline, fill = fill }
end

function espfunctions.add_name(instance)
    if not instance or espinstances[instance] and espinstances[instance].name then return end
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].name = make_label(3)
end

function espfunctions.add_distance(instance)
    if not instance or espinstances[instance] and espinstances[instance].distance then return end
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].distance = make_label(3)
end

function espfunctions.add_tracer(instance)
    if not instance or espinstances[instance] and espinstances[instance].tracer then return end
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].tracer = {
        outline = make_line(2, 1),
        fill    = make_line(1, 2),
    }
end

-- // skeleton bone tables
-- Each bone: { {partName, {xMul,yMul,zMul}}, {partName, {xMul,yMul,zMul}} }
-- Offsets are multipliers of the part's half-size in local space.
local R6_BONES = {
    -- neck: head bottom → torso top
    { {"Head",  {0,-1,0}}, {"Torso", {0, 1, 0}} },
    -- spine: torso top → torso bottom
    { {"Torso", {0, 1, 0}}, {"Torso", {0,-1, 0}} },
    -- left: clavicle (torso top → arm center) + forearm (center → wrist)
    { {"Torso",    {0, 1, 0}}, {"Left Arm",  {0, 0, 0}} },
    { {"Left Arm", {0, 0, 0}}, {"Left Arm",  {0,-1, 0}} },
    -- right
    { {"Torso",     {0, 1, 0}}, {"Right Arm", {0, 0, 0}} },
    { {"Right Arm", {0, 0, 0}}, {"Right Arm", {0,-1, 0}} },
    -- left hip → knee → ankle
    { {"Torso",   {0,-1, 0}}, {"Left Leg",  {0, 1, 0}} },
    { {"Left Leg",{0, 1, 0}}, {"Left Leg",  {0, 0, 0}} },
    { {"Left Leg",{0, 0, 0}}, {"Left Leg",  {0,-1, 0}} },
    -- right hip → knee → ankle
    { {"Torso",     {0,-1, 0}}, {"Right Leg", {0, 1, 0}} },
    { {"Right Leg", {0, 1, 0}}, {"Right Leg", {0, 0, 0}} },
    { {"Right Leg", {0, 0, 0}}, {"Right Leg", {0,-1, 0}} },
}

local R15_BONES = {
    { {"Head",          {0,0,0}}, {"UpperTorso",   {0,0,0}} },
    { {"UpperTorso",    {0,0,0}}, {"LowerTorso",   {0,0,0}} },
    { {"LowerTorso",    {0,0,0}}, {"LeftUpperLeg", {0,0,0}} },
    { {"LowerTorso",    {0,0,0}}, {"RightUpperLeg",{0,0,0}} },
    { {"LeftUpperLeg",  {0,0,0}}, {"LeftLowerLeg", {0,0,0}} },
    { {"LeftLowerLeg",  {0,0,0}}, {"LeftFoot",     {0,0,0}} },
    { {"RightUpperLeg", {0,0,0}}, {"RightLowerLeg",{0,0,0}} },
    { {"RightLowerLeg", {0,0,0}}, {"RightFoot",    {0,0,0}} },
    { {"UpperTorso",    {0,0,0}}, {"LeftUpperArm", {0,0,0}} },
    { {"LeftUpperArm",  {0,0,0}}, {"LeftLowerArm", {0,0,0}} },
    { {"LeftLowerArm",  {0,0,0}}, {"LeftHand",     {0,0,0}} },
    { {"UpperTorso",    {0,0,0}}, {"RightUpperArm",{0,0,0}} },
    { {"RightUpperArm", {0,0,0}}, {"RightLowerArm",{0,0,0}} },
    { {"RightLowerArm", {0,0,0}}, {"RightHand",    {0,0,0}} },
}

local MAX_SKELETON_BONES = 14  -- both rigs use 14 segments

-- resolves a bone point to a world-space 
local function get_bone_pos(instance, point)
    local part = instance:FindFirstChild(point[1])
    if not part then return nil end
    local off = point[2]
    if off[1] == 0 and off[2] == 0 and off[3] == 0 then
        return part.Position
    end
    local h = part.Size * 0.5
    return part.CFrame:PointToWorldSpace(Vector3.new(h.X*off[1], h.Y*off[2], h.Z*off[3]))
end

function espfunctions.add_skeleton(instance)
    if not instance or espinstances[instance] and espinstances[instance].skeleton then return end
    local skel = { lines = {} }
    for _ = 1, MAX_SKELETON_BONES do
        table.insert(skel.lines, {
            outline = make_line(2, 1),
            fill    = make_line(1, 2),
        })
    end
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].skeleton = skel
end

-- // highlight 
local hl_params_cache = {}

local CORNER_OFFSETS = { -- skull
    Vector3.new( 1,  1,  1), Vector3.new(-1,  1,  1),
    Vector3.new( 1, -1,  1), Vector3.new(-1, -1,  1),
    Vector3.new( 1,  1, -1), Vector3.new(-1,  1, -1),
    Vector3.new( 1, -1, -1), Vector3.new(-1, -1, -1),
}

local function is_visible(instance, params)
    local origin = camera.CFrame.Position
    for _, part in ipairs(instance:GetDescendants()) do
        if not part:IsA("BasePart") then continue end
        local cf, half = part.CFrame, part.Size * 0.5
        if not workspace:Raycast(origin, part.Position - origin, params) then return true end
        for _, off in ipairs(CORNER_OFFSETS) do
            local corner = cf:PointToWorldSpace(Vector3.new(half.X*off.X, half.Y*off.Y, half.Z*off.Z))
            if not workspace:Raycast(origin, corner - origin, params) then return true end
        end
    end
    return false
end

function espfunctions.add_highlight(instance)
    if not instance or espinstances[instance] and espinstances[instance].highlight then return end
    local hl = Instance.new("Highlight")
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee   = instance
    hl.Enabled   = false
    hl.Parent    = instance
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { instance }
    params.FilterType = Enum.RaycastFilterType.Exclude
    hl_params_cache[instance] = params
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].highlight = hl
end

-- // main thread
run_service.RenderStepped:Connect(function()
    for instance, data in pairs(espinstances) do

        -- cleanup 
        if not instance or not instance.Parent then
            if data.box then
                for _, l in ipairs(data.box.side_outline)   do l:Destroy() end
                for _, l in ipairs(data.box.side_fill)      do l:Destroy() end
                for _, l in ipairs(data.box.corner_outline) do l:Destroy() end
                for _, l in ipairs(data.box.corner_fill)    do l:Destroy() end
            end
            if data.healthbar then
                data.healthbar.outline:Destroy()
                data.healthbar.fill:Destroy()
            end
            if data.name     then data.name:Destroy()     end
            if data.distance then data.distance:Destroy() end
            if data.tracer   then
                data.tracer.outline:Destroy()
                data.tracer.fill:Destroy()
            end
            if data.skeleton then
                for _, line in ipairs(data.skeleton.lines) do
                    line.outline:Destroy()
                    line.fill:Destroy()
                end
            end
            if data.highlight then
                data.highlight:Destroy()
                hl_params_cache[instance] = nil
            end
            espinstances[instance] = nil
            continue
        end

        if instance:IsA("Model") and not instance.PrimaryPart then continue end

        local min, max, onscreen = get_bounding_box(instance)

        -- box
        if data.box then
            local box = data.box
            if esplib.box.enabled and onscreen then
                local x, y = min.X, min.Y
                local w, h = (max - min).X, (max - min).Y
                local len  = math.min(w, h) * 0.25

                if esplib.box.type == "normal" then
                    -- 4 sides: top, right, bottom, left
                    local sides = {
                        { Vector2.new(x,   y),   Vector2.new(x+w, y)   }, -- top
                        { Vector2.new(x+w, y),   Vector2.new(x+w, y+h) }, -- right
                        { Vector2.new(x,   y+h), Vector2.new(x+w, y+h) }, -- bottom
                        { Vector2.new(x,   y),   Vector2.new(x,   y+h) }, -- left
                    }
                    for i = 1, 4 do
                        local f, t = sides[i][1], sides[i][2]
                        local dir  = (t - f).Unit
                        local o = box.side_outline[i]
                        set_line(o, f - dir, t + dir, esplib.box.outline, 2, esplib.box.outline_transparency)
                        o.Visible = true
                        local fl = box.side_fill[i]
                        set_line(fl, f, t, esplib.box.fill, 1, esplib.box.fill_transparency)
                        fl.Visible = true
                    end
                    for _, l in ipairs(box.corner_fill)    do l.Visible = false end
                    for _, l in ipairs(box.corner_outline) do l.Visible = false end

                elseif esplib.box.type == "corner" then
                    for _, l in ipairs(box.side_outline) do l.Visible = false end
                    for _, l in ipairs(box.side_fill)    do l.Visible = false end
                    local corners = {
                        {Vector2.new(x,y),           Vector2.new(x+len,y)    },
                        {Vector2.new(x,y),           Vector2.new(x,y+len)    },
                        {Vector2.new(x+w-len,y),     Vector2.new(x+w,y)      },
                        {Vector2.new(x+w,y),         Vector2.new(x+w,y+len)  },
                        {Vector2.new(x,y+h),         Vector2.new(x+len,y+h)  },
                        {Vector2.new(x,y+h-len),     Vector2.new(x,y+h)      },
                        {Vector2.new(x+w-len,y+h),   Vector2.new(x+w,y+h)    },
                        {Vector2.new(x+w,y+h-len),   Vector2.new(x+w,y+h)    },
                    }
                    for i = 1, 8 do
                        local f, t = corners[i][1], corners[i][2]
                        local dir  = (t - f).Unit
                        local o = box.corner_outline[i]
                        set_line(o, f - dir, t + dir, esplib.box.outline, 2, esplib.box.outline_transparency)
                        o.Visible = true
                        local fl = box.corner_fill[i]
                        set_line(fl, f, t, esplib.box.fill, 1, esplib.box.fill_transparency)
                        fl.Visible = true
                    end
                end
            else
                for _, l in ipairs(box.side_outline)   do l.Visible = false end
                for _, l in ipairs(box.side_fill)      do l.Visible = false end
                for _, l in ipairs(box.corner_fill)    do l.Visible = false end
                for _, l in ipairs(box.corner_outline) do l.Visible = false end
            end
        end

        -- healthbar
        if data.healthbar then
            local outline, fill = data.healthbar.outline, data.healthbar.fill
            if not esplib.healthbar.enabled or not onscreen then
                outline.Visible = false; fill.Visible = false
            else
                local hum = instance:FindFirstChildOfClass("Humanoid")
                if hum then
                    local height    = max.Y - min.Y
                    local pad       = 1
                    local bx        = min.X - 3 - 1 - pad
                    local by        = min.Y - pad
                    local health    = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                    local fillh     = height * health
                    outline.BackgroundColor3    = esplib.healthbar.outline
                    outline.BackgroundTransparency = esplib.healthbar.outline_transparency
                    outline.Position             = UDim2.fromOffset(bx, by)
                    outline.Size                 = UDim2.fromOffset(1 + 2*pad, height + 2*pad)
                    outline.Visible              = true
                    fill.BackgroundColor3        = esplib.healthbar.fill
                    fill.BackgroundTransparency  = esplib.healthbar.fill_transparency
                    fill.Position                = UDim2.fromOffset(bx + pad, by + (height + pad) - fillh)
                    fill.Size                    = UDim2.fromOffset(1, fillh)
                    fill.Visible                 = true
                else
                    outline.Visible = false; fill.Visible = false
                end
            end
        end

        -- name
        if data.name then
            if esplib.name.enabled and onscreen then
                local t      = data.name
                local cx     = (min.X + max.X) / 2
                local name_s = instance.Name
                local hum    = instance:FindFirstChildOfClass("Humanoid")
                if hum then
                    local pl = players:GetPlayerFromCharacter(instance)
                    if pl then name_s = pl.Name end
                end
                t.Text                = name_s
                t.TextSize            = esplib.name.size
                t.TextColor3          = esplib.name.fill
                t.TextTransparency    = esplib.name.transparency
                t.TextStrokeTransparency = esplib.name.transparency
                t.Size                = UDim2.fromOffset(0, esplib.name.size + 4)
                t.Position            = UDim2.fromOffset(cx, min.Y - esplib.name.size - 4)
                t.Visible             = true
            else
                data.name.Visible = false
            end
        end

        -- distance
        if data.distance then
            if esplib.distance.enabled and onscreen then
                local t    = data.distance
                local cx   = (min.X + max.X) / 2
                local dist
                if instance:IsA("Model") then
                    local pp = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
                    dist = pp and (camera.CFrame.Position - pp.Position).Magnitude or 999
                else
                    dist = (camera.CFrame.Position - instance.Position).Magnitude
                end
                t.Text                = tostring(math.floor(dist)) .. "m"
                t.TextSize            = esplib.distance.size
                t.TextColor3          = esplib.distance.fill
                t.TextTransparency    = esplib.distance.transparency
                t.TextStrokeTransparency = esplib.distance.transparency
                t.Size                = UDim2.fromOffset(0, esplib.distance.size + 4)
                t.Position            = UDim2.fromOffset(cx, max.Y + 5)
                t.Visible             = true
            else
                data.distance.Visible = false
            end
        end

        -- tracer
        if data.tracer then
            if esplib.tracer.enabled and onscreen then
                local outline, fill = data.tracer.outline, data.tracer.fill
                local from_pos = Vector2.new()
                local to_pos   = (min + max) / 2

                if esplib.tracer.from == "mouse" then
                    local ml = user_input_service:GetMouseLocation()
                    from_pos = Vector2.new(ml.X, ml.Y)
                elseif esplib.tracer.from == "head" then
                    local head = instance:FindFirstChild("Head")
                    if head then
                        local p, v = camera:WorldToViewportPoint(head.Position)
                        from_pos = v and Vector2.new(p.X, p.Y) or Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                    else
                        from_pos = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                    end
                elseif esplib.tracer.from == "center" then
                    from_pos = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y/2)
                else -- bottom
                    from_pos = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                end

                local diff = to_pos - from_pos
                local dir  = diff.Magnitude > 0.5 and diff.Unit or Vector2.new(0, 0)
                set_line(outline, from_pos - dir, to_pos + dir, esplib.tracer.outline, 2, esplib.tracer.outline_transparency)
                outline.Visible = true
                set_line(fill, from_pos, to_pos, esplib.tracer.fill, 1, esplib.tracer.fill_transparency)
                fill.Visible = true
            else
                data.tracer.outline.Visible = false
                data.tracer.fill.Visible    = false
            end
        end

        -- skeleton
        if data.skeleton then
            if esplib.skeleton.enabled then
                local bones
                if instance:FindFirstChild("UpperTorso") then
                    bones = R15_BONES
                elseif instance:FindFirstChild("Torso") then
                    bones = R6_BONES
                end

                if bones then
                    for i, bone in ipairs(bones) do
                        local line  = data.skeleton.lines[i]
                        local wposA = get_bone_pos(instance, bone[1])
                        local wposB = get_bone_pos(instance, bone[2])
                        if wposA and wposB then
                            local sA, vA = camera:WorldToViewportPoint(wposA)
                            local sB, vB = camera:WorldToViewportPoint(wposB)
                            if vA and vB then
                                local from = Vector2.new(sA.X, sA.Y)
                                local to   = Vector2.new(sB.X, sB.Y)
                                local diff = to - from
                                local dir  = diff.Magnitude > 0.5 and diff.Unit or Vector2.new(0, 0)
                                set_line(line.outline, from - dir*2, to + dir*2, esplib.skeleton.outline, 2, esplib.skeleton.outline_transparency)
                                line.outline.Visible = true
                                set_line(line.fill, from - dir*2, to + dir*2, esplib.skeleton.fill, 1, esplib.skeleton.fill_transparency)
                                line.fill.Visible = true
                                continue
                            end
                        end
                        line.outline.Visible = false
                        line.fill.Visible    = false
                    end
                    -- hide unused slots (R6 uses 5, R15 uses 14)
                    for i = #bones + 1, MAX_SKELETON_BONES do
                        data.skeleton.lines[i].outline.Visible = false
                        data.skeleton.lines[i].fill.Visible    = false
                    end
                else
                    for _, line in ipairs(data.skeleton.lines) do
                        line.outline.Visible = false
                        line.fill.Visible    = false
                    end
                end
            else
                for _, line in ipairs(data.skeleton.lines) do
                    line.outline.Visible = false
                    line.fill.Visible    = false
                end
            end
        end

        -- highlight
        if data.highlight then
            local hl  = data.highlight
            local cfg = esplib.highlight
            if not cfg.enabled then
                hl.Enabled = false
            else
                hl.Enabled = true
                if cfg.depth_mode == "Always" then
                    hl.FillColor           = cfg.fill
                    hl.FillTransparency    = cfg.fill_transparency
                    hl.OutlineColor        = cfg.outline
                    hl.OutlineTransparency = cfg.outline_transparency

                elseif cfg.depth_mode == "Occluded" then
                    local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
                    local occluded = false
                    if primary then
                        local o = camera.CFrame.Position
                        local r = hl_params_cache[instance] and workspace:Raycast(o, primary.Position - o, hl_params_cache[instance])
                        occluded = r ~= nil
                    end
                    if occluded then
                        hl.FillTransparency = 1; hl.OutlineTransparency = 1
                    else
                        hl.FillColor = cfg.fill; hl.FillTransparency = cfg.fill_transparency
                        hl.OutlineColor = cfg.outline; hl.OutlineTransparency = cfg.outline_transparency
                    end

                elseif cfg.depth_mode == "Both" then
                    local params  = hl_params_cache[instance]
                    local visible = params and is_visible(instance, params) or false
                    if not visible then
                        hl.FillColor = cfg.occ_fill; hl.FillTransparency = cfg.occ_fill_transparency
                        hl.OutlineColor = cfg.occ_outline; hl.OutlineTransparency = cfg.occ_outline_transparency
                    else
                        hl.FillColor = cfg.fill; hl.FillTransparency = cfg.fill_transparency
                        hl.OutlineColor = cfg.outline; hl.OutlineTransparency = cfg.outline_transparency
                    end
                end
            end
        end
    end
end)

-- // return
for k, v in pairs(espfunctions) do
    esplib[k] = v
end

return esplib
