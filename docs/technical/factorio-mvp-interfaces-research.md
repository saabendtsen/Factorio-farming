# Factorio 2.1 interfaces for the MVP wheat loop

Status: decision-ready research for Wayfinder issue [#17](https://github.com/saabendtsen/Factorio-farming/issues/17)

Scope: persistent sowing, 2–3 visible tick-driven growth stages, deterministic harvesting, and depositing into one nearby container while keeping the existing bounded-update architecture.

## Findings

### Persistence and lifecycle

Use the runtime `storage` table as the authoritative crop state. Factorio 2.1 documents that `storage` is serialized with the map, is private to the mod, and replaces the pre-2.0 `global` table. Writes are forbidden in `on_load`; migration/initialization belongs in `on_init` and `on_configuration_changed`, while runtime handlers mutate the restored state. [Factorio 2.1.14 Storage](https://lua-api.factorio.com/latest/auxiliary/storage.html)

Persist compact records per sown plot/strip rather than Lua entity references: field ID, plot coordinate or range, sow tick, stage, and lifecycle state. If an entity projection is used, retain its unit number and re-find/validate it after load; `LuaEntity.valid` explicitly warns that held Lua objects can become invalid after engine removal. [Factorio 2.1.14 LuaEntity](https://lua-api.factorio.com/latest/classes/LuaEntity.html)

### Growth stages

The official `PlantPrototype` supports a positive `growth_ticks` duration plus `growth_variations` and growth-mound visuals. That is a viable engine-managed option, but it is Space Age-only and does not expose a mod-level “stage changed” event in the documented interface. [Factorio 2.1.14 PlantPrototype](https://lua-api.factorio.com/latest/prototypes/PlantPrototype.html)

For this MVP, prefer a mod-owned logical crop state with three deterministic stages. On sowing, persist `sow_tick`; at each scheduled update derive the stage from `game.tick - sow_tick` and fixed thresholds (for example 0, 1/3, and 2/3 of a configured growth duration). Render the stage as a disposable overlay or sprite. This gives exact save/load behavior, deterministic harvest eligibility, and no dependency on Space Age plant prototypes. `LuaRendering.draw_sprite` accepts a sprite path, target, surface, render mode, and optional time-to-live; the returned render object is a projection that can be recreated from `storage`. [Factorio 2.1.14 LuaRendering](https://lua-api.factorio.com/latest/classes/LuaRendering.html) [SpritePath](https://lua-api.factorio.com/latest/concepts/SpritePath.html)

### Tick scheduling and bounded updates

Register one `script.on_nth_tick(N, handler)` callback for growth/harvest work rather than scanning every plot on every tick. Factorio documents `on_nth_tick` as a handler that runs every N ticks; use a stable cursor or queue in `storage` and process at most the agreed crop-record and visual-rebuild budgets per invocation. [Factorio 2.1.14 LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html)

The bounded implementation shape is therefore: sow appends a record to a durable queue; each scheduled pass advances a bounded number of records; a stage transition marks only that plot/range dirty; a later bounded visual pass rebuilds dirty projections. Never derive lifecycle state by rescanning all field cells or render objects.

### Deterministic harvesting

Harvest should be an explicit controller transition after the crop record reaches the final stage. The tractor claims a deterministic plot/range, commits the harvest once, removes or marks the crop record, and produces a fixed wheat count. Avoid relying on engine plant death/loot for the MVP because that introduces prototype/engine behavior outside the authoritative field lifecycle.

If visual crop entities are used, `LuaEntity.valid` must be checked before access and the record must remain authoritative. A generation/token on the job or plot prevents a stale bounded callback from harvesting the same crop twice.

### One nearby container

Find candidate containers with `LuaSurface.find_entities_filtered`, restricted to the configured small area around the field/tractor. Sort candidates by squared distance and then stable `unit_number` (or use a single persisted target entity unit number). Validate the target and call `can_insert({name = "wheat", count = amount})` before `insert`; the documented insert result is the number actually inserted, so retain any remainder in the authoritative harvest state and retry through the bounded queue. [Factorio 2.1.14 LuaSurface](https://lua-api.factorio.com/latest/classes/LuaSurface.html) [Factorio 2.1.14 LuaEntity](https://lua-api.factorio.com/latest/classes/LuaEntity.html) [ItemStackIdentification](https://lua-api.factorio.com/latest/concepts/ItemStackIdentification.html)

This makes “store” deterministic without requiring belts, logistics, markets, or a second vehicle. If no nearby container exists or it is full, leave the crop/job in a `harvested_pending_deposit` state; do not drop or destroy wheat. Retry at the next bounded deposit pass and expose the blocked status through the existing interaction seam.

## Decision

Implement the MVP with mod-owned persisted crop records, three derived stages from `game.tick`, `on_nth_tick` bounded processing, disposable stage rendering, explicit deterministic harvest, and a single selected nearby container using `can_insert`/`insert`. Treat native `PlantPrototype` as a later Space Age-specific alternative, not the MVP dependency. Preserve the existing authoritative `storage` model, generation checks, dirty visual queue, and per-update budgets.

## Uncertainties and follow-up

- The official API documents the plant prototype’s duration and visuals but not a stage-transition callback; engine-managed plants therefore need an integration experiment before they can replace the logical crop model.
- The exact nearest-container radius, crop stage durations, wheat count, and queue budgets remain product/acceptance decisions for the implementation ticket.
- The documented runtime API does not guarantee the order returned by `find_entities_filtered`; explicit sorting is required for deterministic selection.
