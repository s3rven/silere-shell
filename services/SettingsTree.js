.pragma library

// order by user impact and frequency: global appearance first, daily bar surfaces next, then feedback; operational and recovery tools stay last
var tree = [
    { glyph: "󰉦", label: "Appearance", children: [
        { glyph: "󰉦", label: "Theme",       section: "theme",
          description: "Colors, opacity, blur, and shadows" },
        { glyph: "󰛖", label: "Interface", section: "interface",
          description: "Text, scale, and accessibility" }
    ]},
    { glyph: "󰕮", label: "Bar", children: [
        { glyph: "󰍹", label: "Layout",    section: "surface",
          description: "Position, size, shape, and hover" },
        { glyph: "󰍴", label: "Underline", section: "underline",
          description: "Line and event glow" },
        { glyph: "󰤼", label: "Spacing",   section: "separators",
          description: "Gaps and dividers" }
    ]},
    { glyph: "󰀻", label: "Widgets", children: [
        { glyph: "󰀻", label: "Show & order", section: "widgets",
          description: "Choose and reorder bar widgets" },
        { glyph: "󰕰", label: "Workspaces", section: "workspaces",
          description: "Markers, labels, and app icons" },
        { glyph: "󰅐", label: "Clock",      section: "clock",
          description: "Date, time, calendar, and weather" },
        { glyph: "󰝚", label: "Media",      section: "media",
          description: "Track details and visualizer" },
        { glyph: "󰈈", label: "Indicators", section: "indicators",
          description: "Window title, status, and system" }
    ]},
    { glyph: "󰂚", label: "Feedback", children: [
        { glyph: "󰂚", label: "Notifications", section: "popups",
          description: "Popups and quiet hours" },
        { glyph: "󰋚", label: "History", section: "history",
          description: "Saved notifications and muted apps" },
        { glyph: "󱀅", label: "OSD",    section: "osd",
          description: "Volume and brightness feedback" },
        { glyph: "󰀦", label: "Alerts", section: "warnings",
          description: "Battery and temperature limits" }
    ]},
    { glyph: "󰒓", label: "System", children: [
        { glyph: "󰒓", label: "Overview", section: "updates",
          description: "Updates, diagnostics, and recovery" },
        { glyph: "󰦉", label: "Devices", section: "devices",
          description: "Displays, lighting, Bluetooth, and programs" },
        { glyph: "󰌌", label: "Keybinds", section: "keybinds",
          description: "Shortcuts and what each does" }
    ]}
]

var flatSections = []
for (var g = 0; g < tree.length; g++) {
    if (!tree[g].children) flatSections.push(tree[g].section)
    else for (var c = 0; c < tree[g].children.length; c++) flatSections.push(tree[g].children[c].section)
}

function foldName(name) {
    return String(name || "").toLowerCase().replace(/[^a-z0-9]/g, "")
}

// folds only hand-typed ipc names; setSettingsSection stays exact so no caller lands on a page by accident
function ipcSection(name) {
    var fold = foldName(name)
    if (fold.length === 0) return name
    if (fold === "maintenance" || fold === "diagnostics" || fold === "system") return "updates"
    for (var i = 0; i < flatSections.length; i++)
        if (foldName(flatSections[i]) === fold) return flatSections[i]
    for (var g = 0; g < tree.length; g++) {
        var kids = tree[g].children || []
        for (var c = 0; c < kids.length; c++)
            if (foldName(kids[c].label) === fold) return kids[c].section
    }
    return name
}
