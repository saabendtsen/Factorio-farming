# Production source

The production runtime uses Factorio's conventional mod layout at the repository root:

- `control.lua` and `data.lua` are composition roots.
- `prototypes/` contains the temporary planner and fixed tractor.
- `scripts/` contains slice orchestration, field state, movement, and visuals.
- `tests/` contains the isolated Factorio integration adapter and runner.

The module boundaries and acceptance contract remain in [`docs/technical/first-production-vertical-slice.md`](../docs/technical/first-production-vertical-slice.md). This directory is retained as a pointer rather than a second source tree.
