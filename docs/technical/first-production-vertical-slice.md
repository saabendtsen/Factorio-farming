# First production vertical slice

Status: implemented; full acceptance validation pending

Milestone: one field, one tractor, one cultivation lane

## Outcome

Build the smallest playable path through the production architecture: a player defines one rectangular field, creates one farming tractor, and sends it to cultivate one lane. The tractor travels physically to the field entrance, works the lane, and can be paused, saved, loaded, and resumed without losing or duplicating progress.

The reference case is a 64 × 16-tile field and a fixed tractor/cultivator with a 4-tile working width. The slice completes one 64 × 4 lane, so the field ends at 256/1,024 tiles (25%). It deliberately proves partial progress rather than completing a farming lifecycle.

The two feasibility spikes provide the evidence for the choices below; this document does not repeat their benchmark tables:

- [Vehicle controller results](spike-1-vehicle-controller-results.md)
- [Field state and visuals results](spike-2-field-state-visuals-results.md)

## Player and test flow

1. A player obtains the temporary `farming-field-planner` selection tool from `/farming-slice-setup` and drags one axis-aligned rectangle.
2. The selection is normalized to whole-tile, half-open bounds and must be exactly 64 × 16 tiles in either orientation. A second live field is rejected with a clear message.
3. The entrance is the midpoint of the field-end edge nearest the player's position when selection finishes: west/east for an east-west field or north/south for a north-south field. A distance tie chooses west or north.
4. The same setup command creates one `farming-tractor` at the player's safe non-colliding position and registers its fixed logical cultivator (4-tile width). Re-running it reuses the valid tractor and planner rather than duplicating them.
5. Creating the field creates one waiting cultivation job. The single registered tractor reserves it, requests a native asynchronous path, and physically drives to the entrance using custom steering.
6. At the entrance, the controller aligns the tractor with the field's long axis and works the 4-tile band centered on the entrance. For the fixed 16-tile short axis this is offsets `[6, 10)`. No second lane or turn is generated.
7. `/farming-slice-pause` brakes the tractor, closes the current progress interval, invalidates pending movement callbacks with a generation increment, and leaves the job paused. It is idempotent.
8. `/farming-slice-resume` returns the same job to active work. If the tractor is outside the entrance tolerance it travels to the entrance again; otherwise it aligns and resumes at the first uncovered longitudinal position. It is also idempotent.
9. On lane completion, the tractor stops, the job becomes complete, its claim is released, and the field remains partially complete at 25%.

The commands are a temporary slice adapter, not the future player interface. Their behavior is fixed here so implementation and validation do not depend on a UI decision.

## Included behavior

- One field and one farming tractor per surface.
- A dedicated tractor prototype with one logical, non-colliding cultivator; no articulated implement entity.
- Rectangular field definition through a selection tool and deterministic entrance/lane derivation.
- One automatically assigned cultivation job and one exclusive lane claim.
- Native asynchronous Factorio pathfinding for world travel and custom `riding_state` steering.
- Exact deterministic lane waypoints inside the field; no path request for lane work.
- Authoritative completed ranges in `storage`, delta-maintained completed area, and generation tokens for stale callbacks.
- Pause/resume, save/load in every controller phase, entity validity checks, and bounded reverse/repath recovery.
- Disposable rendering rectangles for the field outline, entrance, target lane, and completed progress. Adjacent strips with identical ranges are merged into one rectangle.
- Minimal status messages for setup, rejection, pause, resume, path/recovery failure, and completion.

## Intentionally postponed

- Crops, yield, inventory output, recipes beyond the temporary setup command, economy, progression, and field lifecycle transitions.
- Completing additional lanes, headland turns, whole-field completion, sowing, growth, and harvesting.
- Multiple fields, vehicles, vehicle types, implements, forces, schedulers, priorities, reservations across fleets, and traffic coordination.
- General field sizes, editing/removal, player-chosen entrances, polished GUI/shortcut behavior, multiplayer UI, and circuit control.
- Fuel, equipment pickup, implement physics, vehicle passenger behavior, paving/terrain replacement, and durable field tiles.
- AAI integration or dependency.
- Packed-bitmap mutation and range-to-bitmap promotion. The field module owns the representation seam and persists a representation tag, but this coherent slice writes ranges only. Bitmap promotion is added when fragmented production writes exist to exercise it.
- Scale claims beyond the slice. The spike benchmarks remain evidence, while production-scale fleet and fragmented-state benchmarks remain later gates.

## Authoritative state and transitions

`storage.farming` is the only durable source of truth. Rendering objects and indexes are projections that may be destroyed and rebuilt.

The schema starts versioned and uses numeric IDs:

```text
storage.farming
  schema_version
  next_field_id / next_machine_id / next_job_id
  surfaces[surface_index]
    field                 -- bounds, entrance, axis, strips, counters, generation
    machine               -- entity unit number, fixed capability, controller state
    job                   -- field/machine IDs, state, lane claim, generation, failure
    pending_paths[id]     -- machine ID and generation
    visual_dirty          -- field IDs/ranges, never authoritative
```

The job states are `waiting -> reserved -> travelling -> working -> completed`, with `reserved`, `travelling`, or `working` able to enter `paused` or `failed`. Resume returns `paused` to `travelling` or `working` after validating the entity, field, claim, and generations. A failed path/recovery stops visibly and retains progress; an explicit resume starts a fresh bounded attempt.

Progress is represented as sorted, non-overlapping half-open intervals on canonical one-tile strips. A swept, field-clamped work rectangle is committed at most once per controller update. The field module returns the newly covered area; callers add no area themselves. `completed_area` must be monotonic and equal the union of stored coverage. Overlap therefore changes neither ranges nor counters.

