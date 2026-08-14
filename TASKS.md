# Tasks

## Active

- [ ] **Validate and benchmark the production slice** - run the specification's automated, Factorio integration, save/load, recovery, and five-minute performance gates.
  - All acceptance scenarios pass in production code, including interruption at 25%, 50%, and 75% of the lane and save/load in every controller phase.
  - Record commands, profiler method, average and p95 script update, and any tuned constants in the implementation PR without duplicating the spike result tables.

## Waiting On

## Someday

- [ ] **Compare the custom vehicle controller with AAI**
- [ ] **Prototype circuit-network integration**

## Done

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
