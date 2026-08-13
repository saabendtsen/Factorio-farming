Factorio Farming — Progression v0.1

Purpose

This document describes the intended early-game progression structure for Factorio Farming.

It is deliberately focused on which problems the player encounters, in what order, and what each unlock changes about the gameplay.

Exact costs, crop quantities, timings and balance values are not locked here.

Where numeric values would normally appear, use TBD until prototype testing provides useful data.

────────

Progression philosophy

Progression should not primarily be about gaining flat power.

Each meaningful unlock should do at least one of the following:

• remove a repetitive manual action
• increase available production capacity
• expose a new optimization problem
• allow the player to coordinate a larger system
• make previously built infrastructure worth revisiting and improving

The player should gradually move from:

operating a farm

to:

designing an agricultural production system

The intended progression arc is therefore:

manual orchestration -> fixed automation -> capacity scaling -> reusable machine pools -> programmable dispatch

────────

Early-game goals

The first 30–60 minutes should teach the player the core language of the game:

• fields create work
• machines have finite throughput
• storage limits expansion
• crops are capital resources
• larger scale creates bottlenecks
• automation removes repetitive control but creates new optimization opportunities
• old production remains relevant as new systems unlock

The player should not be overwhelmed by many crops, machinery types or simulation layers during this period.

The initial crop remains:

Wheat

────────

Phase 1 — Learn the production cycle

Player setup

The player begins with a minimal farming system, likely including:

• one small rectangular field
• one small tractor
• basic fixed implements
• one small harvester
• one small barn/silo

Exact starting inventory is TBD.

Core loop

cultivate -> sow -> grow -> harvest -> store

The player manually initiates field operations.

A tractor and implement are treated as a fixed working unit.

Example:

• Tractor A + cultivator accepts cultivation jobs.
• Tractor B + seeder accepts sowing jobs.
• Harvester accepts harvest jobs.

The player should quickly understand that machines physically travel to the field and work it lane by lane.

What the player learns

• A field is a physical workload, not a timer.
• Larger fields require more machine time.
• A machine can be busy, traveling or idle.
• Harvested wheat enters storage.
• Stored wheat is strategically valuable.

First progression pressure

The starter storage fills.

The player must decide how to spend wheat on the next expansion step rather than simply accumulating an abstract currency.

────────

Phase 2 — Storage and capacity become constraints

The player unlocks or becomes able to purchase larger storage and additional machinery.

Example progression relationship:

produce wheat -> invest in storage -> accumulate larger stockpile -> purchase better capacity

Exact costs are TBD.

New player problem

The existing machinery can no longer comfortably service the expanded field area.

The player encounters the first genuine throughput bottleneck:

> The farm has more field workload than the current machinery can process efficiently.

Intended choices

The player should be able to solve this in more than one way:

• add another small machine
• purchase a larger machine
• use a wider implement
• reorganize field layout to reduce travel

Not every solution must exist in the first technical prototype, but the design should support this direction.

Design intent

This phase establishes that expansion creates work rather than free output.

────────

Phase 3 — Auto-repeat fields

A relatively early unlock introduces automatic crop cycling.

Before this unlock, the player manually initiates operations.

After unlocking auto-repeat, a field can be configured with a crop plan:

Crop: Wheat
Mode: Auto Repeat

The field controller generates required jobs automatically:

needs cultivation
needs sowing
growing
needs harvest
repeat

Design intent

This is the first major automation milestone.

It removes repetitive clicking without solving the actual production problem.

The player stops asking:

> What should this field do next?

and starts asking:

> Do I have enough machinery to service all of these fields?

That transition is central to the game.

────────

Phase 4 — Parallel machinery and utilization

As field count grows, the player begins operating multiple machines for the same job type.

Examples:

• two cultivation units
• two sowing units
• multiple harvesters

Compatible units draw from the shared job queue.

New optimization problems

• Which machines spend too much time traveling?
• Are some operations over-provisioned while others are bottlenecked?
• Are machines waiting for jobs?
• Should machinery be duplicated or upgraded?
• Should fields be grouped differently?

Useful telemetry

By this phase the player should ideally have access to simple utilization information:

• working %
• traveling %
• waiting %
• idle %

This information should help diagnose the system rather than simply provide statistics.

────────

Phase 5 — Dynamic equipment pools

This is an important early/mid-game automation upgrade.

Before this unlock:

tractor + implement = fixed job unit

After this unlock:

• tractors can exist in a shared tractor pool
• implements can be parked in an implement storage area
• the dispatcher can pair available tractors with compatible implements based on pending work

Example:

Sowing job appears
-> dispatcher selects idle tractor
-> tractor retrieves compatible seeder
-> tractor travels to field
-> performs sowing job
-> returns/reassigns equipment

