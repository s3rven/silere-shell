# Silere improvement plan

Researched and checked on **28 October 2026**, against **e9b39f4** plus the
existing working-tree changes. This is a proposed roadmap and a record of the
checks below; it does not implement the proposed features.

**Current scope:** finish and validate the existing daily-driver improvements.
Feature expansion is deferred; the palette, preset and other ideas below are
retained as research proposals, outside the current work.

## What is already here

The checkout already has per-app audio, notification actions/replies/search,
wallpaper colours, configurable widget order, reduced motion, high contrast,
signed updates and rollback. Hidden popups unload, dropdowns reuse visible rows,
and idle/visibility gates stop much of the background work.

There is also substantial existing, uncommitted implementation of the
[daily-driver review](daily-driver-review.md): keyboard controls, presentation
privacy, saved VPN controls, Bluetooth/network-manager handoffs, lock-and-sleep,
optional supervised startup, larger text, separate text/icon fonts, external
display brightness, and workflow shortcuts. See
[daily-driver changes](daily-driver-changes.md). These are present in the checkout;
they still need release review and physical-device validation. Treat them as work
to finish, rather than proposing them again as missing features.

The running desktop uses a different installation under
`~/.local/share/silere-shell`. This review did not restart it or deploy this
checkout. The performance samples below belong to an isolated test instance.

## Useful ideas from other shells

These are documented capabilities, not results of installing or benchmarking the
other shells. Their resource use was not measured, so this comparison makes no
speed or memory ranking.

