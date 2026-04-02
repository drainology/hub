-- // table
local esplib = getgenv().esplib
if not esplib then
    esplib = {
        box = {
            enabled = false,
            padding = 1.15,
            outline = Color3.new(1,1,1),
            outline_transparency = 0,
        },
        healthbar = {
            enabled = false,
            color_mode = "static", -- "static" or "gradient_color"
            fill = Color3.new(0,1,0),
            fill_transparency = 0,
            gradient_color_start = Color3.new(1,0,0), -- visual gradient top
            gradient_color_end   = Color3.new(0,1,0), -- visual gradient bottom
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
        team_check = false, -- hide teammates when true
    }
    getgenv().esplib = esplib
end

local espinstances = {}

-- // perf: cache frequently used math/constructors
local v2new     = Vector2.new
local v3new     = Vector3.new
local c3new     = Color3.new
local udim2off  = UDim2.fromOffset
local mathfloor = math.floor
local mathclamp = math.clamp
local mathceil  = math.ceil
local mathdeg   = math.deg
local mathatan2 = math.atan2
local BLACK     = c3new(0, 0, 0)
local tick      = tick
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
    frame.BackgroundColor3       = color
    frame.BackgroundTransparency = transparency or 0
    if length < 0.5 then
        frame.Size = udim2off(0, thickness)
        return
    end
    local len_adj = (thickness > 1) and (mathceil(length) + thickness - 1) or mathceil(length)
    frame.Size     = udim2off(len_adj, thickness)
    frame.Position = udim2off((from.X + to.X) * 0.5, (from.Y + to.Y) * 0.5)
    frame.Rotation = mathdeg(mathatan2(diff.Y, diff.X))
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
-- Pre-baked sign table: avoids creating 8 Vector3s per part per frame
local BBOX_SIGNS = {
    { 1,  1,  1}, {-1,  1,  1}, { 1, -1,  1}, {-1, -1,  1},
    { 1,  1, -1}, {-1,  1, -1}, { 1, -1, -1}, {-1, -1, -1},
}

local function process_part_bbox(p, padding, cam, minX, minY, maxX, maxY)
    local size = p.Size * 0.5 * padding
    local sx, sy, sz = size.X, size.Y, size.Z
    local cf = p.CFrame
    local onscreen = false
    for i = 1, 8 do
        local s = BBOX_SIGNS[i]
        local pos, vis = cam:WorldToViewportPoint(cf:PointToWorldSpace(v3new(sx*s[1], sy*s[2], sz*s[3])))
        if vis then
            local px, py = pos.X, pos.Y
            if px < minX then minX = px end
            if py < minY then minY = py end
            if px > maxX then maxX = px end
            if py > maxY then maxY = py end
            onscreen = true
        end
    end
    return minX, minY, maxX, maxY, onscreen
end

local function get_bounding_box(instance)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local onscreen = false
    local padding = esplib.box.padding
    local cam = camera

    if instance:IsA("Model") then
        for _, p in ipairs(instance:GetChildren()) do
            if p:IsA("BasePart") then
                local on
                minX, minY, maxX, maxY, on = process_part_bbox(p, padding, cam, minX, minY, maxX, maxY)
                onscreen = onscreen or on
            elseif p:IsA("Accessory") then
                local h = p:FindFirstChild("Handle")
                if h and h:IsA("BasePart") then
                    local on
                    minX, minY, maxX, maxY, on = process_part_bbox(h, padding, cam, minX, minY, maxX, maxY)
                    onscreen = onscreen or on
                end
            end
        end
    elseif instance:IsA("BasePart") then
        local on
        minX, minY, maxX, maxY, on = process_part_bbox(instance, 1, cam, minX, minY, maxX, maxY)
        onscreen = on
    end
    return v2new(minX, minY), v2new(maxX, maxY), onscreen
end

-- // add functions

function espfunctions.add_box(instance)
    if not instance or espinstances[instance] and espinstances[instance].box then return end

    local holder = Instance.new("Frame")
    holder.Name                   = "_Box"
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel        = 0
    holder.Visible                = false
    holder.ZIndex                 = 1
    holder.Parent                 = screen_gui

    -- outer black UIStroke (border of holder)
    local outer_stroke = Instance.new("UIStroke")
    outer_stroke.Thickness    = 1
    outer_stroke.Color        = Color3.new(0, 0, 0)
    outer_stroke.Transparency = 0
    outer_stroke.LineJoinMode = Enum.LineJoinMode.Miter
    outer_stroke.Parent       = holder

    -- inner colored UIStroke (inset 1px from holder)
    local inner_frame = Instance.new("Frame")
    inner_frame.BackgroundTransparency = 1
    inner_frame.BorderSizePixel        = 0
    inner_frame.Position               = UDim2.new(0, 1, 0, 1)
    inner_frame.Size                   = UDim2.new(1, -2, 1, -2)
    inner_frame.ZIndex                 = 2
    inner_frame.Parent                 = holder

    local inner_stroke = Instance.new("UIStroke")
    inner_stroke.Thickness    = 1
    inner_stroke.Color        = Color3.new(1, 1, 1)
    inner_stroke.Transparency = 0
    inner_stroke.LineJoinMode = Enum.LineJoinMode.Miter
    inner_stroke.Parent       = inner_frame

    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].box = {
        holder        = holder,
        outer_stroke  = outer_stroke,
        inner_frame   = inner_frame,
        inner_stroke  = inner_stroke,
    }