The schema reserves a per-32 × 32 chunk representation tag (`ranges` or `bitmap`) behind the field module's interface. No caller branches on it. The slice implements `ranges`; later bitmap promotion can change the implementation without changing movement, orchestration, or visuals.

## Minimum production module structure

```text
control.lua
data.lua
prototypes/
  field-planner.lua
  farming-tractor.lua
scripts/
  slice.lua
  field.lua
  movement.lua
  visuals.lua
```

- `control.lua` is the composition root. It registers lifecycle, selection, command, tick, path-result, and entity-removal events and delegates them. It contains no domain decisions.
- `data.lua` loads only the planner and tractor prototypes. The tractor maps to a fixed logical capability; the implement is not a second entity.
- `scripts/slice.lua` is the orchestration module. Its small interface handles setup/selection/pause/resume and consumes movement outcomes. It owns the one-field/one-machine job state machine, reciprocal references, generation changes, and user messages. Jobs and machines stay inside this module until a second workflow makes extraction useful.
- `scripts/field.lua` owns geometry, entrance/lane derivation, claims, range/bitmap representation tags, progress commits, counters, and state queries. Its interface accepts work rectangles and returns progress deltas; callers never edit strips.
- `scripts/movement.lua` owns the rate-limited path queue, path-result validation, waypoint steering, lane motion, stuck detection, and bounded recovery. It reports `arrived`, `progress rectangle`, `paused`, or `failed`; it never edits field progress or job state.
- `scripts/visuals.lua` projects field queries into rendering rectangles and rebuilds dirty projections. It stores only disposable render-object references and never supplies simulation state.

This is intentionally fewer modules than the eventual architecture. Separate scheduler, machine, command, migration, and test-adapter modules would initially be shallow pass-throughs. Extract them only when a second real caller or behavior appears.

## Technical boundaries and budgets

All limits are named constants and are enforced even though the slice has only one vehicle:

| Work | Slice budget |
|---|---:|
| New native path requests | At most 1 per tick and 1 outstanding for the slice |
| Active vehicle steering | Stable 3-tick cadence; at most 1 controller update per tick |
| Recovery | At most 2 reverse/repath attempts per resume generation |
| Work commit | At most 1 swept rectangle per controller update; no full-field scan |
| Visual rebuild | At most 8 dirty field/range projections per tick |
| Durable tile writes | 0; this slice does not call `set_tiles` |
| Authoritative hot state | No entity, table record, or render object per field cell |

Path callbacks must match both request ID and machine generation. Late results are discarded. Controller iteration and tie-breaking use stable numeric IDs. No wall-clock values, unordered outcome decisions, teleports, direct position writes, or silent recovery are allowed.

The acceptance reference is 60 UPS on the spike reference machine. During a five-minute reference run, the farming script update must average no more than 0.25 ms with p95 no more than 0.50 ms, excluding one-time setup. Record the profiler method and result; these are slice regression gates, not fleet-scale claims.

## Acceptance criteria

The slice is accepted only when all of the following pass in a production mod, not on either prototype branch:

- Starting from a new save, the setup command and planner create exactly one valid 64 × 16 field, deterministic entrance, tractor, and cultivation job; the job advances atomically from waiting to a reciprocal tractor reservation and first-lane claim. Invalid sizes and duplicate live fields are rejected without partial state.
- The tractor requests a path through the bounded queue, physically reaches the entrance without teleporting, aligns, and completes exactly the first 64 × 4 lane.
- Pausing at approximately 25%, 50%, and 75% of the lane stops progress. Each resume continues at the first uncovered point and final authoritative coverage is exactly 256 tiles with no overlap inflation.
- Saving/loading once in `reserved`, `travelling`, `working`, and `paused` preserves valid progress and reaches the same final state. Pending path requests are safely reissued or invalidated rather than trusted across load.
- Mining or destroying the tractor while assigned releases reciprocal references, preserves field progress, and produces a visible failed state; setup plus resume can register a replacement and continue.
- Removing render objects through a debug validation hook and rebuilding them changes no authoritative state. The completed overlay matches the stored ranges after rebuild and load.
- The completed job has no live claim or pending path request; the stopped tractor is unassigned; the field reports 256/1,024 tiles and 25%.
- Automated pure-Lua tests cover geometry, interval union/overlap, counter deltas, deterministic lane/entrance selection, transition validity, and stale generations. A Factorio integration scenario covers the full flow and the save/load checkpoints.
- `git diff --check`, the Lua/static checks available in the repository, the automated tests, and the five-minute performance run pass with their commands/results recorded in the implementation PR.

## Executable implementation plan

1. Create the production mod skeleton, versioned storage initialization, prototypes, and pure-Lua test harness. Implement field geometry/ranges first and lock the progress invariants with tests.
2. Implement slice orchestration and temporary commands, including atomic setup, state transitions, reciprocal references, generation tokens, and entity-removal handling.
3. Port only the proven production movement behavior: queued async path requests, 3-tick steering, exact lane motion, pause braking, and two-attempt recovery. Do not copy prototype harness structure or merge its branch.
4. Add disposable merged-range rendering rectangles and dirty rebuilds from field queries.
5. Run unit/integration, interruption, destruction, save/load, visual rebuild, and performance acceptance. Review the full diff for postponed behavior, document results, and merge only when every criterion passes.

Implementation may tune steering constants and tolerances using the spike evidence. Any change to field dimensions, work width, player flow, state ownership, module seams, budgets, or acceptance outcomes requires updating this document in the implementation PR rather than making an implicit product decision.
