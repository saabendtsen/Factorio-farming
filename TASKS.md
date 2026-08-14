# Tasks

## Active

- [ ] **Spike 2 — Field state and visuals**
  - Prototype compressed strip/range state.
  - Support interruption, resume, and overlap.
  - Test fields up to 1,024 × 1,024.
  - Compare batched tiles with compressed rendering ranges.
  - Measure script time, save size, and load time.

## Waiting On

## Someday

- [ ] **Compare the custom vehicle controller with AAI**
- [ ] **Prototype circuit-network integration**

## Done

- [x] ~~Spike 1 — Vehicle controller~~ (2026-08-14)
  - Conditional GO: 300/300 vehicles completed at an average 0.513 ms/update.
  - Production must queue and rate-limit native path requests.
  - Results: `docs/technical/spike-1-vehicle-controller-results.md`.

- [x] ~~Consolidate technical feasibility documentation~~ (2026-08-14)
  - Kept `docs/technical/feasibility_v0.1.md` as the canonical assessment.
  - Removed the superseded duplicate after confirming the deletion target.

- [x] ~~Document Factorio 2.x technical feasibility~~ (2026-08-14)
  - Merged in PR #2.
