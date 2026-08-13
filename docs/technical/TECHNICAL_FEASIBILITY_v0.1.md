# Factorio Farming — Technical Feasibility v0.1

## 1. Executive conclusion

Go. The current Factorio Farming design appears technically feasible as a Factorio 2.x mod without a fundamental API blocker.

The strongest findings are:

- Fields do not need one runtime entity or one Lua table entry per tile. Rectangular, lane-based fields can be represented compactly as field metadata plus generated lanes and compressed lane progress.
- Factorio 2.x exposes `LuaSurface.request_path()` specifically for script pathfinding, and the official documentation explicitly notes that the resulting path can be used to emulate pathing for non-unit entities such as vehicles.
- Car-type vehicles expose writable `riding_state`, `speed`, and `orientation`, so a scripted autonomous vehicle controller is possible.
- Factorio does not provide a turnkey autonomous-car equivalent of train schedules. Steering, waypoint progression, recovery, and request throttling must be implemented in Lua unless delegated to another mod such as AAI Programmable Vehicles.
- Deterministic field lanes should not use global pathfinding for each pass. Once a tractor reaches a field entrance, field movement can be generated directly from known rectangular geometry.
- Jobs, field state, machine assignments, growth deadlines, lane claims, and telemetry can live in persistent storage.
- Circuit-network integration fits naturally at field-controller or dispatcher entities and does not require redesigning the core architecture.
- Field visuals can be handled primarily with custom tiles plus sparse rendering/debug overlays, avoiding large crop-entity counts.

The primary feasibility risk is therefore large-scale vehicle movement, not field state.

The recommended MVP technical architecture is:

1. script-owned rectangular fields;
2. lane/range work state;
3. custom minimal vehicle controller;
4. Factorio pathfinder for world travel only;
5. deterministic lane waypoints inside fields;
6. one physical tractor plus script-side implement component;
7. event-driven surface-level job queues;
8. custom tiles for dense field visuals;
9. staggered updates and no full-field scans.

AAI should not be made a mandatory dependency yet. It is current and maintained, and its existence is useful evidence that programmable car fleets are viable, but it solves a broader RTS vehicle-control problem than the farming MVP needs. The best next step is a direct AAI-vs-custom spike.

---

## 2. Feasibility summary table

| Area | Feasibility | Risk | Recommended approach |
|---|---|---:|---|
| Spatial field state | High | Low–Medium | Field + lanes + compressed ranges |
| Partial progress | High | Low | Per-lane distance/ranges |
| Very large fields | High | Medium | Never scan full area during runtime |
| Vehicle world travel | Feasible | High | `request_path` + scripted steering |
| Precise field lanes | High | Medium | Deterministic field waypoints |
| Collision recovery | Feasible | High | Stuck/recovery state machine |
| AAI integration | Feasible | Medium | Benchmark, not hard dependency yet |
| Tractor + implement | High | Low | Compound scripted unit |
| Job scheduling | High | Low | Indexed, event-driven queues |
| Multi-machine lane claiming | High | Medium | Per-lane claims |
| Field visuals | High | Low–Medium | Tiles + sparse rendering |
| Hundreds of vehicles | Plausible | High | Benchmark required |
| Circuit integration | High | Low | Controller/dispatcher entity |
| Save/load | High | Low | Versioned `storage` schema |
| Multiplayer | High | Medium | Deterministic IDs/order/state |

---

## 3. Field-state representation

The current design requires fields to be spatial workloads with partial progress, implement width, interruption/resumption, and eventual multiple-machine support.

### Rejected primary model: one Lua entry per tile

A structure like:

```lua
field.cells[x][y] = state
```

is simple but scales poorly in Lua memory and save size. Millions of conceptual field cells should not become millions of Lua table entries if the actual work pattern is regular.

This is acceptable for tiny prototypes but not as the canonical megabase representation.

Risk: Medium–High at scale.

### Rejected model: hidden entity per cell

This creates engine objects proportional to field area and is unnecessary for the design.

Risk: High.

### Tiles as authoritative simulation state

Factorio exposes tile read/write APIs including `LuaSurface.set_tiles()`. Tiles are excellent for dense visuals and can encode coarse field state, but they are awkward as the only source of truth for lane claims, scheduler state, partial-lane progress, and interruption.

