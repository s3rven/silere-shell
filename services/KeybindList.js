.pragma library

// `hyprctl binds -j`, as the Keybinds page lists it: in the config's own order, since that is how its author grouped them

var mods = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"], [2, "Caps"], [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]]
var mouseNames = {
    "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
    "mouse_down": "Scroll down", "mouse_up": "Scroll up", "mouse_left": "Scroll left", "mouse_right": "Scroll right"
}

function keyName(key) {
    var k = String(key || "")
    if (mouseNames[k]) return mouseNames[k]
    // XF86AudioRaiseVolume reads as Audio Raise Volume
    if (k.indexOf("XF86") === 0 && k.length > 4) return k.slice(4).replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    // the number row by keycode (evdev + 8), as layout-independent workspace binds use it
    if (k.indexOf("code:") === 0) return /^1[0-9]$/.test(k.slice(5)) ? String((Number(k.slice(5)) - 9) % 10) : "Key " + k.slice(5)
    return k.length === 1 ? k.toUpperCase() : k
}

function chord(modmask, key) {
    var parts = []
    var mask = Number(modmask) || 0
    for (var i = 0; i < mods.length; i++) if ((mask & mods[i][0]) !== 0) parts.push(mods[i][1])
    parts.push(keyName(key))
    return parts.join(" + ")
}

// the shell's own calls, by `silere ipc` target and function; a bind that runs one, or carries its words as its
// description, reads as Silere names it
var silereCalls = {
    "menu toggle": "Open or close the Silere menu",
    "menu close": "Close the Silere menu",
    "calendar toggle": "Open or close the calendar",
    "calendar close": "Close the calendar",
    "quickActions toggle": "Open or close quick actions",
    "quickActions close": "Close quick actions",
    "tray toggle": "Open the first tray app's menu",
    "tray close": "Close the tray menu",
    "quickActions dnd": "Turn Do Not Disturb on or off",
    "quickActions presentation": "Turn Presentation Mode on or off",
    "quickActions keepAwake": "Keep the screen awake, or stop",
    "quickActions nightLight": "Turn night light on or off",
    "quickActions powerMode": "Next power mode",
    "quickActions wifi": "Turn Wi-Fi on or off",
    "quickActions bluetooth": "Turn Bluetooth on or off",
    "quickActions airplane": "Turn airplane mode on or off",
    "audio volumeUp": "Volume up",
    "audio volumeDown": "Volume down",
    "audio toggleMute": "Mute or unmute output",
    "audio cycleOutput": "Next audio output",
    "audio micUp": "Microphone up",
    "audio micDown": "Microphone down",
    "audio toggleMicMute": "Mute or unmute microphone",
    "audio cycleInput": "Next microphone",
    "notifications dismiss": "Dismiss the newest notification",
    "notifications dismissAll": "Dismiss all notifications",
    "notifications invoke": "Open the newest notification",
    "screenshot flash": "Flash the screenshot underline"
}
var silereGlobals = { "silere:menu": "menu toggle", "silere:tray": "tray toggle" }
var menuTabs = ["Home", "Settings", "Notifications", "Now Playing"]

// the launcher's short words for a call (`silere quick`, `silere toggle dnd`), which the page offers to paste;
// shortCall reads them back, as the launcher does
var shortForms = {
    "menu toggle": "menu",
    "calendar toggle": "calendar",
    "quickActions toggle": "quick",
    "tray toggle": "tray",
    "quickActions dnd": "toggle dnd",
    "quickActions nightLight": "toggle night-light",
    "quickActions keepAwake": "toggle keep-awake",
    "audio toggleMute": "volume mute",
    "notifications dismiss": "dismiss",
    "notifications dismissAll": "dismiss all"
}
var menuWords = { home: 0, settings: 1, notifications: 2, playing: 3, nowplaying: 3 }
var toggleWords = { dnd: "dnd", donotdisturb: "dnd", wifi: "wifi", bluetooth: "bluetooth", airplane: "airplane",
    airplanemode: "airplane", nightlight: "nightLight", keepawake: "keepAwake", presentation: "presentation",
    presentationmode: "presentation", powermode: "powerMode" }
