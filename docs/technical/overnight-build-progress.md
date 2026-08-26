# Overnight build progress

This ledger records the autonomous build sequence initiated on 2026-08-25.
It is updated only after a milestone has passed its stated verification gate.

## Authorized direction

1. Make the one-field MVP visually legible and usable without developer-only
   setup commands. Machinery art may be deliberately placeholder quality.
2. Extend the production architecture toward multi-field automation, shared job
   queues, priorities, and fleet scheduling. Preserve authoritative field state,
   fail-closed harvest transfer, save/load recovery, and bounded performance.

## Milestones

| Milestone | State | Verification / handoff |
| --- | --- | --- |
| Player-facing setup and placeholder machinery visuals | Complete | Ctrl+F and toolbar shortcut, onboarding, cursor-safe planner handling, placeholder tractor identity; `tests/run-factorio-tests.ps1 -SkipBenchmark` passed all functional, crop, capture, and replay stages |
| Multi-field scheduler design review | Complete | Independent architecture and test reviews selected schema v3 collections, deterministic dispatch ordering, and staged fleet acceptance |
| Shared queue, priorities, and single-tractor scheduling | Complete | Fresh clean-arena acceptance passed deterministic priority dispatch, pause/resume, exact coverage, tractor-loss failure without requeue, plus invalid-operation and overlap rejection |
| Queue save/load acceptance | In progress | Final Spec review requires queued waiting and assigned/working jobs to survive load before the scheduler foundation is called fully validated |
| Multi-field fleet scheduling | Planned | Two tractors on one surface, separate fields only: durable machine-to-job-to-field assignments; deterministic priority dispatch; no same-field parallel lanes or cross-surface arbitration |
| Independent standards/spec review | Complete with gate | Standards: no hard findings. Spec: queue-specific save/load acceptance is required before fleet implementation starts |

## Two-tractor acceptance seams

The first fleet increment uses established public Factorio seams rather than
private table inspection:

- `remote.call("factorio_farming", "debug_setup"|"debug_add_tractor"|"debug_queue_field", ...)`
  prepares a controlled, headed-or-headless field-operation scenario.
- `remote.call("factorio_farming", "snapshot", surface_index)` observes fleet
  assignments, job states, coverage, and retry-safe failures.
- The existing save/load harness captures and reloads two active assignments.

The first acceptance proves two tractors concurrently work two distinct fields;
a lower-priority third field waits, then dispatches when one tractor becomes
idle. Destroying one tractor fails only its assignment. Authoritative coverage
must restart from the first uncovered range after load. These seams deliberately
do not permit same-field concurrency, cross-surface tractor travel, traffic
coordination, or player fleet UI.

## Non-goals for this pass

- Final art, physical attachment simulation, fuel, economy, recipes, and progression.
- Grain trailers, combines, rendezvous logistics, circuit networks, or AAI.
- Any relaxation of save/load, transfer-retry, or performance gates.