| Project | Relevant capabilities | Lesson for Silere |
|---|---|---|
| [Serpantinum configuration](https://serpantinum.dev/configure/) | Usage-ranked launcher, dock, wallpaper selection, theme presets, configurable bar grouping/placement, interface languages | Make the desktop convenient immediately and let people get a complete look from a few choices. |
| [Dux Shell, formerly DankMaterialShell](https://duxlabs.dev/) | Unified dashboard and desktop controls, plugins, matching application colours | Connected workflows and a coherent appearance make individual features feel like one product. |
| [Noctalia launcher](https://github.com/noctalia-dev/noctalia/blob/main/docs/user/launcher/index.mdx) | Providers for windows, wallpapers and session actions alongside applications | Search can become the common entry point for work that currently requires knowing which panel to open. |
| [Caelestia configuration](https://github.com/caelestia-dots/shell/blob/main/README.md#configuring) | Wallpaper actions from the launcher and per-monitor configuration overrides | Reuse one interaction model and let a laptop screen and an external display serve different needs. |

Current naming matters: DMS is now presented upstream as Dux Shell. Noctalia's
[current documentation](https://docs.noctalia.dev/) identifies its former
Quickshell v4 implementation as archived. Use current product ideas as inspiration;
do not assume their present implementations target Silere's runtime.

## Build in this order

Sizes are relative implementation scope, not delivery dates. Each row should be
reviewed independently.

| Order | Change | User benefit | Scope |
|---|---|---|---|
| 0 | Finish and validate the existing daily-driver changes | Dependable controls and a releasable starting point | Existing work + hardware review |
| 1 | Search palette for apps, windows, settings and actions | Reach common tasks from one shortcut | Medium–large |
| 2 | Appearance/layout presets with preview and undo | Get a coherent, personal desktop quickly | Medium |
| 3 | First-run setup and a shortcut guide | Discover controls and connect existing tools | Small–medium |
| 4 | Profile and tune visualizer workloads | Preserve responsiveness and battery life during playback | Medium, evidence dependent |
| 5 | Wallpaper picker with bounded thumbnails | Apply a wallpaper and see the shell's colours follow | Medium |
| 6 | Per-monitor bar layout overrides | Keep laptop and desktop layouts comfortable | Medium |
| 7 | Notification rules per application | Keep useful alerts while controlling noise and retained content | Medium |
| 8 | Optional clipboard integration, then simple extension points | Add frequently used workflows without persistent cost for everyone | Medium–large |

### 1. A search palette is the strongest first feature

Settings search and notification search already exist, but there is no common
search surface. [`WorkflowActions.qml`](../services/WorkflowActions.qml) can launch
an external launcher; keep that choice while offering an optional built-in palette.

Start with applications and existing shell actions, then add open windows and
settings results. Show which kind of result will run, support pins and keyboard
selection, and make any usage ranking resettable. Reuse the settings catalogue,
[`Compositor.toplevels` and `focusToplevel()`](../services/Compositor.qml), and
Quickshell's desktop-entry model. Instantiate the result view on demand and reuse
visible delegates, following the existing popup/list patterns.

Application launching needs deliberate handling at the supported runtime floor:
Quickshell 0.3.1 documents that
[`DesktopEntry.execute()`](https://quickshell.org/docs/v0.3.1/types/Quickshell/DesktopEntry/)
ignores terminal handling and field codes. Do not assume calling it completes
launcher support. Choose a compatible desktop-entry launch path and test working
directories, terminal apps, desktop actions, entries containing spaces, and
applications installed while Silere is running.

Acceptance: open through IPC/compositor shortcut, search, activate by Enter, and
close by Escape. Focus a window on another workspace on both supported
compositors. Preserve focus behavior if a result disappears. A large synthetic app
catalogue should create only viewport-sized UI and keep typing responsive. Closing
the palette should stop its work and release its view.

### 2. Make appearance choices complete and shareable

The existing accent choices and base tones are useful, but a complete preset could
also select spacing, typography, opacity, bar shape and widget arrangement. Offer
a small set such as Quiet, Compact and Comfortable, with a live preview and undo.
Keep individual controls available after applying a preset.

Add versioned import/export of an allowlist of appearance/layout fields. Exclude
workflow commands, local paths, monitor identities and notification history; show
the changes before applying. Validate through the existing settings schema.

A true light theme is a separate follow-up: [`Theme.qml`](../config/Theme.qml)
currently uses dark base tones and a black depth sink. It needs light surface/text
roles and contrast checks across every state, rather than a single background
colour switch. Preview it with high contrast, disabled controls and wallpaper
palettes before shipping.

Acceptance: round-trip a preset, reject malformed/unknown fields safely, undo an
application, and verify readable layouts at all supported text sizes and scales.

### 3. Show people where to begin

Promote the existing dependency diagnostics and command editors into a dismissible
setup card. Explain the menu/quick-action/clock entry points, help select an
installed launcher, clipboard picker, screenshot tool and locker, and preview the
matching compositor bindings. Apply only choices the user makes; keep the current
installer's configuration preview and backup behavior.

Acceptance: a fresh profile can discover how to open the menu, configure its
preferred tools and find the shortcut guide again. Skipping setup leaves a usable
shell; missing optional tools have a clear next action.

### 4. Profile the visualizer before redesigning it

The most plausible rendering target is
[`MediaVisualizer.qml`](../modules/bar/widgets/MediaVisualizer.qml): it uses
`Canvas.Image` with `Canvas.Immediate` and repaints as the spectrum changes. The
underline variant can span much of the bar. Qt documents that frequently updated
image canvases require texture uploads on accelerated backends.
[Qt Canvas guidance](https://doc.qt.io/qt-6/qml-qtquick-canvas.html).

This is a profiling hypothesis, not a measured defect. Existing code already gates
the active bar, stops hidden work, reduces quality on battery, caches gradients,
and snaps spectrum width. Preserve those safeguards. Measure Cava CPU separately
from shell CPU and UI paint time, at each placement/style/quality setting. Compare
a smaller backing image or scene-graph prototype only after locating the cost;
keep an alternative only if it improves measured frame times or energy use without
visual regressions. Qt likewise recommends profiling before optimizing.
[Qt Quick performance guidance](https://doc.qt.io/qt-6/qtquick-performance.html).

Also measure panel opening and history search at the current 100-entry maximum.
[`FilteredHistory.qml`](../modules/menu/FilteredHistory.qml) reconciles on each
query change, but its bounded model gives no reason to add indexing or debounce
without a typing-latency problem. Background VPN interface sampling is another
candidate to measure; an event subscription is a possible later change if its
runtime dependencies and recovery behavior justify it.

### 5–8. Complete the desktop in bounded steps

- **Wallpaper picker:** scan chosen folders on demand, decode thumbnails at their
  display size, cap the cache, reuse grid delegates, and cancel stale requests.
  Use the user's chosen wallpaper service and existing Matugen integration.
  Test large directories, deleted files and rapid selections.
- **Per-monitor layouts:** existing [`Monitors.qml`](../services/Monitors.qml)
  already enables/disables bars and chooses overlay screens. Add inherited widget
  layouts/density per output, with global defaults and a reset. Test unplugging,
  reconnecting and changing focus without rebuilding every bar.
- **Application notification rules:** history already has grouping/filtering and
  retention. Add rules for popup visibility and history storage, keyed by stable
  application identity where available. Keep presentation privacy authoritative
  and test existing cards, replacements and inline replies when rules change.
- **Clipboard and extensions:** start with the configured external picker. A
  native picker needs an explicit retention policy, a clear-history action and
  bounded text/image storage. For customization, try documented data-driven
  actions before a general plugin marketplace; establish lifecycle and idle-cost
  rules before promising a stable extension API.

## Measurements from this review

Command: `bash dev/test-compositors.sh kwin --bench /tmp/silere-review-bench`.

This used a private KWin session with software rendering, a private session bus,
default settings, no visualizer and no live NetworkManager/audio session services
on that bus. Hardware: Ryzen 7 8845HS; kernel `7.3.0-5-cachyos`; Quickshell 0.3.2;
Qt 6.12.0. Each sample requested 10 seconds. One other Quickshell instance remained
running, affecting shared-memory accounting. The first run overlapped the end of
the validation suite. These are short development observations, not release
benchmarks or a controlled comparison with the historical 90/99 MB figures.

| State | PSS (MiB) | CPU average / median (% of one core) | FDs / change during sample | Assessment |
|---|---|---|---|---|
| Fresh instance | 101 | 1.2 / 0.0 | 73 / +15 | Noisy startup; exclude from an idle baseline |
| After one menu open/close | 117 | 0.1 / 0.0 | 73 / 0 | Steady during the sample |
| After 30 further menu cycles | 123 | 0.1 / 0.0 | 73 / 0 | Steady during the sample; longer memory run needed |

Raw reports: [fresh](perf/review-2026-10-28/kwin-cold.json),
[warm](perf/review-2026-10-28/kwin-warm.json),
[30 cycles](perf/review-2026-10-28/kwin-cycles.json).

The 6 MiB difference between the latter two states does not establish a leak or
show whether memory eventually plateaus. Repeat longer batches with settling time
and record PSS, helpers and descriptors across batches. The existing runner's rapid
cycles are useful for stress, but a retention measurement should also let each
popup finish opening and unloading. Keep a separate GPU-rendered daily-use run.

For release comparisons, record at least three settled samples per scenario on
the same machine/runtime/settings, with no other Quickshell instance. Cover idle,
Home open, history search, playback without a visualizer, each visualizer quality,
quiet idle/fullscreen, and repeated popup lifetimes. Record renderer, display
refresh/scale, enabled widgets, helper CPU, frame-time percentiles and PSS. A
proposed review trigger is a repeatable >10% warm-memory increase or >0.5 percentage
point idle-CPU increase; establish normal measurement variance before making
either a CI gate. Test high-refresh frame pacing on physical hardware.

## Runtime measurements, 31 October 2026

Taken on the same hardware with Quickshell 0.3.2 and Qt 6.12. The soak, process
trace and per-action costs ran in a private session with software rendering, so
their render figures are pessimistic.

| Question | Result |
|---|---|
| Does memory plateau? | Yes. Anonymous PSS held at 79-82 MiB over 8 batches, 240 menu and 240 calendar cycles with settling. Total PSS settled at 129-137 MiB, and threads and descriptors fell. |
| Live idle cost | About 10 wakeups a second, 0.2% of a core, no disk writes in 20 s. |
| Process spawns | None in 60 s idle with the bar's monitor shown, under three per menu open. |
| Startup and first opens | Ready in about 0.5 s, 260 ms main-thread CPU. First menu open 60 ms. |
| Window title churn at 12 Hz | About 0.5% of a core on the main thread. |
| Focus change with 21 windows | About 10 ms main-thread CPU. Removing the extra layout rebuild saved under 1 ms, so it stays. |

Still unmeasured: visualizer cost during playback, including geometry-driven repaints
while its width animates. Measure actual paints and frame times before changing it.

## Validation completed

- `bash scripts/test-qml-headless.sh`: passed, 202 QML files.
- `bash dev/test-logic.sh`: passed, 2,012 checks.
- `bash dev/check.sh`: passed, zero warnings. Includes 91 popup interaction
  behaviors, four screen-removal checks, 184 live settings states and 1,340 UI
  stress checks over 120 cycles, plus structural/layout/helper checks.
- `bash dev/test-compositors.sh kwin --bench /tmp/silere-review-bench`: passed.
- `bash dev/test-compositors.sh hyprland`: passed in an isolated nested compositor.
- niri integration could not run because the `niri` executable is absent locally.

The first sandboxed `dev/check.sh` attempt failed because D-Bus socket creation
was forbidden; the unrestricted rerun passed. Physical pairing, VPN secrets,
DDC/CI, lock-before-sleep and resume were not exercised. Run those deliberate
hardware/session checks before releasing the existing daily-driver changes.
