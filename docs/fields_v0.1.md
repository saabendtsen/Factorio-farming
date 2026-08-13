Factorio Farming — Fields v0.1

Purpose

This document defines the first working design for fields.

The field system is the bridge between crop progression, machinery throughput, and automation.

The goal is to make a field behave like a physical production surface rather than a passive timer.

Exact tile sizes, lane-generation algorithms, crop timings, and implementation details remain TBD until technical feasibility testing.

────────

Core field principle

A field is a spatial workload.

A field does not simply produce crops after a timer expires.

Instead, it moves through a sequence of operations that must be physically performed across its area.

Initial lifecycle:

cultivate -> sow -> grow -> harvest -> ready for next cycle

For Design v0.1, wheat is the only crop.

────────

Field creation

The first implementation uses rectangular fields only.

The player creates a field by selecting a rectangular area.

Each field has:

• rectangular bounds
• one entrance/exit point
• crop assignment
• current lifecycle state
• per-area work state
• generated work lanes
• pending jobs
• assigned machines
• completion progress

Irregular shapes and freeform field drawing are postponed.

The design should leave room for them later if the technical model proves robust.

────────

Entrance / exit

Each field has one defined entrance/exit point in the first iteration.

Machines travel through the normal world to that point.

From there they enter the field work pattern.

Conceptual flow:

farm network -> field entrance -> work lanes -> field entrance -> next destination

Using one access point simplifies:

• routing
• lane generation
• machine handoff
• debugging
• traffic reasoning

Multiple entrances may be added later if large-scale logistics require them.

────────

Field lifecycle

The initial lifecycle is:

1. Uncultivated

The field requires cultivation.

Compatible cultivation units may accept work.

2. Cultivated

The field requires sowing.

Compatible sowing units may accept work.

3. Sown / Growing

No field machinery work is required while growth progresses.

Growth is currently treated as time-based.

Detailed crop simulation is out of scope.

4. Ready to harvest

Compatible harvesters may accept work.

5. Harvested / cycle complete

The field is ready to begin another crop cycle.

In manual mode, the player initiates the next operation.

With auto-repeat unlocked, the field automatically generates the next required job.

────────

Spatial work state

Field work should be tracked spatially.

The preferred conceptual model is a grid/cell or tile-based work state.

Example:

A cultivation operation does not set:

Field 1 = 63% cultivated

as a single abstract number.

Instead, the machine physically processes portions of the field and changes their state.

Conceptually:

uncultivated cell -> cultivated cell

The same applies to sowing and harvesting.

This enables:

• visible partial completion
• interruption and resumption
• multiple machines working simultaneously later
• real implement working width
• overlap detection
• geometry-sensitive throughput
• lane-based movement
• meaningful work visualization

The exact internal representation is a technical feasibility question.

────────

Work lanes

For the first iteration, fields generate simple parallel lanes.

The lane orientation should be chosen from the field geometry.

A basic default:

• use the longest field dimension as the lane direction
• generate parallel passes across the shorter dimension

This minimizes turning overhead in most rectangular fields.

Example:

A long, narrow field should produce long working passes rather than many short passes.

The exact path-generation algorithm remains TBD.

────────

Implement width and lanes

The working width of the attached implement determines how much area is processed during a pass.

Conceptually:

3 m implement -> narrow lane coverage

9 m implement -> wide lane coverage

The field system must support different widths without requiring different field definitions.

This is important because field geometry and machine choice should interact naturally.

────────

Turning / headland

Machines need some non-working movement when transitioning between lanes.

For v0.1 this should be simplified.

The field may reserve a conceptual headland area near lane ends, or the machine may use a simplified turning maneuver.

The exact vehicle physics are not important.

The gameplay requirement is:

turning consumes time and therefore lowers real utilization.

Larger machinery should generally incur more turning overhead than smaller machinery.

This supports the existing machinery design principle:

Machine tiers trade scale for flexibility.

────────

Overlap

Already processed areas should not need to be processed again.

If a machine crosses an area that is already complete for the current operation:

• no additional production benefit is gained
• the movement still consumes time

This makes inefficient routing and overlapping passes measurable.

The first automatic lane system should aim to avoid unnecessary overlap.

Future advanced automation may expose more control over routing.

────────

Job generation

Fields generate jobs based on their current lifecycle state.

Examples:

Field 1: needs cultivation

Field 2: needs sowing

Field 3: ready to harvest

A field job should be treated as a first-class object.

Conceptual job properties:

• job type
• field
• priority
• required machine/implement type
• estimated workload
• progress
• status
• assigned machine(s)

Example:

type: cultivate

field: Field 4

priority: normal

required implement: cultivator

workload: TBD

status: waiting

Machines should consume compatible jobs rather than contain field-specific logic.

This keeps the vehicle system generic and supports later dispatch automation.

────────

Fixed machinery in early game

In the early game:

tractor + implement = fixed job unit

Examples:

• Tractor A + cultivator accepts cultivation jobs.
• Tractor B + seeder accepts sowing jobs.
• Harvester accepts harvest jobs.

The machine searches the job queue for compatible work.

Dynamic equipment swapping is introduced later through equipment pools.

────────

Manual field mode

Fields begin with manual operation control.

