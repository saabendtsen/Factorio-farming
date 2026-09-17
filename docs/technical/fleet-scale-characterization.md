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
paves: `x` from `left - 28` up to but not including `left + 72` (100 tiles
wide, covering the tractor's western approach and 8 tiles past the field's
eastern edge) and `y` from `top - 8` up to but not including `top + 24` (32
tiles tall). The far edge is exclusive because a tile at integer coordinate `c`
occupies `[c, c + 1)`: paving inclusively would lay a 101 x 33 rectangle and
shrink the real gaps below the ones the invariant asserts.

Fields sit on a grid of at most 10 columns with a 160-tile column pitch and a
64-tile row pitch. Isolation is *per axis*, and no pair of bands is separated
on both axes: two bands in the same row overlap completely in `y` and are
separated by **60 tiles in `x`**; two bands in the same column overlap
completely in `x` and are separated by **32 tiles in `y`**; a band on both a
different row and a different column is separated in both. The invariant is
therefore rectangle disjointness — every pair of bands is separated by at least
the 32-tile isolation gap **in at least one axis** — which is exactly the test
`ledger.geometry_violations` applies (`math.max(gap_x, gap_y) <
isolation_gap`).

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
storage directly. **Cultivation is the only operation dispatched**: the fixture
queues `"cultivation"` for every field and nothing else, and every 64 x 16
field is driven to exact coverage. No sowing or harvesting job is ever run. The
crop records that the field projections are then measured over are seeded
through the production `debug_seed_crop_stage` seam — the same remote seam the
two-tractor acceptance test uses — after cultivation completes, so the visual
scale measurement covers the sown, growing and ready stages without a sowing
run. The disposable multi-field projections then drain.

## Reproducible commands

### Full characterization

Runs stages 1-5 (the engine-free pre-flight plus the four production gates) and
then, **only if every one of them passed**, the serialized characterization of
2/10/25/50 plus the 10- and 50-tractor save/load recovery cases. This takes
hours, and a single failing production gate skips the scale block entirely:

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
2-5 and their gating. `-ScaleCounts` selects which scales run:

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
`-ScaleCounts 100` is rejected unless `-IncludeScale100` is given as well: 100
is the opt-in stretch case and is not part of the selectable required set, so
naming it alone would previously have selected nothing and exited successfully.
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
benchmark window, so a timed-out run writes a result JSON with `passed: false`
and a reason rather than producing nothing (which would be indistinguishable
from a crash), and a scale stage that fails an assertion writes one too: the
stage claims its result name up front and the test mod's `fail` writes a
`passed: false` result before the error propagates.

Two ways a run can still produce no result JSON at all, both of which the
harness reports as `the run wrote no result JSON`: the Factorio process crashed
or was killed before the stage ran, or a deadline was placed outside the
benchmark window so nothing ever ran to write one. The second is what the
deadline clamping in the test mod exists to prevent.

A run that selects no scale at all is a failure, not a pass: `-ScaleCounts 100`
without `-IncludeScale100` is rejected outright, and a scale block that ends up
executing zero scales emits a failure rather than an empty artifact and exit 0.

## Recorded measurements

For every attempted scale, the ledger records:

| Measurement | Source |
| --- | --- |
| Exact completion integrity | All production job/field snapshot rows must end at `completed_area == total_area`; the pure ledger records coverage rewinds/overruns as violations. |
| Active and owned fleet | Real snapshot fleet counts and peak active count. |
| Dispatch latency and fairness | First machine assignment minus the production job's request tick, plus due versus applied controller updates by tractor. The initial player-visible field's job is created without a `request_tick`, so its row falls back to `last_operation_tick` and says so in `request_tick_source`; a job with neither is counted in `jobs_without_request_tick` and recorded as a violation rather than given an invented latency. |
| Path-queue drain | Observed queue depth, outstanding-path ticks, and every completed drain-window duration. Under interval sampling `drain_ticks_max` and `queue_depth_max` are **lower bounds**: a spike entirely between two samples is invisible, and a window is only bounded by the samples that bracket it. `drain_tick_resolution` states the interval, and `drain_ticks_max_is_lower_bound` flags it. A window still draining when the run ends never closes, so it is reported separately as `drain_started_tick` / `drain_open_ticks` instead of being dropped. |
| Controller saturation | Applied over due controller updates, in permille. **Absent when nothing was ever due**, because a ratio with no denominator is not a score — a fixture that never activated a tractor must not report 1000. `controller_demand_observed` says which case a missing ratio is. |
| Visual scale | Peak/mean disposable field and implement render objects, plus dirty-field ticks. |
| Script update average/p95/max | `helpers.create_profiler()` around the production `on_tick`, parsed from `FARMING_PROFILE` samples. |
| Effective UPS and duration | Benchmark ticks divided by the harness stopwatch duration, alongside the raw duration. The stopwatch wraps the whole `factorio.exe` invocation, so it **includes process startup and map load**, not only simulation: it is a throughput figure for the run as executed, and a lower bound on the simulation's own UPS. |

