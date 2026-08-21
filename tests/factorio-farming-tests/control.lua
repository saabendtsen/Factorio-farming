local field = require("__factorio-farming__/scripts/field")
local slice = require("__factorio-farming__/scripts/slice")
local mode = require("mode")

local BENCH_TICKS = 18000
local PROFILE_DELAY = 10

local function fail(message)
  error("FACTORIO_FARMING_TEST_FAILURE: " .. message)
end

local function equal(actual, expected, message)
  if actual ~= expected then
    fail(message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

local function truthy(value, message)
  if not value then fail(message) end
end

local function write_result(name, result)
  helpers.write_file(
    "factorio-farming-tests/" .. name .. ".json",
    helpers.table_to_json(result),
    false
  )
  log("FACTORIO_FARMING_TEST_RESULT " .. name .. " " .. helpers.table_to_json(result))
end

local function run_pure_tests()
  local horizontal, horizontal_error = field.normalize_selection({
    left_top = {x = 0, y = 0}, right_bottom = {x = 64, y = 16}
  })
  truthy(horizontal, horizontal_error or "horizontal field rejected")
  local invalid = field.normalize_selection({
    left_top = {x = 0, y = 0}, right_bottom = {x = 63, y = 16}
  })
  equal(invalid, nil, "invalid field size accepted")

  local west = field.create(1, 1, horizontal, {x = -10, y = 8})
  equal(west.axis, "x", "horizontal axis")
  equal(west.entrance.x, 0, "west entrance")
  equal(west.entrance.y, 8, "west entrance midpoint")
  equal(#west.lanes, 4, "whole field lane count")
  equal(west.lanes[1].top, 0, "first lane top")
  equal(west.lanes[1].bottom, 4, "first lane bottom")
  equal(west.lanes[4].top, 12, "last lane top")
  equal(west.lanes[4].bottom, 16, "last lane bottom")
  equal(west.lane_index, 1, "first active lane")
  equal(west.direction, 1, "first lane direction")
  truthy(field.advance_lane(west), "second lane was not generated")
  equal(west.lane_index, 2, "second active lane")
  equal(west.direction, -1, "second lane direction")
  local west_turn = field.headland_waypoints(west)
  equal(#west_turn, 5, "headland waypoint count")
  equal(west_turn[1].x, 66, "headland exits east field edge")
  equal(west_turn[1].y, 2, "headland starts on completed lane center")
  equal(west_turn[5].x, 64, "headland returns to east field edge")
  equal(west_turn[5].y, 6, "headland ends on next lane center")

  local tie = field.create(2, 1, horizontal, {x = 32, y = 8})
  equal(tie.entrance.x, 0, "entrance tie chooses west")
  local east = field.create(3, 1, horizontal, {x = 80, y = 8})
  equal(east.entrance.x, 64, "east entrance")
  equal(east.direction, -1, "east entrance work direction")

  local shifted_bounds = assert(field.normalize_selection({
    left_top = {x = 31, y = 31}, right_bottom = {x = 95, y = 47}
  }))
  local shifted = field.create(30, 1, shifted_bounds, {x = 0, y = 39})
  local chunk_count = 0
  for _ in pairs(shifted.chunk_representations) do chunk_count = chunk_count + 1 end
  equal(chunk_count, 6, "world-aligned chunk representation tags")
  truthy(field.claim_lane(shifted, 10, 20), "first lane claim")
  equal(field.claim_lane(shifted, 11, 21), false, "conflicting lane claim accepted")
  truthy(field.claim_lane(shifted, 10, 20), "idempotent lane claim")
  equal(field.release_lane(shifted, 11), false, "non-owner released lane claim")
  truthy(field.release_lane(shifted, 10), "owner lane release")
  truthy(field.advance_lane(shifted), "shifted field second lane")
  truthy(field.claim_lane(shifted, 10, 20), "second lane claim")
  equal(shifted.lane_claim.lane, 2, "claim follows active lane")
  truthy(field.release_lane(shifted, 10), "second lane release")

  local vertical_bounds = assert(field.normalize_selection({
    left_top = {x = 0, y = 0}, right_bottom = {x = 16, y = 64}
  }))
  local north = field.create(4, 1, vertical_bounds, {x = 8, y = 32})
  equal(north.axis, "y", "vertical axis")
  equal(north.entrance.y, 0, "entrance tie chooses north")
  truthy(field.advance_lane(north), "vertical second lane")
  local north_turn = field.headland_waypoints(north)
  equal(north_turn[1].x, 2, "vertical headland starts on completed lane center")
  equal(north_turn[1].y, 66, "vertical headland exits south field edge")
  equal(north_turn[5].x, 6, "vertical headland ends on next lane center")
  equal(north_turn[5].y, 64, "vertical headland returns to south field edge")

  local ranges = {}
  local delta
  ranges, delta = field._add_interval(ranges, 0, 16)
  equal(delta, 16, "first interval delta")
  ranges, delta = field._add_interval(ranges, 8, 24)
  equal(delta, 8, "overlapping interval delta")
  ranges, delta = field._add_interval(ranges, 24, 32)
  equal(delta, 8, "adjacent interval delta")
  equal(#ranges, 1, "overlapping and adjacent intervals merge")

  local progress = field.create(5, 1, horizontal, {x = -10, y = 8})
  equal(field.commit(progress, {left = 0, top = 0, right = 16, bottom = 4}), 64, "quarter-lane commit")
  equal(field.commit(progress, {left = 8, top = 0, right = 16, bottom = 4}), 0, "overlap is idempotent")
  equal(field.next_uncovered(progress).x, 16, "resume begins at first uncovered position")
  equal(field.commit(progress, {left = 16, top = 0, right = 64, bottom = 4}), 192, "resumed lane delta")
  equal(progress.completed_area, 256, "exact completed lane area")
  equal(field.next_uncovered(progress), nil, "completed lane has no uncovered point")
  for lane_index = 2, 4 do
    truthy(field.advance_lane(progress), "advance to lane " .. lane_index)
    equal(field.commit(progress, progress.lane), 256, "lane " .. lane_index .. " exact delta")
  end
  equal(progress.completed_area, 1024, "exact completed field area")
  equal(field.advance_lane(progress), false, "advanced past final lane")
  local completed = field.completed_rectangles(progress)
  equal(#completed, 1, "coherent field progress projects as one rectangle")
  equal(completed[1].top, 0, "completed projection top")
  equal(completed[1].bottom, 16, "completed projection bottom")

  local job = {state = "waiting"}
  truthy(slice.transition(job, "reserved"), "waiting to reserved transition")
  truthy(slice.transition(job, "travelling"), "reserved to travelling transition")
  local transitioned = slice.transition(job, "completed")
  equal(transitioned, false, "invalid transition accepted")

  local paused_job = {state = "working"}
  truthy(slice.transition(paused_job, "paused"), "working to paused transition")
  truthy(slice.transition(paused_job, "working"), "paused to working transition")
end

local function build_surface(name)
  local surface = game.create_surface("farming-production-slice-test-" .. name, {
    width = 256,
    height = 256,
    peaceful_mode = true,
    autoplace_controls = {}
  })
  surface.generate_with_lab_tiles = true
  surface.request_to_generate_chunks({x = 0, y = 0}, 4)
  surface.force_generate_chunk_requests()
  local test_tiles = {}
  for y = -32, 31 do
    for x = -32, 95 do
      test_tiles[#test_tiles + 1] = {name = "lab-dark-1", position = {x = x, y = y}}
    end
  end
  surface.set_tiles(test_tiles, true, true, true, false)
  for _, entity in pairs(surface.find_entities_filtered({
    type = {"tree", "simple-entity", "cliff", "resource", "unit", "unit-spawner", "turret"}
  })) do
    entity.destroy()
  end
  return surface
end

local FIELD_BOUNDS = {left = 0, top = 0, right = 64, bottom = 16}
local TRACTOR_POSITION = {x = -20, y = 8}

local function setup_slice(surface_index, what)
  local ok, message = remote.call("factorio_farming", "debug_setup", surface_index,
    FIELD_BOUNDS, TRACTOR_POSITION)
  truthy(ok, message or (what .. " setup failed"))
end

local function snapshot(surface_index)
  return remote.call("factorio_farming", "snapshot", surface_index)
end

-- ---------------------------------------------------------------- functional

local function init_functional()
  storage.test_surfaces = {}
  for _, scenario in ipairs({"full", "pause", "turn-pause", "destroy"}) do
    local surface = build_surface(scenario)
    setup_slice(surface.index, scenario)
    storage.test_surfaces[scenario] = surface.index
  end
  storage.test_started_tick = game.tick
  storage.pause_index = 1
  storage.pause_until = nil
  storage.destroyed = false
  storage.replaced = false
  storage.turn_paused = false
  storage.turn_resumed = false
  storage.visual_rebuild_started = false
end

local function drive_functional(event)
  local snapshots = {}
  for scenario, surface_index in pairs(storage.test_surfaces) do
    snapshots[scenario] = snapshot(surface_index)
  end
  if event.tick - storage.test_started_tick >= 11000 then
    write_result("result", {passed = false, reason = "integration timeout", snapshots = snapshots})
    fail("integration timeout")
  end

  local paused = snapshots.pause
  local thresholds = {64, 128, 192}
  if storage.pause_index <= #thresholds then
    if storage.pause_until then
      if event.tick >= storage.pause_until then
        equal(paused.job.state, "paused", "pause state at interruption " .. storage.pause_index)
        equal(paused.field.completed_area, storage.paused_area, "progress changed while paused")
        truthy(remote.call("factorio_farming", "debug_resume", storage.test_surfaces.pause), "resume failed")
        storage.pause_index = storage.pause_index + 1
        storage.pause_until = nil
      end
    elseif paused.job.state == "working" and paused.field.completed_area >= thresholds[storage.pause_index] then
      truthy(remote.call("factorio_farming", "debug_pause", storage.test_surfaces.pause), "pause failed")
      storage.paused_area = paused.field.completed_area
      storage.pause_until = event.tick + 60
    end
  end

  local destroyed = snapshots.destroy
  if not storage.destroyed and destroyed.job.state == "working" and destroyed.field.completed_area >= 64 then
    storage.destroyed_area = destroyed.field.completed_area
    truthy(remote.call("factorio_farming", "debug_destroy_tractor", storage.test_surfaces.destroy), "tractor destruction failed")
    storage.destroyed = true
  elseif storage.destroyed and not storage.replaced and destroyed.job.state == "failed" then
    equal(destroyed.field.completed_area, storage.destroyed_area, "tractor destruction changed progress")
    local replaced, replace_error = remote.call("factorio_farming", "debug_replace_tractor",
      storage.test_surfaces.destroy, TRACTOR_POSITION)
    truthy(replaced, replace_error or "replacement tractor failed")
    truthy(remote.call("factorio_farming", "debug_resume", storage.test_surfaces.destroy), "replacement resume failed")
    storage.replaced = true
  end

  local turn = snapshots["turn-pause"]
  if not storage.turn_paused and turn.field.lane_index == 2 and
     turn.machine.controller_state == "positioning" then
    truthy(remote.call("factorio_farming", "debug_pause", storage.test_surfaces["turn-pause"]),
      "headland pause failed")
    storage.turn_paused = true
    storage.turn_area = turn.field.completed_area
    storage.turn_resume_tick = event.tick + 60
  elseif storage.turn_paused and not storage.turn_resumed and event.tick >= storage.turn_resume_tick then
    equal(turn.job.state, "paused", "headland job did not stay paused")
    equal(turn.field.completed_area, storage.turn_area, "headland pause changed progress")
    truthy(remote.call("factorio_farming", "debug_resume", storage.test_surfaces["turn-pause"]),
      "headland resume failed")
    local resumed = snapshot(storage.test_surfaces["turn-pause"])
    equal(resumed.machine.controller_state, "positioning", "headland resume did not restore positioning")
    storage.turn_resumed = true
  end

  if snapshots.full.job.state ~= "completed" or snapshots.pause.job.state ~= "completed" or
     snapshots["turn-pause"].job.state ~= "completed" or snapshots.destroy.job.state ~= "completed" then return end

  if not storage.visual_rebuild_started then
    for scenario, snap in pairs(snapshots) do
      equal(snap.field.completed_area, 1024, scenario .. " completed area")
      equal(snap.field.total_area, 1024, scenario .. " field area")
      equal(snap.job.machine_id, nil, scenario .. " completed job machine claim")
      equal(snap.job.has_claim, false, scenario .. " completed job lane claim")
      equal(snap.machine.job_id, nil, scenario .. " completed machine assignment")
    end
    equal(snapshots.full.pending_path_count, 0, "completed jobs pending paths")
    remote.call("factorio_farming", "clear_visuals", storage.test_surfaces.full)
    local cleared = snapshot(storage.test_surfaces.full)
    equal(cleared.visual_count, 0, "visual clear hook")
    equal(cleared.field.completed_area, 1024, "visual clear changed authoritative progress")
    remote.call("factorio_farming", "rebuild_visuals", storage.test_surfaces.full)
    storage.visual_rebuild_started = true
    storage.visual_rebuild_tick = event.tick
    return
  end

  if event.tick <= storage.visual_rebuild_tick then return end
  truthy(snapshots.full.visual_count >= 4, "visual rebuild did not restore projections")
  equal(snapshots.full.field.completed_area, 1024, "visual rebuild changed authoritative progress")
  write_result("result", {
    passed = true,
    tick = event.tick,
    completed_area = snapshots.full.field.completed_area,
    total_area = snapshots.full.field.total_area,
    visual_count = snapshots.full.visual_count,
    pure_tests = "passed",
    integration = "passed",
    pause_resume_checkpoints = 3,
    destruction_replacement = "passed",
    headland_pause_resume = "passed"
  })
  script.on_event(defines.events.on_tick, nil)
end

-- ------------------------------------------------------------------ capture

local function init_capture()
  storage.capture = {
    surface = build_surface("capture").index,
    step = 1,
    saved = {},
    started = game.tick
  }
end

-- Freezes the current state into a named save. `test_capture` travels inside the
-- save and tells the replay driver which phase it is looking at.
local function save_phase(capture, phase, snap, tick)
  storage.test_capture = phase
  storage.capture_area = snap and snap.field.completed_area or 0
  storage.capture_generation = snap and snap.machine.generation or 0
  storage.capture_job_state = snap and snap.job.state or "none"
  storage.capture_surface = capture.surface
  capture.saved[#capture.saved + 1] = phase
  capture.step = capture.step + 1
  capture.cooldown = tick + 2
  game.auto_save("phase-" .. phase)
end

local function drive_capture(event)
  local capture = storage.capture
  if capture.done then return end
  if capture.cooldown and event.tick < capture.cooldown then return end
  if event.tick - capture.started > 60000 then
    write_result("capture", {passed = false, reason = "capture timeout", step = capture.step})
    fail("capture timeout at step " .. capture.step)
  end

  if capture.step == 1 then
    setup_slice(capture.surface, "capture")
    local snap = snapshot(capture.surface)
    -- Proves `reserved` is a real observable phase, not a step inside setup.
    equal(snap.job.state, "reserved", "capture job did not settle in reserved")
    save_phase(capture, "reserved", snap, event.tick)
    return
  end

  local snap = snapshot(capture.surface)

  if capture.step == 2 then
    if snap.job.state == "travelling" and snap.machine.controller_state == "following" then
      save_phase(capture, "travelling", snap, event.tick)
    end
  elseif capture.step == 3 then
    if snap.job.state == "working" and snap.field.completed_area >= 64 then
      save_phase(capture, "working", snap, event.tick)
    end
  elseif capture.step == 4 then
    truthy(remote.call("factorio_farming", "debug_pause", capture.surface), "capture pause failed")
    capture.step = 5
    capture.cooldown = event.tick + 2
  elseif capture.step == 5 then
    equal(snap.job.state, "paused", "capture job did not pause")
    save_phase(capture, "paused", snap, event.tick)
  elseif capture.step == 6 then
    -- A separate, untouched slice carries the performance reference run. The
    -- paused capture slice stays paused so only one job is active in it.
    storage.bench_surface = build_surface("bench").index
    capture.step = 7
    capture.cooldown = event.tick + 2
  elseif capture.step == 7 then
    setup_slice(storage.bench_surface, "bench")
    save_phase(capture, "benchmark", snapshot(storage.bench_surface), event.tick)
  elseif capture.step == 8 then
    capture.done = true
    write_result("capture", {passed = true, tick = event.tick, saved = capture.saved})
    script.on_event(defines.events.on_tick, nil)
  end
end

-- ------------------------------------------------------------------- replay

local verify = {}
local bench = {}

local function drive_verify(event, phase)
  if verify.done then return end
  local surface = storage.capture_surface
  local snap = snapshot(surface)

  if not verify.started then
    verify.started = event.tick
    -- The load itself must neither lose nor inflate authoritative progress.
    equal(snap.field.completed_area, storage.capture_area, phase .. " load changed progress")
    equal(snap.field.total_area, 1024, phase .. " field area after load")
    truthy(snap.machine.valid, phase .. " tractor invalid after load")
    -- Generations move on so any callback from the pre-save session is stale.
    truthy(snap.machine.generation > storage.capture_generation,
      phase .. " did not invalidate pre-save callbacks")
    -- The one-outstanding-request budget still holds immediately after a load.
    truthy(snap.pending_path_count <= 1, phase .. " exceeded the outstanding path budget after load")
    if phase == "reserved" or phase == "travelling" then
      -- The saved request is discarded and a fresh one is issued, rather than
      -- the stale in-flight path being trusted.
      equal(snap.machine.controller_state, "requesting", phase .. " did not reissue its path after load")
    elseif phase == "working" then
      equal(snap.job.state, "working", "working save did not load working")
    elseif phase == "paused" then
      equal(snap.job.state, "paused", "paused save did not load paused")
      verify.hold_until = event.tick + 60
    end
    return
  end

  if phase == "paused" and not verify.resumed then
    if event.tick < verify.hold_until then
      equal(snap.job.state, "paused", "paused job left paused without resume")
      equal(snap.field.completed_area, storage.capture_area, "paused job progressed without resume")
      return
    end
    truthy(remote.call("factorio_farming", "debug_resume", surface), "resume after load failed")
    verify.resumed = true
    return
  end

  -- Below the harness tick budget so a stall reports itself instead of the run
  -- simply ending without a result file.
  if event.tick - verify.started > 15000 then
    write_result("saveload-" .. phase, {
      passed = false, reason = "timeout", state = snap.job.state,
      completed_area = snap.field.completed_area, snapshot = snap
    })
    fail(phase .. " save/load run timed out")
  end

  if snap.job.state ~= "completed" then return end
  equal(snap.field.completed_area, 1024, phase .. " final completed area")
  equal(snap.field.total_area, 1024, phase .. " final field area")
  equal(snap.job.machine_id, nil, phase .. " completed job machine claim")
  equal(snap.job.has_claim, false, phase .. " completed job lane claim")
  equal(snap.machine.job_id, nil, phase .. " completed machine assignment")
  equal(snap.pending_path_count, 0, phase .. " pending path after completion")
  verify.done = true
  write_result("saveload-" .. phase, {
    passed = true,
    phase = phase,
    loaded_area = storage.capture_area,
    completed_area = snap.field.completed_area,
    total_area = snap.field.total_area,
    ticks_after_load = event.tick - verify.started
  })
  script.on_event(defines.events.on_tick, nil)
end

local function drive_benchmark(event)
  if bench.done then return end
  local surface = storage.bench_surface
  local snap = snapshot(surface)

  if not bench.start then
    bench.start = event.tick
    return
  end
  if not bench.profiling then
    -- Skip the load-recovery ticks so one-time setup is excluded.
    if event.tick < bench.start + PROFILE_DELAY then return end
    truthy(remote.call("factorio_farming", "debug_profile_start"), "profiler did not start")
    bench.profiling = true
    bench.profile_start = event.tick
    return
  end

  if not bench.completed_tick and snap.job.state == "completed" then
    bench.completed_tick = event.tick
    equal(snap.field.completed_area, 1024, "benchmark field completed area")
  end

  if event.tick >= bench.profile_start + BENCH_TICKS then
    local samples = remote.call("factorio_farming", "debug_profile_stop")
    bench.done = true
    equal(snap.job.state, "completed", "benchmark field did not complete during the reference run")
    write_result("benchmark", {
      passed = true,
      profile_start_tick = bench.profile_start,
      profile_end_tick = event.tick,
      profiled_ticks = event.tick - bench.profile_start,
      samples = samples,
      field_completed_tick = bench.completed_tick,
      completed_area = snap.field.completed_area,
      total_area = snap.field.total_area
    })
    script.on_event(defines.events.on_tick, nil)
  end
end

local function drive_replay(event)
  local phase = storage.test_capture
  if not phase then fail("replayed save carries no captured phase") end
  if phase == "benchmark" then drive_benchmark(event) else drive_verify(event, phase) end
end

-- ----------------------------------------------------------------- dispatch

script.on_init(function()
  run_pure_tests()
  if mode == "capture" then
    init_capture()
  elseif mode == "functional" then
    init_functional()
  else
    fail("mode '" .. tostring(mode) .. "' does not create a map")
  end
end)

script.on_event(defines.events.on_tick, function(event)
  if mode == "capture" then
    drive_capture(event)
  elseif mode == "replay" then
    drive_replay(event)
  else
    drive_functional(event)
  end
end)