Recommendation: use tiles as a visual projection, not the canonical job model.

### Chunk state

Factorio chunks are useful for spatial indexing and dirty-region batching, but chunk-only state is too coarse for working width and partial lanes.

Recommendation: use chunks as a secondary index.

### Recommended primary model: lane-based compressed state

Rectangular fields and parallel passes give a much better representation:

```text
Field
  bounds
  entrance
  orientation
  lifecycle_state
  active_operation
  lanes[]
  completed_area
  required_area

Lane
  start
  end
  coverage_width
  status
  claimed_by
  completed_distance OR completed_ranges[]
```

For ordinary monotonic work, a lane can often be represented with a single completed distance. If interruption or overlap creates holes, that lane can upgrade to a short interval list.

This makes memory scale approximately with lane count rather than field area.

### Recommendation

Use:

- field metadata;
- generated lane descriptors;
- scalar/range progress per lane;
- a chunk→field-ID spatial index;
- custom tiles as visual projection.

### Main risk

Mapping implement sweep to tile visuals must be deterministic and efficient.

### Prototype first

Create fields from 100×100 through 1000×1000 tiles, generate lanes for several implement widths, partially complete them, save/reload, and profile field-state update cost.

---

## 4. Vehicle-control options

### Documented API capability

Current Factorio 2.x runtime documentation provides:

- `LuaSurface.request_path{...}` for asynchronous path generation;
- `on_script_path_request_finished` for results;
- `try_again_later` when the pathfinder is overloaded;
- writable car `riding_state`;
- writable car `speed`;
- writable entity `orientation`.

The `request_path` documentation explicitly states that the generated path can be used to emulate pathing for non-unit entities such as vehicles.

This is the key feasibility result: Factorio gives enough primitives to build autonomous tractors.

### Missing built-in feature

There is no documented:

```text
car.set_destination(...)
car.follow_path(...)
car.schedule = ...
```

equivalent for cars.

The mod needs its own controller:

```text
request route
-> receive path
-> steer toward waypoint
-> advance waypoint
-> detect stuck/overshoot
-> recover or re-path
```

### Recommended split

#### World travel

Use Factorio’s global pathfinder for:

- depot → field entrance;
- field → field;
- later implement depot → field;
- unloading destinations.

Cache the active route. Do not request a new path each tick.

#### Field work

Do not use global pathfinding for every lane.

Once at the field entrance, movement is known:

```text
entrance
-> first lane start
-> lane end
-> turn waypoint
-> next lane
-> ...
-> entrance
```

This is both more precise and cheaper.

### Steering

Default to normal car control through `riding_state`, with optional limited use of writable `speed`/`orientation` for stabilization if the prototype needs it.

Avoid teleport-based movement because it undermines the core design requirement that physical travel matters.

### Collision/stuck recovery

Every autonomous machine should have a recovery state:

```text
DRIVING
-> insufficient positional progress
-> STUCK
-> brake
-> short reverse/turn
-> retry
-> re-path if repeated
-> fail/requeue with diagnostic state
```

Track progress toward waypoint, not merely speed.

### Recommendation

Build a custom minimal car controller first.

### Main risk

Collision recovery and stability with many vehicles.

### Prototype first

Repeated loop:

```text
idle -> path to entrance -> drive field lanes -> exit -> return
```

Then scale to 10/50/100/200 vehicles.

---

## 5. AAI vs custom controller

AAI Programmable Vehicles currently supports Factorio 2.x and describes RTS-style autonomous control, waypoints, programmable vehicle data, and circuit interaction for car-type vehicles.

It is strong evidence that programmable vehicle fleets are possible.

### Option A — AAI

Advantages:

- mature autonomous vehicle system;
- existing path/waypoint control;
- broad vehicle compatibility;
- circuit-oriented ecosystem;
- many real-world edge cases already encountered.

Disadvantages:

- much broader scope than the farming MVP;
- external dependency and compatibility risk;
- exact field-lane precision is not guaranteed;
- potential irrelevant UI/progression/system exposure;
- current portal metadata lists no public source repository and a Limited Distribution Only licence, reducing freedom to fork/vendor/adapt;
- exact hundreds-of-farm-vehicles performance is unknown.

