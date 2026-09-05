# Production fleet scale characterization

This ledger characterizes the production farming scheduler beyond the
two-tractor acceptance case. It is deliberately evidence-oriented: an observed
miss records the exact scenario and bottleneck without changing a performance
budget or claiming a supported fleet limit.

> **Status: a measurement design, not a measured result.** Nothing here is a
> delivered fleet-size claim. The results table at the end of this document is
> a shape waiting to be filled in from a serialized run; every row is still
> pending, and no scale beyond the two-tractor acceptance case currently has a
> recorded passing measurement.

## Scenario boundary

The harness builds 2, 10, 25, and 50 concurrently active `farming-tractor`
machines. Each tractor receives its own non-overlapping 64 x 16 field and a
dedicated west-side approach corridor. A 100-tractor scenario is an explicit
stretch case: it runs only after all four required cases and both recovery
cases passed in the same serialized invocation.

### Field isolation

Isolation is a constraint, not a convention: shared-road congestion and traffic
coordination are out of scope, so a fixture whose corridors touched would be
measuring something else. The layout is computed by `ledger.geometry` in
`scripts/scale_ledger.lua`, and its non-overlap invariant is asserted by
`tests/factorio-farming-tests/scale_ledger_spec.lua` — which runs both inside
Factorio and in the engine-free pre-flight stage — rather than being claimed in
prose here.

Each field's *prepared band* is the tile rectangle the fixture generates and
paves: `x` from `left - 28` to `left + 72` (100 tiles wide, covering the
tractor's western approach and 8 tiles past the field's eastern edge) and `y`
from `top - 8` to `top + 24` (32 tiles tall). Fields sit on a grid of at most
10 columns with a 160-tile column pitch and a 64-tile row pitch, so adjacent
prepared bands are separated by **60 tiles horizontally and 32 tiles
vertically** — at least the 32-tile isolation gap on both axes.

The finite surface size is derived from the columns, rows and strides actually
used, with a 64-tile margin beyond the outermost band. That margin clears the
16-tile `find_non_colliding_position` search radius the production code uses
when spawning a tractor, so no spawn search can reach the map edge or a
neighbouring band. Every chunk a prepared band touches is generated explicitly,
rather than relying on `set_tiles` to generate chunks as a side effect.

### Sampling rate

Reading the production snapshot walks every machine, field, job and queued job,
so sampling it once per tick would make the measurement itself quadratic in the
fleet size — roughly 156x the two-tractor cost at 25 tractors and 625x at 50.
Scale runs therefore sample every **5 ticks** and record that interval in the
emitted ledger, which scales its per-tick counters by it so drain windows,
state occupancy and controller saturation keep the same meaning at either rate.
Ratios such as `controller_saturation_permille` are unaffected: numerator and
denominator are sampled the same way.

Five is chosen because it is coprime with the 3-tick movement cadence. A
machine is due when `(tick + machine_id) % 3 == 0`, so an interval sharing a
factor with the cadence would only ever observe one residue class of machine
ids as due, and would fabricate the fairness result. Real-time save-capture
runs still sample every tick, because they have to catch a genuinely
outstanding path request at the instant they save.

The scenarios use the public test seams already used by production acceptance:
`debug_setup`, `debug_add_tractor`, `debug_queue_field`,
`debug_seed_crop_stage`, and `snapshot`. They never write the mod's durable
storage directly. Cultivation finishes every 64 x 16 field exactly, then a
real sowing commit creates a compact crop record on every field and the
disposable multi-field projections drain.

## Reproducible commands

### Full characterization

Runs stages 0-4 (the production gates) and then, **only if every one of them
passed**, the serialized characterization of 2/10/25/50 plus the 10- and
50-tractor save/load recovery cases. This takes hours, and a single failing
production gate skips the scale block entirely:

```powershell
.\tests\run-factorio-tests.ps1 -RunFleetScale
```

Only after that command has passed may the optional stretch case be attempted.
The 100-tractor run is additionally gated inside the invocation: it is skipped
unless 2/10/25/50 and both recovery cases were correct in that same run.

```powershell
.\tests\run-factorio-tests.ps1 -RunFleetScale -IncludeScale100
```

### Re-running a single scale

Because the harness wipes its run directory on every invocation and the scale
block is gated on the whole suite, re-running one scale needs `-ScaleOnly`,
which stages the mods and runs *only* the fleet-scale block, skipping stages
1-4 and their gating. `-ScaleCounts` selects which scales run:

