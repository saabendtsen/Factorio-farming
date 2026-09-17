-- Deterministic, game-API-free aggregation and fixture geometry for the
-- production fleet scale characterization.
--
-- WHY THIS FILE SHIPS INSIDE THE PRODUCTION MOD DIRECTORY
-- ======================================================
-- Nothing in the shipped mod requires this module: it is used only by the test
-- mod (`tests/factorio-farming-tests/control.lua`) and by the standalone pure
-- Lua driver (`tests/pure/run-pure-lua.lua`).  It still lives under `scripts/`
-- because a Factorio mod can only `require` a file that resolves under a real
-- mod path, and the test mod resolves this one as
-- `__factorio-farming__/scripts/scale_ledger.lua`.  Copying it into the test
-- mod instead would let the fixture geometry the test builds and the geometry
-- the spec asserts drift apart, which is exactly the class of failure this
-- characterization exists to catch.  The cost is a few hundred bytes of unused
-- code in the shipped mod: it defines no prototypes, registers no events, and
-- is never required by `control.lua` or `scripts/slice.lua`.
--
-- A scale scenario samples the public farming snapshot on a fixed tick
-- interval (`sample_interval_ticks`, 1 = every tick).  This module deliberately
-- records observations instead of deciding whether a fleet "passes": an
-- observed limit or integrity miss is evidence to report, not a reason to
-- silently change a production performance budget.

local ledger = {}

local function number(value, fallback)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return fallback
  end
  return value
end

