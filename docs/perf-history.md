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

A dash means that release was not measured.
