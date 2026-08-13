Factorio Farming — Machinery v0.1

Purpose

This document defines the first working design for tractors, implements, harvesters, and machinery throughput.

The goal is not detailed vehicle simulation.

The goal is to create machinery choices that generate meaningful capacity-planning and layout problems at Factorio scale.

Exact prices, speeds, power values, working widths, and balance numbers remain TBD until prototyping.

────────

Core machinery principle

Machine tiers should trade scale for flexibility.

Larger machinery should dominate on large, regular fields.

Smaller machinery should remain useful on:

• small fields
• narrow fields
• fragmented production areas
• crops that only require limited production capacity

The design should avoid artificial penalties such as:

> Large machines receive -30% efficiency on small fields.

Instead, the trade-off should emerge naturally from geometry, travel, turning, and utilization.

────────

Machinery as production capacity

Machinery is the farm equivalent of production machines in Factorio.

A machine’s value is not only its nominal speed.

Its real production capacity depends on:

• working width
• working speed
• travel time
• turning time
• waiting time
• field geometry
• compatibility with implements
• later: unloading/refilling and implement changes

The player should be able to compare theoretical capacity with realized capacity and optimize the gap.

────────

Tractor model

The first tractor model should remain deliberately simple.

Initial tractor properties:

• Power
• Travel speed
• Cost

Possible later properties:

• turning radius
• physical size
• fuel consumption
• maintenance
• traction
• weight

These later properties should not be introduced unless they create meaningful automation or layout gameplay.

Tractor power

Power is primarily a compatibility constraint.

Example:

• Small tractor: 80 hp
• Medium tractor: 140 hp
• Large tractor: 250 hp

An implement may require:

• 60 hp
• 120 hp
• 220 hp

A tractor below the required power cannot operate that implement.

A tractor far above the power requirement should not automatically make the implement dramatically faster.

Example:

A 300 hp tractor attached to a 3 m cultivator should not cultivate three times faster than a 100 hp tractor if both meet the implement requirement.

This prevents tractor tiers from becoming simple linear speed upgrades.

────────

Implement model

Initial implement properties:

• Job type
• Required power
• Working width
• Working speed
• Cost

Examples of job types:

• cultivation
• sowing
• later: fertilizing, spraying, etc.

In the early game:

tractor + implement = fixed job unit

Example:

Tractor A + cultivator = cultivation unit

Tractor B + seeder = sowing unit

The unit automatically accepts compatible jobs.

Dynamic tractor/implement pooling is a later automation unlock described in the progression design.

────────

Theoretical throughput

A first-order approximation:

theoretical throughput ~= working width × working speed

This represents the amount of field area the combination can process while actively working.

It is not the player’s actual throughput.

────────

Real throughput

Real throughput should account for non-working time.

Conceptually:

real throughput = theoretical throughput × utilization

Where utilization is reduced by:

• turning
• travel between farm and field
• positioning
• waiting for work
• poor field fit
• later: implement swapping
• later: unloading/refilling

The exact calculation does not need to be exposed as a complex simulation formula.

The important gameplay outcome is that two machines with similar theoretical capacity may achieve very different real throughput depending on farm layout.

────────

Utilization

Useful machinery telemetry should eventually show:

• Working %
• Traveling %
• Turning %
• Waiting %
• Idle %

This is intended to be gameplay feedback, not only debugging information.

Example player diagnosis:

> The new large cultivator has excellent theoretical capacity, but it only works 61% of the time because the assigned fields are too small and far apart.

That should lead naturally to layout or fleet changes.

────────

Field geometry and machinery size

Large fields

Large implements should perform very efficiently when fields have:

• long working lanes
• sufficient width
• predictable rectangular geometry
• enough turning/headland space

A large machine should spend a high percentage of its time doing productive field work.

Small fields

Small or narrow fields naturally reduce large-machine utilization.

A large implement may complete each working lane very quickly but spend a larger percentage of its cycle:

• turning
• positioning
• entering/leaving the field

A smaller implement has lower theoretical throughput but may have better real utilization.

This keeps smaller machinery relevant without arbitrary stat penalties.

────────

Turning and headland

Larger machine combinations should require more room to turn.

The first iteration does not require realistic vehicle physics.

Instead, machinery size may define a simplified turning/headland requirement.

Conceptually:

• small combination -> small turning overhead
• medium combination -> moderate turning overhead
• large combination -> significant turning/headland requirement

This creates a layout decision:

> Should several small fields be merged into one large field so that large machinery can operate efficiently?

Field layout therefore becomes part of production optimization.

────────

Field fit

A useful conceptual metric is how well an implement fits a field.

Factors include:

• field width
• field length
• implement working width
• number of required lanes
• turning overhead

Example:

A 12 m implement on a very narrow field may have excellent width but poor utilization.

A 4 m implement may process the same field more efficiently in real time despite lower theoretical throughput.

The game may later expose a simple recommendation such as:

Recommended implement size: Small-Medium

This should be informational only.

It must not become a hard restriction.

────────

Why smaller machinery remains relevant

Small machinery should remain strategically useful later in the game because:

• some crops may only need small production volumes
• fragmented layouts may favor smaller equipment
• small fields create lower turning overhead
• specialized production areas may not justify large equipment
• shared equipment pools may benefit from a mixed fleet

Crop diversity can therefore naturally create different optimal scales.

Example:

Wheat -> huge fields -> large machinery

Rapeseed -> smaller fields -> small/medium machinery

This helps prevent late-game progression from becoming:

> Replace every machine with the largest tier.

────────

Harvester model

Harvesters can initially be self-contained machines rather than tractor + implement combinations.

Initial properties:

• Working width
• Working speed
• Internal storage
• Travel speed
• Cost

Later, internal storage creates a major logistics bottleneck:

harvester -> grain cart -> truck -> silo

For the earliest prototype, unloading may be simplified.

The long-term design should allow harvesters to stop when their internal storage is full, making output logistics analogous to blocked assembler output in Factorio.

────────

Design rules

The following are strong working decisions:

• Machinery represents production capacity.
• Tractor power is primarily a compatibility constraint.
• Implements define job type, width, and working speed.
• Larger machinery should not simply obsolete smaller machinery.
• Large machines dominate large, regular fields.
• Small machines retain better flexibility on small or fragmented fields.
• Trade-offs should emerge from geometry and utilization rather than arbitrary penalties.
• Travel and turning count against real throughput.
• Theoretical and realized throughput should be distinguishable.
• Field layout is part of machinery optimization.
• Detailed fuel, maintenance, traction, and durability simulation is postponed.
• Exact machinery stats and balance values remain TBD.

────────

Open questions

These can wait until prototyping:

• How should turning time be calculated?
• Should turning radius be a visible stat or an internal abstraction?
• How much headland should each machine tier need?
• Should implements have strict power requirements or efficiency curves near the minimum?
• Should very large implements have transport-width constraints outside fields?
• When should harvester unloading become fully physical?
• How should utilization be surfaced in UI?
• Should the game recommend machinery size for a field?