var audioWords = { volume: ["volumeUp", "volumeDown", "toggleMute", "cycleOutput", "setVolume"],
    mic: ["micUp", "micDown", "toggleMicMute", "cycleInput", "setMicVolume"] }

function fold(word) {
    return String(word || "").toLowerCase().replace(/[^a-z0-9]/g, "")
}

// `silere <verb> [word] [word]` as the call the launcher makes for it, or "" for words it refuses
function shortCall(verb, word, extra) {
    var w = fold(word)
    var has = word !== undefined && word !== ""
    if (extra !== undefined && extra !== "" && !(verb === "menu" && w === "settings")) return ""
    switch (verb) {
    case "menu":
        if (!has) return "menu toggle"
        if (w === "close") return "menu close"
        if (w === "settings" && extra) return "menu settings " + extra
        if (menuWords.hasOwnProperty(w)) return "menu tab " + menuWords[w]
        return "menu settings " + word
    case "calendar":
    case "tray":
    case "quick":
    case "quick-actions":
        var target = verb === "calendar" || verb === "tray" ? verb : "quickActions"
        return !has ? target + " toggle" : String(word) === "close" ? target + " close" : ""
    case "toggle":
        if (!has) return ""
        return toggleWords.hasOwnProperty(w) ? "quickActions " + toggleWords[w] : "settings toggle " + word
    case "volume":
    case "mic":
        var fns = audioWords[verb]
        var words = ["up", "down", "mute", "next"]
        var at = words.indexOf(String(word).toLowerCase())
        if (at >= 0) return "audio " + fns[at]
        var level = /^([0-9]{1,3})%?$/.exec(String(word))
        return level ? "audio " + fns[4] + " " + Number(level[1]) : ""
    case "dismiss":
        return !has ? "notifications dismiss" : String(word) === "all" ? "notifications dismissAll" : ""
    }
    return ""
}

