-- // esplib.lua  (rewrite – holder pattern + UIStroke + Drawing skeleton)
-- Public config table (shared across requires via getgenv)
local esplib = getgenv().esplib
if not esplib then
    esplib = {
        box = {
            enabled             = false,
            type                = "normal",   -- "normal" | "corner"
            fill                = Color3.new(1, 1, 1),
            fill_transparency   = 1,          -- 1 = invisible fill (outline-only box)
            outline             = Color3.new(0, 0, 0),
            outline_transparency = 0,
        },
        healthbar = {
            enabled              = false,
            fill                 = Color3.new(0, 1, 0),
            fill_transparency    = 0,
            outline              = Color3.new(0, 0, 0),
            outline_transparency = 0,
        },
        name = {
            enabled     = false,
            fill        = Color3.new(1, 1, 1),
            transparency = 0,
            size        = 13,
        },
        distance = {
            enabled     = false,
            fill        = Color3.new(1, 1, 1),
            transparency = 0,
            size        = 13,
        },
        tracer = {
            enabled              = false,
            fill                 = Color3.new(1, 1, 1),
            fill_transparency    = 0,
            outline              = Color3.new(0, 0, 0),
            outline_transparency = 0,
            from                 = "bottom",  -- "bottom" | "center" | "mouse" | "head"
        },
        skeleton = {
            enabled              = false,
            fill                 = Color3.new(1, 1, 1),
            fill_transparency    = 0,
            outline              = Color3.new(0, 0, 0),
            outline_transparency = 0,
        },
        highlight = {
            enabled                  = false,
            depth_mode               = "Always", -- "Always" | "Occluded" | "Both"
            fill                     = Color3.new(1, 0, 0),
            fill_transparency        = 0.5,
            outline                  = Color3.new(1, 1, 1),
            outline_transparency     = 0,
            occ_fill                 = Color3.new(1, 0.5, 0),
            occ_fill_transparency    = 0.5,
            occ_outline              = Color3.new(1, 0.5, 0),
            occ_outline_transparency = 0,
        },
    }
    getgenv().esplib = esplib
end

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

-- off-screen bin (parent here to hide elements without destroying them)
local cache_gui = local_player:WaitForChild("PlayerGui"):FindFirstChild("_ESPCache")
if not cache_gui then
    cache_gui = Instance.new("ScreenGui")
    cache_gui.Name         = "_ESPCache"
    cache_gui.Enabled      = false
    cache_gui.ResetOnSpawn = false
    cache_gui.Parent       = local_player:WaitForChild("PlayerGui")
end

-- // ──────────────────────────────────────────────────────────────
-- // Frame-line helpers (rotated frames, same as original esplib)
-- // ──────────────────────────────────────────────────────────────
local function make_line(thickness, z)
    local f = Instance.new("Frame")
    f.BorderSizePixel  = 0
    f.AnchorPoint      = Vector2.new(0.5, 0.5)
    f.BackgroundColor3 = Color3.new(1, 1, 1)
    f.Size             = UDim2.fromOffset(0, thickness)
    f.Visible          = false
    f.ZIndex           = z or 1
    f.Parent           = screen_gui
    return f
end

local function set_line(frame, from, to, color, thickness, transparency)
    local diff   = to - from
    local length = diff.Magnitude
    frame.BackgroundColor3       = color
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

-- // espinstances: instance → { holder, ... }
local espinstances = {}
local espfunctions = {}

-- // ──────────────────────────────────────────────────────────────
-- // Helper: create an Instance with a property table
-- // ──────────────────────────────────────────────────────────────
local function new(class, props)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        obj[k] = v
    end
    return obj
end

