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
which starts the bar about 120 ms sooner with about 7 MB less memory. The menu itself compiles
three seconds after startup, so its first open is as quick as later ones. A popup that fails to
compile leaves the bar running and shows an alert. Menu and popup instances unload after closing. The first open also loads code, font and
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

## Optional tuning

**Two settings for the user service save about 10 MB.** Neither is on by default, because they
fit one setup rather than every desktop. Add what suits you with
`systemctl --user edit silere-shell.service`:

```ini
[Service]
# fewer allocator caches: about 6 MB less at start and 7 MB less once the menu has opened
Environment=MALLOC_CONF=narenas:1,tcache:false,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0
# only if your session sets a KDE platform theme: about 4 MB less
Environment=QT_QPA_PLATFORMTHEME=
Environment=QT_QUICK_CONTROLS_STYLE=
Environment=QS_ICON_THEME=your-icon-theme
```

| Setting | The trade-off |
|---|---|
| Allocator | No difference above noise in 25 menu cycles. It suits one small process, not a heavy multithreaded one. |
| KDE theme off | The shell draws its own UI, and apps it opens go through the compositor and keep their theme. The icon theme becomes a fixed name here, so change it if you change your theme. |

## Animation driver

Keep Awake uses an input-free overlay window so it keeps receiving frame callbacks
even when other windows cover the desktop.

Silere defaults to Qt's elapsed-time animation driver. Qt otherwise moves regular QML
animations to a roughly 16 ms timer when the bar and a popup are visible as separate
windows, making a high-refresh display look like 60 Hz. Launch with
`QSG_USE_SIMPLE_ANIMATION_DRIVER=0` to compare or work around a driver-specific issue.

## Visualizer and Cava

The visualizer is the main optional CPU cost, and only while it is on screen and music plays.
Drawing it costs the shell more than Cava costs to listen. Measured in a nested 1920x1200 session at
scale 1.25 with audio playing, as percent of one core for the shell plus Cava:

| Visualizer | Shell | Cava |
|---|---|---|
| Off | 0.1 | 0 |
| Media position, Wave: Eco / Balanced / Smooth | 3.0 / 4.6 / 5.1 | 0.8 / 1.1 / 1.1 |
| Media position, Balanced: Bars / Pulse | 3.5 / 2.3 | 0.7 / 0.6 |
| Center position, Wave, Balanced | 5.3 | 1.1 |
| Underline position, Wave, Balanced | 8.2 | 1.2 |

The underline position traces a curve across the whole bar each frame, so it costs about twice
the others. A larger display or a higher scale raises every row. Pulse at Eco is the
lightest choice that still moves.

Silere creates its own temporary Cava profile at runtime, so it does not alter or depend on your
personal Cava configuration.

Cava stays asleep through a pause of up to eight seconds, so resuming does not restart it
and its gain does not start over. A longer pause, idle or a fullscreen window stops it.
On battery it runs at the Eco preset whatever preset is chosen.
