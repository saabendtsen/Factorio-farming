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

  -- Version-2 field authority is pure Lua: each operation owns normalized
  -- coverage and only sowing creates durable crop records.
  local authority = field.create(6, 1, horizontal, {x = -10, y = 8})
  equal(field.commit_operation(authority, "sowing", {left = 0, top = 0, right = 4, bottom = 4}, 100),
    0, "sowing without cultivation is rejected")
  equal(field.commit_operation(authority, "cultivation", {left = 0, top = 0, right = 64, bottom = 16}),
    1024, "cultivation authority delta")
  equal(field.commit_operation(authority, "sowing", {left = 0, top = 0, right = 16, bottom = 4}, 100),
    64, "sowing authority delta")
  equal(field.operation_area(authority, "sowing"), 64, "sowing coverage area")
  equal(#authority.crops, 1, "sowing creates one compact crop record")
  equal(authority.crops[1].sow_tick, 100, "crop record persists sow tick")
  equal(field.lifecycle(authority, 99), "sowing", "partially sown field remains sowing")
  equal(field.commit_operation(authority, "harvesting", {left = 0, top = 0, right = 16, bottom = 4}, 100, 64),
    0, "unready crop cannot be harvested")
  equal(field.commit_operation(authority, "harvesting", {left = 0, top = 0, right = 16, bottom = 4}, 3700, 0),
    0, "failed transfer retains ready crop coverage")
  equal(field.operation_area(authority, "sowing"), 64, "failed transfer does not remove crop coverage")
  equal(field.commit_operation(authority, "harvesting", {left = 0, top = 0, right = 16, bottom = 4}, 3700, 64),
    64, "ready crop harvest delta")
  equal(field.operation_area(authority, "sowing"), 0, "harvest removes live crop coverage")
  equal(#authority.crops, 0, "harvest deletes harvested crop record")
  equal(field.lifecycle(authority, 3700), "prepared", "harvested field returns to prepared")

  -- The player-facing operation is derived from durable coverage and crop
  -- timing. No controller state decides what can happen next.
  local cycle = field.create(8, 1, horizontal, {x = -10, y = 8})
  equal(field.next_operation(cycle, 0), "cultivation", "new field starts with cultivation")
  equal(field.commit_operation(cycle, "cultivation", cycle.bounds), 1024, "cycle cultivation")
  equal(field.next_operation(cycle, 0), "sowing", "prepared field offers sowing")
  equal(field.commit_operation(cycle, "sowing", cycle.bounds, 100), 1024, "cycle sowing")
  equal(field.crop_stage(cycle.crops[1], 100), "sown", "new crop visual stage")
  equal(field.crop_stage(cycle.crops[1], 1900), "growing", "mid-growth visual stage")
  equal(field.next_operation(cycle, 1900), nil, "growing crop has no operation")
  equal(field.crop_stage(cycle.crops[1], 3700), "ready", "mature crop visual stage")
  equal(field.next_operation(cycle, 3700), "harvesting", "ready crop offers harvesting")
  equal(field.next_uncovered_for(cycle, "harvesting").x, 0, "harvesting starts at its first uncovered tile")
  equal(field.commit_operation(cycle, "harvesting", {left = 0, top = 0, right = 32, bottom = 4}, 3700, 128),
    128, "cycle harvest partial lane")
  equal(field.next_uncovered_for(cycle, "harvesting").x, 32, "harvesting follows its own authoritative coverage")
  equal(field.operation_rectangle_is_uncovered(cycle, "harvesting", {left = 0, top = 0, right = 32, bottom = 4}), false,
    "harvested coverage cannot be transferred twice")
  field.begin_operation(cycle)
  truthy(field.advance_lane(cycle), "cycle second lane for westbound harvest geometry")
  local westbound_harvest = field.next_uncovered_rectangle(cycle, "harvesting")
  equal(westbound_harvest.left, 63, "westbound harvest begins at the final in-bounds tile")
  equal(westbound_harvest.right, 64, "westbound harvest rectangle stays inside field bounds")

  local legacy = field.create(7, 1, horizontal, {x = -10, y = 8})
  field.commit(legacy, {left = 0, top = 0, right = 64, bottom = 4})
  legacy.schema_version = nil
  local root = {
    schema_version = 1,
    next_field_id = 8,
    next_machine_id = 2,
    next_job_id = 2,
    path_queue = {{machine_id = 1}},
    pending_paths = {one = {machine_id = 1}},
    outstanding_path_id = 99,
    surfaces = {[1] = {field = legacy, job = {id = 1, state = "working", machine_id = 1, lane_claim = 1,
      paused_from = "working", paused_motion = {remaining_waypoints = {{x = 1, y = 1}}}},
      machine = {id = 1, job_id = 1, controller = {state = "working"}}}}
  }
  truthy(field.migrate_storage(root), "legacy storage migration")
  equal(root.schema_version, 2, "storage schema version")
  equal(field.operation_area(root.surfaces[1].field, "cultivation"), 256, "legacy coverage converts exactly")
  equal(field.operation_area(root.surfaces[1].field, "sowing"), 0, "migration invents no sowing")
  equal(#root.surfaces[1].field.crops, 0, "migration invents no crops")
  equal(root.surfaces[1].job.state, "paused", "legacy operation requires explicit recovery")
  equal(root.surfaces[1].job.lane_claim, nil, "legacy lane claim discarded")
  equal(root.surfaces[1].job.paused_motion, nil, "legacy controller motion discarded")
  equal(#root.path_queue, 0, "legacy queued paths discarded")
  equal(next(root.pending_paths), nil, "legacy pending paths discarded")

  local malformed_root = {schema_version = 1, surfaces = {[1] = {field = {
    id = 9, surface_index = 1, bounds = horizontal, axis = "x", strips = {{{8, 4}}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}},
    completed_area = 0
  }, job = {state = "working", machine_id = 4, lane_claim = 1}, machine = {job_id = 4, generation = 2}}}}
  truthy(field.migrate_storage(malformed_root), "malformed migration completes fail-closed conversion")
  truthy(malformed_root.surfaces[1].field.migration_failed, "malformed field fails closed")
  truthy(malformed_root.surfaces[1].field.legacy_raw, "malformed field retains diagnostics")
  equal(malformed_root.surfaces[1].job.state, "paused", "malformed job is disabled")
  equal(malformed_root.surfaces[1].machine.job_id, nil, "malformed machine assignment cleared")

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

-- --------------------------------------------------------------- crop cycle

local function init_cycle()
  local surface = build_surface("crop-cycle")
  storage.cycle_surface = surface.index
  storage.cycle_storage = surface.create_entity({name = "farming-storage-container", position = {x = -10, y = 20}, force = game.forces.player})
  setup_slice(surface.index, "crop cycle")
  storage.cycle_operation = "cultivation"
  storage.cycle_started = game.tick
  storage.cycle_sow_paused = false
  storage.cycle_sow_resumed = false
  storage.cycle_storage_destroyed = false
  storage.cycle_storage_retried = false
  storage.cycle_tractor_destroyed = false
  storage.cycle_tractor_replaced = false
end

local function drive_cycle(event)
  local snap = snapshot(storage.cycle_surface)
  if snap.job.state == "failed" then
    if storage.cycle_storage_destroyed and not storage.cycle_storage_retried then
      equal(snap.field.harvested_area, 0, "missing destination changes no harvest coverage")
      equal(snap.field.sown_area, 1024, "missing destination retains ready crop coverage")
      storage.cycle_storage = game.get_surface(storage.cycle_surface).create_entity({
        name = "farming-storage-container", position = {x = -10, y = 20}, force = game.forces.player
      })
      truthy(remote.call("factorio_farming", "debug_resume", storage.cycle_surface), "resume after storage replacement")
      storage.cycle_storage_retried = true
      return
    end
    if storage.cycle_tractor_destroyed and not storage.cycle_tractor_replaced then
      equal(snap.field.harvested_area, storage.cycle_harvest_area_before_destroy,
        "tractor loss changes no harvested coverage")
      local replaced, message = remote.call("factorio_farming", "debug_replace_tractor",
        storage.cycle_surface, TRACTOR_POSITION)
      truthy(replaced, message or "replace harvest tractor")
      truthy(remote.call("factorio_farming", "debug_resume", storage.cycle_surface), "resume after harvest tractor replacement")
      storage.cycle_tractor_replaced = true
      return
    end
    local inventory = storage.cycle_storage.get_inventory(defines.inventory.chest)
    write_result("cycle", {passed = false, reason = snap.job.failure, operation = storage.cycle_operation, snapshot = snap,
      wheat_stack_size = prototypes.item["farming-wheat"].stack_size,
      storage_slots = #inventory,
      stored_wheat = inventory.get_item_count("farming-wheat")})
    fail("crop cycle failed: " .. tostring(snap.job.failure))
  end
  if event.tick - storage.cycle_started > 90000 then
    write_result("cycle", {passed = false, reason = "timeout", operation = storage.cycle_operation, snapshot = snap,
      wheat_stack_size = prototypes.item["farming-wheat"].stack_size,
      storage_slots = #storage.cycle_storage.get_inventory(defines.inventory.chest)})
    fail("crop cycle timeout")
  end
  if storage.cycle_sow_pause_until then
    equal(snap.job.state, "paused", "sowing stays paused")
    equal(snap.field.sown_area, storage.cycle_sow_pause_area, "sowing pause changes no coverage")
    if event.tick >= storage.cycle_sow_pause_until then
      truthy(remote.call("factorio_farming", "debug_resume", storage.cycle_surface), "resume sowing")
      storage.cycle_sow_pause_until = nil
      storage.cycle_sow_resumed = true
    end
    return
  end
  if storage.cycle_operation == "sowing" and not storage.cycle_sow_paused and
     snap.job.state == "working" and snap.field.sown_area >= 64 then
    truthy(remote.call("factorio_farming", "debug_pause", storage.cycle_surface), "pause sowing")
    storage.cycle_sow_paused = true
    storage.cycle_sow_pause_area = snap.field.sown_area
    storage.cycle_sow_pause_until = event.tick + 60
    return
  end
  if storage.cycle_operation == "harvesting" and not storage.cycle_storage_destroyed and
     snap.job.state == "working" and snap.field.harvested_area == 0 then
    storage.cycle_storage.destroy()
    storage.cycle_storage_destroyed = true
    return
  end
  if storage.cycle_operation == "harvesting" and storage.cycle_storage_retried and
     not storage.cycle_tractor_destroyed and snap.job.state == "working" and snap.field.harvested_area >= 64 then
    storage.cycle_harvest_area_before_destroy = snap.field.harvested_area
    truthy(remote.call("factorio_farming", "debug_destroy_tractor", storage.cycle_surface), "destroy harvest tractor")
    storage.cycle_tractor_destroyed = true
    return
  end
  if snap.job.state == "completed" and storage.cycle_operation == "cultivation" then
    equal(snap.field.cultivated_area, 1024, "crop cycle cultivation coverage")
    truthy(remote.call("factorio_farming", "debug_start_next_operation", storage.cycle_surface), "crop cycle sowing start")
    storage.cycle_operation = "sowing"
  elseif snap.job.state == "completed" and storage.cycle_operation == "sowing" then
    truthy(storage.cycle_sow_resumed, "sowing pause and explicit resume completed")
    equal(snap.field.sown_area, 1024, "crop cycle sowing coverage")
    equal(snap.field.lifecycle, "growing", "crop cycle enters growth")
    storage.cycle_operation = "growing"
  elseif storage.cycle_operation == "growing" then
    if snap.field.lifecycle == "ready" then
      truthy(remote.call("factorio_farming", "debug_start_next_operation", storage.cycle_surface), "crop cycle harvest start")
      storage.cycle_operation = "harvesting"
    end
  elseif snap.job.state == "completed" and storage.cycle_operation == "harvesting" then
    truthy(storage.cycle_storage_retried, "harvest retries after destination replacement")
    truthy(storage.cycle_tractor_replaced, "harvest retries after tractor replacement")
    equal(snap.field.harvested_area, 1024, "crop cycle harvest coverage")
    equal(snap.field.sown_area, 0, "crop cycle removes harvested sowing coverage")
    equal(storage.cycle_storage.get_inventory(defines.inventory.chest).get_item_count("farming-wheat"), 1024,
      "crop cycle deposits one wheat per tile")
    write_result("cycle", {passed = true, completed_area = snap.field.cultivated_area, wheat = 1024})
    script.on_event(defines.events.on_tick, nil)
  end
end

-- ------------------------------------------------------- crop save / load

local function save_cycle_phase(capture, phase, snap)
  storage.test_capture = "cycle-" .. phase
  storage.capture_area = snap.field.completed_area
  storage.capture_sown_area = snap.field.sown_area
  storage.capture_harvested_area = snap.field.harvested_area
  storage.capture_generation = snap.machine.generation
  storage.capture_surface = capture.surface
  capture.saved[#capture.saved + 1] = phase
  game.auto_save("cycle-" .. phase)
end

local function init_cycle_capture()
  init_cycle()
  storage.cycle_capture = {surface = storage.cycle_surface, stage = "cultivation", saved = {}, started = game.tick}
end

local function drive_cycle_capture(event)
  local capture = storage.cycle_capture
  local snap = snapshot(capture.surface)
  if event.tick - capture.started > 40000 then fail("crop save capture timeout") end
  if capture.stage == "cultivation" and snap.job.state == "completed" then
    truthy(remote.call("factorio_farming", "debug_start_next_operation", capture.surface), "capture start sowing")
    capture.stage = "sowing"
  elseif capture.stage == "sowing" and snap.job.state == "working" and snap.field.sown_area >= 64 then
    save_cycle_phase(capture, "sowing", snap)
    capture.stage = "sowing-saved"
  elseif capture.stage == "sowing-saved" and snap.job.state == "completed" then
    capture.stage = "growing"
  elseif capture.stage == "growing" and snap.field.lifecycle == "ready" then
    truthy(remote.call("factorio_farming", "debug_start_next_operation", capture.surface), "capture start harvesting")
    capture.stage = "harvesting"
  elseif capture.stage == "harvesting" and snap.job.state == "working" and snap.field.harvested_area >= 64 then
    save_cycle_phase(capture, "harvesting", snap)
    write_result("cycle-capture", {passed = true, saved = capture.saved, tick = event.tick})
    script.on_event(defines.events.on_tick, nil)
  end
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
local cycle_verify = {}

local function drive_cycle_verify(event, phase)
  local snap = snapshot(storage.capture_surface)
  if not cycle_verify.started then
    cycle_verify.started = event.tick
    equal(snap.field.completed_area, storage.capture_area, phase .. " load changed cultivation coverage")
    equal(snap.field.sown_area, storage.capture_sown_area, phase .. " load changed sowing coverage")
    equal(snap.field.harvested_area, storage.capture_harvested_area, phase .. " load changed harvesting coverage")
    truthy(snap.machine.generation > storage.capture_generation, phase .. " did not invalidate saved controller")
    local expected_operation = phase == "cycle-sowing" and "sowing" or "harvesting"
    equal(snap.job.operation, expected_operation, phase .. " loaded the wrong crop operation")
    return
  end
  if event.tick - cycle_verify.started > 25000 then fail(phase .. " crop replay timeout") end
  if phase == "cycle-sowing" then
    if not cycle_verify.harvest_started and snap.job.state == "completed" and snap.field.lifecycle == "ready" then
      truthy(remote.call("factorio_farming", "debug_start_next_operation", storage.capture_surface), "loaded sowing starts harvest")
      cycle_verify.harvest_started = true
      return
    end
  end
  if phase == "cycle-sowing" and not cycle_verify.harvest_started then return end
  if snap.job.state ~= "completed" then return end
  equal(snap.field.harvested_area, 1024, phase .. " replay harvest coverage")
  equal(snap.field.sown_area, 0, phase .. " replay removes sown coverage")
  equal(snap.field.stored_wheat, 1024, phase .. " replay deposits exact wheat")
  cycle_verify.done = true
  write_result("saveload-" .. phase, {passed = true, phase = phase, wheat = 1024})
  script.on_event(defines.events.on_tick, nil)
end

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
  if phase == "benchmark" then drive_benchmark(event)
  elseif phase == "cycle-sowing" or phase == "cycle-harvesting" then drive_cycle_verify(event, phase)
  else drive_verify(event, phase) end
end

-- ----------------------------------------------------------------- dispatch

script.on_init(function()
  run_pure_tests()
  if mode == "capture" then
    init_capture()
  elseif mode == "cycle-capture" then
    init_cycle_capture()
  elseif mode == "cycle" then
    init_cycle()
  elseif mode == "functional" then
    init_functional()
  else
    fail("mode '" .. tostring(mode) .. "' does not create a map")
  end
end)

script.on_event(defines.events.on_tick, function(event)
  if mode == "capture" then
    drive_capture(event)
  elseif mode == "cycle-capture" then
    drive_cycle_capture(event)
  elseif mode == "cycle" then
    drive_cycle(event)
  elseif mode == "replay" then
    drive_replay(event)
  else
    drive_functional(event)
  end
end)
