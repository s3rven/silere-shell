# Performance

Background work only runs when it has something to do. CPU sits near zero when nothing is
happening and rises with what is on screen: a playing track costs about four times idle,
and the media visualizer costs more than everything else combined. Once the session goes
idle, or the bar steps aside for the compositor overview, every animation stops on its own
until you come back.

## Reference numbers

| State | PSS | What it is |
|---|---|---|
| cold | ~88 MB | Freshly started, menu never opened. Only the bar has drawn. |
| warm | ~95 MB | The same session after the menu has been opened once. |

The first menu open loads code and caches that stay for the life of the process, so memory
rises once and then holds. An empty Quickshell panel measures about 57 MB on the same
machine, so much of the cold number is Qt and the GPU driver rather than Silere.

Read PSS, not RSS. `top` and `htop` show RSS, which counts shared Qt, Mesa and font pages in
full and reads about 180 to 190 MB for the same session.

Results vary with hardware, drivers, fonts and which widgets you enable. To measure your own
setup, close other heavy programs first:

```bash
bash scripts/bench.sh 30            # as you left it
bash scripts/bench.sh 30 --warm     # after one menu open and close
```

The number is how many seconds to sample. Quote the `per-second` median rather than the
`cpu` average, which folds a single keystroke or menu open into the idle figure.

## Fonts

The interface font is mapped into the process, so its file size lands in the numbers. Each
JetBrainsMono Nerd Font face is about 2.6 MB; each IosevkaTerm Nerd Font face is about
14.5 MB. With three weights loaded that is roughly 9 MB PSS and 37 MB RSS between them.

## Animation driver

Silere defaults to Qt's elapsed-time animation driver. Qt otherwise moves regular QML
animations to a roughly 16 ms timer when the bar and a popup are visible as separate
windows, making a high-refresh display look like 60 Hz. Launch with
`QSG_USE_SIMPLE_ANIMATION_DRIVER=0` to compare or work around a driver-specific issue.

## Cava

Cava is the main optional CPU cost, and only while the visualizer is on screen. Silere
creates its own temporary Cava profile at runtime, so it does not alter or depend on your
personal Cava configuration.
