# Performance

The visualizer, animations and system readings pause when the session goes idle.
Hidden menus and popups unload their content after closing.

## Reference numbers

These are the 1.5.0 release measurements on reference machine A in
[performance history](perf-history.md), not a memory limit for the current checkout.

| State | PSS | What it is |
|---|---|---|
| cold | ~93 MB | Freshly started, menu never opened. Only the bar has drawn. |
| warm | ~101 MB | The same session after the menu has been opened once. |

Popups and the menu's large pages compile the first time they are wanted, off the GUI thread,
which starts the bar about 120 ms sooner with about 7 MB less memory and adds about 55 ms to the
first menu open of a session. A popup that fails to compile leaves the bar running and shows an alert. Menu and popup instances unload after closing. The first open also loads code, font and
driver caches that can remain warm, so closing a menu does not return the process to its
startup footprint. An earlier empty Quickshell panel measurement was about 57 MB on the same machine.

Dropdown rows are created around the visible viewport and reused while scrolling. A
workspace hover can prepare the menu for 2.5 seconds; leaving it unused releases that
instance. The logic suite checks both lifetimes, including a thousand-option dropdown.

Remote cover downloads begin only while the menu shows its media rail or Now Playing
page, and pause during quiet idle. The bar's text and progress display needs no cover
downloads. A hidden Now Playing page also stops cover decoding, retries and unfinished
animations.

Underline event animations stop during quiet idle; a critical temperature warning
stays lit but still.

Read PSS, not RSS. `top` and `htop` show RSS, which counts shared Qt, Mesa and font pages in
full and reads about 190 to 205 MB for the same session.

Results vary with hardware, drivers, fonts and which widgets you enable. To measure your own
setup, close other heavy programs first:

```bash
bash scripts/bench.sh 30            # as you left it
bash scripts/bench.sh 30 --warm     # after one menu open and close
```

The number is how many seconds to sample. Quote the `per-second` median rather than the
`cpu` average, which folds a single keystroke or menu open into the idle figure.
CPU percentages use the measured elapsed time, including collection overhead, rather
than assuming every sample takes exactly one second. JSON reports include both the
requested `sample_seconds` and the measured `elapsed_seconds`.

## Animation driver

Keep Awake uses an input-free overlay window so it keeps receiving frame callbacks
even when other windows cover the desktop.

Silere defaults to Qt's elapsed-time animation driver. Qt otherwise moves regular QML
animations to a roughly 16 ms timer when the bar and a popup are visible as separate
windows, making a high-refresh display look like 60 Hz. Launch with
`QSG_USE_SIMPLE_ANIMATION_DRIVER=0` to compare or work around a driver-specific issue.

## Cava

Cava is the main optional CPU cost, and only while the visualizer is on screen. Silere
creates its own temporary Cava profile at runtime, so it does not alter or depend on your
personal Cava configuration.

Cava stays asleep through a pause of up to eight seconds, so resuming does not restart it
and its gain does not start over. A longer pause, idle or a fullscreen window stops it.
On battery it runs at the Eco preset whatever preset is chosen.
