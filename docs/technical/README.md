# Technical feasibility

The [Factorio 2.x technical feasibility baseline](feasibility_v0.1.md) is the canonical technical assessment for the current design.

The investigation found no fundamental API blocker. [Spike 1 validated the minimal custom vehicle controller](spike-1-vehicle-controller-results.md) through 300 active vehicles, with a conditional GO and a requirement to rate-limit path requests. [Spike 2 validated a hybrid field-state and visual architecture](spike-2-field-state-visuals-results.md): ranges for coherent work, packed fragmented chunks, compressed render overlays, and bounded tile batches.

Both go/no-go spikes required before gameplay implementation are complete.

The [first production vertical slice](first-production-vertical-slice.md) fixes the next implementation milestone: one selected field, one tractor, physical travel, one persistent and resumable lane, and a disposable progress projection.

The [whole-field cultivation extension](whole-field-cultivation.md) records the next accepted production increment: four exact lanes, generated physical headland turns, full persistent coverage, and updated save/load and performance evidence.

The [production fleet scale characterization](fleet-scale-characterization.md) records the measured multi-field evidence ledger for 2, 10, 25, and 50 concurrently active tractors, with a gated 100-tractor stretch case. Exact completion and save/load recovery hold at 10 tractors; 25 and 50 miss, and the 100-tractor case was skipped by its own gate. The limit is controller service rather than CPU cost: at 50 tractors the farming script update stays inside its 0.25 ms / 0.50 ms budgets while the fleet completes no coverage at all, so no budget change would help. The shortfall is also uneven rather than thin -- at 25 tractors ten machines received no controller update at all -- so it is a selection problem, not only a budget one. The slice is certified for exact completion at up to 10 concurrently active tractors; the repair is tracked as issue #52.

See the repository [task tracker](../../TASKS.md) for current scope and status.
