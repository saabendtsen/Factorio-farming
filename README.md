# Factorio Farming

A Factorio mod focused on farming, automation, logistics, and production optimization at Factorio scale.

## Core pillars

- Physical fields generate machinery work.
- Machines physically travel to and operate on fields.
- Machinery throughput creates production bottlenecks.
- Field geometry affects real machinery utilization.
- Farming scales from small operations toward megabase-scale agriculture.
- Crops are used as capital resources for machinery and infrastructure.
- Automation progresses from fixed tractor/implement combinations toward shared equipment pools and advanced circuit-controlled dispatch.

## Current status

First production vertical slice implemented; full acceptance validation and benchmarking remain

## Current design docs

- [Design v0.1](docs/DESIGN_v0.1.md)
- [Progression v0.1](docs/progression_v0.1.md)
- [Machinery v0.1](docs/machinery_v0.1.md)
- [Fields v0.1](docs/fields_v0.1.md)
- [Technical feasibility v0.1](docs/technical/feasibility_v0.1.md)
- [First production vertical slice](docs/technical/first-production-vertical-slice.md)

## Next milestone

First production vertical slice

Both go/no-go prototypes are complete:

1. [Custom vehicle controller](docs/technical/spike-1-vehicle-controller-results.md): conditional GO through 300 active vehicles; production must rate-limit path requests.
2. [Compressed field state and scalable visuals](docs/technical/spike-2-field-state-visuals-results.md): GO with ranges for coherent work, packed fragmented chunks, compressed render overlays, and bounded tile batches.

The [first production vertical slice](docs/technical/first-production-vertical-slice.md) now implements one 64 × 16 field, one fixed tractor/cultivator, physical travel to the entrance, and one persistent, resumable 64 × 4 lane. The next task is full save/load, recovery, and five-minute performance validation. Crops, economy, progression, multiple vehicle types, and polished UI remain postponed.

Run the isolated Factorio 2.1 integration suite with `tests\run-factorio-tests.bat`. It uses temporary mods, saves, and script output below `%LOCALAPPDATA%\FactorioFarmingProductionTests` and does not touch personal Factorio data.

See [TASKS.md](TASKS.md) for current scope and status.
