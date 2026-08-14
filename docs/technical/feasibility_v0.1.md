# Factorio Farming — Technical Feasibility v0.1

Status: proposed technical baseline

Research date: 2026-08-14

Target: Factorio 2.x; the official online API documentation reported version 2.1.14 during research

This document evaluates the design in `docs/DESIGN_v0.1.md`, `docs/progression_v0.1.md`, `docs/machinery_v0.1.md`, and `docs/fields_v0.1.md`. Those documents remain the game-design source of truth. No gameplay system is redesigned here.

## 1. Executive conclusion

**The current design is technically feasible as a Factorio 2.x mod.** No documented API limitation prevents rectangular spatial fields, partial lane-based work, physically moving machinery, a lightweight job scheduler, circuit integration, save/load, or deterministic multiplayer.

The important qualification is vehicle scale. Factorio exposes an asynchronous pathfinder that is explicitly suitable for emulating paths for non-unit entities such as vehicles, but it does not provide general autopilot for `car` entities. A mod must follow returned waypoints and steer each car in Lua. The reliability and cost of hundreds of simultaneously moving cars therefore remain an empirical risk, not a solved API feature.

The smallest architecture worth prototyping is:

1. Rectangular field geometry and compressed completed ranges in `storage`, not one Lua record or entity per tile.
2. One visible `car` entity per machine; tractor and implement form one scripted compound unit.
3. A per-surface indexed job queue with event-driven assignment and explicit reservations.
4. Native asynchronous path requests for travel to a field entrance.
5. A custom, staggered car controller for returned waypoints and deterministic field lanes.
6. Parallel boustrophedon passes, simplified low-speed turns, and persistent lane claims.
7. Batched field tiles or compressed rendering ranges as a visual projection of authoritative state.

**Controller recommendation:** custom minimal controller first, with one bounded AAI Programmable Vehicles comparison spike. Do not make AAI a mandatory MVP dependency.

**Decision:** GO to technical spikes. Do not begin full gameplay implementation until the car-controller and large-field representation spikes pass.

## 2. Feasibility summary

| Area | Feasibility | Scale risk | MVP decision |
|---|---|---:|---|
| Rectangular spatial fields | High | Low | Bounds plus compressed strip/lane ranges |
| Partial and resumable work | High | Low | Completed intervals and aggregate counters |
| Parallel lane generation | High | Low | Longest axis, deterministic alternating passes |
| Car pathfinding | Supported indirectly | High | Native async path request plus custom steering |
| Exact field-lane movement | Feasible in Lua | Medium | Low-speed waypoint tracking and simple turns |
| Hundreds of moving vehicles | Plausible, unproven | High | Mandatory 100/200/300-vehicle benchmark |
| Tractor plus implement | High | Low | One car plus logical implement and attached sprite |
| Job scheduling | High | Low | Indexed per-surface queues; event-driven dispatch |
| Field visuals | High | Medium | Batched tiles or range-level render objects |
| Circuit integration | High | Low | Thin field/dispatcher adapter later |
| Save/load and multiplayer | High | Medium | Plain deterministic `storage`, migrations, validity checks |
| AAI integration | Possible | Medium | Optional adapter, not a hard dependency |

Risk describes performance exposure and uncertainty, not evidence that a feature is impossible.

## 3. Research evidence boundary

This document distinguishes:

- **Documented capability:** stated in current official Factorio 2.x API documentation.
- **Observed mod behavior:** stated by the current publisher-maintained AAI mod page or changelog.
- **Recommendation/inference:** an architecture proposed for this project and subject to the listed spikes.

Important current facts:

