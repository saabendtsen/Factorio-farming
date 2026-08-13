Factorio Farming — Design v0.1

Working vision

Farming at Factorio scale.

The game/mod should treat agriculture as a large production and logistics system:

• Fields generate work.
• Machinery provides capacity.
• Storage constrains expansion.
• Logistics determines real throughput.
• Scaling should create new bottlenecks, not merely larger numbers.

The player should optimize systems rather than micromanage workers or manually drive vehicles.

────────

Core design principles

1. Fields are production systems

A field is not just a passive timer that periodically outputs crops.

It creates a sequence of operations that must physically be performed by machinery.

Initial field lifecycle:

cultivate -> sow -> grow -> harvest -> store

Later systems may add fertilizer, spraying, soil condition, weather, seasons, etc., but these are explicitly outside Design v0.1.

2. Machinery is capacity

Machines physically travel to fields and work them.

Their practical throughput depends on things such as:

• working width
• movement speed
• field size
• travel time
• routing
• idle time
• unloading/refilling
• availability of suitable implements

This should create the same kind of capacity-planning problems as assemblers and logistics systems in Factorio.

Example design question:

> Is it better to run several small tractors with narrow implements, or invest in fewer large tractors with wider implements?

Neither answer should always be optimal.

3. Physical movement matters

Vehicles should not teleport between jobs.

Travel time, routing and physical positioning should affect utilization.

At larger scale, poor farm layout should therefore become a real bottleneck.

The player should eventually be able to look at a machine and understand whether its time is spent:

• working
• traveling
• waiting
• idle

4. Automation over employees

Avoid a traditional employee-management system.

The preferred model is closer to drones/logistic agents:

idle -> find job -> fetch/attach implement -> travel -> perform operation -> unload/refill if needed -> next job

The gameplay should be about designing and supplying the system rather than managing named workers, schedules, salaries or personalities.

5. Scaling must introduce new problems

A farm ten times larger should not simply require ten times as many identical machines.

Increasing scale should gradually expose new constraints:

• machinery throughput
• travel distance
• storage
• unloading
• routing
• traffic/congestion
• processing capacity
• logistics hubs
• later potentially rail and bulk transport

The desired experience is similar to discovering why a Factorio production block is achieving only part of its theoretical throughput.

────────

Economy and progression

A conventional money-first economy is deliberately avoided as the primary progression system.

The concern is that a pure money economy collapses most production decisions into a single metric:

gold per hour

That would make older crops obsolete as soon as a more profitable crop becomes available.

Instead:

Production rate unlocks capability

New crops, machinery tiers and systems should primarily be unlocked through production performance.

The exact unlock system is not locked yet.

A future candidate is contracts or throughput milestones, for example:

• sustain a required wheat throughput
• fulfill a large delivery target within a time window
• demonstrate a certain production capacity

Contracts are considered promising, but are not part of Design v0.1.

The important principle is that unlocks should reward efficient production, not merely waiting until a lifetime total is reached.

Stored crops are capital resources

Crops themselves are used to purchase machinery and infrastructure.

Example only — numbers are not balance targets:

• Small barn capacity: 100 t wheat
• Medium barn cost: 50 t wheat
• Medium barn capacity: 1,000 t wheat
• Medium tractor cost: 300 t wheat

This creates a progression loop where storage itself becomes strategically important.

The player may need to invest crops into storage before they can accumulate enough resources to purchase the next machinery tier.

Early crops remain relevant

Late-game machinery and infrastructure should continue to require meaningful quantities of earlier crops.

Example:

A late-game purchase might require:

• wheat
• barley
• corn
• rapeseed

This prevents newly unlocked crops from simply replacing previous production chains.

A player’s old wheat system should remain worth optimizing deep into progression.

Care must be taken not to simply replace gold/hour with wheat/hour; multiple commodities should eventually contribute to important purchases.

Gold is secondary

Gold/money may exist, but should not be the primary progression currency.

A promising model is:

crop output -> storage -> reserve stock -> overflow -> market -> gold

Gold therefore represents surplus production rather than the direct purpose of farming.

Possible future uses:

• land
• fuel
• electricity
• maintenance
• transport fees
• services
• operating costs

Core machinery and infrastructure should not become directly purchasable with gold if doing so allows the player to bypass commodity progression.

Working design shorthand:

Crops are capital. Gold is surplus.

And:

Throughput unlocks capability. Stockpiles purchase capacity.

────────

Storage as gameplay

Storage is not only a buffer.

It is part of progression and capacity planning.

Example:

A machine costs 300 t wheat, but the player’s current storage can only hold 100 t.

The player must first invest in larger storage.

