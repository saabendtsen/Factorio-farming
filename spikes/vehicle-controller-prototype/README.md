# Vehicle controller prototype

> **Throwaway prototype.** This is a feasibility harness, not production mod architecture.

## Question

Can Factorio 2.1 use its asynchronous pathfinder plus custom `car.riding_state` steering to move physical cars to a field entrance, traverse one deterministic lane, recover from one deliberate obstruction with bounded retries, and remain viable at 1, 10, 100, 200, and 300 active vehicles?

The harness exposes its complete relevant outcome state as a JSON report: completion, path latency, stuck/repath counts, collision suspicions, and arrival error. Factorio's built-in benchmark output supplies update-time and UPS evidence.

## Run

From this directory in PowerShell:

```powershell
.\run-benchmarks.ps1
```

The runner copies the mod into a timestamped directory below `%LOCALAPPDATA%\FactorioFarmingSpike1`, uses an isolated Factorio config, mod directory, save, and script-output directory, and never reads or changes the player's personal mods or saves.

Use `-VehicleCounts 1 -Runs 1` for a quick smoke run. The canonical benchmark uses all five counts and three runs of 7,200 ticks each.

## Deliberate constraints

- Vanilla cars and fuel; no farming gameplay, crops, economy, progression, or AAI dependency.
- Independent lanes keep the scale test focused on controller cost rather than traffic scheduling.
- The first vehicle receives a five-wall obstruction. A low-displacement window is recorded as a collision suspicion because the runtime does not emit a generic car-collision event.
- Recovery is limited to two reverse-and-repath attempts. Vehicles are never teleported.

## Result on Factorio 2.1.14

The canonical Windows run used three repetitions of 7,200 updates at each fleet size. Full structured results are in `results/factorio-2.1.14-windows.json`.

| Vehicles | Complete | Average update | Max update | Script update | Path deferrals | Max arrival error |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1/1 | 0.171 ms | 3.239 ms | 0.0071 ms | 0 | 0.752 tiles |
| 10 | 10/10 | 0.182 ms | 3.492 ms | 0.0221 ms | 0 | 0.995 tiles |
| 100 | 100/100 | 0.285 ms | 8.148 ms | 0.1461 ms | 0 | 0.995 tiles |
| 200 | 200/200 | 0.400 ms | 14.893 ms | 0.2632 ms | 116 | 0.995 tiles |
| 300 | 300/300 | 0.513 ms | 17.825 ms | 0.3771 ms | 397 | 0.995 tiles |

**Verdict: conditional GO.** The minimal staggered controller is comfortably inside the average 60 UPS budget in this isolated independent-lane scenario, and the deliberately obstructed first vehicle recovers with one of two allowed repaths. A burst of 200 or 300 path requests causes native pathfinder backpressure, and the 300-car run includes one update above the 16.667 ms budget. Production code must therefore queue and rate-limit new path requests instead of issuing fleet-sized bursts.

This does not prove traffic, shared intersections, arbitrary terrain, or a complete farming job system. Those remain outside this spike; the benchmark isolates controller feasibility.