- [`LuaSurface::request_path`](https://lua-api.factorio.com/latest/classes/LuaSurface.html#request_path) asynchronously generates a unit-pathfinder route and explicitly says the result can emulate pathing for non-unit entities such as vehicles.
- [`LuaControl::riding_state`](https://lua-api.factorio.com/latest/classes/LuaControl.html#riding_state) exposes writable acceleration and steering for a car. Car [`speed`](https://lua-api.factorio.com/latest/classes/LuaEntity.html#speed) and entity [`orientation`](https://lua-api.factorio.com/latest/classes/LuaEntity.html#orientation) are also writable.
- `LuaEntity::commandable` applies to Units and SpiderUnits, not Cars. SpiderVehicle autopilot is likewise SpiderVehicle-only. There is no general car-autopilot call.
- [`storage`](https://lua-api.factorio.com/latest/auxiliary/storage.html) is serialized with the save and supports basic values, tables, registered metatables, and Factorio LuaObject references under documented restrictions.
- Factorio replaces relevant Lua iteration, random, and mathematical behavior with deterministic implementations; see [Libraries and functions](https://lua-api.factorio.com/latest/auxiliary/libraries.html).
- [`LuaSurface::set_tiles`](https://lua-api.factorio.com/latest/classes/LuaSurface.html#set_tiles) accepts batches and recommends one bulk call over many small calls.
- [`LuaRendering`](https://lua-api.factorio.com/latest/classes/LuaRendering.html) can draw persistent world-space rectangles, polygons, sprites, and text, including visuals attached to entities.
- [AAI Programmable Vehicles](https://mods.factorio.com/mod/aai-programmable-vehicles) version 0.9.1 declares Factorio 2.1 support and provides car commands, paths, waypoints, signals, and circuit-oriented structures. Its current page also states that commanded vehicles use biter AI and that this AI “can be a bit derpy.”

Factorio does not publish universal safe limits for mod-owned cells, render objects, path requests, or vehicles. Any scale number below is a project benchmark target, not an official engine guarantee.

## 4. Field-state representation

### Options

| Representation | Memory and save behavior | Update/lookup | Judgment |
|---|---|---|---|
| Lua dictionary keyed by `"x,y"` | Very high key, value, hash, and serialization overhead | Average O(1), allocation-heavy | Reject |
| Nested table per row and cell | Less key duplication, still one Lua slot per cell | O(1) | Reject as megabase default |
| Packed chunk bitmaps/strings | Compact; mutation and debugging are more complex | O(1) decode | Fallback for fragmented chunks |
| Completed ranges per strip/lane | Proportional to boundaries, not field area | O(1) for prefixes; small range search | Preferred |
| Hidden entity per cell | Engine entity, update, and save overhead | Convenient but excessive | Reject |
| Tiles as authoritative state | Engine-owned and visible, but terrain/mods may alter them | Efficient bulk operations | Visual projection only |
| Render objects as truth | Rendering lifecycle coupled to simulation | Awkward querying | Visual projection only |

### Recommendation

Store authoritative work as **compressed intervals over canonical axis-aligned strips**, with a chunk index only for spatial lookup.

For a field whose long axis is X, each logical strip is a Y offset with sorted, non-overlapping completed intervals `[x0, x1)`. For a Y-oriented field, transpose the axes. A machine of working width `w` claims `w` adjacent strips and advances a common longitudinal interval. Maintain `completed_area` by delta so progress and completion never require a full-field scan.

```lua
storage.surfaces[surface_index] = {
  fields = {
    [field_id] = {
      bounds = {left_top = {x = 0, y = 0}, right_bottom = {x = 256, y = 64}},
      entrance = {x = 0.5, y = 32.5},
      long_axis = "x",
      lifecycle = "needs-cultivation",
      operation_generation = 4,
      strips = {
        [1] = {{0, 256}},
        [2] = {{0, 117}}
      },
      completed_area = 373,
      required_area = 16384
    }
  },
  field_chunks = {}
}
```

Use dense integer arrays and numeric IDs. Avoid coordinate strings in hot state. Uniform complete strips may be represented by a flag or shared extent rather than an explicit interval.

### Why

- The initial field geometry and generated work are both highly coherent.
- Memory grows with the short dimension and fragmentation, not total area.
- Partial work closes or extends one range.
- Multiple machines can claim separate strip bands later.
- Plain numeric tables save reliably in `storage`.

### Relative memory risk

A 1,024 × 1,024 field contains 1,048,576 cells. A Lua entry per cell is likely tens of megabytes after table overhead and is unacceptable when multiplied across fields and lifecycle states. A raw one-bit bitmap for the same field is 128 KiB per operation before Lua representation overhead. A coherent range model needs approximately one range per strip, usually orders of magnitude fewer records than cells. These are engineering estimates; the spike must measure actual script memory, save size, and load time.

### Main risk

Ranges fragment if arbitrary traversal becomes common. Generated lanes keep fragmentation low. If real scenarios create heavily fragmented 32 × 32 regions, promote only those regions to packed bitmaps while keeping coherent state as ranges.

### What to prototype first

Create synthetic 64 × 64, 256 × 256, and 1,024 × 1,024 fields. Apply full passes, interruption/resumption, overlap, and randomized fragmentation. Compare intervals and packed chunks for update time, script memory, save growth, and load time.

## 5. Vehicle-control options

### Documented capabilities

`LuaSurface::request_path` accepts a vehicle bounding box, collision mask, start, goal, force, goal radius, gates, resolution, and pathfinder flags. It returns a request ID and later raises `on_script_path_request_finished`.

A car can be driven through writable riding state, preserving acceleration, braking, steering, and native collision. Speed and orientation are writable alternatives, but using position writes or teleport-like motion would violate the physical-movement design.

### Missing engine behavior

The API does not provide:

- a car destination queue or schedule;
- automatic consumption of returned path waypoints;
- a car traffic reservation system;
- field-lane following;
- car-specific stuck recovery.

Those behaviors must be simulated in Lua.

### Recommendation

Use different policies for travel and work:

- **World travel:** native asynchronous path request, waypoint simplification/look-ahead, ordinary car steering, cached common routes, and stuck detection.
- **Inside a field:** precomputed exact waypoints, controlled low speed, fixed headings, and no path request for each lane.

Suggested state machine:

```text
idle
  -> request-world-path
  -> travel-to-entrance
  -> align-at-entrance
  -> travel-to-lane-start
  -> work-lane
  -> turn/transfer
  -> work-lane ...
  -> return-to-entrance
  -> next-job/idle
```

Store route generation, request ID, waypoint index, target, controller phase, last progress position/tick, job ID, and lane claim. Ignore a late path result when its generation no longer matches.

Update active vehicles in stable tick buckets, for example `unit_number % 3`, while temporarily increasing frequency near braking or collision states. A three-tick cadence is 20 Hz at 60 UPS, but the benchmark should compare cadences rather than lock one prematurely.

### Collision and recovery

1. Measure displacement and distance-to-waypoint over a fixed tick window.
2. Brake and wait briefly when blocked.
3. Perform one bounded deterministic reverse/re-align maneuver.
4. Request a new path from the current position.
5. After bounded retries, fail travel visibly, release the reservation, and retry later.

Do not silently teleport a blocked machine.

### Main risk

The quality and per-tick cost of hundreds of custom-steered cars are undocumented. Asynchronous pathfinding avoids blocking Lua, but excessive path requests can still create backlog and UPS pressure. Congestion may dominate even when steering math is cheap.

### What to prototype first

Drive 1, 10, 100, 200, and 300 cars through repeatable roads, obstacles, intersections, field entries, lanes, and turns. Record mod update time, UPS, path-request latency, stuck/repath rate, collisions, arrival error, and completed routes.

## 6. AAI versus custom controller

| Criterion | AAI dependency | Custom minimal controller |
|---|---|---|
| Initial travel features | Commands, paths, zones already exist | Steering and recovery must be built |
| Precise field lanes | Farming-specific logic still required | Full control of lane semantics |
| Performance | Used in real mods, target fleet budget undocumented | Narrowly optimizable, still unproven |
| Circuit integration | Rich signal/unit-data ecosystem | Thin native adapter later |
| Dependency risk | Alpha, AAI Signals dependency, limited-distribution license | Project controls behavior and compatibility |
| Player UX | Adds a substantial parallel control system | Can match farming progression exactly |
| Vehicle compatibility | Broad vanilla/modded support | Project prototypes first |
| Debugging | External controller behavior | End-to-end farming telemetry |

### Recommendation

**Custom minimal controller first, using the native Factorio pathfinder. Prototype current AAI as a comparator before making a permanent dependency decision.**

Do not reproduce all AAI functionality. Implement only world-route consumption, waypoint steering, field-lane execution, bounded recovery, and telemetry. Do not let AAI and the farming controller steer the same car simultaneously.

### Why

The differentiating behavior is exact field work, not general RTS command. AAI is strongest in general commands, zones, hauling, and circuits, while its own current description identifies biter-AI movement as imperfect. The MVP would still need custom field, job, claim, and progress logic.

### Main risk

Custom control can expand into a general traffic system. Keep the MVP constrained to one entrance, broad routes, no convoy logic, no dynamic implement pickup, simplified turns, and bounded recovery.

### What to prototype first

Run the same 100-vehicle route and lane scenario with custom control and AAI 0.9.1. Compare UPS, success rate, lane error, stuck rate, save behavior, integration work, and player-visible control conflicts.

## 7. Lane generation and work execution

### Recommendation

Generate deterministic, axis-aligned boustrophedon passes when a job is assigned:

1. Normalize integer field bounds as half-open rectangles.
2. Use the longest field dimension as the lane axis; resolve squares with a fixed rule.
3. Begin at the edge nearest the entrance.
4. Partition the short axis into bands matching the implement working width.
5. Center one lane in each band; clip the last band to the field.
6. Alternate travel direction between adjacent lanes.
7. Add fixed headland/transfer waypoints.

The work footprint is the swept, field-clamped rectangle between sampled machine positions. Commit only newly covered ranges and add the uncovered area to `completed_area`. Sampling should follow distance moved, not scan every field cell every tick.

Lane state needs `available`, `claimed`, and `complete` status, claimant machine ID, claim/operation generation, covered strips, direction, and completed intervals. Interruption closes the current interval and either pauses or releases the claim. A stale controller cannot update a lane after reassignment because its generation differs.

For the one-machine MVP, generate lanes for the assigned implement. Later, canonical one-tile strips remain authoritative and machines claim adjacent groups matching their widths. Concurrent heterogeneous widths may be introduced after homogeneous multi-machine claims work reliably.

### Turning

Use a time-consuming simplified transfer: finish and stop, enter the headland, align through fixed waypoints, then enter the next lane. This retains turning overhead and geometry trade-offs without articulated-vehicle physics.

### Main risk

Fractional widths complicate exact area accounting. Define v0.1 widths in whole tiles or one fixed sub-tile spatial quantum. This is the smallest viable technical constraint and does not remove width gameplay.

### What to prototype first

Test square, long, narrow, odd-width, and smaller-than-implement fields. Interrupt at multiple positions, resume, overlap passes, and prove exactly 100% completion with no duplicate yield.

## 8. Tractor and implement representation

### Recommendation

Use a **scripted compound object with one physical car entity**:

- The tractor or harvester is the only moving runtime entity.
- Implement definitions contain job type, working width, required power, working speed, compatibility tags, and visual identity.
- The equipped implement and fixed-pair state live in the machine record in `storage`.
- Render the implement as an entity-attached oriented sprite, or include it in a combination-specific vehicle animation.
- Do not create an independently colliding moving implement entity.

Separate prototypes/items for supported fixed combinations are acceptable if they simplify graphics or collision boxes. Internally they should map to the same generic capability record so future equipment pools do not change the field or scheduler model.

### Why

Factorio has no general rigid-body joint API. Two moving colliding entities create synchronization, collision, destruction, selection, save, and recovery problems without improving the v0.1 gameplay properties.

### Main risk

An attached sprite has no separate collision footprint. That is compatible with the current simplified physics. If transport width later becomes gameplay, use combination-specific coarse collision boxes or restrictions rather than scripted towing physics.

### What to prototype first

One tractor/cultivator and one harvester: verify all orientations, build/mine/destroy, save/load, passenger behavior, and visible working width.

## 9. Job scheduler

### Recommendation

Use one centralized scheduler per surface and force. It is indexed, deterministic, and event-driven.

```text
waiting -> reserved -> active -> completed
             |           |
             v           v
          waiting <- interrupted
             |
             v
           failed -> waiting after bounded retry
```

A job record contains ID, field ID, operation generation, type, priority, creation tick, required capability tags, estimated and completed area, status, assigned machine IDs, retry count/tick, and failure reason.

Maintain waiting queues keyed by job type/capability and priority bucket, plus idle-machine indexes keyed by capability. On `machine became idle`, inspect only compatible queue heads. On `job became waiting`, wake a compatible idle machine. Resolve ties by priority, creation tick, then numeric job ID.

Reservation happens atomically inside one event handler: validate job and machine generations, mark both reserved, and initiate travel. Travel failure releases both sides and applies bounded retry. Active jobs own lane claims. Completing the last required range advances the field lifecycle exactly once.

Reserved machinery becomes an eligibility flag or pool ID. Future priorities, multiple pools, multiple machines per field, and circuits add indexes or policy; they do not require a distributed scheduler.

### Main risk

Cancellation, destruction, and late callbacks can orphan claims. Generation tokens, reciprocal job/machine references, entity destruction handling, and invariant checks belong in the first implementation.

### What to prototype first

Run thousands of synthetic jobs and machines through assignment, cancellation, destruction, retry, priority change, save/load, and migration. Assert that no lane has two owners and every live reservation has a reciprocal valid reference.

## 10. Visual field representation

### Recommendation

Prototype two projections over the same authoritative range state.

**A. Batched custom tiles — preferred baseline**

- Variants for field/base, cultivated, sown/growing, ready, and harvested.
- Queue changed cells/ranges and call `set_tiles` in bounded batches every few ticks.
- Update only deltas; never repaint or scan the whole field for progress.

**B. Compressed rendering — fallback/overlay**

- One ground rectangle or sprite per contiguous run/chunk rectangle.
- Rebuild only dirty strips/chunks.
- Use sparse borders, entrance, lane, claim, and debug overlays.

Do not place one crop entity or render object per cell. If crops need height or texture, use tile graphics, sparse decoratives, or a small number of large run/chunk sprites. Visuals are rebuildable caches; yield and completion must never be inferred by scanning them.

### Main risk

Large tile bursts can hitch and alter save size; fragmented render objects can affect render performance and management cost. Measure both rather than assuming either has a universal safe count.

### What to prototype first

Render fields totaling 1 million and 10 million cells. Compare tile batches and strip/chunk rectangles for update time, FPS/render time, save/load, zoomed-out readability, paving conflicts, and restoration after field removal.

## 11. Performance and UPS

| Hotspot | Risk | Required pattern |
|---|---:|---|
| Steering active cars | High | Active-only dense set, tick buckets, simple math/state |
| Path requests | High | Async, rate-limited, cached, only on assignment/failure |
| Vehicle congestion | High | Broad access, entrance queue, deterministic yielding, telemetry |
| Per-cell field state | High if naive | Ranges; optional packed fragmented chunks |
| Visual updates | Medium–High | Dirty deltas, merged ranges, bounded bulk calls |
| Full-field scans | High | Counters, frontiers, and indexes |
| Job polling | Medium if naive | Indexed queues and event-driven wakeups |
| Entity counts | High if cell-based | One entity per machine/controller, none per crop cell |
| Save/load/migration | Medium | Compact schema and per-field/chunk migration |
| UI/telemetry | Medium | Open-player only, paginated, low-frequency aggregates |

Recommended patterns:

- Maintain dense active-machine arrays and O(1) ID indexes.
- Stagger controllers and cap new path requests per tick.
- Cache routes between stable hubs and entrances; invalidate after repeated blocking or topology changes.
- Maintain completed area and next-gap cursors.
- Merge adjacent visual changes before API calls.
- Avoid scheduler polling, full-field scans, and per-cell entities.
- Measure with representative `/editor` benchmark scenarios and Factorio profiler data.

### Proposed acceptance targets

These are project gates, not engine limits:

- Maintain 60 UPS with 200 moving/working vehicles and at least 10 million logical field cells on an agreed reference machine.
- Farming script update average ≤ 1.5 ms and p95 ≤ 3 ms in that scenario.
- Zero orphaned job/lane claims in a two-hour deterministic interruption/destruction soak.
- Preserve exact progress through save/load and multiplayer join.
- Characterize 300 vehicles as a stretch test even if it misses 60 UPS.

If 200 active cars miss the budget, first reduce controller cadence, route-request concurrency, and simultaneous activity before considering design changes. “Hundreds owned” may be practical with fewer simultaneously moving, but that distinction must be measured and communicated.

## 12. Circuit-network compatibility

### Recommendation

Add circuits later through one visible field controller and/or dispatcher entity. The runtime API exposes red/green networks through [`LuaControlBehavior::get_circuit_network`](https://lua-api.factorio.com/latest/classes/LuaControlBehavior.html#get_circuit_network), while script-managed combinator behavior can expose outputs.

Sample inputs at a modest staggered cadence and emit an internal policy-change event only when values change. Useful inputs include enable field/job type, priority, reserved-machine count/pool, storage-high conditions, and desired capability/tier. Useful outputs include lifecycle, progress, pending jobs, assigned/working/blocked machines, and remaining work.

Keep scheduler policy as plain data so GUI defaults and circuits call the same interface. Circuit disconnection should restore explicit defaults rather than preserve stale values.

### Main risk

Reading every controller every tick and rewriting unchanged signals wastes time. Index connected/enabled controllers and update only changed aggregates.

### What to prototype first

After the field/vehicle gate, prove one enable input, priority input, and status output without changing scheduler internals.

## 13. Multiplayer and save stability

- Initialize schema in `on_init`.
- Store `schema_version`; use migrations or `on_configuration_changed` for upgrades.
- `on_load` may rebuild local aliases/handlers but must not mutate `storage` or game state. The [data lifecycle documentation](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html) warns that other behavior can desync multiplayer and replays.
- Store stable numeric IDs and generation counters. LuaObject references may be persisted but must be checked for `.valid` before use.
- Treat visual caches and derived indexes as rebuildable where practical.
- Register or handle entity destruction and release reciprocal reservations/claims.
- Store path request IDs and route generations; discard late results from obsolete generations.
- Use deterministic tie-breaking and no wall-clock state.
- Keep authoritative fields, jobs, routes, and machines global to the simulation; only UI is player-specific.

The primary correctness risk is stale asynchronous/controller state after destruction, reassignment, migration, or delayed path results. Generation tokens and invariant checks are the main defense.

### What to prototype first

Save/load during every controller phase, join a multiplayer host while vehicles move, destroy assigned machines, and run a schema migration. Verify identical progress and scheduler invariants afterward.

## 14. Recommended MVP architecture

```text
Field controller/UI
       |
       v
Field state ----------> indexed per-surface scheduler <---------- machine capabilities
bounds/lifecycle            jobs/reservations                     tractor+implement
strip intervals             priority/retry                        visible car
lane claims                       |                                attached sprite
       |                           v                                    |
       +-------------------- machine assignment ------------------------+
                                   |
                                   v
                         travel/work controller
                         native async path request
                         custom waypoint steering
                         exact field lanes
                                   |
                  +----------------+----------------+
                  v                                 v
          progress interval delta           visual dirty ranges
                                                tiles/rendering
```

Recommended module boundaries:

- `field`: geometry, lifecycle, intervals, completion, lane generation;
- `jobs`: transitions, queues, assignment, retry;
- `machines`: capability and compound tractor/implement identity;
- `movement`: path requests, steering, and recovery;
- `visuals`: disposable projection from state;
- `circuits`: later translation between signals and scheduler policy;
- `migrations`: schema upgrades and invariant repair.

The field module must not know about AAI or circuits. The scheduler must not steer entities. Movement reports arrival, failure, and progress events but does not advance lifecycle directly.

### First vertical slice

1. One 64 × 32 rectangular field and one entrance.
2. One fixed tractor/cultivator compound unit.
3. One manually created cultivation job.
4. Native path to the entrance.
5. Deterministic lanes and partial interval completion.
6. Visible cultivated projection.
7. Interruption, save/load, resume, completion, and telemetry.

Only after this passes should sowing, growth, harvest, crop storage/capital, and multiple fields be added.

## 15. Technical risks

| Risk | Severity | Mitigation/smallest adjustment |
|---|---:|---|
| Car controller fails to converge reliably | High | Improve low-speed controller/roads; compare AAI; retain physical movement |
| 200+ active cars exceed UPS budget | High | Stagger, cache, cap path concurrency; distinguish owned from active fleets |
| Congestion causes stall/repath feedback | High | Entrance queues, broad routes, deterministic yield, blocked telemetry |
| Work ranges fragment | Medium | Promote only fragmented chunks to packed bitmaps |
| Tile visuals conflict with terrain/mods | Medium | Restorable field tiles or compressed render projection |
| Visual batches hitch | Medium | Dirty ranges and bounded batches across ticks |
| AAI couples behavior/dependencies/license | Medium | Optional adapter only |
| Stale claims/path results corrupt work | High | Generation tokens, reciprocal references, invariant tests |
| Migration becomes area-proportional | Medium | Version and migrate per field/chunk incrementally |

No identified limitation requires passive timer fields, teleporting machinery, or removal of field geometry.

## 16. Proposed technical spikes

### Spike 1 — Custom car controller and pathfinder (go/no-go critical)

- Implement minimal `request_path` integration and car steering.
- Test travel, exact lane entry, long passes, turns, obstruction, collision, and recovery.
- Scale 1/10/100/200/300 active vehicles.
- Capture controller time, UPS, path latency/backlog, repath/stuck/collision rate, completion, and position error.

### Spike 2 — Compressed state and visuals (go/no-go critical)

- Implement strip intervals, synthetic fragmentation, and a packed-chunk comparator.
- Compare tile and compressed-render projections at 1 million and 10 million logical cells.
- Capture runtime update, memory, save/load, rendering, and restoration.

### Spike 3 — AAI comparator

- Run current AAI in the same 100-vehicle route/lane scenario.
- Determine whether exact lane handoff is stable and conflict-free.
- Compare performance, precision, stuck rate, dependencies, UX, and integration effort.

### Spike 4 — Scheduler invariants

- Run thousands of synthetic jobs with randomized deterministic assignment, interruption, destruction, retry, and priority changes.
- Assert reciprocal assignment, at-most-one claim, monotonic completed area, and eventual release.

### Spike 5 — Save/load and multiplayer soak

- Save/load in every machine state and during pending path requests.
- Join/reconnect while vehicles work.
- Run a two-hour deterministic soak with destruction, field disable/enable, and a schema migration.

Spikes 1 and 2 answer the material feasibility uncertainties and should precede full gameplay code.

## 17. Go / no-go recommendation

**GO to technical prototyping. NO-GO to full gameplay implementation until Spikes 1 and 2 pass.**

The current design can be implemented without unacceptable known API limitations. Spatial fields, partial work, lane geometry, fixed tractor/implement units, centralized scheduling, field visuals, circuits, saves, and multiplayer all have viable Factorio 2.x mechanisms, and the architecture can avoid entity-per-cell and per-tick area scans.

The unresolved question is quantitative: how many concurrently steered cars operate reliably within the UPS budget, especially under congestion. The responsible next step is the one-field vertical slice plus scale harness, not the complete cultivate/sow/grow/harvest economy.

If both custom and AAI controller spikes fail at the desired active-fleet scale, the smallest design adjustment is to limit simultaneously active machinery through dispatch/path concurrency and emphasize higher-capacity equipment. That does not require abandoning physical fields, machinery movement, geometry, or capacity bottlenecks.

## 18. Source register

Current primary sources checked on 2026-08-13 and 2026-08-14:

- Factorio Runtime API: [`LuaSurface::request_path`](https://lua-api.factorio.com/latest/classes/LuaSurface.html#request_path) and [`PathfinderFlags`](https://lua-api.factorio.com/latest/concepts/PathfinderFlags.html).
- Factorio Runtime API: [`LuaControl::riding_state`](https://lua-api.factorio.com/latest/classes/LuaControl.html#riding_state), [`RidingState`](https://lua-api.factorio.com/latest/concepts/RidingState.html), and [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html).
- Factorio Prototype API: [`CarPrototype`](https://lua-api.factorio.com/latest/prototypes/CarPrototype.html).
- Factorio Runtime API: [`LuaSurface::set_tiles`](https://lua-api.factorio.com/latest/classes/LuaSurface.html#set_tiles) and [`LuaRendering`](https://lua-api.factorio.com/latest/classes/LuaRendering.html).
- Factorio Auxiliary API: [`Storage`](https://lua-api.factorio.com/latest/auxiliary/storage.html), [`Data lifecycle`](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html), and [`Libraries and functions`](https://lua-api.factorio.com/latest/auxiliary/libraries.html).
- Factorio Runtime API: [`LuaBootstrap`](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html) and [`LuaControlBehavior`](https://lua-api.factorio.com/latest/classes/LuaControlBehavior.html).
- Factorio Mod Portal: [AAI Programmable Vehicles](https://mods.factorio.com/mod/aai-programmable-vehicles), including current version, compatibility, description, dependencies, and license metadata.

The official `latest` URLs intentionally point readers at the maintained 2.x documentation. Re-check the displayed API version before implementation if Factorio has advanced beyond 2.1.x.
