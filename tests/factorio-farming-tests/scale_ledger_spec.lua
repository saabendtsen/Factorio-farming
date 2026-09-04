-- Engine-free assertions for the fleet scale ledger.
--
-- The ledger is pure arithmetic over per-tick observations, so this spec is
-- loaded twice: by the Factorio test mod pure-test pass, and by the standalone
-- Lua driver in `tests/pure/`. Neither path touches the game API, which keeps
-- the scale characterization arithmetic verifiable without booting Factorio.
--
-- `ledger` is the module under test; `assertions` supplies `equal`/`truthy`.
return function(ledger, assertions)
  local equal, truthy = assertions.equal, assertions.truthy

  local function sample(tick, overrides)
    local base = {
      tick = tick,
      machines_total = 2,
      machines_active = 2,
      controller_due = 1,
      controller_updated_machine_id = 1,
      path_queue_depth = 0,
      outstanding_paths = 0,
      visual_objects = 0,
      dirty_fields = 0,
      jobs = {}
    }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
  end

  -- A fresh ledger reports nothing rather than dividing by an empty window.
  local empty = ledger.new({label = "empty", fleet_size = 2, field_count = 2, window_ticks = 10})
  local empty_report = ledger.summarize(empty)
  equal(empty_report.samples, 0, "empty ledger samples")
  equal(empty_report.ticks_observed, 0, "empty ledger observed ticks")
  equal(empty_report.controller_saturation_permille, 0, "empty ledger saturation")
  equal(#empty_report.violations, 0, "empty ledger violations")
  equal(empty_report.fleet_size, 2, "empty ledger fleet size")

  -- Controller demand versus applied updates is the headline scale metric: the
  -- production tick applies at most one controller update per tick, so a fleet
  -- that demands more than one is measurably deferred.
  local saturated = ledger.new({label = "saturated", fleet_size = 6, field_count = 6, window_ticks = 4})
  for tick = 1, 4 do
    ledger.record(saturated, sample(tick, {
      machines_total = 6,
      machines_active = 6,
      controller_due = 2,
      controller_updated_machine_id = ((tick - 1) % 2) + 1
    }))
  end
  local saturated_report = ledger.summarize(saturated)
  equal(saturated_report.samples, 4, "saturated samples")
  equal(saturated_report.ticks_observed, 4, "saturated observed ticks")
  equal(saturated_report.controller_updates, 4, "saturated applied updates")
  equal(saturated_report.controller_due_total, 8, "saturated demanded updates")
  equal(saturated_report.controller_due_max, 2, "saturated peak demand")
  equal(saturated_report.controller_deferred_total, 4, "saturated deferred updates")
  equal(saturated_report.controller_saturation_permille, 500, "saturated service ratio")
  equal(saturated_report.machines_active_max, 6, "saturated peak active machines")

  -- Fairness: a round-robin controller must serve every machine, and the
  -- ledger has to name the starved ones rather than average them away.
  equal(saturated_report.fairness.machines_served, 2, "saturated machines served")
  equal(saturated_report.fairness.machines_unserved, 4, "saturated machines unserved")
  equal(saturated_report.fairness.min_updates, 0, "saturated minimum updates")
  equal(saturated_report.fairness.max_updates, 2, "saturated maximum updates")
  equal(saturated_report.fairness.spread, 2, "saturated update spread")
  equal(#saturated_report.fairness.updates_by_machine, 2, "saturated served machine rows")
  equal(saturated_report.fairness.updates_by_machine[1].machine_id, 1, "fairness rows sort by machine id")
  equal(saturated_report.fairness.updates_by_machine[1].updates, 2, "fairness rows carry counts")

  -- Idle ticks are recorded, not skipped: a tick with no due machine still
  -- advances the window and must not be counted as a deferral.
  local idle = ledger.new({label = "idle", fleet_size = 2, field_count = 2, window_ticks = 2})
  ledger.record(idle, sample(10, {controller_due = 0, controller_updated_machine_id = nil}))
  ledger.record(idle, sample(11, {controller_due = 0, controller_updated_machine_id = nil}))
  local idle_report = ledger.summarize(idle)
  equal(idle_report.controller_deferred_total, 0, "idle deferrals")
  equal(idle_report.controller_saturation_permille, 1000, "idle service ratio is fully served")
  equal(idle_report.first_tick, 10, "idle first tick")
  equal(idle_report.last_tick, 11, "idle last tick")
  equal(idle_report.ticks_observed, 2, "idle observed ticks")

  -- Path requests are globally serialized, so queue depth and outstanding
  -- ticks are first-class scale signals.
  local paths = ledger.new({label = "paths", fleet_size = 3, field_count = 3, window_ticks = 3})
  ledger.record(paths, sample(1, {path_queue_depth = 0, outstanding_paths = 0}))
  ledger.record(paths, sample(2, {path_queue_depth = 5, outstanding_paths = 1}))
  ledger.record(paths, sample(3, {path_queue_depth = 4, outstanding_paths = 1}))
  local paths_report = ledger.summarize(paths)
  equal(paths_report.path.queue_depth_max, 5, "peak path queue depth")
  equal(paths_report.path.queue_depth_total, 9, "total path queue depth")
  equal(paths_report.path.queue_depth_mean_permille, 3000, "mean path queue depth")
  equal(paths_report.path.outstanding_path_ticks, 2, "ticks with an outstanding path")

  local drained = ledger.new({label = "drained", fleet_size = 2, field_count = 2, window_ticks = 4})
  ledger.record(drained, sample(10, {path_queue_depth = 3, outstanding_paths = 0}))
  ledger.record(drained, sample(11, {path_queue_depth = 1, outstanding_paths = 1}))
  ledger.record(drained, sample(12, {path_queue_depth = 0, outstanding_paths = 0}))
  local drained_report = ledger.summarize(drained)
  equal(drained_report.path.drain_windows, 1, "completed path drain window")
  equal(drained_report.path.drain_ticks_total, 2, "path queue drain duration")
  equal(drained_report.path.drain_ticks_max, 2, "longest path queue drain")

  local dispatch = ledger.new({label = "dispatch", fleet_size = 2, field_count = 2, window_ticks = 2})
  ledger.record(dispatch, sample(20, {jobs = {
    {id = 7, request_tick = 18, machine_id = 1, state = "reserved", completed_area = 0, total_area = 1024},
    {id = 8, request_tick = 18, state = "waiting", completed_area = 0, total_area = 1024}
  }}))
  ledger.record(dispatch, sample(23, {jobs = {
    {id = 7, request_tick = 18, machine_id = 1, state = "working", completed_area = 64, total_area = 1024},
    {id = 8, request_tick = 18, machine_id = 2, state = "reserved", completed_area = 0, total_area = 1024}
  }}))
  local dispatch_report = ledger.summarize(dispatch)
  equal(dispatch_report.dispatch.jobs_assigned, 2, "dispatch records every first assignment")
  equal(dispatch_report.dispatch.latency_ticks_total, 7, "dispatch latency total")
  equal(dispatch_report.dispatch.latency_ticks_max, 5, "dispatch latency maximum")
  equal(dispatch_report.dispatch.jobs[1].job_id, 7, "dispatch rows sort by job id")
  equal(dispatch_report.dispatch.jobs[1].machine_id, 1, "dispatch records assigned tractor")
  equal(dispatch_report.dispatch.jobs[1].request_tick, 18, "dispatch records request tick")
  equal(dispatch_report.dispatch.jobs[1].assigned_tick, 20, "dispatch records first assignment tick")
  equal(dispatch_report.dispatch.jobs[1].latency_ticks, 2, "dispatch records first assignment latency")
  equal(dispatch_report.dispatch.jobs[2].machine_id, 2, "later job records its own tractor")

  -- Visual objects scale with the field count, so the ledger tracks their peak
  -- and mean the same way.
  local visuals = ledger.new({label = "visuals", fleet_size = 2, field_count = 2, window_ticks = 2})
  ledger.record(visuals, sample(1, {visual_objects = 8, dirty_fields = 1}))
  ledger.record(visuals, sample(2, {visual_objects = 12, dirty_fields = 0}))
  local visuals_report = ledger.summarize(visuals)
  equal(visuals_report.visuals.objects_max, 12, "peak visual objects")
  equal(visuals_report.visuals.objects_mean_permille, 10000, "mean visual objects")
  equal(visuals_report.visuals.dirty_field_ticks, 1, "ticks with dirty field work")

  -- Coverage is authoritative: the ledger tracks exactness per job and counts
  -- how many jobs reached their own total area.
  local coverage = ledger.new({label = "coverage", fleet_size = 2, field_count = 2, window_ticks = 3})
  ledger.record(coverage, sample(1, {jobs = {
    {id = 1, state = "working", completed_area = 0, total_area = 1024},
    {id = 2, state = "waiting", completed_area = 0, total_area = 1024}
  }}))
  ledger.record(coverage, sample(2, {jobs = {
    {id = 1, state = "working", completed_area = 512, total_area = 1024},
    {id = 2, state = "working", completed_area = 256, total_area = 1024}
  }}))
  ledger.record(coverage, sample(3, {jobs = {
    {id = 1, state = "completed", completed_area = 1024, total_area = 1024},
    {id = 2, state = "working", completed_area = 512, total_area = 1024}
  }}))
  local coverage_report = ledger.summarize(coverage)
  equal(coverage_report.coverage.completed, 1536, "final completed coverage")
  equal(coverage_report.coverage.total, 2048, "authoritative total coverage")
  equal(coverage_report.coverage.permille, 750, "coverage ratio")
  equal(coverage_report.coverage.exact_jobs, 1, "jobs at exact coverage")
  equal(coverage_report.coverage.tracked_jobs, 2, "tracked jobs")
  equal(#coverage_report.violations, 0, "clean coverage violations")

  -- Job state occupancy is reported as a sorted array so the recorded ledger is
  -- byte-stable across runs.
  equal(#coverage_report.job_state_ticks, 3, "distinct observed job states")
  equal(coverage_report.job_state_ticks[1].state, "completed", "job states sort alphabetically")
  equal(coverage_report.job_state_ticks[1].ticks, 1, "completed occupancy")
  equal(coverage_report.job_state_ticks[3].state, "working", "last sorted job state")
  equal(coverage_report.job_state_ticks[3].ticks, 4, "working occupancy")

  -- Violations are recorded, not raised: a scale run must finish and report
  -- rather than abort mid-window.
  local broken = ledger.new({label = "broken", fleet_size = 1, field_count = 1, window_ticks = 3})
  ledger.record(broken, sample(5, {jobs = {{id = 1, state = "working", completed_area = 512, total_area = 1024}}}))
  ledger.record(broken, sample(4, {jobs = {{id = 1, state = "working", completed_area = 256, total_area = 1024}}}))
  ledger.record(broken, sample(6, {jobs = {{id = 1, state = "working", completed_area = 2048, total_area = 1024}}}))
  local broken_report = ledger.summarize(broken)
  equal(#broken_report.violations, 3, "recorded violation count")
  truthy(string.find(broken_report.violations[1], "tick"), "tick regression is reported first")
  truthy(string.find(broken_report.violations[2], "coverage"), "coverage rewind is reported")
  truthy(string.find(broken_report.violations[3], "exceeds"), "coverage overrun is reported")
  equal(broken_report.samples, 3, "violating samples are still recorded")
end