// `silere ipc menu toggle`, `silere menu`, or `qs -c silere ipc call menu toggle`, as "menu toggle"; any other
// command as "". The launcher takes no `call`, so `silere ipc call` is the third form's config name followed by its verb
function silereCall(command) {
    var c = String(command || "")
    var m = /(?:^|[\s;&|/("'])silere['"]?\s+ipc\s+(?!call\s)([A-Za-z]+)\s+([A-Za-z]+)(?:\s+([^\s;&|"')]+))?/.exec(c)
    if (!m) {
        var s = /(?:^|[\s;&|/("'])silere['"]?\s+(menu|calendar|quick|quick-actions|tray|toggle|volume|mic|dismiss)(?=$|[\s;&|"')])(?:[ \t]+([^\s;&|"')]+))?(?:[ \t]+([^\s;&|"')]+))?/.exec(c)
        if (s) return shortCall(s[1], s[2], s[3])
    }
    // a quickshell call names Silere in its config or path; other shells' targets can share these names
    if (!m && /silere/i.test(c))
        m = /(?:^|[\s;&|/("'])(?:qs|quickshell)\s[^;&|]*?\bipc\s+call\s+([A-Za-z]+)\s+([A-Za-z]+)(?:\s+([^\s;&|"')]+))?/.exec(c)
    if (!m) return ""
    return m[1] + " " + m[2] + (m[3] !== undefined ? " " + m[3] : "")
}

function silereLabel(call) {
    var words = String(call || "").split(" ")
    var key = words.slice(0, 2).join(" ")
    if (silereCalls[key]) return silereCalls[key]
    if (key === "menu tab" && menuTabs[Number(words[2])]) return "Open the menu on " + menuTabs[Number(words[2])]
    if (key === "menu settings" && words.length > 2) return "Open Settings on " + words[2]
    return ""
}

// hyprlang's direction arguments, and the keys that point (arrows, and vim's h j k l)
var directions = { l: "left", r: "right", u: "up", t: "up", d: "down", b: "down", left: "left", right: "right", up: "up", down: "down" }
var keyDirections = { left: "left", right: "right", up: "up", down: "down", h: "left", j: "down", k: "up", l: "right" }
function direction(arg) {
    var a = String(arg || "").trim().toLowerCase()
    return directions.hasOwnProperty(a) ? directions[a] : ""
}
function keyDirection(key) {
    var k = String(key || "").toLowerCase()
    return keyDirections.hasOwnProperty(k) ? keyDirections[k] : ""
}

// a workspace argument as words: `2` workspace 2, `e+1` the next workspace, `special:scratch` special workspace scratch
function workspace(arg) {
    var a = String(arg || "").trim()
    if (/^-?\d+$/.test(a)) return "workspace " + a
    if (/^[emr]?\+\d+$/.test(a)) return "the next workspace"
    if (/^[emr]?-\d+$/.test(a)) return "the previous workspace"
    if (a === "previous" || a === "previous_per_monitor") return "the previous workspace"
    if (a.indexOf("empty") === 0) return "an empty workspace"
    if (a.indexOf("special") === 0) return a.indexOf(":") > 0 ? "special workspace " + a.slice(a.indexOf(":") + 1) : "the special workspace"
    if (a.indexOf("name:") === 0) return "workspace " + a.slice(5)
    return a.length > 0 ? "workspace " + a : "a workspace"
}

// a media key says what it does; with a modifier held it may do something else
var mediaKeys = {
    XF86AudioRaiseVolume: "Volume up", XF86AudioLowerVolume: "Volume down", XF86AudioMute: "Mute or unmute output",
    XF86AudioMicMute: "Mute or unmute microphone", XF86MonBrightnessUp: "Brightness up", XF86MonBrightnessDown: "Brightness down",
    XF86KbdBrightnessUp: "Keyboard light up", XF86KbdBrightnessDown: "Keyboard light down",
    XF86AudioPlay: "Play or pause", XF86AudioPause: "Pause", XF86AudioStop: "Stop playback",
    XF86AudioNext: "Next track", XF86AudioPrev: "Previous track"
}

// a launcher wrapper in front of a command says nothing about what it runs
function command(text) {
    var c = String(text || "").replace(/\s+/g, " ").trim()
    var before = ""
    while (before !== c) {
        before = c
        c = c.replace(/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+/, "")
            .replace(/^(?:uwsm(?:-app| app)|app2unit)(?:\s+-\S+)*\s+--\s+/, "")
            .replace(/^(?:uwsm(?:-app| app)|app2unit|setsid|nohup|exec)\s+(?:-\S+\s+)*/, "")
    }
    return c
}

// a hyprlang config names its dispatcher and argument
function hyprlangAction(dispatcher, arg, bind) {
    var a = String(arg || "").trim()
    var dir = direction(a)
    var mouse = bind.mouse === true
    switch (dispatcher) {
    case "exec": case "execr": return a.length > 0 ? "Run " + command(a) : ""
    case "killactive": return "Close window"
    case "forcekillactive": return "Force close window"
    case "exit": return "Exit Hyprland"
    case "workspace": return "Go to " + workspace(a)
    case "movetoworkspace": return "Move window to " + workspace(a)
    case "movetoworkspacesilent": return "Send window to " + workspace(a)
    case "togglespecialworkspace": return "Show or hide " + (a.length > 0 ? "special workspace " + a : "the special workspace")
    case "movefocus": return dir ? "Focus " + dir : "Move focus"
    case "movewindow": return mouse ? "Drag window" : dir ? "Move window " + dir : "Move window"
    case "swapwindow": return dir ? "Swap window " + dir : "Swap window"
    case "resizewindow": return "Resize window"
    case "resizeactive": return "Resize window"
    case "moveactive": return "Move window"
    case "togglefloating": return "Float or tile window"
    case "setfloating": return "Float window"
    case "settiled": return "Tile window"
    case "fullscreen": return a === "1" ? "Maximize" : "Fullscreen"
    case "fullscreenstate": return "Fullscreen state"
    case "pseudo": return "Pseudotile window"
    case "pin": return "Pin window"
    case "centerwindow": return "Center window"
    case "togglesplit": return "Toggle split"
    case "swapsplit": return "Swap split"
    case "layoutmsg": return a.length > 0 ? "Layout: " + a : "Layout message"
    case "cyclenext": return a.indexOf("prev") === 0 ? "Previous window" : "Next window"
    case "focusurgentorlast": return "Urgent or last window"
    case "focuscurrentorlast": return "Last window"
    case "focusmonitor": return "Focus monitor " + a
    case "movecurrentworkspacetomonitor": return "Move workspace to monitor " + a
    case "swapactiveworkspaces": return "Swap workspaces between monitors"
    case "togglegroup": return "Group or ungroup"
    case "changegroupactive": return a === "b" ? "Previous window in group" : "Next window in group"
    case "moveoutofgroup": return "Move window out of group"
    case "lockgroups": return "Lock groups"
    case "bringactivetotop": return "Bring window to top"
    case "submap": return a === "reset" ? (bind.submap ? "Leave " + bind.submap : "Leave the submap") : "Enter " + a
    case "dpms": return a.indexOf("off") === 0 ? "Turn displays off" : a.indexOf("on") === 0 ? "Turn displays on" : "Turn displays on or off"
    case "pass": return "Pass to " + a
    case "sendshortcut": return "Send a shortcut"
    case "forcerendererreload": return "Reload the renderer"
    case "global": return "Global shortcut " + a
    }
    return a.length > 0 ? dispatcher + " " + a : dispatcher
}

// a Lua config's hyprctl reply names only the dispatcher, `HL.Dispatcher(focus)`, and an index for its argument,
// so a digit or arrow key says the rest: Super + 1 on focus is that workspace, Super + left focuses left
var luaVerbs = {
    exec_cmd: "", exec_raw: "", close: "Close window", kill: "Force close window", exit: "Exit Hyprland",
    float: "Float or tile window", pseudo: "Pseudotile window", pin: "Pin window", center: "Center window",
    fullscreen: "Fullscreen", fullscreen_state: "Fullscreen state", drag: "Drag window", resize: "Resize window",
    swap: "Swap window", cycle_next: "Next window", bring_to_top: "Bring window to top", alter_zorder: "Raise or lower window",
    toggle_special: "Show or hide a special workspace", layout: "Layout message", global: "Global shortcut",
    submap: "Enter or leave a submap", dpms: "Turn displays on or off", reload_config: "Reload config",
    force_renderer_reload: "Reload the renderer", pass: "Pass to a window", send_shortcut: "Send a shortcut",
    rename: "Rename workspace", swap_monitors: "Swap workspaces between monitors", move_to_corner: "Move the cursor to a corner",
    toggle: "Group or ungroup", next: "Next window in group", prev: "Previous window in group",
    lock: "Lock groups", lock_active: "Lock this group", move_window: "Move window into group",
    toggle_swallow: "Swallow or release window", tag: "Tag window", set_prop: "Set a window property"
}
// the verbs whose reading is a category, not what the bind does
var luaGeneric = { layout: true, global: true, submap: true, pass: true, send_shortcut: true, set_prop: true, tag: true }

function luaAction(verb, bind) {
    var key = String(bind.key || "")
    var digit = /^[0-9]$/.test(key) ? (key === "0" ? "10" : key) : ""
    var dir = keyDirection(key)
    if (verb === "focus")
        return digit ? { text: "Go to workspace " + digit, exact: true } : dir ? { text: "Focus " + dir, exact: true }
            : key === "mouse_down" || key === "mouse_up" ? { text: "Switch workspace", exact: true }
            : { text: "Focus", exact: false }
    if (verb === "move")
        return digit ? { text: "Move window to workspace " + digit, exact: true } : dir ? { text: "Move window " + dir, exact: true }
            : { text: "Move window", exact: false }
    if (verb === "swap" && dir) return { text: "Swap window " + dir, exact: true }
    var text = luaVerbs.hasOwnProperty(verb) ? luaVerbs[verb] : ""
    return { text: text, exact: text.length > 0 && !luaGeneric[verb] }
}

// what a bind does, and whether that is its own words or a fair reading (`exact`); a generic reading such as
// "Run a command" is not. Its description first; a Lua function says nothing about itself
function describe(bind) {
    var described = String(bind.description || "").replace(/\s+/g, " ").trim()
    if (bind.has_description && described.length > 0) return { text: described, exact: true, own: true }
    var dispatcher = String(bind.dispatcher || "")
    var arg = String(bind.arg || "")
    var lua = /^HL\.Dispatcher\((\w*)\)$/.exec(dispatcher)
    var fn = dispatcher.indexOf("function:") === 0
    var runs = fn || dispatcher === "exec" || dispatcher === "execr" || (lua !== null && lua[1].indexOf("exec") === 0)
    if (!lua && !fn) {
        var call = dispatcher === "global" ? (silereGlobals[arg.trim()] || "") : runs ? silereCall(arg) : ""
        var label = silereLabel(call)
        if (label.length > 0) return { text: label, exact: true, own: false, silere: call }
    }
    if (runs && (Number(bind.modmask) || 0) === 0 && mediaKeys.hasOwnProperty(String(bind.key || "")))
        return { text: mediaKeys[String(bind.key)], exact: true, own: false }
    if (fn) return { text: "", exact: false, own: false }
    if (lua) {
        if (runs) return { text: "Run a command", exact: false, own: false }
        var reading = luaAction(lua[1], bind)
        reading.own = false
        return reading
    }
    if (dispatcher.length === 0) return { text: "", exact: false, own: false }
    var text = hyprlangAction(dispatcher, arg, bind)
    return { text: text, exact: text.length > 0, own: false }
}

function action(bind) {
    return describe(bind).text
}

// null when the output is not a list of binds; text is bounded per field, rows by limit
function parse(text, limit) {
    var data = null
    try { data = JSON.parse(String(text || "")) } catch (e) { return null }
    if (!Array.isArray(data)) return null
    var rows = []
    var cap = Number(limit) > 0 ? Number(limit) : 500
    for (var i = 0; i < data.length && rows.length < cap; i++) {
        var b = data[i]
        if (!b || typeof b !== "object" || b.catch_all === true) continue
        var d = describe(b)
        var words = d.text.slice(0, 160)
        // hyprctl leaves key empty for a bind made by keycode and gives the number instead
        var key = String(b.key || "") || (Number(b.keycode) > 0 ? "code:" + Number(b.keycode) : "")
        var call = d.silere || ""
        // a line pasted from the Keybinds page keeps its words as the description; only those, since a description
        // such as "volume up" is as likely a wpctl bind as Silere's
        for (var k = 0; k < suggestions.length && !call && d.own; k++)
            if (silereCalls[suggestions[k].call].toLowerCase() === words.toLowerCase()) call = suggestions[k].call
        rows.push({
            keys: chord(b.modmask, key).slice(0, 80),
            action: words,
            exact: d.exact,
            own: d.own,
            silere: call,
            lua: /^(?:HL\.|function:)/.test(String(b.dispatcher || "")),
            // a Lua global names no shortcut, so which one it reaches is unknown
            luaGlobal: String(b.dispatcher || "") === "HL.Dispatcher(global)",
            modmask: Number(b.modmask) || 0,
            key: key.slice(0, 40),
            submap: String(b.submap || "").slice(0, 40)
        })
    }
    return rows
}

// every word of the query, against the action, the keys and the submap
function filter(rows, query) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) { return w.length > 0 })
    if (words.length === 0) return rows
    return rows.filter(function (r) {
        var hay = (r.action + " " + r.keys + " " + r.submap).toLowerCase()
        return words.every(function (w) { return hay.indexOf(w) >= 0 })
    })
}

// the calls worth a key of their own, each with keys to try in order; the first no bind in the main keymap holds
// is offered. A global shortcut answers without starting a process, so the menu and tray use one when the shell owns them
var suggestions = [
    { call: "menu toggle", glyph: "󰍜", global: "silere:menu", keys: [[64, "slash"], [64, "backslash"], [72, "M"]] },
    { call: "quickActions toggle", glyph: "󰒓", keys: [[64, "A"], [72, "A"], [65, "A"]] },
    { call: "calendar toggle", glyph: "󰃭", keys: [[72, "C"], [68, "C"], [72, "D"]] },
    { call: "quickActions dnd", glyph: "󰂛", keys: [[72, "N"], [68, "N"], [72, "D"]] },
    { call: "notifications dismiss", glyph: "󰎟", keys: [[65, "N"], [68, "X"], [72, "X"]] },
    { call: "tray toggle", glyph: "󰀻", global: "silere:tray", keys: [[65, "slash"], [72, "slash"], [65, "backslash"]] }
]

var luaMods = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
function modWords(mask) {
    var parts = []
    for (var i = 0; i < luaMods.length; i++) if ((mask & luaMods[i][0]) !== 0) parts.push(luaMods[i][1])
    return parts
}

// one config line, in the config's own language; `lua` false writes hyprlang's bindd
// the launcher as a line's first word: `silere` when it is on PATH, else its own path, quoted for the shell the
// compositor runs the line with
function launcherWord(path) {
    var p = String(path || "")
    if (p.length === 0) return "silere"
    return /^[A-Za-z0-9_.\/~+-]+$/.test(p) ? p : "'" + p.replace(/'/g, "'\\''") + "'"
}

function bindLine(lua, mask, key, label, call, globalName, launcher) {
    var run = (launcher || "silere") + " " + (shortForms[call] || "ipc " + call)
    if (lua) {
        var keys = modWords(mask).concat([key]).join(" + ")
        var dsp = globalName ? "hl.dsp.global(\"" + globalName + "\")"
            : "hl.dsp.exec_cmd(\"" + run.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\")"
        return "hl.bind(\"" + keys + "\", " + dsp + ", { description = \"" + label.replace(/"/g, "\\\"") + "\" })"
    }
    var d = globalName ? "global, " + globalName : "exec, " + run
    return "bindd = " + modWords(mask).join(" ") + ", " + key + ", " + label.replace(/,/g, "") + ", " + d
}

// each suggestion against the binds there are: bound (and where), or the free keys to offer and the line to paste
function suggest(rows, lua, globals, launcher) {
    var taken = {}
    var bound = {}
    var list = rows || []
    for (var i = 0; i < list.length; i++) {
        var r = list[i]
        if (r.submap.length === 0) taken[r.modmask + " " + r.key.toLowerCase()] = true
        if (r.silere.length > 0 && !bound[r.silere]) bound[r.silere] = r.keys
    }
    // a Lua global on the keys these docs suggest for one is taken to be that one
    for (var j = 0; j < list.length; j++) {
        var q = list[j]
        if (!q.luaGlobal || q.submap.length > 0) continue
        for (var t = 0; t < suggestions.length; t++) {
            var first = suggestions[t].keys[0]
            if (suggestions[t].global && !bound[suggestions[t].call] && q.modmask === first[0]
                    && q.key.toLowerCase() === first[1].toLowerCase()) bound[suggestions[t].call] = q.keys
        }
    }
    var out = []
    for (var s = 0; s < suggestions.length; s++) {
        var g = suggestions[s]
        var label = silereCalls[g.call]
        var pick = null
        for (var k = 0; k < g.keys.length && !pick; k++) if (!taken[g.keys[k][0] + " " + g.keys[k][1].toLowerCase()]) pick = g.keys[k]
        var free = pick !== null
        if (!pick) pick = g.keys[0]
        out.push({
            call: g.call,
            glyph: g.glyph,
            label: label,
            bound: bound[g.call] || "",
            keys: chord(pick[0], pick[1]),
            free: free,
            line: bindLine(lua, pick[0], pick[1], label, g.call, globals ? (g.global || "") : "", launcher)
        })
    }
    return out
}
