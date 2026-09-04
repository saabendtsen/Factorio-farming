-- Deterministic, game-API-free aggregation for production fleet scale runs.
--
-- A scale scenario samples the public farming snapshot once per tick.  This
-- module deliberately records observations instead of deciding whether a fleet
-- "passes": an observed limit or integrity miss is evidence to report, not a
-- reason to silently change a production performance budget.

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
    visuals = {objects_max = 0, objects_total = 0, dirty_field_ticks = 0},
    jobs = {},
    job_state_ticks = {},
    violations = {}
  }
end

local function record_job(state, job)
  if type(job) ~= "table" or job.id == nil then return end
  local id = job.id
  local completed = number(job.completed_area, 0)
  local total = number(job.total_area, 0)
  local previous = state.jobs[id]
  if previous and completed < previous.completed_area then
    state.violations[#state.violations + 1] = "coverage rewound for job " .. tostring(id)
  end
  if completed > total then
    state.violations[#state.violations + 1] = "coverage exceeds total for job " .. tostring(id)
  end
  state.jobs[id] = {completed_area = completed, total_area = total, state = job.state}
  if job.state ~= nil then
    state.job_state_ticks[job.state] = (state.job_state_ticks[job.state] or 0) + 1
  end
end

function ledger.record(state, sample)
  sample = sample or {}
  local tick = number(sample.tick, state.last_tick or 0)
  if state.last_tick ~= nil and tick <= state.last_tick then
    state.violations[#state.violations + 1] = "tick regressed from " .. tostring(state.last_tick) .. " to " .. tostring(tick)
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
      if type(job.request_tick) ~= "number" then
        state.violations[#state.violations + 1] = "assigned job has no request tick: " .. tostring(job.id)
      else
        state.dispatch_assignments[job.id] = {machine_id = job.machine_id, request_tick = job.request_tick,
          assigned_tick = tick, latency_ticks = math.max(0, tick - job.request_tick)}
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
  local updates = sorted_rows(state.updates_by_machine, "machine_id", "updates")
  local served = #updates
  local minimum = served < state.fleet_size and 0 or nil
  local maximum = 0
  for _, row in ipairs(updates) do
    if minimum == nil or row.updates < minimum then minimum = row.updates end
    if row.updates > maximum then maximum = row.updates end
  end
  minimum = minimum or 0
  local samples = state.samples
  local saturation = samples == 0 and 0 or state.controller_due_total == 0 and 1000 or
    math.floor(state.controller_updates * 1000 / state.controller_due_total)
  local dispatch_rows = {}
  for job_id, assignment in pairs(state.dispatch_assignments) do
    dispatch_rows[#dispatch_rows + 1] = {job_id = job_id, machine_id = assignment.machine_id,
      request_tick = assignment.request_tick, assigned_tick = assignment.assigned_tick,
      latency_ticks = assignment.latency_ticks}
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
    first_tick = state.first_tick,
    last_tick = state.last_tick,
    ticks_observed = samples,
    machines_active_max = state.machines_active_max,
    controller_updates = state.controller_updates,
    controller_due_total = state.controller_due_total,
    controller_due_max = state.controller_due_max,
    controller_deferred_total = state.controller_deferred_total,
    controller_saturation_permille = saturation,
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
      queue_depth_total = state.path.queue_depth_total,
      queue_depth_mean_permille = samples == 0 and 0 or math.floor(state.path.queue_depth_total * 1000 / samples),
      outstanding_path_ticks = state.path.outstanding_path_ticks,
      drain_windows = state.path.drain_windows,
      drain_ticks_total = state.path.drain_ticks_total,
      drain_ticks_max = state.path.drain_ticks_max
    },
    dispatch = {jobs_assigned = #dispatch_rows, latency_ticks_total = dispatch_total,
      latency_ticks_max = dispatch_max,
      latency_ticks_mean_permille = #dispatch_rows == 0 and 0 or
        math.floor(dispatch_total * 1000 / #dispatch_rows), jobs = dispatch_rows},
    visuals = {
      objects_max = state.visuals.objects_max,
      objects_mean_permille = samples == 0 and 0 or math.floor(state.visuals.objects_total * 1000 / samples),
      dirty_field_ticks = state.visuals.dirty_field_ticks
    },
    coverage = {
      completed = coverage_completed,
      total = coverage_total,
      permille = coverage_total == 0 and 0 or math.floor(coverage_completed * 1000 / coverage_total),
      exact_jobs = exact_jobs,
      tracked_jobs = tracked_jobs
    },
    job_state_ticks = sorted_rows(state.job_state_ticks, "state", "ticks"),
    violations = state.violations
  }
end

return ledger
