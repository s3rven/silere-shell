# Performance

Background work only runs when it has something to do. CPU sits near zero when nothing is
happening and rises with what is on screen: a playing track costs about four times idle,
and the media visualizer costs more than everything else combined. Once the session goes
idle, or the bar steps aside for the compositor overview, every animation stops on its own
until you come back.

## Reference numbers

These are the 1.3.0 release measurements on reference machine A in
[performance history](perf-history.md), not a memory limit for the current checkout.

| State | PSS | What it is |
|---|---|---|
| cold | ~83 MB | Freshly started, menu never opened. Only the bar has drawn. |
| warm | ~91 MB | The same session after the menu has been opened once. |

Menu and popup instances unload after closing. The first open also loads code, font and
driver caches that can remain warm, so closing a menu does not return the process to its
startup footprint. An empty Quickshell panel measures about 57 MB on the same machine.

Dropdown rows are created around the visible viewport and reused while scrolling. A
workspace hover can prepare the menu for 2.5 seconds; leaving it unused releases that
instance. The logic suite checks both lifetimes, including a thousand-option dropdown.

Remote cover downloads begin only while the media widget or menu can use them, and
pause during quiet idle. A hidden Now Playing page also stops cover decoding, retries
and unfinished animations.

Read PSS, not RSS. `top` and `htop` show RSS, which counts shared Qt, Mesa and font pages in
full and reads about 175 to 185 MB for the same session.

Results vary with hardware, drivers, fonts and which widgets you enable. To measure your own
setup, close other heavy programs first:

```bash
bash scripts/bench.sh 30            # as you left it
bash scripts/bench.sh 30 --warm     # after one menu open and close
```

The number is how many seconds to sample. Quote the `per-second` median rather than the
`cpu` average, which folds a single keystroke or menu open into the idle figure.

## Development memory check

On 2026-10-04, revision `466bec2` was measured on reference machine A with kernel
`7.2.8-2-cachyos`, the live user's settings, and no other Quickshell instances. These
are short development samples, separate from the release measurements above.

| State | Sample | PSS | RSS average | USS |
|---|---|---|---|---|
| Existing process, about 3.8 hours old | 5 seconds | 121 MiB | 220 MiB | 98 MiB |
| Updated process after restart | 10 seconds | 85 MiB | 175 MiB | 66 MiB |
| Updated process after Home opened and closed | 10 seconds | 93 MiB | 184 MiB | 73 MiB |

Restarting also clears caches, so the old and new process measurements do not isolate
the savings from a code change or prove a long-running leak is gone. Repeated menu
load/unload cycles in an isolated 20-cycle fixture levelled off after warming.

An isolated GPU render with a synthetic 1,000-option dropdown using one font created
7 option rows after virtualization instead of 1,000. Its process PSS fell from about
171 MiB to 73 MiB. This exercises the large-list case; it is not the normal idle saving
for a font picker with only a few installed families.

## Fonts

The interface font is mapped into the process, so its file size lands in the numbers. Each
JetBrainsMono Nerd Font face is about 2.6 MB; each IosevkaTerm Nerd Font face is about
14.5 MB. With three weights loaded that is roughly 9 MB PSS and 37 MB RSS between them.
The font picker loads previews as they scroll into view, so opening it does not immediately
load every installed family.

## Animation driver

Silere defaults to Qt's elapsed-time animation driver. Qt otherwise moves regular QML
animations to a roughly 16 ms timer when the bar and a popup are visible as separate
windows, making a high-refresh display look like 60 Hz. Launch with
`QSG_USE_SIMPLE_ANIMATION_DRIVER=0` to compare or work around a driver-specific issue.

## Cava

Cava is the main optional CPU cost, and only while the visualizer is on screen. Silere
creates its own temporary Cava profile at runtime, so it does not alter or depend on your
personal Cava configuration.
