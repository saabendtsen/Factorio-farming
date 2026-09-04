# Production fleet scale characterization

This ledger characterizes the production farming scheduler beyond the
two-tractor acceptance case. It is deliberately evidence-oriented: an observed
miss records the exact scenario and bottleneck without changing a performance
budget or claiming a supported fleet limit.

## Scenario boundary

The harness builds 2, 10, 25, and 50 concurrently active `farming-tractor`
machines. Each tractor receives its own non-overlapping 64 x 16 field and a
dedicated west-side approach corridor. Fields are separated by 32 or more
tiles, so the run exercises production machine/job/field collections, the
bounded native-path queue, the real car controller, authoritative cultivation
coverage, crop records, and field/implement projections without measuring
shared-road congestion or traffic coordination. A 100-tractor scenario is an
explicit stretch case: it runs only after all four required cases and both
recovery cases passed in the same serialized invocation.

The scenarios use the public test seams already used by production acceptance:
`debug_setup`, `debug_add_tractor`, `debug_queue_field`,
`debug_seed_crop_stage`, and `snapshot`. They never write the mod's durable
storage directly. Cultivation finishes every 64 x 16 field exactly, then a
real sowing commit creates a compact crop record on every field and the
disposable multi-field projections drain.

## Reproducible command

Run the normal production harness plus the serialized characterization from a
clean checkout:

```powershell
.\tests\run-factorio-tests.ps1 -RunFleetScale
```

Only after that command has passed may the optional stretch case be attempted:

```powershell
.\tests\run-factorio-tests.ps1 -RunFleetScale -IncludeScale100
```

The harness writes
`%LOCALAPPDATA%\FactorioFarmingProductionTests\current\write-data\script-output\factorio-farming-tests\fleet-scale-ledger.json`.
It contains one row per completed scale and recovery run, including the
reproducible tick allowance and host-measured duration.

## Recorded measurements

For every successful scale, the ledger records:

| Measurement | Source |
| --- | --- |
| Exact completion integrity | All production job/field snapshot rows must end at `completed_area == total_area`; the pure ledger records coverage rewinds/overruns as violations. |
| Active and owned fleet | Real snapshot fleet counts and peak active count. |
| Dispatch latency and fairness | First machine assignment minus production job request tick, plus due versus applied controller updates by tractor. |
| Path-queue drain | Observed queue depth, outstanding-path ticks, and every completed drain-window duration. |
| Visual scale | Peak/mean disposable field and implement render objects, plus dirty-field ticks. |
| Script update average/p95/max | `helpers.create_profiler()` around the production `on_tick`, parsed from `FARMING_PROFILE` samples. |
| Effective UPS and duration | Benchmark ticks divided by the harness stopwatch duration, alongside the raw duration. |

The 10- and 50-tractor cases additionally capture a real headless-server save
only after every job has an assignment, at least one field has advanced, and an
actual path request remains pending. Replay lazily initializes its test driver
(loaded saves do not run `on_init`), then must prove that all controller
generations increased (saved asynchronous callbacks are stale), coverage did
not rewind, every field completed exactly, and the captured pending path has
been cleaned up. The artifact records the ZIP byte size and replay result.

## Results

No result is pre-filled in this document. The merged characterization must add
the exact command artifact values below; a timeout or integrity failure belongs
here as a reproducible miss with its smallest observed bottleneck.

| Fleet | Completion | Active peak | Dispatch max ticks | Path drain max ticks | Script avg/p95/max ms | Effective UPS | Duration | Notes |
| ---: | --- | ---: | ---: | ---: | --- | ---: | ---: | --- |
| 2 | Pending serialized run | — | — | — | — | — | — | — |
| 10 | Pending serialized run | — | — | — | — | — | — | Includes save/load |
| 25 | Pending serialized run | — | — | — | — | — | — | — |
| 50 | Pending serialized run | — | — | — | — | — | — | Includes save/load |
| 100 (optional) | Not attempted until the required cases pass | — | — | — | — | — | — | Stretch only |