end

function espfunctions.add_healthbar(instance)
    if not instance or espinstances[instance] and espinstances[instance].healthbar then return end
    local outline = make_frame(1); outline.BackgroundTransparency = 0
    local fill    = make_frame(2); fill.BackgroundTransparency    = 0
    -- UIGradient for "gradient_color" mode (bottom-to-top on vertical bar)
    local ui_gradient = Instance.new("UIGradient")
    ui_gradient.Rotation = 90  -- top to bottom
    ui_gradient.Enabled  = false
    ui_gradient.Parent   = fill
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].healthbar = { outline = outline, fill = fill, ui_gradient = ui_gradient }
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
        outline = make_line(1, 1),
        fill    = make_line(0.5, 2),
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

-- R6
local R6_BONES = {
    -- neck: head center -> torso center
    { {"Head",  {0, 0, 0}}, {"Torso", {0, 0, 0}} },
    -- spine: torso center -> torso bottom
    { {"Torso", {0, 0, 0}}, {"Torso", {0,-1, 0}} },
    -- left arm: torso center -> wrist
    { {"Torso",    {0, 0, 0}}, {"Left Arm",  {0, -1, 0}} },
    -- right arm: torso center -> wrist
    { {"Torso",    {0, 0, 0}}, {"Right Arm", {0, -1, 0}} },
    -- left hip (torso bottom -> leg center) + shin (center -> ankle)
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
            outline = make_line(1, 1),
            fill    = make_line(0.5, 2),
        })
    end
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].skeleton = skel
end

-- // highlight 
local hl_params_cache = {}
local hl_vis_cache    = {}  -- cached visibility result per instance
local hl_vis_tick     = {}  -- last tick we computed visibility
local HL_VIS_INTERVAL = 0.2 -- seconds between raycast checks (5 Hz)