local function sorted_rows(values, key, value_name)
  local rows = {}
  for row_key, value in pairs(values) do rows[#rows + 1] = {[key] = row_key, [value_name] = value} end
  table.sort(rows, function(first, second) return first[key] < second[key] end)
  return rows
end

function ledger.new(config)
  config = config or {}
  return {
    label = config.label or "unnamed",
    fleet_size = math.max(0, number(config.fleet_size, 0)),
    field_count = math.max(0, number(config.field_count, 0)),
    window_ticks = math.max(0, number(config.window_ticks, 0)),
    -- Sampling the full production snapshot walks every machine, field, job
    -- and queued job, so a per-tick sample is O(N^2) across a scale window.
    -- The ledger therefore records its own sampling rate and scales the
    -- per-tick counters by it, so every derived rate keeps the same meaning
    -- whether the window was sampled every tick or every Nth tick.
    sample_interval_ticks = math.max(1, math.floor(number(config.sample_interval_ticks, 1))),
    samples = 0,
    first_tick = nil,
    last_tick = nil,
    machines_active_max = 0,
    controller_updates = 0,
    controller_due_total = 0,
    controller_due_max = 0,
    controller_deferred_total = 0,
    updates_by_machine = {},
    path = {queue_depth_max = 0, queue_depth_total = 0, outstanding_path_ticks = 0,
      drain_started_tick = nil, drain_windows = 0, drain_ticks_total = 0, drain_ticks_max = 0},
    -- First assignments are immutable observations: a completion later clears
    -- `job.machine_id`, but the scale ledger must retain which tractor first
    -- accepted the request and how long that dispatch took.
    dispatch_assignments = {},
    -- Assigned jobs the ledger could not time at all. Counted as well as
    -- recorded as a violation, so a summary reader sees how much of the
    -- dispatch latency figure is missing rather than only that something was.
    dispatch_untimed = 0,
    visuals = {objects_max = 0, objects_total = 0, dirty_field_ticks = 0},
    jobs = {},
    job_state_ticks = {},
    violations = {}
  }
end

-- Coverage monotonicity holds *within one operation*, not across a job's whole
-- life. `slice.start_next_operation` reuses the job id for the field's next
-- operation and `field.begin_operation` resets `completed_area` to zero, so a
-- check keyed by job id alone raises a spurious rewind the moment any field
-- reaches a second operation. The observed phase -- the job's generation plus
-- its operation name -- is therefore part of the key.
local function job_phase(job)
  return tostring(job.generation) .. "/" .. tostring(job.operation)
end

local function record_job(state, job)
  if type(job) ~= "table" or job.id == nil then return end
  local id = job.id
  local completed = number(job.completed_area, 0)
  local total = number(job.total_area, 0)
  local phase = job_phase(job)
  local previous = state.jobs[id]
  if previous and previous.phase == phase and completed < previous.completed_area then
    state.violations[#state.violations + 1] = "coverage rewound for job " .. tostring(id)
  end
  if completed > total then
    state.violations[#state.violations + 1] = "coverage exceeds total for job " .. tostring(id)
  end
  state.jobs[id] = {completed_area = completed, total_area = total, state = job.state, phase = phase}
  if job.state ~= nil then
    state.job_state_ticks[job.state] = (state.job_state_ticks[job.state] or 0) + 1
  end
end

function ledger.record(state, sample)
  sample = sample or {}
  local tick = number(sample.tick, state.last_tick or 0)
  if state.last_tick ~= nil and tick <= state.last_tick then
    state.violations[#state.violations + 1] = "tick regressed from " .. tostring(state.last_tick) .. " to " .. tostring(tick)
  elseif state.sample_interval_ticks > 1 and state.last_tick ~= nil and
         (tick - state.last_tick) ~= state.sample_interval_ticks then
    -- An interval-sampled window scales its per-tick counters by the declared
    -- interval, so an irregular gap silently biases every derived rate. It is
    -- recorded as evidence rather than smoothed away. A per-tick ledger
    -- (interval 1) makes no evenness claim: its drivers legitimately observe
    -- only the ticks they care about.
    state.violations[#state.violations + 1] = "sample interval was " ..
      tostring(tick - state.last_tick) .. " ticks, expected " .. tostring(state.sample_interval_ticks)
  end
  state.samples = state.samples + 1
  state.first_tick = state.first_tick or tick
  state.last_tick = tick

  local active = math.max(0, number(sample.machines_active, 0))
  state.machines_active_max = math.max(state.machines_active_max, active)

  local due = math.max(0, number(sample.controller_due, 0))
  state.controller_due_total = state.controller_due_total + due
  state.controller_due_max = math.max(state.controller_due_max, due)
  local updated_id = sample.controller_updated_machine_id
  local applied = updated_id == nil and 0 or 1
  state.controller_updates = state.controller_updates + applied
  state.controller_deferred_total = state.controller_deferred_total + math.max(0, due - applied)
  if updated_id ~= nil then
    state.updates_by_machine[updated_id] = (state.updates_by_machine[updated_id] or 0) + 1
  end

  local queue_depth = math.max(0, number(sample.path_queue_depth, 0))
  state.path.queue_depth_max = math.max(state.path.queue_depth_max, queue_depth)
  state.path.queue_depth_total = state.path.queue_depth_total + queue_depth
  if number(sample.outstanding_paths, 0) > 0 then
    state.path.outstanding_path_ticks = state.path.outstanding_path_ticks + 1
  end
  if queue_depth > 0 or number(sample.outstanding_paths, 0) > 0 then
    state.path.drain_started_tick = state.path.drain_started_tick or tick
  elseif state.path.drain_started_tick ~= nil then
    local drain_ticks = math.max(0, tick - state.path.drain_started_tick)
    state.path.drain_windows = state.path.drain_windows + 1
    state.path.drain_ticks_total = state.path.drain_ticks_total + drain_ticks
    state.path.drain_ticks_max = math.max(state.path.drain_ticks_max, drain_ticks)
    state.path.drain_started_tick = nil
  end

  local visual_objects = math.max(0, number(sample.visual_objects, 0))
  state.visuals.objects_max = math.max(state.visuals.objects_max, visual_objects)
  state.visuals.objects_total = state.visuals.objects_total + visual_objects
  if number(sample.dirty_fields, 0) > 0 then state.visuals.dirty_field_ticks = state.visuals.dirty_field_ticks + 1 end

  for _, job in ipairs(sample.jobs or {}) do
    record_job(state, job)
    if job.id ~= nil and job.machine_id ~= nil and state.dispatch_assignments[job.id] == nil then
      -- Queued fleet jobs are stamped with `request_tick` when they are
      -- created. The initial player-visible field's job is created by
      -- `create_field_job` without one and only later given an operation, so
      -- for that path the ledger measures from `last_operation_tick`, the
      -- measurement-only stamp `start_next_operation` records. Neither field is
      -- read by `field.job_precedes`, so which one is used cannot influence
      -- dispatch order; the row names the source it measured from.
      local source = "request"
      local request_tick = job.request_tick
      if type(request_tick) ~= "number" then
        source = "operation"
        request_tick = job.last_operation_tick
      end
      if type(request_tick) ~= "number" then
        state.dispatch_untimed = state.dispatch_untimed + 1
        state.violations[#state.violations + 1] = "assigned job has no request tick: " .. tostring(job.id)
      else
        state.dispatch_assignments[job.id] = {machine_id = job.machine_id, request_tick = request_tick,
          request_tick_source = source, assigned_tick = tick,
          latency_ticks = math.max(0, tick - request_tick)}
      end
    end
  end
  return state
end

function ledger.summarize(state)
  local coverage_completed, coverage_total, exact_jobs, tracked_jobs = 0, 0, 0, 0
  for _, job in pairs(state.jobs) do
    tracked_jobs = tracked_jobs + 1
    coverage_completed = coverage_completed + job.completed_area
    coverage_total = coverage_total + job.total_area
    if job.completed_area == job.total_area then exact_jobs = exact_jobs + 1 end
  end
  -- Every counter below that counts "one per observed tick" is scaled by the
  -- sampling interval, so a window sampled every Nth tick reports the same
  -- estimated tick totals as a window sampled every tick. Ratios (saturation,
  -- coverage permille, means per sample) are unaffected by the scaling; they
  -- stay unbiased as long as the interval is coprime with the controller
  -- cadence, which the fixture guarantees.
  local interval = state.sample_interval_ticks
  local updates = sorted_rows(state.updates_by_machine, "machine_id", "updates")
  for _, row in ipairs(updates) do row.updates = row.updates * interval end
  local served = #updates
  local minimum = served < state.fleet_size and 0 or nil
  local maximum = 0
  for _, row in ipairs(updates) do
    if minimum == nil or row.updates < minimum then minimum = row.updates end
    if row.updates > maximum then maximum = row.updates end
  end
  minimum = minimum or 0
  local samples = state.samples
  -- Saturation is served/demanded. With no demand there is no denominator and
  -- therefore no ratio: reporting 1000 would let a fixture that never activated
  -- a tractor -- a dead run -- score as "every due tractor was updated". The
  -- ledger reports no ratio instead, and states separately whether it ever saw
  -- any demand, so a reader can tell "fully served" from "nothing to serve".
  local demand_observed = state.controller_due_total > 0
  local saturation = nil
  if demand_observed then
    saturation = math.floor(state.controller_updates * 1000 / state.controller_due_total)
  end
  -- A drain window that never closed is dropped from `drain_windows` and
  -- `drain_ticks_total` by construction, and at scale the longest drain is
  -- exactly the one most likely to be still open when a run times out. Report
  -- the open window explicitly so it cannot vanish.
  local drain_started = state.path.drain_started_tick
  local drain_open_ticks = 0
  if drain_started ~= nil and state.last_tick ~= nil then
    drain_open_ticks = math.max(0, state.last_tick - drain_started)
  end
  local dispatch_rows = {}
  for job_id, assignment in pairs(state.dispatch_assignments) do
    dispatch_rows[#dispatch_rows + 1] = {job_id = job_id, machine_id = assignment.machine_id,
      request_tick = assignment.request_tick, request_tick_source = assignment.request_tick_source,
      assigned_tick = assignment.assigned_tick, latency_ticks = assignment.latency_ticks}
  end
  table.sort(dispatch_rows, function(first, second) return first.job_id < second.job_id end)
  local dispatch_total, dispatch_max = 0, 0
  for _, row in ipairs(dispatch_rows) do
    dispatch_total = dispatch_total + row.latency_ticks
    dispatch_max = math.max(dispatch_max, row.latency_ticks)
  end
  return {
    label = state.label,
    fleet_size = state.fleet_size,
    field_count = state.field_count,
    window_ticks = state.window_ticks,
    samples = samples,
    sample_interval_ticks = interval,
    first_tick = state.first_tick,
    last_tick = state.last_tick,
    -- Ticks the samples stand for, not ticks actually inspected.
    ticks_observed = samples * interval,
    ticks_spanned = (state.first_tick == nil) and 0 or (state.last_tick - state.first_tick + interval),
    machines_active_max = state.machines_active_max,
    controller_update_samples = state.controller_updates,
    controller_updates = state.controller_updates * interval,
    controller_due_total = state.controller_due_total * interval,
    controller_due_max = state.controller_due_max,
    controller_deferred_total = state.controller_deferred_total * interval,
    -- Share of observed controller demand that was served in the same observed
    -- tick, in permille. Both numerator and denominator are sampled the same
    -- way, so the interval scaling cancels and the ratio keeps its per-tick
    -- meaning: 1000 = every due tractor was updated, 500 = half were deferred.
    -- Absent (nil) when no controller update was ever due, because a ratio with
    -- no denominator is not a score. `controller_demand_observed` says which
    -- case a missing ratio is.
    controller_saturation_permille = saturation,
    controller_demand_observed = demand_observed,
    fairness = {
      machines_served = served,
      machines_unserved = math.max(0, state.fleet_size - served),
      min_updates = minimum,
      max_updates = maximum,
      spread = maximum - minimum,
      updates_by_machine = updates
    },
    path = {
      queue_depth_max = state.path.queue_depth_max,
      queue_depth_total = state.path.queue_depth_total * interval,
      queue_depth_mean_permille = samples == 0 and 0 or math.floor(state.path.queue_depth_total * 1000 / samples),
      outstanding_path_ticks = state.path.outstanding_path_ticks * interval,
      -- Drain windows are measured from real tick numbers, so they stay in
      -- ticks under interval sampling; their resolution is the interval.
      drain_windows = state.path.drain_windows,
      drain_ticks_total = state.path.drain_ticks_total,
      drain_ticks_max = state.path.drain_ticks_max,
      -- `drain_ticks_max` and `queue_depth_max` are lower bounds under interval
      -- sampling: a spike between two samples is invisible, and a window is
      -- only measured from the samples that bracket it.
      drain_ticks_max_is_lower_bound = interval > 1,
      -- Present only when the window ended with a drain still in flight.
      drain_started_tick = drain_started,
      drain_open_ticks = drain_open_ticks,
      drain_tick_resolution = interval
    },
    dispatch = {jobs_assigned = #dispatch_rows, jobs_without_request_tick = state.dispatch_untimed,
      latency_ticks_total = dispatch_total,
      latency_ticks_max = dispatch_max,
      latency_ticks_mean_permille = #dispatch_rows == 0 and 0 or
        math.floor(dispatch_total * 1000 / #dispatch_rows), jobs = dispatch_rows},
    visuals = {
      objects_max = state.visuals.objects_max,
      objects_mean_permille = samples == 0 and 0 or math.floor(state.visuals.objects_total * 1000 / samples),
      dirty_field_ticks = state.visuals.dirty_field_ticks * interval
    },
    coverage = {
      completed = coverage_completed,
      total = coverage_total,
      permille = coverage_total == 0 and 0 or math.floor(coverage_completed * 1000 / coverage_total),
      exact_jobs = exact_jobs,
      tracked_jobs = tracked_jobs
    },
    job_state_ticks = (function()
      local rows = sorted_rows(state.job_state_ticks, "state", "ticks")
      for _, row in ipairs(rows) do row.ticks = row.ticks * interval end
      return rows
    end)(),
    violations = state.violations
  }
end

-- ------------------------------------------------------------------ geometry
--
-- The scale fixture lays identical 64 x 16 fields out on a grid. Every field
-- owns a west-side tractor approach and a prepared tile band, and the whole
-- point of the characterization is that neighbouring bands do not interact:
-- issue #44 puts shared-road congestion and traffic coordination out of scope,
-- so a fixture whose bands touch would be measuring something else entirely.
--
-- The layout is therefore computed here, as a pure function, and the same
-- function is asserted by `scale_ledger_spec.lua`. The isolation invariant is
-- a test, not a comment.
--
-- Per-field extents, relative to the field's own `left`/`top`:
--   field   x in [left,      left + 64]   y in [top,     top + 16]
--   tractor x  = left - 20                y  = top + 8
--   band    x in [left - 28, left + 72]   y in [top - 8, top + 24]
-- The band is the tile rectangle the fixture prepares with `set_tiles`; it
-- extends 8 tiles beyond the tractor on the west and 8 tiles beyond the field
-- on the other three sides.  Band width 100, band height 32.
--
-- Stride arithmetic (all values in tiles):
--   x stride 160 >= band width 100  + isolation gap 32  ->  actual gap 60
--   y stride  64 >= band height 32  + isolation gap 32  ->  actual gap 32
-- Both strides are multiples of 32 so a band boundary never splits a chunk
-- request in a way that leaves a neighbour's chunk half generated.
--
-- `SCALE_COLUMNS` stays at 10. Fewer columns would not make the surface
-- smaller (the occupied area is count * x_stride * y_stride either way), it
-- would only trade width for height, and 10 keeps the common 10-, 50- and
-- 100-tractor cases on 1, 5 and 10 rows with the same column pitch, so the
-- x-axis layout is identical across every scale that is compared.
local geometry_constants = {
  columns = 10,
  x_stride = 160,
  y_stride = 64,
  isolation_gap = 32,
  field_width = 64,
  field_height = 16,
  tractor_offset_x = -20,
  tractor_offset_y = 8,
  band_left_offset = -28,
  band_right_offset = 72,
  band_top_offset = -8,
  band_bottom_offset = 24,
  -- `slice.create_machine` calls `find_non_colliding_position(..., 16, 0.5)`,
  -- so a tractor may be displaced by up to 16 tiles in any direction. A
  -- 64-tile margin keeps that search, and the band it starts from, clear of
  -- the finite surface's edge at every scale.
  edge_margin = 64,
  spawn_search_radius = 16
}
ledger.geometry_constants = geometry_constants

local function round_up_to_chunk(value)
  return math.ceil(value / 32) * 32
end

-- Returns the complete fixture layout for `count` tractors/fields: the grid
-- shape, the finite surface size derived from it, and every field's bounds,
-- tractor position and prepared tile band. Pure arithmetic, no game API.
function ledger.geometry(count)
  local constants = geometry_constants
  count = math.max(1, math.floor(number(count, 1)))
  local columns = math.min(count, constants.columns)
  local rows = math.ceil(count / columns)
  local band_width = constants.band_right_offset - constants.band_left_offset
  local band_height = constants.band_bottom_offset - constants.band_top_offset
  -- Extent of the union of every prepared band.
  local span_x = (columns - 1) * constants.x_stride + band_width
  local span_y = (rows - 1) * constants.y_stride + band_height
  -- A finite Factorio surface is centred on zero, so centre the band union on
  -- zero rather than treating the surface's left boundary as x = 0.
  local origin_left = -span_x / 2 - constants.band_left_offset
  local origin_top = -span_y / 2 - constants.band_top_offset
  local layout = {
    count = count,
    columns = columns,
    rows = rows,
    x_stride = constants.x_stride,
    y_stride = constants.y_stride,
    isolation_gap = constants.isolation_gap,
    edge_margin = constants.edge_margin,
    band_width = band_width,
    band_height = band_height,
    span_x = span_x,
    span_y = span_y,
    origin_left = origin_left,
    origin_top = origin_top,
    width = round_up_to_chunk(span_x + 2 * constants.edge_margin),
    height = round_up_to_chunk(span_y + 2 * constants.edge_margin),
    fields = {}
  }
  for index = 1, count do
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    local left = origin_left + column * constants.x_stride
    local top = origin_top + row * constants.y_stride
    layout.fields[index] = {
      index = index,
      column = column,
      row = row,
      bounds = {left = left, top = top,
        right = left + constants.field_width, bottom = top + constants.field_height},
      tractor = {x = left + constants.tractor_offset_x, y = top + constants.tractor_offset_y},
      band = {left = left + constants.band_left_offset, top = top + constants.band_top_offset,
        right = left + constants.band_right_offset, bottom = top + constants.band_bottom_offset}
    }
  end
  return layout
end

-- Returns every way the layout fails its own isolation contract, as a list of
-- messages. An empty list is the invariant the fixture claims.
function ledger.geometry_violations(layout)
  local problems = {}
  local half_width = layout.width / 2
  local half_height = layout.height / 2
  local margin = layout.edge_margin
  for index, entry in ipairs(layout.fields) do
    local band = entry.band
    if band.left < -half_width + margin or band.right > half_width - margin or
       band.top < -half_height + margin or band.bottom > half_height - margin then
      problems[#problems + 1] = "band " .. tostring(index) .. " is closer than the edge margin to the map edge"
    end
    if entry.tractor.x < band.left or entry.tractor.x > band.right or
       entry.tractor.y < band.top or entry.tractor.y > band.bottom then
      problems[#problems + 1] = "tractor " .. tostring(index) .. " starts outside its own prepared band"
    end
  end
  for first = 1, #layout.fields do
    for second = first + 1, #layout.fields do
      local a, b = layout.fields[first].band, layout.fields[second].band
      local gap_x = math.max(b.left - a.right, a.left - b.right)
      local gap_y = math.max(b.top - a.bottom, a.top - b.bottom)
      if math.max(gap_x, gap_y) < layout.isolation_gap then
        problems[#problems + 1] = "bands " .. tostring(first) .. " and " .. tostring(second) ..
          " are separated by less than " .. tostring(layout.isolation_gap) .. " tiles"
      end
    end
  end
  return problems
end

return ledger
