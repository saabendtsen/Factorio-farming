# Tasks

## Active

- [ ] **Define the second production vertical slice** - choose the next deliberately small end-to-end farming capability after whole-field cultivation.
  - Produce one scoped technical specification with included/postponed behavior, acceptance criteria, module changes, and executable implementation tasks.
  - Preserve the established controller, path, field-state, visualization, and performance boundaries unless new evidence justifies a documented change.

## Waiting On

## Someday

- [ ] **Compare the custom vehicle controller with AAI**
- [ ] **Prototype circuit-network integration**

## Done

- [x] ~~Cultivate the whole field~~ (2026-08-21)
  - Generated four non-overlapping lanes and three physical U-turns from field geometry, alternating direction while holding exactly one lane claim.
  - Exact range progress reaches 1,024/1,024 with no overlap inflation; pause/resume, destruction/replacement, visuals, and save/load in every controller phase pass.
  - The five-minute active-job window averaged 0.0219 ms with a 0.0793 ms p95 against unchanged 0.25 ms and 0.50 ms budgets.
  - Results: `docs/technical/whole-field-cultivation.md`.

- [x] ~~Validate and benchmark the production slice~~ (2026-08-16)
  - Made `reserved` an observable phase and rebuilt load recovery per phase: in-flight path requests are always discarded, generations invalidate pre-save callbacks, and `paused`/`failed` stay stopped until an explicit resume.
  - The harness now captures real saves in `reserved`, `travelling`, `working`, and `paused` on a headless server, replays each to exactly 256/1,024 tiles, and runs a five-minute profiled reference run.
  - Active-job script update averaged 0.0183 ms with a 0.0597 ms p95, against 0.25 ms and 0.50 ms budgets. No constants needed tuning.
  - Results: `docs/technical/first-production-vertical-slice.md`.

- [x] ~~Implement the first production vertical slice~~ (2026-08-14)
  - Added the one-field, one-tractor, one-lane production architecture from `docs/technical/first-production-vertical-slice.md`.
  - Exact range progress, pause/resume, initial-load recovery, destruction/replacement, disposable visuals, and bounded controller/path budgets pass the isolated Factorio integration harness.
  - The completed reference result is exactly 256/1,024 tiles (25%); postponed gameplay and AAI remain out of scope.

- [x] ~~Spike 2 — Field state and visuals~~ (2026-08-14)
  - GO with a hybrid architecture: coherent ranges plus packed fragmented chunks.
  - Use compressed render overlays and bounded, amortized tile batches.
  - Results: `docs/technical/spike-2-field-state-visuals-results.md`.

- [x] ~~Spike 1 — Vehicle controller~~ (2026-08-14)
  - Conditional GO: 300/300 vehicles completed at an average 0.513 ms/update.
  - Production must queue and rate-limit native path requests.
  - Results: `docs/technical/spike-1-vehicle-controller-results.md`.

- [x] ~~Consolidate technical feasibility documentation~~ (2026-08-14)
  - Kept `docs/technical/feasibility_v0.1.md` as the canonical assessment.
  - Removed the superseded duplicate after confirming the deletion target.

- [x] ~~Document Factorio 2.x technical feasibility~~ (2026-08-14)
  - Merged in PR #2.
