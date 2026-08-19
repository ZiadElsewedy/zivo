# M7 — Performance results (fill this in from the traces)

> Device: __________________  OS: __________  ProMotion/120Hz? __________
> Flutter: 3.44.2 · build: --profile

## Pass 1 — Cold start (from start_up_info.json, microseconds → ms)

| Run          | timeToFrameworkInit | timeToFirstFrame | timeToFirstFrameRasterized |
|--------------|---------------------|------------------|----------------------------|
| Cold (1st)   |                     |                  |                            |
| Warm (2nd)   |                     |                  |                            |
| Warm (3rd)   |                     |                  |                            |

Rough bar: first frame < ~2000ms cold on a mid device is fine; > ~3000ms is a
problem worth fixing (prime suspect: serial Firebase + App Check awaits in
`lib/main.dart`).

## Pass 2 — Jank (from the DevTools timeline export + overlay screenshots)

| Screen + gesture            | Worst UI frame (ms) | Worst raster frame (ms) | Notes |
|-----------------------------|---------------------|-------------------------|-------|
| Expenses — fast scroll      |                     |                         |       |
| Schedule — fast scroll      |                     |                         |       |
| Moments — scroll (images)   |                     |                         |       |
| Today — open / refresh      |                     |                         |       |

Budget: 16ms/frame at 60Hz, 8ms at 120Hz. Anything consistently over budget is
a candidate.

## Pass 3 — Rebuilds (from the inspector screenshots)

| Widget / screen             | Rebuild count | Expected? | Notes |
|-----------------------------|---------------|-----------|-------|
|                             |               |           |       |

## Top issues to fix (we'll fill this together, ranked)

1.
2.
3.