### Option B — custom minimal controller

Advantages:

- full control over update cadence and hot paths;
- no unrelated RTS feature set;
- field work can bypass general pathfinding;
- straightforward farming telemetry;
- direct integration with jobs, lane claims, and machine pools;
- no mandatory external dependency.

Disadvantages:

- steering and recovery are our responsibility;
- vehicle-vehicle deadlocks may be difficult;
- scaling is unproven.

### Option C — hybrid

Possible later:

- AAI for world travel;
- custom field-lane controller;
- optional AAI integration rather than hard dependency.

This should not be the first production architecture because maintaining two backends immediately doubles test complexity.

### Recommendation

Prototype both, with custom as the default architectural direction.

Use the same scenario for both:

- common depot;
- several fields;
- fixed entrances;
- identical vehicle count;
- repeated trips;
- record stuck rate, lane accuracy, UPS/script time, dependency/setup complexity.

---

## 6. Lane generation and work execution

For field bounds:

```text
width = x2 - x1
height = y2 - y1
```

Choose the longest dimension for lane direction.

If width ≥ height, run lanes east/west. Otherwise run north/south.

For implement working width W, generate parallel centerlines approximately W apart across the short dimension. The last lane may cover a remainder; field dimensions do not need to divide evenly by implement width.

Use a boustrophedon pattern:

```text
lane 1: A -> B
lane 2: B -> A
lane 3: A -> B
```

This minimizes turns.

### Work application

During productive lane movement:

```text
processed_area += productive_distance_travelled * effective_working_width
```

Do not grant progress based only on elapsed time if the machine is stuck.

### Interruption

Store:

```text
lane.status = PARTIAL
lane.completed_distance = ...
lane.claimed_by = nil
```

A later machine resumes the uncompleted portion.

### Turning

Realistic articulated physics are unnecessary for v0.1.

Use:

1. finish lane;
2. headland/offset waypoint;
3. align to next lane;
4. start productive work again.

Actual non-working movement naturally lowers utilization.

### Multiple machines

Future claiming:

```text
UNCLAIMED -> CLAIMED(machine_id) -> COMPLETE
```

No distributed locking system is required because Factorio scripting is one deterministic simulation.

### Heterogeneous implement widths

This is the main future complication. The simplest first multi-machine implementation should require machines sharing one field operation to use the same effective lane layout/width. Mixed widths can be solved later if needed.

---

## 7. Tractor + implement representation

The early gameplay relationship:

```text
tractor + implement = fixed working unit
```

should not imply realistic towing physics.

### Fully physical trailer entity

Not recommended for v0.1. It creates articulation, collision, turning, and pathfinding complexity that does not add meaningful early gameplay.

### Script-side implement + visual

Recommended authoritative model:

```text
implement = {
  type,
  job_type,
  working_width,
  required_power,
  working_speed
}
```

The tractor remains the one physical car entity.

The implement can be displayed using:

- a rendering sprite attached relative to the tractor; or
- one non-/lightly-colliding visual child entity.

One extra object per tractor is not the scale problem. One object per field cell would be.

### Later equipment pools

Parked implements can later become real selectable entities. Attaching one simply updates the tractor’s implement component and visual.

The scheduler and field model do not need to change.

### Recommendation

Use a compound scripted unit:

- one physical tractor;
- one script-side implement component;
- optional attached visual.

Harvesters can be self-contained machines.

---

## 8. Job scheduler

Use explicit job states:

```text
WAITING
ASSIGNED
ACTIVE
INTERRUPTED
COMPLETED
FAILED_RETRYABLE
FAILED
```

Suggested job fields:

```text
id
surface_index
field_id
job_type
priority
status
required_capability
estimated_work
completed_work
assigned_machine_id
retry_count
created_tick
```

### Avoid polling

Do not make every idle machine scan every field/job every tick.

Maintain indexed waiting queues:

```text
waiting[surface][cultivate]
waiting[surface][sow]
waiting[surface][harvest]
```

and later priority buckets/pools.

Dispatch when:

- a machine becomes idle;
- a relevant new job appears;
- a job is requeued.

### Assignment

For v0.1:

```text
WAITING -> ASSIGNED(machine) -> ACTIVE
```