-- // ──────────────────────────────────────────────────────────────
-- // box_solve – returns BoxSize (V2), BoxPosition (V2), on_screen (bool), distance (num)
-- // Uses torso as anchor: cheap, stable, same approach as reference
-- // ──────────────────────────────────────────────────────────────
local function box_solve(torso)
    if not torso then return nil, nil, false, 0 end

    local vp       = camera.ViewportSize
    local lpos     = camera.CFrame:PointToObjectSpace(torso.Position)
    local half_h   = -lpos.Z * math.tan(math.rad(camera.FieldOfView / 2))

    if half_h <= 0 then return nil, nil, false, 0 end

    local up_w   = torso.Position + (torso.CFrame.UpVector * 1.8) + camera.CFrame.UpVector
    local down_w = torso.Position - (torso.CFrame.UpVector * 2.5) - camera.CFrame.UpVector

    local function to_screen(wp)
        local lp = camera.CFrame:PointToObjectSpace(wp)
        local ar = vp.X / vp.Y
        local hh = -lp.Z * math.tan(math.rad(camera.FieldOfView / 2))
        local hw = ar * hh
        local far_corner = Vector3.new(-hw, hh, lp.Z)
        local rel = lp - far_corner
        local sx  = rel.X / (hw * 2)
        local sy  = -rel.Y / (hh * 2)
        local on  = -lp.Z > 0 and sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1
        return Vector2.new(sx * vp.X, sy * vp.Y), on
    end

    local top_s,    top_on    = to_screen(up_w)
    local bottom_s, bottom_on = to_screen(down_w)

    local on_screen = top_on or bottom_on
    if not (top_on or bottom_on) then
        -- still try to compute: might be partially clipped
    end

    local w = math.max(math.floor(math.abs(top_s.X - bottom_s.X)), 3)
    local h = math.max(math.floor(math.max(math.abs(bottom_s.Y - top_s.Y), w / 2)), 3)
    local box_w = math.floor(math.max(h / 1.5, w))
    local box_h = h
    local box_size = Vector2.new(box_w, box_h)
    local box_pos  = Vector2.new(
        math.floor((top_s.X + bottom_s.X) / 2 - box_w / 2),
        math.floor(math.min(top_s.Y, bottom_s.Y))
    )
    local dist = (torso.Position - camera.CFrame.Position).Magnitude
    return box_size, box_pos, on_screen, dist
end

-- // ──────────────────────────────────────────────────────────────
-- // get_torso – best-effort torso from a character Model
-- // ──────────────────────────────────────────────────────────────
local function get_torso(instance)
    if not instance:IsA("Model") then return nil end
    return instance:FindFirstChild("HumanoidRootPart")
        or instance:FindFirstChild("UpperTorso")
        or instance:FindFirstChild("Torso")
        or instance.PrimaryPart
        or instance:FindFirstChildWhichIsA("BasePart")
end

-- // ──────────────────────────────────────────────────────────────
-- // death fade helpers
-- // ──────────────────────────────────────────────────────────────
local FADE_DURATION = 0.5

local function compute_fade(data, is_dead)
    if is_dead then
        data.death_time = data.death_time or tick()
        local t = math.clamp((tick() - data.death_time) / FADE_DURATION, 0, 1)
        data.fade_alpha = t * t * (3 - 2 * t)
    else
        data.death_time  = nil
        data.fade_alpha  = 0
    end
    return data.fade_alpha or 0
end

local function fade_t(base, alpha)
    -- blends base transparency toward 1 by alpha
    return 1 - (1 - base) * (1 - alpha)
end

-- // ──────────────────────────────────────────────────────────────
-- // show_holder / hide_holder
-- // ──────────────────────────────────────────────────────────────
local function show_in(obj, parent)
    if obj.Parent ~= parent then obj.Parent = parent end
end

local function hide_to_cache(obj)
    if obj.Parent ~= cache_gui then obj.Parent = cache_gui end
end

