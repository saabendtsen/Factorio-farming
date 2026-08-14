# Spike 2 — Field state and visuals results

Status: GO with a hybrid architecture

Test date: 2026-08-14

Runtime: Factorio 2.1.14, Windows 10, AMD Ryzen 5 3600

## Question

Can compressed strip intervals represent coherent, interrupted, resumed, overlapping, and fragmented work through 1,024 × 1,024 fields more effectively than packed 32 × 32 chunks, and should completed-field visuals use batched tiles or compressed rendering ranges at roughly 1 million and 10 million logical cells?

## Result

Yes. Coherent generated field work is compact and fast as strip intervals. Heavy fragmentation reverses the result: a packed chunk is bounded while a general range merge becomes nonlinear and produces hundreds of thousands of records. The authoritative model should therefore keep ranges by default and promote only fragmented chunks to bitmaps.

Compressed render ranges are orders of magnitude faster to create and remove than a synchronous full-field tile rewrite. Tiles remain suitable for durable ground appearance only when dirty changes are bounded and amortized over many ticks. Save and load behavior did not expose a blocker for either projection at the tested scale.

## Method

- State cases used 64², 256², and 1,024² fields.
- The coherent case interrupted each strip halfway, applied a fully overlapping update, then resumed to completion.
- The fragmented case completed alternating two-tile runs, split each run into interruption/resume operations, then replayed the full run as an overlap.
- Range state stored sorted, merged half-open intervals per canonical strip.
- Packed state stored one 128-byte bitmap string per touched 32 × 32 chunk after applying changes in a mutable buffer.
- Visual cases used one or ten separate 1,024² fields, preserving the maximum individual field size.
- Each visual projected 75% completion: batched custom tiles in groups of 16,384 or one filled render rectangle per completed strip.
- Factorio's profiler measured state construction, projection, and restoration. Actual ZIP size and map-load timestamps measured persistence.

The throwaway harness and structured primary results are preserved on the [`codex/spike-2-field-state-visuals-prototype`](https://github.com/saabendtsen/Factorio-farming/tree/codex/spike-2-field-state-visuals-prototype/spikes/field-state-visuals-prototype) branch and in [draft PR #8](https://github.com/saabendtsen/Factorio-farming/pull/8). They are intentionally not part of `main`.

## State benchmark

Every interruption/resume and overlap invariant passed.

| Field and pattern | Ranges | Packed chunks | Range records | Packed payload | Range save | Packed save |
|---|---:|---:|---:|---:|---:|---:|
| 64² coherent | 0.31 ms | 3.16 ms | 64 | 512 B | 0.744 MiB | 0.744 MiB |
| 256² coherent | 1.24 ms | 50.13 ms | 256 | 8 KiB | 0.745 MiB | 0.744 MiB |
| 1,024² coherent | 5.06 ms | 799.38 ms | 1,024 | 128 KiB | 0.746 MiB | 0.747 MiB |
| 64² fragmented | 15.77 ms | 2.82 ms | 1,024 | 512 B | 0.745 MiB | 0.744 MiB |
| 256² fragmented | 714.86 ms | 44.69 ms | 16,384 | 8 KiB | 0.762 MiB | 0.744 MiB |
| 1,024² fragmented | 41,081.02 ms | 710.12 ms | 262,144 | 128 KiB | 1.362 MiB | 0.747 MiB |

The fragmented range implementation intentionally performs a general sorted merge for arbitrary overlaps. Append-only generated passes can be optimized, but that does not remove the record-count problem when fragmentation is real.

Save compression makes coherent ranges and packed strings look similar in these small isolated saves. Operation time and representation units, not ZIP size alone, decide the authoritative representation.

## Visual benchmark

| Logical cells | Projection | Project time | Restore time | Projected save | Projected load | Restored load |
|---:|---|---:|---:|---:|---:|---:|
| 1,048,576 | 786,432 tiles | 3,815.65 ms | 1,880.77 ms | 0.798 MiB | 113 ms | 126 ms |
| 1,048,576 | 1,024 render ranges | 4.54 ms | 0.78 ms | 0.840 MiB | 118 ms | 133 ms |
| 10,485,760 | 7,864,320 tiles | 37,079.62 ms | 18,740.51 ms | 1.391 MiB | 466 ms | 472 ms |
| 10,485,760 | 10,240 render ranges | 36.10 ms | 11.41 ms | 1.770 MiB | 452 ms | 463 ms |

The synchronous tile totals are stress measurements, not an implementation plan. Production must enqueue only dirty deltas and spread bounded batches across ticks. Render ranges trade somewhat larger saves in this synthetic case for dramatically lower projection and lifecycle cost.

## Decision carried forward

- Use canonical strip intervals for coherent authoritative field progress.
- Maintain `completed_area` by delta; never derive progress by rescanning the field or its visuals.
- Track fragmentation per 32 × 32 chunk and promote a chunk to a packed bitmap when its range count crosses a configurable, benchmarked threshold.
- Allow packed chunks to remain local exceptions; do not convert an entire coherent field because one region fragmented.
- Use compressed render ranges for changing progress, claims, selection, and debug overlays.
- Use tiles only for durable field appearance, with dirty queues and a strict per-tick batch budget.
- Keep visuals disposable and rebuildable from authoritative state. Restore prior terrain when a tile-backed field is removed.

## Limits

The benchmark was headless. It measures script work, persistence, and engine load, but not GPU frame time, zoomed-out readability, art quality, or conflicts with player paving and other terrain mods. Those are integration and UX checks for the production vertical slice, not blockers found by this state-and-scale spike.

Load time is derived from one Factorio log-timestamped load per case and is coarse to roughly one millisecond. It is sufficient to rule out an order-of-magnitude regression, not to distinguish small differences between projections.

## Acceptance result

- Compressed strip/range state: passed.
- Interruption, resume, and overlap: passed for both representations and both patterns.
- Fields through 1,024 × 1,024: passed.
- Batched tiles versus compressed rendering ranges: passed at approximately 1 million and 10 million logical cells.
- Script time, save size, load time, and restoration: captured.
