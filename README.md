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

Design / technical prototyping

No gameplay implementation yet.

## Current design docs

- [Design v0.1](docs/DESIGN_v0.1.md)
- [Progression v0.1](docs/progression_v0.1.md)
- [Machinery v0.1](docs/machinery_v0.1.md)
- [Fields v0.1](docs/fields_v0.1.md)
- [Technical feasibility v0.1](docs/technical/feasibility_v0.1.md)

## Next milestone

Technical spikes

The first of two go/no-go prototypes is complete:

1. [Custom vehicle controller](docs/technical/spike-1-vehicle-controller-results.md): conditional GO through 300 active vehicles; production must rate-limit path requests.
2. Compressed field state and scalable field visuals: next.

See [TASKS.md](TASKS.md) for current scope and status.