-- // ──────────────────────────────────────────────────────────────
-- // Skeleton bone tables (Drawing API lines, R15 only for now)
-- // ──────────────────────────────────────────────────────────────
local R15_BONES = {
    {"Head",         "UpperTorso"},
    {"UpperTorso",   "LowerTorso"},
    {"UpperTorso",   "LeftUpperArm"},
    {"UpperTorso",   "RightUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"RightUpperArm","RightLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"RightLowerArm","RightHand"},
    {"LowerTorso",   "LeftUpperLeg"},
    {"LowerTorso",   "RightUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"RightUpperLeg","RightLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"RightLowerLeg","RightFoot"},
}

local R6_BONES = {
    {"Head",      "Torso"},
    {"Torso",     "Left Arm"},
    {"Torso",     "Right Arm"},
    {"Torso",     "Left Leg"},
    {"Torso",     "Right Leg"},
}

local function get_2d(part)
    if not part then return nil, false end
    local p, on = camera:WorldToViewportPoint(part.Position)
    return Vector2.new(p.X, p.Y), on
end

local function get_bone_pos(instance, part_name)
    local part = instance:FindFirstChild(part_name)
    return part and part.Position or nil
end

-- // ──────────────────────────────────────────────────────────────
-- // add_box  (holder + UIStroke normal, corner frames)
-- // ──────────────────────────────────────────────────────────────
function espfunctions.add_box(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    if espinstances[instance].holder then return end  -- already set up

    local data = espinstances[instance]

    -- HOLDER – the single positioned/sized frame everything hangs off
    local holder = new("Frame", {
        Name                 = "_ESPHolder",
        BackgroundTransparency = 1,
        BorderSizePixel      = 0,
        Size                 = UDim2.fromOffset(0, 0),
        Position             = UDim2.fromOffset(0, 0),
        Parent               = cache_gui,
    })

    -- ── NORMAL BOX ──────────────────────────────────────────────
    -- outer black outline (UIStroke on holder)
    local box_outline = new("UIStroke", {
        Color         = esplib.box.outline,
        Thickness     = 2,
        LineJoinMode  = Enum.LineJoinMode.Miter,
        Parent        = holder,
    })

    -- inner white fill frame (inset 1 px)
    local box_inner = new("Frame", {
        Name                 = "_BoxInner",
        BackgroundTransparency = esplib.box.fill_transparency,
        BackgroundColor3     = esplib.box.fill,
        BorderSizePixel      = 0,
        Position             = UDim2.new(0, 1, 0, 1),
        Size                 = UDim2.new(1, -2, 1, -2),
        Parent               = holder,
    })
    -- inset outline on inner (the colored box stroke)
    local box_color_stroke = new("UIStroke", {
        Color        = esplib.box.fill,
        Thickness    = 1,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Parent       = box_inner,
    })

    -- ── CORNER BOX ──────────────────────────────────────────────
    -- Corner box: 4 corners each built from 2 frames (H + V)
    -- Parent is a corners container (same size as holder)
    local corners_frame = new("Frame", {
        Name                 = "_Corners",
        BackgroundTransparency = 1,
        BorderSizePixel      = 0,
        Size                 = UDim2.new(1, 0, 1, 0),
        Position             = UDim2.new(0, 0, 0, 0),
        Parent               = cache_gui,
    })

    -- helper: create one corner L-shape (hlen, vlen in scale of box)
    local CORNER_SCALE = 0.25  -- corner arm = 25% of box dimension
    local function make_corner(ax, ay, pos_x, pos_y)
        -- black outline bar
        local h_outer = new("Frame", {
            AnchorPoint          = Vector2.new(ax, ay),
            BackgroundColor3     = esplib.box.outline,
            BackgroundTransparency = 0,
            BorderSizePixel      = 0,
            Position             = UDim2.new(pos_x, 0, pos_y, ay == 1 and -2 or 0),
            Size                 = UDim2.new(CORNER_SCALE, 0, 0, 3),
            Parent               = corners_frame,
        })
        local h_inner = new("Frame", {
            BackgroundColor3     = esplib.box.fill,
            BackgroundTransparency = 0,
            BorderSizePixel      = 0,
            Position             = UDim2.new(0, 1, 0, 1),
            Size                 = UDim2.new(1, -2, 1, -2),
            Parent               = h_outer,
        })
        local v_outer = new("Frame", {
            AnchorPoint          = Vector2.new(ax, ay),
            BackgroundColor3     = esplib.box.outline,
            BackgroundTransparency = 0,
            BorderSizePixel      = 0,
            Position             = UDim2.new(pos_x, ax == 1 and -2 or 0, pos_y, ay == 1 and -3 or 1),
            Size                 = UDim2.new(0, 3, CORNER_SCALE, 0),
            Parent               = corners_frame,
        })
        local v_inner = new("Frame", {
            BackgroundColor3     = esplib.box.fill,
            BackgroundTransparency = 0,
            BorderSizePixel      = 0,
            Position             = UDim2.new(0, 1, 0, -2),
            Size                 = UDim2.new(1, -2, 1, 1),
            Parent               = v_outer,
        })
        return {h_outer=h_outer, h_inner=h_inner, v_outer=v_outer, v_inner=v_inner}
    end

    local corner_objects = {
        make_corner(0, 0, 0, 0), -- top-left
        make_corner(1, 0, 1, 0), -- top-right
        make_corner(0, 1, 0, 1), -- bottom-left
        make_corner(1, 1, 1, 1), -- bottom-right
    }

    data.holder        = holder
    data.box_outline   = box_outline
    data.box_inner     = box_inner
    data.box_color_stroke = box_color_stroke
    data.corners_frame = corners_frame
    data.corner_objects = corner_objects
end

-- // ──────────────────────────────────────────────────────────────
-- // add_healthbar
-- // ──────────────────────────────────────────────────────────────
function espfunctions.add_healthbar(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    local data = espinstances[instance]
    if data.healthbar_holder then return end

    local holder = data.holder
    if not holder then return end

    local hb_holder = new("Frame", {
        Name                 = "_HBHolder",
        AnchorPoint          = Vector2.new(1, 0),
        BackgroundColor3     = esplib.healthbar.outline,
        BackgroundTransparency = esplib.healthbar.outline_transparency,
        BorderSizePixel      = 0,
        Position             = UDim2.new(0, -5, 0, -1),
        Size                 = UDim2.new(0, 4, 1, 2),
        Parent               = holder,
    })
    local hb_fill = new("Frame", {
        Name                 = "_HBFill",
        AnchorPoint          = Vector2.new(0, 1),
        BackgroundColor3     = esplib.healthbar.fill,
        BackgroundTransparency = esplib.healthbar.fill_transparency,
        BorderSizePixel      = 0,
        Position             = UDim2.new(0, 1, 1, -1),
        Size                 = UDim2.new(1, -2, 1, -2),
        Parent               = hb_holder,
    })

    data.healthbar_holder = hb_holder
    data.healthbar_fill   = hb_fill
end

-- // ──────────────────────────────────────────────────────────────
-- // add_name
-- // ──────────────────────────────────────────────────────────────
function espfunctions.add_name(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    local data = espinstances[instance]
    if data.name_label then return end
    if not data.holder then return end

    local lbl = new("TextLabel", {
        Name                  = "_Name",
        AnchorPoint           = Vector2.new(0, 1),
        BackgroundTransparency = 1,
        BorderSizePixel       = 0,
        Font                  = Enum.Font.Gotham,
        TextColor3            = esplib.name.fill,
        TextStrokeColor3      = Color3.new(0, 0, 0),
        TextStrokeTransparency = 0,
        TextSize              = esplib.name.size,
        Text                  = "",
        AutomaticSize         = Enum.AutomaticSize.XY,
        Size                  = UDim2.new(1, 0, 0, 0),
        Position              = UDim2.new(0, 0, 0, -5),
        Parent                = data.holder,
    })
    data.name_label = lbl
end

-- // ──────────────────────────────────────────────────────────────
-- // add_distance
-- // ──────────────────────────────────────────────────────────────
function espfunctions.add_distance(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    local data = espinstances[instance]
    if data.distance_label then return end
    if not data.holder then return end

    local lbl = new("TextLabel", {
        Name                  = "_Dist",
        AnchorPoint           = Vector2.new(0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel       = 0,
        Font                  = Enum.Font.Gotham,
        TextColor3            = esplib.distance.fill,
        TextStrokeColor3      = Color3.new(0, 0, 0),
        TextStrokeTransparency = 0,
        TextSize              = esplib.distance.size,
        Text                  = "",
        AutomaticSize         = Enum.AutomaticSize.XY,
        Size                  = UDim2.new(1, 0, 0, 0),
        Position              = UDim2.new(0, 0, 1, 5),
        Parent                = data.holder,
    })
    data.distance_label = lbl
end

-- // ──────────────────────────────────────────────────────────────
-- // add_tracer  (rotated Frame lines)
-- // ──────────────────────────────────────────────────────────────
function espfunctions.add_tracer(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    local data = espinstances[instance]
    if data.tracer then return end
    data.tracer = {
        outline = make_line(3, 1),
        fill    = make_line(1, 2),
    }
end

-- // ──────────────────────────────────────────────────────────────
-- // add_skeleton  (rotated Frame lines)
-- // ──────────────────────────────────────────────────────────────
function espfunctions.add_skeleton(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    local data = espinstances[instance]
    if data.skeleton then return end

    local MAX = math.max(#R15_BONES, #R6_BONES)
    local lines = {}
    for _ = 1, MAX do
        lines[#lines + 1] = {
            outline = make_line(3, 1),
            fill    = make_line(1, 2),
        }
    end
    data.skeleton = { lines = lines }
end

-- // ──────────────────────────────────────────────────────────────
-- // add_highlight
-- // ──────────────────────────────────────────────────────────────
local hl_params_cache = {}

function espfunctions.add_highlight(instance)
    if not instance then return end
    espinstances[instance] = espinstances[instance] or {}
    local data = espinstances[instance]
    if data.highlight then return end

    local hl = Instance.new("Highlight")
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee   = instance
    hl.Enabled   = false
    hl.Parent    = instance

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { instance }
    params.FilterType = Enum.RaycastFilterType.Exclude
    hl_params_cache[instance] = params

    data.highlight = hl
end

-- // ──────────────────────────────────────────────────────────────
-- // remove  (destroy all elements for an instance)
-- // ──────────────────────────────────────────────────────────────
local function destroy_instance_esp(instance, data)
    if data.holder        then data.holder:Destroy()         end
    if data.corners_frame then data.corners_frame:Destroy()  end
    if data.tracer then
        data.tracer.outline:Destroy()
        data.tracer.fill:Destroy()
    end
    if data.skeleton then
        for _, l in ipairs(data.skeleton.lines) do
            l.outline:Destroy()
            l.fill:Destroy()
        end
    end
    if data.highlight then
        data.highlight:Destroy()
        hl_params_cache[instance] = nil
    end
    espinstances[instance] = nil
end

-- // ──────────────────────────────────────────────────────────────
-- // hide all elements without destroying (dead fade state)
-- // ──────────────────────────────────────────────────────────────
local function hide_all(data)
    if data.holder        then hide_to_cache(data.holder)         end
    if data.corners_frame then hide_to_cache(data.corners_frame)  end
    if data.tracer then
        data.tracer.outline.Visible = false
        data.tracer.fill.Visible    = false
    end
    if data.skeleton then
        for _, l in ipairs(data.skeleton.lines) do
            l.outline.Visible = false
            l.fill.Visible    = false
        end
    end
    if data.highlight then data.highlight.Enabled = false end
end

-- // ──────────────────────────────────────────────────────────────
-- // RenderStepped main loop
-- // ──────────────────────────────────────────────────────────────
run_service.RenderStepped:Connect(function()
    for instance, data in pairs(espinstances) do

        -- ── destroyed? clean up ────────────────────────────────
        if not instance or not instance.Parent then
            destroy_instance_esp(instance, data)
            continue
        end

        -- ── death detection ────────────────────────────────────
        local is_dead = false
        if instance:IsA("Model") then
            local hum = instance:FindFirstChildOfClass("Humanoid")
            if hum then
                data.had_humanoid = true
                if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
                    is_dead = true
                end
            elseif data.had_humanoid then
                is_dead = true  -- humanoid was deleted (ragdoll systems)
            end
            if not instance.PrimaryPart then
                is_dead = true
            end
        end

        local fade = compute_fade(data, is_dead)

        if fade >= 0.99 and is_dead then
            hide_all(data)
            continue
        end

        -- ── box solve ──────────────────────────────────────────
        local torso = get_torso(instance)
        local box_size, box_pos, on_screen, distance = box_solve(torso)

        -- ── holder position ────────────────────────────────────
        local holder = data.holder
        if holder then
            if on_screen and box_size then
                show_in(holder, screen_gui)
                holder.Position = UDim2.fromOffset(box_pos.X, box_pos.Y)
                holder.Size     = UDim2.fromOffset(box_size.X, box_size.Y)
                holder.Visible  = true
            else
                holder.Visible = false
            end
        end

        -- ── box drawing ────────────────────────────────────────
        if data.holder and on_screen and box_size then
            local is_corner = esplib.box.type == "corner"
            local box_enabled = esplib.box.enabled

            -- normal box via UIStroke
            if data.box_outline then
                data.box_outline.Parent = (box_enabled and not is_corner) and holder or cache_gui
                data.box_outline.Color  = esplib.box.outline
                data.box_outline.Transparency = fade_t(esplib.box.outline_transparency, fade)
            end
            if data.box_inner then
                data.box_inner.Parent = (box_enabled and not is_corner) and holder or cache_gui
                data.box_inner.BackgroundColor3 = esplib.box.fill
                data.box_inner.BackgroundTransparency = fade_t(esplib.box.fill_transparency, fade)
            end
            if data.box_color_stroke then
                data.box_color_stroke.Color = esplib.box.fill
                data.box_color_stroke.Transparency = fade_t(esplib.box.fill_transparency, fade)
            end

            -- corner box
            if data.corners_frame then
                if box_enabled and is_corner then
                    show_in(data.corners_frame, screen_gui)
                    data.corners_frame.Position = UDim2.fromOffset(box_pos.X, box_pos.Y)
                    data.corners_frame.Size     = UDim2.fromOffset(box_size.X, box_size.Y)
                    data.corners_frame.Visible  = true

                    local out_t  = fade_t(esplib.box.outline_transparency, fade)
                    local fill_t = fade_t(esplib.box.fill_transparency, fade)
                    for _, c in ipairs(data.corner_objects) do
                        c.h_outer.BackgroundColor3 = esplib.box.outline
                        c.h_outer.BackgroundTransparency = out_t
                        c.v_outer.BackgroundColor3 = esplib.box.outline
                        c.v_outer.BackgroundTransparency = out_t
                        c.h_inner.BackgroundColor3 = esplib.box.fill
                        c.h_inner.BackgroundTransparency = fill_t
                        c.v_inner.BackgroundColor3 = esplib.box.fill
                        c.v_inner.BackgroundTransparency = fill_t
                    end
                else
                    data.corners_frame.Visible = false
                end
            end
        elseif data.holder then
            -- off screen: hide corner frame too
            if data.corners_frame then data.corners_frame.Visible = false end
            if data.box_outline   then data.box_outline.Parent   = cache_gui end
            if data.box_inner     then data.box_inner.Parent     = cache_gui end
        end

        -- ── healthbar ──────────────────────────────────────────
        if data.healthbar_holder then
            local hb_on = esplib.healthbar.enabled and on_screen and box_size
            if hb_on then
                local hum = instance:FindFirstChildOfClass("Humanoid")
                if hum and hum.MaxHealth > 0 then
                    local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                    data.healthbar_holder.Parent = holder
                    data.healthbar_holder.BackgroundColor3     = esplib.healthbar.outline
                    data.healthbar_holder.BackgroundTransparency = fade_t(esplib.healthbar.outline_transparency, fade)

                    local fill = data.healthbar_fill
                    fill.Size     = UDim2.new(1, -2, pct, -2)
                    fill.Position = UDim2.new(0, 1, 1 - pct, 1)
                    fill.BackgroundColor3 = Color3.fromHSV(pct * 0.33, 1, 1) -- green→red
                    fill.BackgroundTransparency = fade_t(esplib.healthbar.fill_transparency, fade)
                else
                    data.healthbar_holder.Parent = cache_gui
                end
            else
                data.healthbar_holder.Parent = cache_gui
            end
        end

        -- ── name ───────────────────────────────────────────────
        if data.name_label then
            if esplib.name.enabled and on_screen and box_size then
                local name_s = instance.Name
                if instance:IsA("Model") then
                    local hum = instance:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local pl = players:GetPlayerFromCharacter(instance)
                        if pl then name_s = pl.Name end
                    end
                end
                data.name_label.Parent              = holder
                data.name_label.Text                = name_s
                data.name_label.TextSize            = esplib.name.size
                data.name_label.TextColor3          = esplib.name.fill
                data.name_label.TextTransparency    = fade_t(esplib.name.transparency, fade)
                data.name_label.TextStrokeTransparency = fade_t(esplib.name.transparency + 0.5, fade)
            else
                data.name_label.Parent = cache_gui
            end
        end

        -- ── distance ───────────────────────────────────────────
        if data.distance_label then
            if esplib.distance.enabled and on_screen and box_size then
                data.distance_label.Parent           = holder
                data.distance_label.Text             = math.floor(distance) .. "m"
                data.distance_label.TextSize         = esplib.distance.size
                data.distance_label.TextColor3       = esplib.distance.fill
                data.distance_label.TextTransparency = fade_t(esplib.distance.transparency, fade)
                data.distance_label.TextStrokeTransparency = fade_t(esplib.distance.transparency + 0.5, fade)
            else
                data.distance_label.Parent = cache_gui
            end
        end

        -- ── tracer ─────────────────────────────────────────────
        if data.tracer then
            local ol, fl = data.tracer.outline, data.tracer.fill
            if esplib.tracer.enabled and on_screen and box_size then
                local from_pos
                local vp = camera.ViewportSize
                if esplib.tracer.from == "mouse" then
                    local ml = user_input_service:GetMouseLocation()
                    from_pos = Vector2.new(ml.X, ml.Y)
                elseif esplib.tracer.from == "head" then
                    local head = instance:FindFirstChild("Head")
                    if head then
                        local p, v = camera:WorldToViewportPoint(head.Position)
                        from_pos = v and Vector2.new(p.X, p.Y) or Vector2.new(vp.X/2, vp.Y)
                    else
                        from_pos = Vector2.new(vp.X/2, vp.Y)
                    end
                elseif esplib.tracer.from == "center" then
                    from_pos = Vector2.new(vp.X/2, vp.Y/2)
                else
                    from_pos = Vector2.new(vp.X/2, vp.Y)
                end
                local to_pos = Vector2.new(
                    box_pos.X + box_size.X / 2,
                    box_pos.Y + box_size.Y
                )
                set_line(ol, from_pos, to_pos, esplib.tracer.outline, 3, fade_t(esplib.tracer.outline_transparency, fade))
                ol.Visible = true
                set_line(fl, from_pos, to_pos, esplib.tracer.fill,    1, fade_t(esplib.tracer.fill_transparency, fade))
                fl.Visible = true
            else
                ol.Visible = false
                fl.Visible = false
            end
        end

        -- ── skeleton ───────────────────────────────────────────
        if data.skeleton then
            if esplib.skeleton.enabled then
                local bones
                if instance:FindFirstChild("UpperTorso") then
                    bones = R15_BONES
                elseif instance:FindFirstChild("Torso") then
                    bones = R6_BONES
                end

                local out_t  = fade_t(esplib.skeleton.outline_transparency, fade)
                local fill_t = fade_t(esplib.skeleton.fill_transparency, fade)

                local used = bones and #bones or 0
                if bones then
                    for i, bone in ipairs(bones) do
                        local line  = data.skeleton.lines[i]
                        if not line then continue end
                        local wA = get_bone_pos(instance, bone[1])
                        local wB = get_bone_pos(instance, bone[2])
                        if wA and wB then
                            local sA, vA = camera:WorldToViewportPoint(wA)
                            local sB, vB = camera:WorldToViewportPoint(wB)
                            if vA and vB then
                                local p2A = Vector2.new(sA.X, sA.Y)
                                local p2B = Vector2.new(sB.X, sB.Y)
                                set_line(line.outline, p2A, p2B, esplib.skeleton.outline, 3, out_t)
                                line.outline.Visible = true
                                set_line(line.fill,    p2A, p2B, esplib.skeleton.fill,    1, fill_t)
                                line.fill.Visible = true
                                continue
                            end
                        end
                        line.outline.Visible = false
                        line.fill.Visible    = false
                    end
                end
                for i = used + 1, #data.skeleton.lines do
                    data.skeleton.lines[i].outline.Visible = false
                    data.skeleton.lines[i].fill.Visible    = false
                end
            else
                for _, l in ipairs(data.skeleton.lines) do
                    l.outline.Visible = false
                    l.fill.Visible    = false
                end
            end
        end

        -- ── highlight ──────────────────────────────────────────
        if data.highlight then
            local hl  = data.highlight
            local cfg = esplib.highlight
            if not cfg.enabled then
                hl.Enabled = false
            else
                hl.Enabled = true
                local fill_t    = fade_t(cfg.fill_transparency, fade)
                local outline_t = fade_t(cfg.outline_transparency, fade)
                if cfg.depth_mode == "Always" then
                    hl.FillColor           = cfg.fill
                    hl.FillTransparency    = fill_t
                    hl.OutlineColor        = cfg.outline
                    hl.OutlineTransparency = outline_t
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
                        hl.FillColor = cfg.fill; hl.FillTransparency = fill_t
                        hl.OutlineColor = cfg.outline; hl.OutlineTransparency = outline_t
                    end
                elseif cfg.depth_mode == "Both" then
                    local params  = hl_params_cache[instance]
                    local origin  = camera.CFrame.Position
                    local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
                    local visible = false
                    if primary and params then
                        visible = workspace:Raycast(origin, primary.Position - origin, params) == nil
                    end
                    if not visible then
                        hl.FillColor = cfg.occ_fill; hl.FillTransparency = fade_t(cfg.occ_fill_transparency, fade)
                        hl.OutlineColor = cfg.occ_outline; hl.OutlineTransparency = fade_t(cfg.occ_outline_transparency, fade)
                    else
                        hl.FillColor = cfg.fill; hl.FillTransparency = fill_t
                        hl.OutlineColor = cfg.outline; hl.OutlineTransparency = outline_t
                    end
                end
            end
        end
    end
end)

-- // expose all add_* functions on esplib
for k, v in pairs(espfunctions) do
    esplib[k] = v
end

return esplib
