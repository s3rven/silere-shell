# Performance history

One row per release, so a regression shows as a number that moved.

Rows compare only within one reference machine and one state.

## States

| State | Meaning |
|---|---|
| cold | Freshly restarted, menu never opened. Only the bar has drawn. |
| warm | The same session after one menu open and close. |

The menu builds its pages on first open and holds them for the life of the process. The
retention is bounded; repeated opens do not grow it. Warm is the state a session spends
its day in.

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

0.9.0 was sampled one commit past the tag, with `fontFamily` set to `IosevkaTerm Nerd
Font`. That font costs about 9 MB PSS over the JetBrainsMono Nerd Font default, so the
drop to 1.0.0 is about 9 MB smaller than the two rows read.

While the menu was cycled repeatedly on that run, PSS peaked between 164 and 170 MB, file
descriptors reached 59, and threads settled at 41-42. All three came back down once the
session went idle again.

The two rows were sampled under different machine load, so their CPU figures are not
comparable with each other. Take a matched pair on a quiet machine to compare states.

## Recording a row

```bash
systemctl --user restart silere-shell.service
sleep 30
bash scripts/bench.sh 30 --label 0.9.0            # cold
bash scripts/bench.sh 30 --warm --label 0.9.0     # warm
```

The restart is what makes the cold row cold. Without it `bench.sh` reports the state as
`as-found`.

`--json` writes the same fields plus CPU model, kernel and Quickshell version:

```bash
bash scripts/bench.sh 30 --warm --json --label 0.9.0 >> /tmp/silere-perf.jsonl
```

Thirty seconds is the shortest window worth quoting: a session that reads 0% over 30
seconds can read several percent over 2.

Only record a run the report calls `steady` and whose per-second median is near zero.
`noisy` means input landed mid-sample; a `steady` run with a high median means the session
was busy throughout. Neither is an idle row.

Both rows go in against the reference letter the numbers came from. A few MB between
releases is font and driver noise. Tens of MB, a descriptor count that no longer settles,
or a thread count past the core count is a regression.