Future multi-machine field operations can retain one job with multiple machine assignments while individual lanes are claimed separately.

### Priority

Use a few priority buckets rather than repeatedly sorting all jobs.

### Recommendation

A simple surface-level event-driven dispatcher is sufficient.

The main scheduler performance trap is O(all jobs × all machines) distance scanning. Candidate evaluation should be bounded or indexed.

---

## 9. Visual field representation

The player must distinguish:

- uncultivated;
- cultivated;
- sown/growing;
- ready;
- harvested/processed;
- partial work.

### Primary visual: tiles

Use custom field-state tiles, for example:

```text
farm-soil-uncultivated
farm-soil-cultivated
farm-soil-sown
farm-soil-growing
farm-soil-ready
farm-soil-harvested
```

Update only newly processed strips as a machine advances.

Do not repaint entire huge fields every tick.

Growth-stage changes can be batched over ticks if large synchronized updates prove expensive.

### Rendering API

Use sparse render objects for:

- field outline;
- entrance icon;
- lane debug;
- claimed lane indicator;
- route/waypoint debugging.

Do not create one render object per field cell.

### Crop entities

Avoid dense crop entities. Individual wheat plants are unnecessary for the gameplay model and create the wrong scaling pressure.

### Recommendation

Start with tiles + debug overlays. Add decorative crop detail only after performance is proven.

---

## 10. Performance / UPS

The architecture should scale with active changes, not total farm area.

### Vehicle steering

Risk: High.

Hundreds of vehicles updated every tick may be expensive.

Mitigation:

- stagger controllers into tick buckets;
- update idle machines rarely;
- experiment with 3–10 tick steering cadence;
- avoid temporary-table allocation in hot geometry code.

### Pathfinding

Risk: High.

The API explicitly has `try_again_later`, so request saturation is a real design concern.

Mitigation:

- request only on destination change/failure;
- never pathfind individual field lanes;
- cap requests per tick;
- back off on busy result;
- cache active/common routes where safe.

### Per-cell field simulation

Risk: High if naive; Low with lane/range state.

Never scan every cell to determine completion.

Maintain `completed_area` incrementally.

### Growth

Do not poll every growing field.

At sowing completion:

```text
ready_tick = current_tick + growth_duration
```

put the field in a scheduled structure/time bucket.

### Job queue

Risk: Medium–High if polling; Low if event-driven.

### Entity counts

Risk: High if crops/cells are entities.

Hundreds of tractors are a reasonable benchmark target. Hundreds of thousands of crop entities are avoidable.

### Tile updates

Risk: Medium.

Batch large visual changes.

### Recommended update model

```text
events/callbacks:
  immediate bounded processing

vehicles:
  tick-bucket updates

growth:
  scheduled completion ticks

visuals:
  dirty-region queue with per-tick budget

jobs:
  event-driven dispatch
  occasional low-frequency recovery sweep
```

### Key benchmark

Profile 10/50/100/200 moving tractors with:

- steering cost;
- path requests;
- field work state;
- tile updates;
- scheduler cost separated.

---

## 11. Circuit-network compatibility

Current Factorio 2.x APIs expose circuit networks through entities/control behaviours, including circuit-network retrieval and signal reads.

A future field or dispatcher can therefore expose a physical circuit-connected controller entity.

Suggested later boundaries:

- field controller;
- machine-pool dispatcher;
- implement depot/controller.

Potential inputs:

```text
enable field
priority
reserve tractors
enable cultivate
enable sow
enable harvest
machine-size selector
```

Potential outputs:

```text
field area
progress
pending jobs
assigned machines
idle tractors
```

No circuit implementation is needed now.

### Architectural requirement

Use stable IDs and explicit field/job/machine policy state so circuits can modify policy without directly manipulating movement internals.

---

## 12. Multiplayer and save stability

Use Factorio 2.x `storage` for persistent mutable mod data.

Suggested layout:

```text
storage.schema_version
storage.surfaces[surface_index]
storage.fields[field_id]
storage.machines[machine_id]
storage.jobs[job_id]
storage.path_requests[request_id]
```

### Entity references

Stored LuaObjects can become invalid. Check `.valid` after entity-removal possibilities.