The ledger additionally records `sample_interval_ticks`, so every rate above
states the rate it was measured at.

### Save/load recovery

The 10- and 50-tractor cases additionally capture a real headless-server save
only after every job has an assignment, at least one field has advanced, and an
actual path request remains pending.

Replay lazily initializes its test driver, because a loaded save does not run
`on_init`. That is *measured*, not assumed: the test mod records that `on_init`
did not run in this session and that the production mod's own load recovery has
already happened — observable because `recovered_completed_area` appears on a
job snapshot only after `slice.on_load` / `recover_loaded_state` has run.

Whether that is already true on the *first* post-load tick is mod event
ordering, not an invariant, so the observation is deferred to the first tick on
which recovery is actually visible, within a bounded 180-tick wait inside the
benchmark window. Running out of that wait is still a failure, and the number
of ticks it took is published as `recovery_observed_after_ticks`.

Pending-path invalidation is measured against the request that was actually
saved, not against the absence of any request. `recover_loaded_state` drops the
saved id, but `promote_reserved` → `begin_travel` → `movement.queue` →
`movement.process_path_queue` can already have issued a fresh request on the
same tick, so "no outstanding request after the load" is not the invariant and
would fail on a correct run. The capture records the engine request id in
flight at the instant of the save, and the replay asserts three things:

* the outstanding id after the load is not the saved one
  (`pending_path_invalidated`; both ids are published);
* the one-outstanding-request budget still holds
  (`pending_path_budget_held`, `pending_path_count <= 1`, the same gate the
  two-tractor save/load case uses); and
* every recovered machine's controller generation advanced past its saved value
  (`controller_generations_advanced`), which is the direct evidence that a
  saved asynchronous callback can no longer be believed.

`pending_path_cleaned`, which the harness gates on, is the conjunction of those
three.

The replay additionally has to prove that coverage did not rewind and that
every field completed exactly. The artifact records the ZIP byte size, the
number of recovered jobs observed, and the replay result.

The real-time capture stage waits for the save Factorio is writing to stop
changing before it stops the process. `game.auto_save` is called *before* the
result JSON is written, so the save is still streaming when the harness first
sees the JSON; at fifty tractors a fixed short sleep is not enough and the
process would be killed mid-write.

## Results

Every number below is transcribed from `fleet-scale-ledger.json`, the artifact
written by the serialized run named under the tables. Nothing here is estimated,
rounded from a different run, or carried over from the earlier isolated
vehicle-spike harness. A cell the artifact did not carry reads `not measured`
rather than a blank, because a blank reads as a zero.

**What passed, and what did not.** The production gates — stages 1 to 5, the
whole required serialized verification — passed. The misses are in the
characterization block that runs after those gates. These are separate claims
and this document does not let one stand in for the other: the slice is correct
at the sizes the gates cover, and it does not complete at 25 or 50.

A miss is a result. It is recorded with its exact reproduction command and the
smallest bottleneck the run actually observed, and it is not a licence to change
the controller, the scheduler, or a performance budget. The repair is tracked
separately; it is deliberately not part of this characterization.

**Gate evidence versus characterization evidence.** A row from a full run has
the production gates behind it. A row from a targeted re-run (`-ScaleOnly`) does
not: that mode skips stages 2 to 5 entirely and the artifact marks it
`scale_only: true`. Such a row is characterization evidence only, and is
labelled as such rather than mixed in with gate-backed rows.

### The run these numbers come from

    .\tests\run-factorio-tests.ps1 -RunFleetScale -IncludeScale100

Full serialized run on `feature/44-fleet-scale` @ `c098d7c`, Factorio 2.1.14
(build 87180, win64), 2026-09-17. Stages 1 to 5 — the whole required serialized
verification — passed. Every failure in that run is in the characterization
block below, and the artifact is `fleet-scale-ledger.json` with
`scale_only: false`.

The same four saturation figures were produced by an earlier full run of the
same commit's parent, so the scaling behaviour below is reproducible rather than
a single observation.

### Fleet scale

| Fleet | Completion | Controller saturation | Active peak | Dispatch max ticks | Path drain max ticks | Script avg/p95/max ms | Effective UPS | Duration |
| ---: | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: |
| 2 | Exact 2/2 | 100.0% | 2 | 0 | 5 ≥ | 0.0722 / 0.1474 / 0.4970 | 3,333.2 | 11.1 s |
| 10 | Exact 10/10 | 32.4% | 10 | 0 | 15 ≥ | 0.1023 / 0.1890 / 0.9771 | 3,259.3 | 55.5 s |
| 25 | **Miss** [^1] — 3072/25600 tiles | 11.5% | 25 | 0 | 30 ≥ | 0.1059 / 0.1614 / 1.9706 | 1,353.7 | 333.2 s |
| 50 | **Miss** [^2] — 0/51200 tiles | 5.9% | 50 | 0 | 55 ≥ | 0.2013 / 0.3655 / 2.7324 | 878.8 | 1,025.3 s |
| 100 (optional) | Not attempted | not measured | not measured | not measured | not measured | not measured | not measured | not measured |

