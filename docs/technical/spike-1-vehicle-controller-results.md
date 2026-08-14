# Spike 1 — Vehicle controller results

Status: conditional GO

Test date: 2026-08-14

Runtime: Factorio 2.1.14, Windows 10, AMD Ryzen 5 3600

## Question

Can Factorio 2.1 use native asynchronous pathfinding plus custom `car.riding_state` steering to move physical cars to a field entrance, traverse one deterministic lane, recover from a deliberate obstruction with bounded retries, and remain viable at 1, 10, 100, 200, and 300 active vehicles?

## Result

Yes, within the deliberately narrow benchmark scenario. Every tested vehicle reached its field entrance and completed its lane. The obstructed first vehicle reversed and repathed once without teleporting. Average update time remained far below the 16.667 ms budget for 60 UPS at every tested fleet size.

The result is conditional because a burst of 200 or 300 path requests produced native pathfinder backpressure. The 300-vehicle run also recorded one maximum update above the 60 UPS budget. Production code must queue and rate-limit path requests, and shared-road congestion remains untested.

## Method

- A minimal Factorio 2.1 mod used `LuaSurface::request_path` and consumed the asynchronous completion event.
- Physical vanilla cars were controlled only through `riding_state`; no position writes or teleports were used.
- Each vehicle travelled along an independent clear road to a field entrance and then one deterministic lane.
- The first lane contained a wall. Low displacement triggered a bounded reverse-and-repath sequence with at most two recovery attempts.
- Active controllers were staggered on a three-tick cadence.
- Each scale ran for 7,200 updates, repeated three times with Factorio's built-in benchmark mode.
- A separate 600-update verbose profile captured `scriptUpdate`, pathfinder, and car-entity time.

The throwaway harness and structured primary results are preserved on the [`codex/spike-1-vehicle-controller-prototype`](https://github.com/saabendtsen/Factorio-farming/tree/codex/spike-1-vehicle-controller-prototype/spikes/vehicle-controller-prototype) branch and in [draft PR #6](https://github.com/saabendtsen/Factorio-farming/pull/6). They are intentionally not part of `main`.

## Benchmark results

| Active vehicles | Completed | Average update | Maximum update | Average script update | Path deferrals | Maximum path latency | Maximum arrival error |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1/1 | 0.171 ms | 3.239 ms | 0.0071 ms | 0 | 0 ticks | 0.752 tiles |
| 10 | 10/10 | 0.182 ms | 3.492 ms | 0.0221 ms | 0 | 9 ticks | 0.995 tiles |
| 100 | 100/100 | 0.285 ms | 8.148 ms | 0.1461 ms | 0 | 97 ticks | 0.995 tiles |
| 200 | 200/200 | 0.400 ms | 14.893 ms | 0.2632 ms | 116 | 193 ticks | 0.995 tiles |
| 300 | 300/300 | 0.513 ms | 17.825 ms | 0.3771 ms | 397 | 289 ticks | 0.995 tiles |

Average total update time used 3.08% of the 60 UPS budget at 300 vehicles. The 300-vehicle path burst took at most 289 ticks, or about 4.8 seconds at 60 UPS, to clear. This is evidence for a bounded request queue, not evidence that unlimited simultaneous requests are safe.

The collision count is reported as a collision suspicion derived from low displacement because Factorio does not expose a generic car-collision event. The single deliberate obstruction produced one stuck event and one successful repath at every scale.

## Decision carried forward

- Keep a custom minimal vehicle controller as the baseline architecture.
- Keep the three-tick staggered update cadence as the initial implementation value.
- Cap outstanding path requests below the observed backpressure threshold and release new requests gradually. Re-benchmark the chosen cap in the production vertical slice.
- Use exact deterministic field-lane waypoints after the world-path handoff.
- Preserve bounded reverse-and-repath recovery and visible failure after its retry budget is exhausted.
- Do not claim traffic-system feasibility from this result. Shared intersections, congestion, arbitrary terrain, save/load, multiplayer, and long soaks need later validation.

## Acceptance result

- Minimal Factorio 2.1 mod skeleton: passed.
- Native asynchronous pathfinding and custom car steering: passed.
- Travel to a field entrance, one lane, and bounded stuck recovery: passed.
- Benchmarks at 1, 10, 100, 200, and 300 active vehicles: passed.
- Crops, economy, progression, and full gameplay remained out of scope.
