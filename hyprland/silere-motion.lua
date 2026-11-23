-- Silere's motion for Hyprland: windows, workspaces and focus move at the shell's pace, with fixes for two
-- Hyprland 0.57 animation faults. Opt in with the installer, or load it from hyprland.lua:
--
--     dofile("/path/to/silere-shell/hyprland/silere-motion.lua")
--
-- Anything your config sets after that line wins. It needs Hyprland's Lua config (0.55 and later). Every call is
-- guarded, so a version that lacks one skips that piece instead of failing your config. It changes animation curves
-- and timings, and one dimming value (below), nothing else: no binds, rules, gaps, colours or monitors.

if type(hl) ~= "table" or type(hl.curve) ~= "function" or type(hl.animation) ~= "function" then return end

local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and type(hl.log) == "function" then pcall(hl.log, "silere-motion: " .. tostring(err)) end
    return ok
end

-- Durations in seconds. Hyprland's `speed` is in deciseconds, so 0.40 s is 4.0.
local window = {
    -- popin scale and length; the fade leads the growth, so an open reads as a surface growing, not a dissolve
    open  = { scale = 78, duration = 0.40, fade = 0.20 },
    -- the shrink leads the fade, so a close reads as motion
    close = { scale = 78, duration = 0.22, fade = 0.21 },
}
local workspace_duration = 0.32
-- percent of the screen the special workspace travels
local special_travel = 40
-- a focus change recolours the border at the pace Silere fades its own colours (160 ms)
local focus_duration = 0.16

local bezier = {
    silereQuint  = { 0.23, 1,    0.32, 1    },
    silereQuart  = { 0.25, 1,    0.5,  1    },
    silereQuad   = { 0.25, 0.46, 0.45, 0.94 },
    silereCubic  = { 0.33, 1,    0.68, 1    },
    -- a bounded stand-in for the reflow spring below, so a new tile and its neighbours move as one and it ends
    silereReveal = { 0.32, 0.60, 0.08, 1    },
    -- a workspace slide that keeps moving when a swipe releases into it
    silereGlide  = { 0.18, 0.12, 0.09, 1    },
    -- hold, then go: the two 0.57 fixes below
    silereFullscreenHold = { 0.7, 0,    0.84, 0 },
    silereCloseHold      = { 1,   0,    1,    0 },
}
-- critically damped springs (bounce 0) of a given length; springs keep their velocity when retargeted mid-flight
local spring = {
    silereSmooth = 0.28,
    silereSheet  = 0.28,
}

for name, p in pairs(bezier) do
    try(hl.curve, name, { type = "bezier", points = { { p[1], p[2] }, { p[3], p[4] } } })
end
local spring_speed = {}
for name, duration in pairs(spring) do
    if try(hl.curve, name, { type = "spring", mass = 1, stiffness = (2 * math.pi / duration) ^ 2,
            damping = 4 * math.pi / duration }) then
        -- a spring leaf without a speed falls back to its parent's, so it carries its own length
        spring_speed[name] = duration * 10
    end
end

local function leaf(name, speed, curve, style)
    if speed == nil then return try(hl.animation, { leaf = name, enabled = false }) end
    local spec = { leaf = name, enabled = true, speed = speed, style = style }
    if spring_speed[curve] then spec.spring = curve else spec.bezier = curve end
    return try(hl.animation, spec)
end
local function spring_leaf(name, curve, style)
    if spring_speed[curve] then return leaf(name, spring_speed[curve], curve, style) end
    return leaf(name, 2.8, "silereQuint", style)
end

leaf("global", 2.8, "silereQuint")
leaf("border", focus_duration * 10, "silereQuint")
-- solid borders: a rotating angle would repaint nothing
leaf("borderangle")

spring_leaf("windows", "silereSmooth")
local open_style = ("popin %d%%"):format(window.open.scale)
local close_style = ("popin %d%%"):format(window.close.scale)
leaf("windowsIn", window.open.duration * 10, "silereReveal", open_style)
local function window_out() return leaf("windowsOut", window.close.duration * 10, "silereQuart", close_style) end
window_out()
spring_leaf("windowsMove", "silereSmooth")

leaf("fade", 2.0, "silereQuart")
local function fade_in() return leaf("fadeIn", window.open.fade * 10, "silereQuart") end
fade_in()
leaf("fadeOut", window.close.fade * 10, "silereQuad")
leaf("fadeSwitch", 1.4, "silereQuint")
leaf("fadeShadow", focus_duration * 10, "silereQuint")
leaf("fadeGlow", focus_duration * 10, "silereQuint")
-- a modal's parent lifts with the dialog's own fade
leaf("fadeDim", window.close.fade * 10, "silereQuad")
-- menus and tooltips only fade; an exit eases out like every other exit
leaf("fadePopupsIn", 1.8, "silereQuart")
leaf("fadePopupsOut", 1.3, "silereQuad")
leaf("fadeDpms", 2.0, "silereQuart")

-- other apps' layers (launchers, pickers); Silere's own animate themselves (the installer's silere-no-anim rule)
leaf("layers", 2.4, "silereQuint")
leaf("layersIn", 3.5, "silereReveal", "fade")
leaf("layersOut", 1.5, "silereQuad", "fade")
leaf("fadeLayersIn", 2.2, "silereCubic")
leaf("fadeLayersOut", 1.5, "silereQuad")

-- a full slide, so the two workspaces never overlap; In and Out inherit one leaf, so their edges stay aligned
leaf("workspaces", workspace_duration * 10, "silereGlide", "slide")
spring_leaf("specialWorkspace", "silereSheet", ("slidefadevert %d%%"):format(special_travel))

-- Hyprland 0.57 faults, fixed only while they apply; each restores the leaf it borrowed
if type(hl.on) == "function" and type(hl.timer) == "function" then
    -- 0.57.2 drops fullscreen before it builds a close, so a closing fullscreen window shrank toward its old tile and
    -- bared the wallpaper. Its geometry holds until the fade is done instead, and it dissolves in place
    local closing = 0
    try(hl.on, "window.close", function(target)
        if not target or (target.fullscreen or 0) == 0 then return end
        closing = closing + 1
        local mine = closing
        leaf("windowsOut", 3.0, "silereCloseHold", close_style)
        try(hl.timer, function() if mine == closing then window_out() end end, { timeout = 350, type = "oneshot" })
    end)
    -- entering fullscreen, the other tiles faded out long before the window covered them; they hold until it does
    local holding = 0
    try(hl.on, "window.fullscreen", function(target)
        holding = holding + 1
        if not target or (target.fullscreen or 0) == 0 then return fade_in() end
        local mine = holding
        leaf("fadeIn", 3.0, "silereFullscreenHold")
        try(hl.timer, function() if mine == holding then fade_in() end end, { timeout = 450, type = "oneshot" })
    end)
end

-- 0.57.2 starts every new focused window at dim_strength even with dim_inactive off, so each open began half
-- dimmed. With dimming off the strength does nothing else, so it goes to 0; a config that dims keeps its own
if type(hl.get_config) == "function" and type(hl.config) == "function" then
    local ok, dims = pcall(hl.get_config, "decoration:dim_inactive")
    if ok and (dims == false or dims == 0) then try(hl.config, { decoration = { dim_strength = 0 } }) end
end
