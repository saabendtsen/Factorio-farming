# Field state and visuals prototype

> **Throwaway prototype.** This harness answers a feasibility question; it is not production mod architecture.

## Question

Can compressed strip intervals represent coherent, interrupted, resumed, overlapping, and fragmented work through 1,024 × 1,024 fields more effectively than packed 32 × 32 chunks, and should completed-field visuals use batched tiles or compressed rendering ranges at roughly 1 million and 10 million logical cells?

## Run

From this directory in PowerShell:

```powershell
.\run-benchmarks.ps1
```

Use `-Cases ranges-coherent-64` for a smoke case. The runner uses timestamped isolated configs, mods, saves, and script output below `%LOCALAPPDATA%\FactorioFarmingSpike2`; personal Factorio saves and mods are not read or changed.

## Scenarios

- Range and packed state at 64², 256², and 1,024².
- Coherent completion with interruption, resume, and overlap.
- Highly fragmented two-cells-on/two-cells-off completion with the same overlap checks.
- Batched cultivated tiles at one and ten 1,024² fields.
- One compressed render rectangle per completed strip at the same logical scales.
- Projection, restoration, save size, and map-load timing.

The visual benchmark intentionally stacks separate 1,024² fields for the 10-million-cell case, preserving the project's maximum individual field size.

## Result on Factorio 2.1.14

The canonical Windows run is preserved in `results/factorio-2.1.14-windows.csv`. Every interruption/resume and overlap invariant passed, and every visual case saved, loaded, and restored successfully.

### State

| 1,024² pattern | Representation | Build time | Stored units | Save size | Load time |
|---|---|---:|---:|---:|---:|
| Coherent/full | Ranges | 5.06 ms | 1,024 ranges | 0.746 MiB | 90 ms |
| Coherent/full | Packed | 799.38 ms | 128 KiB payload | 0.747 MiB | 98 ms |
| Fragmented/half | Ranges | 41,081.02 ms | 262,144 ranges | 1.362 MiB | 98 ms |
| Fragmented/half | Packed | 710.12 ms | 128 KiB payload | 0.747 MiB | 106 ms |

The general range insertion intentionally merges arbitrary overlaps and therefore exposes the nonlinear failure mode when every second two-tile run remains separate. Generated coherent lanes stay compact and fast; heavily fragmented chunks do not.

### Visuals

| Logical cells | Projection | Project time | Restore time | Projected save | Load time |
|---:|---|---:|---:|---:|---:|
| 1,048,576 | 786,432 tiles | 3,815.65 ms | 1,880.77 ms | 0.798 MiB | 113 ms |
| 1,048,576 | 1,024 render ranges | 4.54 ms | 0.78 ms | 0.840 MiB | 118 ms |
| 10,485,760 | 7,864,320 tiles | 37,079.62 ms | 18,740.51 ms | 1.391 MiB | 466 ms |
| 10,485,760 | 10,240 render ranges | 36.10 ms | 11.41 ms | 1.770 MiB | 452 ms |

**Verdict: GO with a hybrid architecture.** Keep canonical strip intervals for coherent field work. Promote only chunks whose range fragmentation crosses a measured threshold to packed bitmaps. Use compressed render ranges for rapidly changing progress and debug overlays. Batched tiles remain viable for durable ground appearance only when dirty work is bounded and amortized across ticks; never project or restore a whole large field synchronously as this harness does for measurement.

Save compression makes coherent ranges and packed strings look similar in small isolated saves, so save size alone must not choose the authoritative representation. The operation-time and record-count divergence is decisive.
