# Tasks

## Active

- [ ] **Spike 1 — Vehicle controller**
  - Build a minimal Factorio 2.1 mod skeleton.
  - Use native asynchronous pathfinding and custom car steering.
  - Support travel to a field entrance, one lane, and bounded stuck recovery.
  - Benchmark 1, 10, 100, 200, and 300 active vehicles.
  - Do not implement crops, economy, progression, or full gameplay.

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

- [x] ~~Consolidate technical feasibility documentation~~ (2026-08-14)
  - Kept `docs/technical/feasibility_v0.1.md` as the canonical assessment.
  - Removed the superseded duplicate after confirming the deletion target.

- [x] ~~Document Factorio 2.x technical feasibility~~ (2026-08-14)
  - Merged in PR #2.