Prefer stable script IDs and entity `unit_number` as keys rather than LuaObject references.

### on_load

Do not mutate storage or game state during `on_load`. Use it only for documented reconstruction tasks such as local references/metatables/event setup.

### Migrations

Version persistent schemas immediately.

Use explicit migrations:

```text
v1 -> v2
v2 -> v3
```

### Determinism

When ordering affects outcomes:

- use stable numeric IDs;
- explicitly sort candidate sets when needed;
- avoid relying on unspecified hash-table iteration order;
- use game ticks, not local wall-clock time.

### Save mid-job

Persist enough state to restore:

- machine state;
- current job;
- lane claim;
- lane progress;
- route index or route-regeneration intent;
- scheduled growth completion.

Pending path requests should be mapped by request ID and safely ignored if obsolete.

---

## 13. Recommended MVP architecture

### Surface state

```text
fields_by_id
fields_by_chunk
machines_by_id
waiting_jobs_by_type_priority
active_jobs
path_requests
vehicle_update_buckets
dirty_visual_regions
growth_schedule
```

### Machine state machine

```text
IDLE
-> ASSIGNED
-> REQUESTING_PATH
-> TRAVELING_TO_FIELD
-> ENTERING_FIELD
-> POSITIONING_TO_LANE
-> WORKING_LANE
-> TURNING
-> WORKING_LANE ...
-> LEAVING_FIELD
-> TRAVELING
-> IDLE
```

Recovery:

```text
STUCK_RECOVERY
WAITING_FOR_PATHFINDER
FAILED_RETRYABLE
```

### Field lifecycle

```text
UNCULTIVATED
-> CULTIVATION_ACTIVE
-> CULTIVATED
-> SOWING_ACTIVE
-> GROWING
-> READY_TO_HARVEST
-> HARVEST_ACTIVE
-> HARVESTED
```

Manual mode controls when a new job is generated.

Auto-repeat later only automates those lifecycle transitions; it does not require a scheduler redesign.

### Source-of-truth boundary

Script owns:

- lifecycle;
- lanes/progress;
- jobs;
- pairing/capabilities;
- scheduler policy;
- growth deadlines;
- telemetry.

Factorio engine owns:

- physical entity position/collision;
- map tiles;
- inventories/storage;
- circuit network;
- global pathfinding.

---

## 14. Technical risks

### 1. Custom vehicle controller stability — High

Cars may overshoot, oscillate, deadlock, or get stuck.

Smallest design fallback if required:

Constrain autonomous world travel to designated farm-road tiles/corridors.

This preserves physical movement and layout bottlenecks while simplifying navigation.

Do not adopt this restriction unless the open-world controller actually proves unreliable.

### 2. Pathfinder saturation — High

Mitigate with capped request queues, caching, backoff, and no path requests inside normal field work.

### 3. Vehicle congestion — High at large fleet scale

Mitigation:

- wider roads;
- entrance queues;
- spacing;
- later one-way routes/reservations.

Traffic can become intended gameplay if it is predictable rather than random controller failure.

### 4. Visual update spikes — Medium

Batch dirty tile regions and possibly stagger large growth-stage visual changes.

### 5. Heterogeneous lane coverage — Medium later

Initially keep one field operation on one common lane layout.

### 6. AAI dependency risk — Medium

Keep field/scheduler code independent from the movement backend until the benchmark decision.

---

## 15. Proposed technical spikes

### Spike A — field representation

Build:

- rectangle generator;
- lane generator;
- partial completion;
- compressed progress;
- completed-area counter;
- save/load.

Stress several million tiles of conceptual field area.

Pass: runtime cost follows active lane work, not field area.

### Spike B — one custom tractor

Scenario:

```text
home -> field entrance -> lanes -> home
```

Requirements:

- `request_path` for world travel;
- deterministic field waypoints;
- no teleportation;
- stuck recovery;
- travel/working/turning telemetry.

Pass: 100 repeated cycles without manual correction in a controlled layout.

### Spike C — fleet scaling

Run:

- 10;
- 50;
- 100;
- 200 vehicles.

Measure:

- UPS;
- script time;
- path requests/sec;
- stuck events;
- recovery success;
- trip time.

### Spike D — AAI comparison