Design intent

Dynamic equipment pools improve fleet utilization.

Instead of purchasing a dedicated tractor for every operation type, the player can build a flexible fleet.

This should feel like a meaningful automation upgrade rather than a default feature available immediately.

It also creates new optimization concerns:

• implement storage location
• time spent changing implements
• tractor-to-implement ratios
• reserved versus shared machinery
• queue priorities

────────

Phase 6 — Advanced dispatch and circuit control

The basic dispatcher should work without circuits.

Circuit integration is an advanced control layer for players who want precise behavior.

Possible conditions:

• only assign large tractors to fields above a certain size
• keep a minimum number of tractors idle/reserved
• prioritize specific fields
• stop wheat operations when wheat storage is above a threshold
• prioritize barley when barley stock is low
• disable lower-priority jobs during harvest pressure

Example concepts:

Enable Field 7 when wheat < 5,000 t

Reserve 2 tractors for priority jobs

Use large tractor if field_area > threshold

Design intent

Circuit control should not be required for basic automation.

It should provide the same kind of optional deep control that Factorio circuits provide to logistics and factories.

The progression should be:

automation works by default

then:

advanced players can program how it works

────────

First 30–60 minute progression outline

This is a structural draft, not a timing commitment.

Step 1 — First wheat field

Player learns:

cultivate -> sow -> grow -> harvest -> store

Manual operation control.

Step 2 — First storage upgrade

Starter storage becomes limiting.

Player spends wheat to increase storage.

This demonstrates:

Crops are capital.

Step 3 — First machinery expansion

Field area increases.

Existing tractor/implement capacity becomes inadequate.

Player adds or upgrades machinery.

This demonstrates:

Machinery is capacity.

Step 4 — Auto-repeat unlock

Fields can automatically cycle wheat.

Manual operation scheduling is removed.

This demonstrates:

Automation shifts the player’s attention upward.

Step 5 — Multiple fields / shared job queues

The farm becomes large enough that machinery utilization and travel time matter.

The player begins diagnosing bottlenecks.

Step 6 — Better machinery

Wider/faster machinery becomes available.

The player chooses between parallel small units and fewer large units.

Step 7 — Dynamic equipment pools

Tractors can dynamically retrieve compatible implements.

Fleet utilization becomes a design problem.

Step 8 — Advanced dispatch

Circuit-based conditions and priorities become available.

The player can begin designing sophisticated automated farm behavior.

────────

Unlock design rules

Unlocks should ideally be tied to production capability rather than pure elapsed time.

Possible future unlock criteria include:

• sustained crop throughput
• storage capacity
• successful contracts
• demonstrated field area serviced
• machinery utilization targets
• delivery performance

Exact mechanisms remain TBD.

A promising future system is contracts that function as production benchmarks.

Contracts are intentionally outside the first implementation.

────────

Things progression should avoid

Pure lifetime-total gating

Example to avoid:

> Harvest 10,000 wheat eventually.

This rewards waiting more than optimization.

A better unlock should ideally care about production capability, rate, or system performance.

Pure gold gating

If every unlock is solved by maximizing gold/hour, crop diversity and old production chains become strategically irrelevant.

Too many systems at once

Do not introduce:

• multiple crops
• fuel
• maintenance
• weather
• fertilizer
• processing
• contracts
• advanced logistics

before the wheat + machinery + storage loop has proven itself.

Automation that removes gameplay

Automation should remove repetitive commands, not eliminate optimization.

A new automation tier should generally expose a larger-scale problem after solving a smaller-scale one.

────────

Current progression decisions

The following are considered strong working decisions:

• The game starts with wheat only.
• Early operations are manually initiated.
• Tractor + implement begins as a fixed job unit.
• Machines automatically accept compatible jobs.
• Fields use a rectangular shape and a defined entrance/exit in the first iteration.
• Field work is spatial and lane-based.
• Auto-repeat is an early automation unlock.
• Multiple machines can eventually draw from shared job queues.
• Dynamic tractor/implement pools unlock after fixed machinery has been learned.
• Basic pooling works without circuits.
• Circuit networks provide advanced dispatch control.
• Storage progression is tightly coupled to machinery progression.
• Production capability should matter more than elapsed time for unlocks.
• Exact prices, throughput requirements and timings remain TBD.

────────

Open questions for later iterations

These do not need answers before the first prototype:

• Should larger implements require minimum tractor power?
• How expensive should implement swapping be in travel/time?
• Can multiple machines work the same field simultaneously in the first release?
• How should field priority be exposed in UI?
• Should field entrance/exit be manually placed or automatically selected?
• At what point should grain transport become separate from harvesting?
• What is the first unlock criterion that proves throughput rather than lifetime production?
• How should new crop unlocks interact with old crop requirements?