The player initiates the next lifecycle step.

Example:

Field 1 -> Start cultivation

Once initiated, the field generates a cultivation job.

This gives the player time to understand:

• field lifecycle
• machinery roles
• job assignment
• machine throughput

before full automation is introduced.

────────

Auto-repeat mode

Auto-repeat is an early progression unlock.

A field can then be configured with:

Crop: Wheat

Mode: Auto Repeat

The field automatically generates the next required job when the previous lifecycle stage completes.

Conceptually:

cultivation complete
-> generate sowing job

sowing complete
-> grow

growth complete
-> generate harvest job

harvest complete
-> generate cultivation job

This removes repetitive scheduling without solving machinery capacity.

The player moves from:

> What should this field do next?

to:

> Can my machine fleet keep up with all pending work?

────────

Multiple machines on one field

The architecture should allow multiple compatible machines to work the same field eventually.

However, this does not need to be part of the first technical prototype.

If supported later, the field should divide remaining work so machines do not intentionally duplicate the same lanes.

Potential strategies:

• lane claiming
• work-region splitting
• first-unclaimed-lane assignment

The exact scheduler is a technical design problem.

────────

Operation completion

A field operation is complete when all required work areas for that operation have been processed.

Examples:

Cultivation complete when all cultivatable cells are cultivated.

Sowing complete when all cultivated cells are sown.

Harvest complete when all ready crop cells are harvested.

Progress can therefore be shown as:

completed work area / required work area

rather than only elapsed time.

────────

Growth

Growth is intentionally simple in v0.1.

After sowing completes:

Sown -> Growing -> Ready to harvest

Growth may be represented by:

• a timer
• one or more visual growth stages

No weather, soil chemistry, moisture, fertilizer, disease, or crop-quality simulation is required for the first iteration.

The field system should not be designed around those systems yet.

────────

Harvest output

Harvesting converts ready crop area into wheat output.

The exact output model is TBD.

Possible conceptual models:

• fixed wheat per field cell
• fixed wheat per processed area
• yield modifier applied to field area

For v0.1, yield should remain simple and deterministic.

The important first-order relationship is:

more harvested area -> more wheat

Detailed yield optimization is postponed.

────────

Storage interaction

Harvested wheat eventually enters storage.

For the earliest prototype, transport from harvester to storage may be simplified.

Long-term design should support physical grain logistics:

harvester -> grain cart -> truck -> silo

The field system should therefore not assume that harvested output instantly becomes stored inventory forever.

That logistics layer can be added later.

────────

Field statistics / UI

Useful field information should include:

• field name/id
• dimensions
• area
• assigned crop
• lifecycle state
• current operation
• operation progress
• pending jobs
• assigned machinery
• estimated completion time

Later useful metrics:

• machine utilization on this field
• turning overhead
• travel overhead
• recommended implement size
• realized throughput
• yield history

The first UI can remain crude.

The important requirement is that the player can diagnose why a field is progressing slowly.

────────

Field geometry as gameplay

Field dimensions should matter.

Two fields with the same total area may have different machinery efficiency.

Example:

A long rectangular field may provide:

• long working lanes
• few turns
• high utilization for large machinery

A short/wide or fragmented layout may create:

• many turns
• more positioning
• lower large-machine utilization

This supports the broader design principle:

Farm layout is part of production optimization.

────────

Relationship to machinery progression

Field design and machinery design must reinforce each other.

Small machinery:

• lower theoretical throughput
• low turning overhead
• flexible on small fields

Large machinery:

• high theoretical throughput
• higher power requirements
• larger turning/headland needs
• best utilization on large regular fields

The player should eventually ask:

> Should I buy larger equipment, add more small machines, or redesign the fields?

That is a desired core optimization decision.

────────

Design rules

The following are strong working decisions:

• Fields are physical work areas, not passive production timers.
• The first field shape is rectangular.
• Each field has one entrance/exit in the first iteration.
• Field work is spatial and lane-based.
• Work progress is tracked across the field area.
• Parallel lanes are the default work pattern.
• Lane orientation should favor long working passes.
• Machinery physically processes the field.
• Implement width affects processed area per pass.
• Turning consumes time and affects real throughput.
• Already completed areas do not provide duplicate benefit.
• Fields generate first-class jobs.
• Machines consume compatible jobs.
• Manual field operation comes before auto-repeat.
• Auto-repeat is an early automation unlock.
• Wheat is the only crop in v0.1.
• Growth remains simple.
• Irregular fields are postponed.
• Detailed agronomy is postponed.

────────

Open questions for technical feasibility

These should be answered through Factorio 2.x API research and prototyping rather than pure design discussion:

• What is the most performance-efficient representation of per-field work state?
• Should work state use tiles, hidden entities, chunk-level data, or another structure?
• How many field cells can reasonably exist at megabase scale?
• How should work lanes be represented internally?
• Can Factorio vehicles reliably follow deterministic lane paths?
• How should turns be handled?
• Can an implement’s physical width map cleanly to processed field cells?
• How should a field entrance be represented and connected to world pathfinding?
• How expensive is frequent vehicle pathfinding at large fleet sizes?
• How should multiple machines claim lanes without excessive runtime cost?
• How can field progress be rendered visually without creating huge entity counts?