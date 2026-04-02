-- // table
local esplib = getgenv().esplib
if not esplib then
    esplib = {
        box = {
            enabled = false,
            type = "normal",
            padding = 1.15,
            outline = Color3.new(1,1,1),
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
    local len_adj = (thickness > 1) and (math.ceil(length) + thickness - 1) or math.ceil(length)
    frame.Size     = UDim2.fromOffset(len_adj, thickness)
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

    -- holder: positioned/sized to the bounding box each frame, transparent bg
    local holder = Instance.new("Frame")
    holder.Name                   = "_Box"
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel        = 0
    holder.Visible                = false
    holder.ZIndex                 = 1
    holder.Parent                 = screen_gui

    -- LAYER 1: outer black stroke (2px) on the holder itself
    local stroke_outer = Instance.new("UIStroke")
    stroke_outer.Thickness    = 2
    stroke_outer.Color        = Color3.new(0, 0, 0)
    stroke_outer.Transparency = 0
    stroke_outer.LineJoinMode = Enum.LineJoinMode.Miter
    stroke_outer.Parent       = holder

    -- LAYER 2: main configurable stroke (1px) on a frame inset 2px
    local mid_frame = Instance.new("Frame")
    mid_frame.BackgroundTransparency = 1
    mid_frame.BorderSizePixel        = 0
    mid_frame.Position               = UDim2.new(0, 2, 0, 2)
    mid_frame.Size                   = UDim2.new(1, -4, 1, -4)
    mid_frame.ZIndex                 = 2
    mid_frame.Parent                 = holder

    local stroke_mid = Instance.new("UIStroke")
    stroke_mid.Thickness    = 1
    stroke_mid.Color        = Color3.new(1, 1, 1)
    stroke_mid.Transparency = 0
    stroke_mid.LineJoinMode = Enum.LineJoinMode.Miter
    stroke_mid.Parent       = mid_frame

    -- LAYER 3: inner black stroke (2px) on a frame inset 3px
    local inner_frame = Instance.new("Frame")
    inner_frame.BackgroundTransparency = 1
    inner_frame.BorderSizePixel        = 0
    inner_frame.Position               = UDim2.new(0, 3, 0, 3)
    inner_frame.Size                   = UDim2.new(1, -6, 1, -6)
    inner_frame.ZIndex                 = 3
    inner_frame.Parent                 = holder

    local stroke_inner = Instance.new("UIStroke")
    stroke_inner.Thickness    = 2
    stroke_inner.Color        = Color3.new(0, 0, 0)
    stroke_inner.Transparency = 0
    stroke_inner.LineJoinMode = Enum.LineJoinMode.Miter
    stroke_inner.Parent       = inner_frame

    -- corner box: 4 L-shapes parented to holder using relative UDim2 scale
    -- Each arm has 3 layers: outer black | mid color | inner black
    local corner_pieces = {}
    local CS = 0.25  -- arm length = 25% of the box dimension
    local function add_corner(ax, ay, px, py)
        local function make_arm(is_horiz)
            -- outer black bar
            local sw = is_horiz and UDim2.new(CS, 0, 0, 5) or UDim2.new(0, 5, CS, 0)
            local ox = is_horiz and 0 or (ax == 1 and -4 or 0)
            local oy = is_horiz and (ay == 1 and -4 or 0) or (ay == 1 and -5 or 1)
            local fo = Instance.new("Frame")
            fo.AnchorPoint          = Vector2.new(ax, ay)
            fo.BackgroundColor3     = Color3.new(0, 0, 0)
            fo.BackgroundTransparency = 0
            fo.BorderSizePixel      = 0
            fo.Position             = UDim2.new(px, ox, py, oy)
            fo.Size                 = sw
            fo.ZIndex               = 3
            fo.Parent               = holder
            -- mid color bar (inset 1px)
            local fm = Instance.new("Frame")
            fm.BackgroundColor3     = Color3.new(1, 1, 1)
            fm.BackgroundTransparency = 0
            fm.BorderSizePixel      = 0
            fm.Position             = UDim2.new(0, 1, 0, 1)
            fm.Size                 = UDim2.new(1, -2, 1, -2)
            fm.ZIndex               = 4
            fm.Parent               = fo
            -- inner black bar (inset 1px more)
            local fi = Instance.new("Frame")
            fi.BackgroundColor3     = Color3.new(0, 0, 0)
            fi.BackgroundTransparency = 0
            fi.BorderSizePixel      = 0
            fi.Position             = UDim2.new(0, 1, 0, 1)
            fi.Size                 = UDim2.new(1, -2, 1, -2)
            fi.ZIndex               = 5
            fi.Parent               = fm
            return { outer = fo, mid = fm, inner = fi }
        end
        corner_pieces[#corner_pieces + 1] = { h = make_arm(true), v = make_arm(false) }
    end
    add_corner(0, 0, 0, 0)  -- top-left
    add_corner(1, 0, 1, 0)  -- top-right
    add_corner(0, 1, 0, 1)  -- bottom-left
    add_corner(1, 1, 1, 1)  -- bottom-right

    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].box = {
        holder        = holder,
        stroke_outer  = stroke_outer,
        mid_frame     = mid_frame,
        stroke_mid    = stroke_mid,
        inner_frame   = inner_frame,
        stroke_inner  = stroke_inner,
        corner_pieces = corner_pieces,
    }
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

-- // skeleton helpers

-- Part-offset helper (used by R15)
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
local MAX_SKELETON_BONES = 14

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

-- R6: offset-based bone table (half-size multipliers in local space)
local R6_BONES = {
    -- neck: head center → torso top
    { {"Head",  {0, 0, 0}}, {"Torso", {0, 1, 0}} },
    -- spine: torso top → torso bottom
    { {"Torso", {0, 1, 0}}, {"Torso", {0,-1, 0}} },
    -- left: clavicle (torso top → elbow) + forearm (elbow → wrist)
    { {"Torso",    {0, 1,   0}}, {"Left Arm",  {0, 0.5, 0}} },
    { {"Left Arm", {0, 0.5, 0}}, {"Left Arm",  {0, -1,  0}} },
    -- right
    { {"Torso",     {0, 1,   0}}, {"Right Arm", {0, 0.5, 0}} },
    { {"Right Arm", {0, 0.5, 0}}, {"Right Arm", {0, -1,  0}} },
    -- left hip (torso bottom → leg center) + shin (center → ankle)
    { {"Torso",   {0,-1, 0}}, {"Left Leg",  {0, 0, 0}} },
    { {"Left Leg",{0, 0, 0}}, {"Left Leg",  {0,-1, 0}} },
    -- right
    { {"Torso",     {0,-1, 0}}, {"Right Leg", {0, 0, 0}} },
    { {"Right Leg", {0, 0, 0}}, {"Right Leg", {0,-1, 0}} },
}

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

-- // hide all elements for an instance without destroying them
local function hide_instance(data)
    if data.box then
        data.box.holder.Visible = false
    end
    if data.healthbar then
        data.healthbar.outline.Visible = false
        data.healthbar.fill.Visible    = false
    end
    if data.name     then data.name.Visible     = false end
    if data.distance then data.distance.Visible = false end
    if data.tracer   then
        data.tracer.outline.Visible = false
        data.tracer.fill.Visible    = false
    end
    if data.skeleton then
        for _, line in ipairs(data.skeleton.lines) do
            line.outline.Visible = false
            line.fill.Visible    = false
        end
    end
    if data.highlight then
        data.highlight.Enabled = false
    end
end

-- // main thread
run_service.RenderStepped:Connect(function(dt)
    for instance, data in pairs(espinstances) do

        -- cleanup 
        if not instance or not instance.Parent then
            if data.box      then data.box.holder:Destroy() end
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

        local is_dead = false
        if instance:IsA("Model") then
            local hum = instance:FindFirstChildOfClass("Humanoid")
            if hum then
                data.had_humanoid = true
                if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
                    is_dead = true
                end
            else
                if data.had_humanoid then
                    is_dead = true
                end
            end
            
            if not instance.PrimaryPart then
                is_dead = true
            end
        end

        local FADE_DURATION = 0.5 -- seconds
        if is_dead then
            data.death_time = data.death_time or tick()
            local elapsed_time = tick() - data.death_time
            data.fade_alpha = math.clamp(elapsed_time / FADE_DURATION, 0, 1)
        else
            data.death_time = nil
            data.fade_alpha = 0
        end

        local alpha = data.fade_alpha
        local current_fade = alpha * alpha * (3 - 2 * alpha) -- smooth easing

        local function fade_trans(base)
            return 1 - (1 - base) * (1 - current_fade)
        end

        if current_fade >= 0.99 and is_dead then
            hide_instance(data)
            continue
        end

        local min, max, onscreen = get_bounding_box(instance)

        -- box
        if data.box then
            local box = data.box
            local x, y = math.floor(min.X), math.floor(min.Y)
            local w, h = math.floor((max - min).X), math.floor((max - min).Y)
            local is_corner = esplib.box.type == "corner"

            if esplib.box.enabled and onscreen then
                local holder = box.holder
                holder.Position = UDim2.fromOffset(x, y)
                holder.Size     = UDim2.fromOffset(w, h)
                holder.Visible  = true

                local out_t = fade_trans(esplib.box.outline_transparency)

                if not is_corner then
                    -- normal: 3 concentric UIStrokes — outer black | mid color | inner black
                    box.stroke_outer.Transparency = out_t
                    box.stroke_outer.Enabled      = true
                    box.stroke_mid.Color          = esplib.box.outline
                    box.stroke_mid.Transparency   = out_t
                    box.stroke_mid.Enabled        = true
                    box.stroke_inner.Transparency = out_t
                    box.stroke_inner.Enabled      = true
                    for _, c in ipairs(box.corner_pieces) do
                        c.h.outer.Visible = false
                        c.v.outer.Visible = false
                    end
                else
                    -- corner: hide strokes, show L-shaped pieces
                    box.stroke_outer.Enabled = false
                    box.stroke_mid.Enabled   = false
                    box.stroke_inner.Enabled = false
                    for _, c in ipairs(box.corner_pieces) do
                        -- outer black
                        c.h.outer.BackgroundTransparency = out_t
                        c.v.outer.BackgroundTransparency = out_t
                        -- mid configurable color
                        c.h.mid.BackgroundColor3     = esplib.box.outline
                        c.h.mid.BackgroundTransparency = out_t
                        c.v.mid.BackgroundColor3     = esplib.box.outline
                        c.v.mid.BackgroundTransparency = out_t
                        -- inner black
                        c.h.inner.BackgroundTransparency = out_t
                        c.v.inner.BackgroundTransparency = out_t
                        c.h.outer.Visible = true
                        c.v.outer.Visible = true
                    end
                end
            else
                box.holder.Visible = false
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
                    outline.BackgroundTransparency = fade_trans(esplib.healthbar.outline_transparency)
                    outline.Position             = UDim2.fromOffset(bx, by)
                    outline.Size                 = UDim2.fromOffset(1 + 2*pad, height + 2*pad)
                    outline.Visible              = true
                    fill.BackgroundColor3        = esplib.healthbar.fill
                    fill.BackgroundTransparency  = fade_trans(esplib.healthbar.fill_transparency)
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
                
                -- // DEBUG TAG
                if is_dead then
                    name_s = name_s .. string.format(" [D:%.2f]", current_fade)
                end

                t.Text                = name_s
                t.TextSize            = esplib.name.size
                t.TextColor3          = esplib.name.fill
                t.TextTransparency    = fade_trans(esplib.name.transparency)
                t.TextStrokeTransparency = fade_trans(esplib.name.transparency)
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
                t.TextTransparency    = fade_trans(esplib.distance.transparency)
                t.TextStrokeTransparency = fade_trans(esplib.distance.transparency)
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
                set_line(outline, from_pos, to_pos, esplib.tracer.outline, 3, fade_trans(esplib.tracer.outline_transparency))
                outline.Visible = true
                set_line(fill, from_pos, to_pos, esplib.tracer.fill, 1, fade_trans(esplib.tracer.fill_transparency))
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
                                set_line(line.outline, from, to, esplib.skeleton.outline, 3, fade_trans(esplib.skeleton.outline_transparency))
                                line.outline.Visible = true
                                set_line(line.fill,    from, to, esplib.skeleton.fill,    1, fade_trans(esplib.skeleton.fill_transparency))
                                line.fill.Visible = true
                                continue
                            end
                        end
                        line.outline.Visible = false
                        line.fill.Visible    = false
                    end
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
                    hl.FillTransparency    = fade_trans(cfg.fill_transparency)
                    hl.OutlineColor        = cfg.outline
                    hl.OutlineTransparency = fade_trans(cfg.outline_transparency)

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
                        hl.FillColor = cfg.fill; hl.FillTransparency = fade_trans(cfg.fill_transparency)
                        hl.OutlineColor = cfg.outline; hl.OutlineTransparency = fade_trans(cfg.outline_transparency)
                    end

                elseif cfg.depth_mode == "Both" then
                    local params  = hl_params_cache[instance]
                    local visible = params and is_visible(instance, params) or false
                    if not visible then
                        hl.FillColor = cfg.occ_fill; hl.FillTransparency = fade_trans(cfg.occ_fill_transparency)
                        hl.OutlineColor = cfg.occ_outline; hl.OutlineTransparency = fade_trans(cfg.occ_outline_transparency)
                    else
                        hl.FillColor = cfg.fill; hl.FillTransparency = fade_trans(cfg.fill_transparency)
                        hl.OutlineColor = cfg.outline; hl.OutlineTransparency = fade_trans(cfg.outline_transparency)
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