-- Fast visibility: check only key parts (PrimaryPart, HumanoidRootPart, Head)
-- Center ray first for early exit, corner rays only as fallback
local function is_visible(instance, params)
    local origin = camera.CFrame.Position

    -- Check key parts only (avoids iterating all children)
    local parts_to_check = {}
    local pp = instance.PrimaryPart
    if pp then parts_to_check[1] = pp end
    local hrp = instance:FindFirstChild("HumanoidRootPart")
    if hrp and hrp ~= pp then parts_to_check[#parts_to_check + 1] = hrp end
    local head = instance:FindFirstChild("Head")
    if head and head ~= pp then parts_to_check[#parts_to_check + 1] = head end

    -- If no key parts found, fall back to first BasePart child
    if #parts_to_check == 0 then
        for _, p in ipairs(instance:GetChildren()) do
            if p:IsA("BasePart") then
                parts_to_check[1] = p
                break
            end
        end
    end

    for _, part in ipairs(parts_to_check) do
        -- Center ray (cheapest, most likely to succeed)
        if not workspace:Raycast(origin, part.Position - origin, params) then return true end
    end

    -- Corner rays only on primary part as last resort
    if pp then
        local cf, half = pp.CFrame, pp.Size * 0.5
        local hx, hy, hz = half.X, half.Y, half.Z
        for i = 1, 8 do
            local s = BBOX_SIGNS[i]
            local corner = cf:PointToWorldSpace(v3new(hx*s[1], hy*s[2], hz*s[3]))
            if not workspace:Raycast(origin, corner - origin, params) then return true end
        end
    end

    return false
end

-- Throttled wrapper: only recomputes every HL_VIS_INTERVAL seconds
local function is_visible_cached(instance, params)
    local now = tick()
    local last = hl_vis_tick[instance]
    if last and (now - last) < HL_VIS_INTERVAL then
        return hl_vis_cache[instance] or false
    end
    local result = is_visible(instance, params)
    hl_vis_cache[instance] = result
    hl_vis_tick[instance]  = now
    return result
end

function espfunctions.add_highlight(instance)
    if not instance or espinstances[instance] and espinstances[instance].highlight then return end
    local hl = Instance.new("Highlight")
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee   = instance
    hl.Enabled   = false
    hl.Parent    = instance
    local params = RaycastParams.new()
    local lp_char = local_player.Character
    params.FilterDescendantsInstances = lp_char and { instance, lp_char } or { instance }
    params.FilterType = Enum.RaycastFilterType.Exclude
    hl_params_cache[instance] = params
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].highlight = {
        instance = hl,
        -- dirty-check cache: avoid redundant property sets
        _fc = nil, _ft = nil, _oc = nil, _ot = nil, _en = nil,
    }
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
        data.highlight.instance.Enabled = false
        data.highlight._en = false
    end
end

-- // inline fade helper (avoids closure allocation per instance)
local function fade_trans(base, current_fade)
    return 1 - (1 - base) * (1 - current_fade)
end

-- // highlight property setter with dirty-checking
local function hl_set(hld, fc, ft, oc, ot, enabled)
    local hl = hld.instance
    if hld._en ~= enabled then hl.Enabled = enabled; hld._en = enabled end
    if not enabled then return end
    if hld._fc ~= fc then hl.FillColor = fc;           hld._fc = fc end
    if hld._ft ~= ft then hl.FillTransparency = ft;    hld._ft = ft end
    if hld._oc ~= oc then hl.OutlineColor = oc;        hld._oc = oc end
    if hld._ot ~= ot then hl.OutlineTransparency = ot; hld._ot = ot end
end

local FADE_DURATION = 0.5 -- seconds (moved outside loop)
local _last_lp_char = nil  -- track character changes for highlight filter

-- // main thread
local _render_connection = run_service.RenderStepped:Connect(function(dt)
    local cam_cf  = camera.CFrame
    local cam_pos = cam_cf.Position
    local vp_size = camera.ViewportSize
    local lp_char = local_player.Character

    -- Only update raycast filters when the character reference actually changes
    if lp_char ~= _last_lp_char then
        _last_lp_char = lp_char
        if lp_char then
            for inst, params in pairs(hl_params_cache) do
                params.FilterDescendantsInstances = { inst, lp_char }
            end
        end
    end

    for instance, data in pairs(espinstances) do

        -- cleanup 
        if not instance or not instance.Parent then
            if data.box then
                data.box.holder:Destroy()
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
                data.highlight.instance:Destroy()
                hl_params_cache[instance] = nil
                hl_vis_cache[instance]    = nil
                hl_vis_tick[instance]     = nil
            end
            espinstances[instance] = nil
            continue
        end

        -- Cache humanoid lookup once per frame per instance
        local hum = instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") or nil

        local is_dead = false
        if instance:IsA("Model") then
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

        -- team check: skip teammates
        if esplib.team_check and not is_dead then
            local pl = players:GetPlayerFromCharacter(instance)
            if pl and pl ~= local_player and pl.Team and pl.Team == local_player.Team then
                hide_instance(data)
                continue
            end
        end

        if is_dead then
            data.death_time = data.death_time or tick()
            local elapsed_time = tick() - data.death_time
            data.fade_alpha = mathclamp(elapsed_time / FADE_DURATION, 0, 1)
        else
            data.death_time = nil
            data.fade_alpha = 0
        end

        local alpha = data.fade_alpha
        local current_fade = alpha * alpha * (3 - 2 * alpha) -- smooth easing

        if current_fade >= 0.99 and is_dead then
            hide_instance(data)
            continue
        end

        local min, max, onscreen = get_bounding_box(instance)

        -- box
        if data.box then
            local box = data.box
            if esplib.box.enabled and onscreen then
                local x, y = mathfloor(min.X), mathfloor(min.Y)
                local w, h = mathfloor((max.X - min.X)), mathfloor((max.Y - min.Y))
                local holder = box.holder
                holder.Position = udim2off(x, y)
                holder.Size     = udim2off(w, h)
                holder.Visible  = true

                local out_t = fade_trans(esplib.box.outline_transparency, current_fade)

                box.outer_stroke.Transparency = out_t
                box.outer_stroke.Enabled      = true
                box.inner_stroke.Color        = esplib.box.outline
                box.inner_stroke.Transparency = out_t
                box.inner_stroke.Enabled      = true
            else
                box.holder.Visible = false
            end
        end

        -- healthbar
        if data.healthbar then
            local outline, fill = data.healthbar.outline, data.healthbar.fill
            local ui_grad = data.healthbar.ui_gradient
            if not esplib.healthbar.enabled or not onscreen then
                outline.Visible = false; fill.Visible = false
            else
                if hum then
                    local height    = max.Y - min.Y
                    local pad       = 1
                    local bx        = min.X - 5
                    local by        = min.Y - pad
                    local health    = mathclamp(hum.Health / hum.MaxHealth, 0, 1)
                    local fillh     = height * health
                    local mode = esplib.healthbar.color_mode
                    local fill_color
                    if mode == "gradient_color" then
                        fill_color = Color3.new(1,1,1) -- base white so gradient colors show true
                        ui_grad.Color = ColorSequence.new(esplib.healthbar.gradient_color_start, esplib.healthbar.gradient_color_end)
                        ui_grad.Enabled = true
                    else
                        fill_color = esplib.healthbar.fill
                        ui_grad.Enabled = false
                    end
                    outline.BackgroundColor3       = BLACK
                    outline.BackgroundTransparency = fade_trans(0, current_fade)
                    outline.Position               = udim2off(bx, by)
                    outline.Size                   = udim2off(1 + 2*pad, height + 2*pad)
                    outline.Visible                = true
                    fill.BackgroundColor3           = fill_color
                    fill.BackgroundTransparency     = fade_trans(esplib.healthbar.fill_transparency, current_fade)
                    fill.Position                   = udim2off(bx + pad, by + (height + pad) - fillh)
                    fill.Size                       = udim2off(1, fillh)
                    fill.Visible                    = true
                else
                    outline.Visible = false; fill.Visible = false
                end
            end
        end

        -- name
        if data.name then
            if esplib.name.enabled and onscreen then
                local t      = data.name
                local cx     = (min.X + max.X) * 0.5
                local name_s = instance.Name
                if hum then
                    local pl = players:GetPlayerFromCharacter(instance)
                    if pl then name_s = pl.Name end
                end
                
                -- // DEBUG TAG
                if is_dead then
                    name_s = name_s .. string.format(" [D:%.2f]", current_fade)
                end

                local sz = esplib.name.size
                local ft = fade_trans(esplib.name.transparency, current_fade)
                t.Text                   = name_s
                t.TextSize               = sz
                t.TextColor3             = esplib.name.fill
                t.TextTransparency       = ft
                t.TextStrokeTransparency = ft
                t.Size                   = udim2off(0, sz + 4)
                t.Position               = udim2off(cx, min.Y - sz - 4)
                t.Visible                = true
            else
                data.name.Visible = false
            end
        end

        -- distance
        if data.distance then
            if esplib.distance.enabled and onscreen then
                local t    = data.distance
                local cx   = (min.X + max.X) * 0.5
                local dist
                if instance:IsA("Model") then
                    local pp = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
                    dist = pp and (cam_pos - pp.Position).Magnitude or 999
                else
                    dist = (cam_pos - instance.Position).Magnitude
                end
                local sz = esplib.distance.size
                local ft = fade_trans(esplib.distance.transparency, current_fade)
                t.Text                   = tostring(mathfloor(dist)) .. "m"
                t.TextSize               = sz
                t.TextColor3             = esplib.distance.fill
                t.TextTransparency       = ft
                t.TextStrokeTransparency = ft
                t.Size                   = udim2off(0, sz + 4)
                t.Position               = udim2off(cx, max.Y + 5)
                t.Visible                = true
            else
                data.distance.Visible = false
            end
        end

        -- tracer
        if data.tracer then
            if esplib.tracer.enabled and onscreen then
                local outline, fill = data.tracer.outline, data.tracer.fill
                local from_pos
                local to_pos = (min + max) * 0.5

                local tracer_from = esplib.tracer.from
                if tracer_from == "mouse" then
                    local ml = user_input_service:GetMouseLocation()
                    from_pos = v2new(ml.X, ml.Y)
                elseif tracer_from == "head" then
                    local head = instance:FindFirstChild("Head")
                    if head then
                        local p, v = camera:WorldToViewportPoint(head.Position)
                        from_pos = v and v2new(p.X, p.Y) or v2new(vp_size.X * 0.5, vp_size.Y)
                    else
                        from_pos = v2new(vp_size.X * 0.5, vp_size.Y)
                    end
                elseif tracer_from == "center" then
                    from_pos = v2new(vp_size.X * 0.5, vp_size.Y * 0.5)
                else -- bottom
                    from_pos = v2new(vp_size.X * 0.5, vp_size.Y)
                end

                set_line(outline, from_pos, to_pos, esplib.tracer.outline, 3, fade_trans(esplib.tracer.outline_transparency, current_fade))
                outline.Visible = true
                set_line(fill, from_pos, to_pos, esplib.tracer.fill, 1, fade_trans(esplib.tracer.fill_transparency, current_fade))
                fill.Visible = true
            else
                data.tracer.outline.Visible = false
                data.tracer.fill.Visible    = false
            end
        end

        -- skeleton
        if data.skeleton then
            if esplib.skeleton.enabled then
                -- Cache rig type per instance to avoid FindFirstChild every frame
                local rig = data._rig
                if not rig then
                    if instance:FindFirstChild("UpperTorso") then
                        rig = "r15"
                    elseif instance:FindFirstChild("Torso") then
                        rig = "r6"
                    end
                    data._rig = rig
                end

                local bones = rig == "r15" and R15_BONES or (rig == "r6" and R6_BONES or nil)

                if bones then
                    for i, bone in ipairs(bones) do
                        local line  = data.skeleton.lines[i]
                        local wposA = get_bone_pos(instance, bone[1])
                        local wposB = get_bone_pos(instance, bone[2])
                        if wposA and wposB then
                            local sA, vA = camera:WorldToViewportPoint(wposA)
                            local sB, vB = camera:WorldToViewportPoint(wposB)
                            if vA and vB then
                                local from = v2new(sA.X, sA.Y)
                                local to   = v2new(sB.X, sB.Y)
                                set_line(line.outline, from, to, esplib.skeleton.outline, 3, fade_trans(esplib.skeleton.outline_transparency, current_fade))
                                line.outline.Visible = true
                                set_line(line.fill,    from, to, esplib.skeleton.fill,    1, fade_trans(esplib.skeleton.fill_transparency, current_fade))
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

        -- highlight (with caching + dirty-checking)
        if data.highlight then
            local hld = data.highlight
            local cfg = esplib.highlight
            if not cfg.enabled then
                hl_set(hld, nil, nil, nil, nil, false)
            else
                if cfg.depth_mode == "Always" then
                    hl_set(hld,
                        cfg.fill,    fade_trans(cfg.fill_transparency, current_fade),
                        cfg.outline, fade_trans(cfg.outline_transparency, current_fade),
                        true)

                elseif cfg.depth_mode == "Occluded" then
                    local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
                    local occluded = false
                    if primary then
                        local params = hl_params_cache[instance]
                        if params then
                            local r = workspace:Raycast(cam_pos, primary.Position - cam_pos, params)
                            occluded = r ~= nil
                        end
                    end
                    if occluded then
                        hl_set(hld, cfg.fill, 1, cfg.outline, 1, true)
                    else
                        hl_set(hld,
                            cfg.fill,    fade_trans(cfg.fill_transparency, current_fade),
                            cfg.outline, fade_trans(cfg.outline_transparency, current_fade),
                            true)
                    end

                elseif cfg.depth_mode == "Both" then
                    local params  = hl_params_cache[instance]
                    local visible = params and is_visible_cached(instance, params) or false
                    if not visible then
                        hl_set(hld,
                            cfg.occ_fill,    fade_trans(cfg.occ_fill_transparency, current_fade),
                            cfg.occ_outline, fade_trans(cfg.occ_outline_transparency, current_fade),
                            true)
                    else
                        hl_set(hld,
                            cfg.fill,    fade_trans(cfg.fill_transparency, current_fade),
                            cfg.outline, fade_trans(cfg.outline_transparency, current_fade),
                            true)
                    end
                end
            end
        end
    end
end)

-- // unload
function espfunctions.unload()
    -- disconnect render loop
    if _render_connection then
        _render_connection:Disconnect()
        _render_connection = nil
    end
    -- destroy all ESP drawing objects
    for instance, data in pairs(espinstances) do
        if data.box     then data.box.holder:Destroy() end
        if data.healthbar then
            data.healthbar.outline:Destroy()
            data.healthbar.fill:Destroy()
        end
        if data.name     then data.name:Destroy() end
        if data.distance then data.distance:Destroy() end
        if data.tracer   then
            data.tracer.outline:Destroy()
            data.tracer.fill:Destroy()
        end
        if data.skeleton then
            for _, ln in ipairs(data.skeleton.lines) do
                ln.outline:Destroy()
                ln.fill:Destroy()
            end
        end
        if data.highlight then
            data.highlight.instance:Destroy()
        end
        espinstances[instance] = nil
    end
    -- destroy the entire screen gui
    if screen_gui and screen_gui.Parent then
        screen_gui:Destroy()
    end
    -- wipe global so re-requiring gets a fresh copy
    getgenv().esplib = nil
end

-- // return
for k, v in pairs(espfunctions) do
    esplib[k] = v
end

return esplib
