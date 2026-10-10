# Performance history

One row per release, so a regression shows as a number that moved.

Rows compare only within one reference machine and one state.

## States

| State | Meaning |
|---|---|
| cold | Freshly restarted, menu never opened. Only the bar has drawn. |
| warm | The same session after one menu open and close. |

The menu releases its page instances after closing. Code, font and driver caches can stay
warm across opens. Warm is the state a session spends its day in.

## Reference machines

| Ref | CPU | Rendering GPU | Kernel | Quickshell | Qt |
|---|---|---|---|---|---|
| A | AMD Ryzen 7 8845HS, 16T | Radeon 780M iGPU, 2560x1600@240 | 7.2.0-cachyos | 0.3.1 | 6.11.2 |

Hardware not already listed takes a new letter.

## Recorded runs

| Version | Date | Ref | State | PSS | RSS avg | CPU | Threads | FDs |
|---|---|---|---|---|---|---|---|---|
| 0.9.0 | 2026-09-01 | A | cold | 142 MB | 271 MB | 1.4% | 31 | 51 |
| 0.9.0 | 2026-09-01 | A | warm | 154 MB | 292 MB | 3.3% | 42 | 52 |
| 1.0.0 | 2026-09-07 | A | cold | 87 MB | 179 MB | 0.1% | 21 | 46 |
| 1.0.0 | 2026-09-07 | A | warm | 96 MB | 191 MB | 0.0% | 23 | 47 |
| 1.1.0 | 2026-09-17 | A | cold | 82 MB | 181 MB | 0.0% | 21 | 50 |
| 1.1.0 | 2026-09-17 | A | warm | 93 MB | 195 MB | 0.0% | 22 | 50 |
| 1.1.1 | 2026-09-17 | A | cold | — | — | — | — | — |
| 1.1.1 | 2026-09-17 | A | warm | — | — | — | — | — |
| 1.2.0 | 2026-09-27 | A | cold | 88 MB | 177 MB | 0.1% | 21 | 52 |
| 1.2.0 | 2026-09-27 | A | warm | 96 MB | 186 MB | 0.2% | 21 | 52 |
| 1.3.0 | 2026-10-05 | A | cold | 83 MB | 174 MB | 0.4% | 21 | 50 |
| 1.3.0 | 2026-10-05 | A | warm | 91 MB | 184 MB | 0.5% | 21 | 50 |
| 1.4.0 | 2026-10-09 | A | cold | 91 MB | 177 MB | 1.0% | 21 | 50 |
| 1.4.0 | 2026-10-09 | A | warm | 100 MB | 188 MB | 0.8% | 21 | 50 |
| 1.4.1 | 2026-10-10 | A | cold | 98 MB | 185 MB | 0.2% | 26 | 54 |
| 1.4.1 | 2026-10-10 | A | warm | 106 MB | 193 MB | 0.0% | 27 | 54 |

A dash means that release was not measured.

The 1.4.0 runs use the same reference-A hardware with kernel `7.2.9-1-cachyos`,
Quickshell 0.3.1, Qt 6.12.0, and the display at 60 Hz / 125% scale. Earlier rows
used the environment listed above; this is not a controlled comparison of code changes
alone. Both 30-second samples were classified as steady, with a per-second CPU median
of 1.0% of one core, 21 threads and 50 file descriptors. The cold descriptor count stayed
flat; the warm count fell by three during its run. The visualizer
was stopped, and no second Quickshell instance was running.

Raw reports: [cold](perf/1.4.0-cold.json) · [warm](perf/1.4.0-warm.json). They were collected
from runtime commit `11ea599` while the release metadata and notes were being prepared,
so their Git description still names the preceding tag.

The 1.4.1 runs use reference-A hardware with kernel `7.2.9-2-cachyos`, Quickshell 0.3.2,
Qt 6.12.0, and the display at 60 Hz / 125% scale. Quickshell and the kernel changed since
1.4.0, so this is not a controlled comparison of code changes alone. Both 30-second samples
were steady, with a per-second CPU median of 0.0% of one core, and both descriptor counts
stayed flat. One of the extra threads is the Qt pool thread that the five-second interface
check for the VPN indicator keeps alive. The visualizer was stopped, and no second
Quickshell instance was running.

Raw reports: [cold](perf/1.4.1-cold.json) · [warm](perf/1.4.1-warm.json). They were collected
from runtime commit `d1b3154` while the release metadata and notes were being prepared.