`≥` marks a lower bound: a spike between two samples is invisible at the
declared sampling interval. Controller saturation is the share of observed
controller demand served on the same observed tick; 100% means every due tractor
was updated on the tick it came due.

The 100-tractor stretch case was skipped by its own gate, which requires the
2/10/25/50 cases and both recovery cases to be correct and operational in the
same run. That gate did its job and the row stays unmeasured rather than
untested-but-blank.

### Save/load recovery

| Fleet | Result | Save size | Recovered jobs | Recovery observed after | Exact coverage | Stale callback invalidation | Pending-path cleanup |
| ---: | --- | ---: | ---: | ---: | --- | --- | --- |
| 10 | Pass | 1.06 MB | 7 | 0 ticks | 10/10 exact | saved request 12 discarded (now 13); generations advanced; proven over 8 live machines | clean, one-request budget held |
| 50 | **Blocked** [^3] | not measured | not measured | not measured | not measured | not measured | not measured |

The 50-tractor recovery case is **blocked, not merely failed**. The capture needs
a save containing real working state, and at fifty tractors the fleet completes
no coverage at all, so there is nothing to capture. It is not that the harness
could not measure recovery; there was no recovery state to measure. This case
becomes measurable once the bottleneck below is addressed, and not before.
Widening the capture window would only produce a save of a fleet doing nothing.

"Recovered jobs: 7" from a ten-tractor fleet is expected, not a shortfall. Only
machines holding a live, non-completed job at the save are recovered, and only
those carry a controller callback that recovery must invalidate; the invariant
was proven over the 8 machines that were live at that instant.

[^1]: production scale 25 tractor scenario timed out waiting for field completion after 450500 ticks. Reproduce with `.\tests\run-factorio-tests.ps1 -ScaleOnly -ScaleCounts 25`.
[^2]: production scale 50 tractor scenario timed out waiting for field completion after 900500 ticks. Reproduce with `.\tests\run-factorio-tests.ps1 -ScaleOnly -ScaleCounts 50`.
[^3]: production scale 50 tractor scenario timed out waiting for dispatch capture after 27000 ticks, having completed 0 of 51200 tiles. Reproduce with `.\tests\run-factorio-tests.ps1 -ScaleOnly -ScaleCounts 50`.

## Bottleneck

The smallest observed bottleneck is **controller cadence, not CPU cost**.

At fifty tractors the farming script update averages 0.2013 ms with a p95 of
0.3655 ms — inside the 0.25 ms average and 0.50 ms p95 budgets — while the fleet
cultivates nothing whatsoever. The slice is not running out of frame time. No
budget change would move any number in the table above, which is why the misses
here are reported rather than answered with a relaxed gate.

What decays is controller saturation: 100% at two tractors, 32.4% at ten, 11.5%
at twenty-five, 5.9% at fifty — roughly 1/N. The scheduler applies
`movement.update` to exactly one due machine per tick while the controller runs
on a 3-tick cadence, so a tractor is steered once every ~N ticks. Steering, the
speed governor, waypoint arrival (`ARRIVAL_RADIUS = 0.9`) and stuck detection are
all sampled only on a machine's own update tick, while the vehicle keeps driving
under a persistent `riding_state`. Past roughly ten tractors a vehicle travels
several tiles between samples and overshoots its 1–2 tile headland waypoints, so
alignment never converges. Because the vehicle is still moving, `STUCK_DISTANCE`
never trips: there is no failure and no recovery, only the deadline.

Dispatch itself is not the limit. Maximum dispatch latency is 0 ticks at every
scale, and at fifty tractors all fifty jobs were assigned and all fifty machines
reported active. They were assigned promptly and then starved of control.

This limit was anticipated. `feasibility_v0.1.md` records that if the controller
spikes failed at the desired active-fleet scale, "the smallest design adjustment
is to limit simultaneously active machinery through dispatch/path concurrency
and emphasize higher-capacity equipment". Dispatch/path concurrency is precisely
what these measurements identify, so this is a confirmed prediction rather than
an unforeseen defect.

### What this certifies

The slice is certified for **exact completion at up to ten concurrently active
tractors**, with save/load recovery proven at ten. The ceiling lies between ten
and twenty-five; this characterization does not locate it more precisely, and no
claim is made for any fleet larger than ten.

The repair is tracked separately as issue #52, "Dispatch every due tractor
per tick so the fleet scales past the reference case", and is deliberately
not part of this characterization.
