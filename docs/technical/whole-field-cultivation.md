# Whole-field cultivation

Status: implemented and accepted

Milestone: extend the accepted one-lane production slice to one complete 64 × 16 field

## Outcome

The fixed 4-tile cultivator now completes four non-overlapping 64 × 4 lanes, reaching exactly 1,024/1,024 authoritative tiles. The field module generates the lane partition and a physical U-turn between adjacent lanes. The slice still owns one field, tractor, and job per surface; no crop or economy behavior is introduced.

The original architecture, limits, and evidence remain in [first-production-vertical-slice.md](first-production-vertical-slice.md). This document records only the production increment.

## Superseded slice behavior

The one-lane proof placed its only lane at short-axis offsets `[6, 10)`, centered on the original entrance. Whole-field cultivation replaces that test geometry with the exact partition `[0, 4)`, `[4, 8)`, `[8, 12)`, and `[12, 16)`. Four non-overlapping lanes of a fixed 4-tile implement cannot retain `[6, 10)` as one member while covering a 16-tile axis exactly. Entrance selection remains unchanged; after reaching the entrance, the tractor physically positions at the first lane start.

## Included behavior

- Four lanes partition the short field axis in deterministic top-to-bottom or left-to-right order.
- Work direction alternates on each lane, producing a serpentine traversal.
- Each of the three headland turns is a five-waypoint U-turn generated from field axis, bounds, adjacent lane centers, and active direction.
- The completed lane claim is released before the next lane is activated and claimed by the same job. At most one lane is claimed at any time.
- Pause/resume and working-state load recovery restart from the first authoritative uncovered coordinate. The next swept range begins at that coordinate, so small physical overshoot or rollback cannot skip tiles or inflate overlap. Pausing during alignment or a headland turn preserves the remaining positioning plan and resumes without committing work.
- Rendering continues to project disposable rectangles from authoritative strips. Adjacent strips with identical ranges merge, so a fully cultivated field is one progress rectangle.
- Sampled movement segments count as reaching a waypoint when they cross its arrival radius. This prevents a bounded-cadence controller from missing a waypoint between updates.

## Postponed behavior

- Crops, sowing, growth, harvesting, yield, inventories, recipes, economy, and progression.
- Multiple fields, tractors, vehicle types, implements, schedulers, priorities, and traffic coordination.
- General field dimensions, selectable lane order or entrance, polished UI, fuel, durable tile changes, and AAI integration.
- Save/load checkpoints during each individual headland turn. The established controller-phase checkpoints remain the regression gate.

## Technical boundaries

The production module structure is unchanged. `scripts/field.lua` owns lanes, headland geometry, claims, progress, and merged progress queries; `scripts/slice.lua` owns atomic lane handoff and job completion; `scripts/movement.lua` consumes generated waypoints without editing field state.

All accepted budgets remain unchanged:

| Work | Budget |
|---|---:|
| Native path requests | At most 1 per tick and 1 outstanding |
| Vehicle steering | 3-tick cadence; at most 1 controller update per tick |
| Recovery | At most 2 attempts per resume generation |
| Work commit | At most 1 swept rectangle per controller update |
| Visual rebuild | At most 8 projections per tick |
| Durable tile writes | 0 |
| Script update gate | 0.25 ms average; 0.50 ms p95 |

## Acceptance and validation

`tests\run-factorio-tests.bat` passes against Factorio 2.1.14 (build 87180, win64):

| Gate | Result |
|---|---|
| Pure geometry, lane sequence, U-turn, claims, ranges, and transitions | pass |
| Direct completion, three first-lane interruption/resume checkpoints, headland interruption/resume, destruction/replacement, visual rebuild | pass, 1,024/1,024 at tick 8,456 |
| Save/load in `reserved` | pass, completed in 3,718 ticks after load |
| Save/load in `travelling` | pass, completed in 3,746 ticks after load |
| Save/load in `working` | pass, loaded at 64 tiles and completed in 3,041 ticks |
| Save/load in `paused` | pass, loaded at 64 tiles and completed in 3,115 ticks |
| Five-minute performance run | pass |

The profiler method is unchanged: `helpers.create_profiler()` measures the farming mod's `on_tick`, with each sample stopped before logging. The harness computes average and nearest-rank p95 from 18,000 samples.

| Window | Ticks | Average | p95 | Budget |
|---|---:|---:|---:|---|
| Whole five-minute run | 18,000 | 0.0114 ms | 0.0329 ms | — |
| Ticks with an active job | 3,708 | 0.0219 ms | 0.0793 ms | 0.25 ms average; 0.50 ms p95 |

The reference field completed at tick 4,390 of the benchmark replay. No controller, steering, path, recovery, work, or visualization budget was raised.