Use the same depot/field scenario.

Compare:

- setup;
- dependency footprint;
- precise lane control;
- stuck rate;
- performance;
- circuit fit;
- irrelevant UI/system leakage.

Decision after measurement: custom / AAI / hybrid.

### Spike E — field visuals

Use custom tiles updated only behind active work.

Stress large concurrent fields.

Pass: no dense runtime entities and no unacceptable update spike.

### Spike F — save + multiplayer

Save/reload during:

- pending path request;
- world travel;
- partial lane;
- growth timer.

Repeat in a two-player test.

Pass: no duplicated work, lost claims, stale assignments, or desync.

---

## 16. Go / no-go recommendation

GO to technical spikes.

Do not start full gameplay implementation until the vehicle and scale spikes pass.

The current design does not appear to require a fundamental compromise. Rectangular fields and parallel lanes are especially favorable because they let us represent spatial farming compactly and avoid global pathfinding during most productive movement.

The smallest architecture worth prototyping is:

1. one car-type tractor;
2. one fixed script-side cultivator;
3. one rectangular field;
4. one entrance;
5. generated parallel lanes along the longest dimension;
6. lane progress stored as completed distance/ranges;
7. `LuaSurface.request_path` only for home ↔ field entrance;
8. custom steering for world route;
9. deterministic field waypoints;
10. tile strips changing as work physically advances;
11. one cultivation job through waiting → assigned → active → complete;
12. save/reload in the middle;
13. then load-test the same architecture with many tractors and fields.

If this fails, the likely failure point is vehicle world-navigation scale/stability. The smallest viable design adjustment is to constrain autonomous vehicles to a farm-road/corridor network. That would preserve all important design pillars: physical fields, physical machinery, capacity bottlenecks, geometry, travel time, one entrance, lane work, and megabase-scale logistics.

---

## Research sources

Official Factorio 2.x documentation:

- [LuaSurface](https://lua-api.factorio.com/latest/classes/LuaSurface.html)
  - `request_path`
  - `set_tiles`
- [LuaControl](https://lua-api.factorio.com/latest/classes/LuaControl.html)
  - writable `riding_state`
- [LuaEntity](https://lua-api.factorio.com/latest/classes/LuaEntity.html)
  - writable `speed`
  - writable `orientation`
- [Events](https://lua-api.factorio.com/latest/events.html)
  - `on_script_path_request_finished`
- [LuaRendering](https://lua-api.factorio.com/latest/classes/LuaRendering.html)
- [LuaCircuitNetwork](https://lua-api.factorio.com/latest/classes/LuaCircuitNetwork.html)
- [LuaControlBehavior](https://lua-api.factorio.com/latest/classes/LuaControlBehavior.html)
- [Storage](https://lua-api.factorio.com/latest/auxiliary/storage.html)
- [Factorio 2.0 modding tutorial / multiplayer notes](https://wiki.factorio.com/Tutorial:Modding_tutorial)

AAI Programmable Vehicles:

- https://mods.factorio.com/mod/aai-programmable-vehicles
- https://mods.factorio.com/mod/aai-programmable-vehicles/downloads
- https://mods.factorio.com/mod/aai-programmable-vehicles/changelog

Current mod-portal observations during this investigation:

- AAI has current Factorio 2.x releases, including 2.0 and 2.1.
- It advertises autonomous control of car-type vehicles, paths/waypoints, and circuit-oriented automation.
- The portal lists Earendel as owner.
- The portal currently lists no public source repository and a Limited Distribution Only licence.

---

## Decision checkpoint

- Field representation: lane/range state + chunk spatial index.
- Field visuals: custom tiles + sparse rendering.
- World navigation: Factorio asynchronous path requests.
- Field navigation: deterministic generated waypoints.
- Vehicle controller: custom minimal controller as default prototype.
- AAI: benchmark alternative; dependency not locked.
- Tractor + implement: one physical tractor + script-side implement + visual.
- Scheduler: surface-level event-driven indexed queues.
- Persistence: versioned storage schema with stable IDs.
- Performance: stagger active agents, schedule growth, batch dirty visuals, never scan whole fields per tick.
- Project status: GO to technical spikes; NO-GO to full gameplay implementation until vehicle/scale spikes pass.