This should be communicated clearly in UI so it feels like a solvable infrastructure problem rather than an arbitrary progression wall.

Future automation possibilities could include rules such as:

• sell wheat when storage > 80%
• keep at least 5,000 t barley
• export corn only when silo B is full

These are not required for the first implementation.

────────

Initial gameplay loop

The first minutes should expose the real identity of the project immediately.

Initial crop:

Wheat only

Initial loop:

cultivate -> sow -> grow -> harvest -> store wheat

The player starts with a very small farming setup, likely including:

• one small field
• one small tractor
• simple implements
• one small harvester
• one small barn/silo

Exact equipment is not locked yet.

The first progression objective is to produce enough wheat to invest in the next step.

The player should quickly experience:

1. machinery physically performing field work
2. production taking measurable time
3. storage filling
4. crops being spent on infrastructure/equipment
5. expansion causing the original machinery to become insufficient

The core early-game realization should be:

> My farm has grown beyond the throughput of my current machinery.

────────

MVP / first playable iteration

The first implementation should answer one question:

> Is it fun to build an increasingly large wheat farm where progression is driven by throughput, storage and machinery capacity?

It should prove these concepts:

1. A field is a real work area, not just a timer.
2. Machines have finite throughput.
3. Machines physically move between jobs.
4. Storage is a meaningful constraint.
5. Crops function as capital resources.
6. Increasing farm size creates bottlenecks.
7. Upgrading or parallelizing machinery noticeably solves those bottlenecks.

Potential MVP end-state:

> Reach a medium-scale automated wheat farm and accumulate a large wheat stockpile.

An earlier illustrative target was 1,000 t wheat stored, but exact numbers are intentionally not locked.

────────

Useful MVP telemetry

Even crude debug UI should expose information useful for diagnosing throughput.

Example field data:

• area
• current operation
• progress
• estimated completion time

Example vehicle data:

• utilization
• percentage working
• percentage traveling
• percentage waiting
• percentage idle

These metrics are part of the gameplay feedback loop, not merely developer diagnostics.

────────

Explicitly out of scope for Design v0.1

Do not add these until the core loop has been proven:

• multiple crops
• seasons
• weather
• soil chemistry
• fertilizer complexity
• fuel
• maintenance
• contracts
• dynamic markets
• employees
• food processing
• trains
• large technology trees
• detailed economic simulation

Many of these may become valuable later, but none are required to validate the core game.

────────

Future design directions

These are promising but intentionally not yet designed in detail.

Contracts as progression

Contracts could act as throughput benchmarks rather than generic quests.

Example concept:

> Deliver or sustain 120 t wheat/hour.

A player may have 150 t/hour theoretical field capacity but achieve only 94 t/hour due to poor unloading or routing.

The contract then becomes a benchmark for the production system.

Processing chains

Later progression may add chains such as:

wheat -> flour -> bread

Processing should create another layer of capacity and logistics rather than simply multiplying sale value.

Bulk logistics

A larger farm could develop logistics such as:

combine -> grain cart -> truck -> silo -> processor

A harvester stopping because its internal storage is full should be analogous to an assembler blocked on output.

Large-scale farm networks

Long-term scale could involve:

• many fields
• fleets of tractors
• harvesters
• logistics vehicles
• processing hubs
• bulk storage
• rail terminals

The desired end-game visual is a farm operating at megabase scale, with large numbers of autonomous machines moving through a system the player has designed.

────────

Technical direction to investigate later

Factorio is currently the preferred platform because it already provides:

• very large map scale
• logistics systems
• inventories
• research/progression infrastructure
• trains
• circuits
• blueprints
• performance-conscious simulation
• mod support

A future technical feasibility phase should investigate:

• field representation
• vehicle pathfinding
• autonomous job scheduling
• machine/implement interaction
• performance at large scale
• whether to depend on AAI vehicle systems or implement a custom simplified controller

No technical architecture is considered locked yet.

────────

Current design checkpoint

The following are considered strong working decisions:

• Factorio-scale farming is the core fantasy.
• The game is primarily about optimization and automation.
• Machines physically operate on fields.
• Employees are avoided in favor of autonomous machine agents.
• Travel and routing matter.
• Machinery throughput should become a bottleneck.
• Wheat is the first crop.
• The first lifecycle is cultivate -> sow -> grow -> harvest -> store.
• Production performance drives unlocks.
• Stored crops are used as capital resources.
• Storage is part of progression.
• Early crops remain economically relevant in later tiers.
• Gold is secondary rather than the primary progression resource.
• Contracts are promising, but postponed.
• The first playable version should stay extremely small and prove the core loop before adding simulation depth.