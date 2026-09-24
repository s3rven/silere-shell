# Performance

Background work only runs when it has something to do. CPU sits near zero when nothing is
happening and rises with what is on screen: a playing track costs about four times idle,
and the media visualizer costs more than everything else combined. Once the session goes
idle, or the bar steps aside for the compositor overview, every animation stops on its own
until you come back.

## Reference numbers

Silere holds two steady states.

| State | PSS | What it is |
|---|---|---|
| cold | ~82 MB | Freshly started, menu never opened. Only the bar has drawn. |
| warm | ~93 MB | The same session after the menu has been opened once. |

Both hold across a day of uptime. Warm is the number to quote.

The gap is what the first menu open leaves loaded: its compiled code and caches. The panel
itself is released a moment after it closes. The gap is bounded: across more than 30 open and close cycles, PSS peaked between
164 and 170 MB and returned to its warm figure once idle, while open file descriptors and threads
settled rather than climbing.

An empty Quickshell panel doing nothing measured about **57 MB PSS** on the same machine,
so a large part of even the cold number is the Qt and GPU driver floor rather than Silere.
On an AMD system Mesa's `radeonsi` driver and the LLVM shader compiler behind it account
for about 11 MB PSS of that floor.

Read PSS, not RSS. The same session reads 181-195 MB RSS, most of the difference being
shared Qt, Mesa and font pages other processes already pay for.

Measure with nothing else running. A second Quickshell process maps the same Qt and driver
pages and moves them out of this one's private total: 7.0 MB PSS and 6.6 MB USS per extra
instance on this machine, returned in full once it exits. Neither figure is comparable
across runs without that count, so the report names it when it is not zero. A crashed
Quickshell leaves its crash reporter behind, so check for strays before quoting a number.

Results vary with hardware, drivers, fonts, and which widgets you enable. The report names
the widgets that were drawing; rows measured on different sets do not compare. Measure your
own checkout:

```bash
bash scripts/bench.sh 30            # as-found
bash scripts/bench.sh 30 --warm     # after one menu cycle
```

The number is how many seconds to sample. Thirty is the shortest window worth quoting —
a session that measures 0% CPU over 30 seconds can read several percent over 2. The report
tracks open file descriptors too, so a leak shows up as a climbing number while everything
else stays flat.

Read the `per-second` line before the `cpu` line. The average folds a keystroke or a menu
open into the idle figure; the median does not:

```
cpu:        2.6% main / 2.6% tree
per-second: median 0.0%, worst 15.0% (noisy)
```

That session was asleep for most of its seconds, and 2.6% describes the one second it was
not. Quote the median.

`steady` and `noisy` say whether the average represents the sample, not whether the
session was idle. A sustained load reads `steady` at any level. For an idle figure the
median has to be near zero as well.

Per-release numbers and the machines they came from:
[`perf-history.md`](perf-history.md).

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