```powershell
# just the 25-tractor benchmark, no production gates, no recovery runs
.\tests\run-factorio-tests.ps1 -ScaleOnly -ScaleCounts 25

# the 10-tractor benchmark plus its save/load recovery case
.\tests\run-factorio-tests.ps1 -ScaleOnly -ScaleCounts 10

# both recovery scales and their benchmarks
.\tests\run-factorio-tests.ps1 -ScaleOnly -ScaleCounts 10,50
```

`-ScaleOnly` implies `-RunFleetScale`. A recovery case runs for each selected
scale that has one (10 and 50); selecting only 25 therefore runs no recovery.
Results from a `-ScaleOnly` run are marked `scale_only: true` in the artifact
and are **not** evidence that the production gates are green — they never ran.

### Artifact

The harness writes
`%LOCALAPPDATA%\FactorioFarmingProductionTests\current\write-data\script-output\factorio-farming-tests\fleet-scale-ledger.json`.

It contains one row per **attempted** scale and recovery run — not only the
successful ones. A row that missed carries `passed: false`, a `reason`, and the
ledger the test mod wrote before it errored, so the bottleneck is recoverable
from the artifact. The top level also records `attempted_scales`,
`scales_passed`, `scales_failed`, `recovery_passed` and `recovery_failed`, so a
miss cannot disappear by omission. Every scale's deadline is bounded inside its
benchmark window, so a timed-out run always writes a result JSON with
`passed: false` and a reason rather than producing nothing (which would be
indistinguishable from a crash).

## Recorded measurements

For every attempted scale, the ledger records:

| Measurement | Source |
| --- | --- |
| Exact completion integrity | All production job/field snapshot rows must end at `completed_area == total_area`; the pure ledger records coverage rewinds/overruns as violations. |
| Active and owned fleet | Real snapshot fleet counts and peak active count. |
| Dispatch latency and fairness | First machine assignment minus production job request tick, plus due versus applied controller updates by tractor. |
| Path-queue drain | Observed queue depth, outstanding-path ticks, and every completed drain-window duration. |
| Visual scale | Peak/mean disposable field and implement render objects, plus dirty-field ticks. |
| Script update average/p95/max | `helpers.create_profiler()` around the production `on_tick`, parsed from `FARMING_PROFILE` samples. |
| Effective UPS and duration | Benchmark ticks divided by the harness stopwatch duration, alongside the raw duration. |

The ledger additionally records `sample_interval_ticks`, so every rate above
states the rate it was measured at.

### Save/load recovery

The 10- and 50-tractor cases additionally capture a real headless-server save
only after every job has an assignment, at least one field has advanced, and an
actual path request remains pending.

Replay lazily initializes its test driver, because a loaded save does not run
`on_init`. That is *measured*, not assumed: the test mod records, on the first
post-load tick, that `on_init` did not run in this session and that the
production mod's own load recovery has already happened — observable because
`recovered_completed_area` appears on a job snapshot only after
`slice.on_load` / `recover_loaded_state` has run. Pending-path cleanup is
measured the same way, from an observed `pending_path_count == 0` on that first
tick, even though the save was taken with a request in flight.

The replay then has to prove that all controller generations increased (saved
asynchronous callbacks are stale), coverage did not rewind, and every field
completed exactly. The artifact records the ZIP byte size, the number of
recovered jobs observed, and the replay result.

## Results

**No measured result exists yet.** No number below is invented, estimated, or
carried over from another run; every row is pending a serialized invocation of
the commands above. When that run completes, its artifact values are copied in
here. A timeout or integrity failure belongs in this table too, as a
reproducible miss with its smallest observed bottleneck — a miss is a result,
not a reason to omit the row.

| Fleet | Completion | Active peak | Dispatch max ticks | Path drain max ticks | Script avg/p95/max ms | Effective UPS | Duration | Notes |
| ---: | --- | ---: | ---: | ---: | --- | ---: | ---: | --- |
| 2 | Awaiting serialized run | — | — | — | — | — | — | — |
| 10 | Awaiting serialized run | — | — | — | — | — | — | Includes save/load |
| 25 | Awaiting serialized run | — | — | — | — | — | — | — |
| 50 | Awaiting serialized run | — | — | — | — | — | — | Includes save/load |
| 100 (optional) | Not attempted until the required cases pass | — | — | — | — | — | — | Stretch only |
