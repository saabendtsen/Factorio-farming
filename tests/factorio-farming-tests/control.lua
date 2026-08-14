local field = require("__factorio-farming__/scripts/field")
local slice = require("__factorio-farming__/scripts/slice")

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
  equal(west.lane.top, 6, "centered lane top")
  equal(west.lane.bottom, 10, "centered lane bottom")

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

  local vertical_bounds = assert(field.normalize_selection({
    left_top = {x = 0, y = 0}, right_bottom = {x = 16, y = 64}
  }))
  local north = field.create(4, 1, vertical_bounds, {x = 8, y = 32})
  equal(north.axis, "y", "vertical axis")
  equal(north.entrance.y, 0, "entrance tie chooses north")

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
  equal(field.commit(progress, {left = 0, top = 6, right = 16, bottom = 10}), 64, "quarter-lane commit")
  equal(field.commit(progress, {left = 8, top = 6, right = 16, bottom = 10}), 0, "overlap is idempotent")
  equal(field.next_uncovered(progress).x, 16, "resume begins at first uncovered position")
  equal(field.commit(progress, {left = 16, top = 6, right = 64, bottom = 10}), 192, "resumed lane delta")
  equal(progress.completed_area, 256, "exact completed lane area")
  equal(field.next_uncovered(progress), nil, "completed lane has no uncovered point")
  equal(#field.completed_rectangles(progress), 1, "coherent progress projects as one rectangle")

  local job = {state = "waiting"}
  truthy(slice.transition(job, "reserved"), "waiting to reserved transition")
  truthy(slice.transition(job, "travelling"), "reserved to travelling transition")
  local transitioned = slice.transition(job, "completed")
  equal(transitioned, false, "invalid transition accepted")
end

local function write_result(result)
  helpers.write_file(
    "factorio-farming-tests/result.json",
    helpers.table_to_json(result),
    false
  )
  log("FACTORIO_FARMING_TEST_RESULT " .. helpers.table_to_json(result))
end

script.on_init(function()
  run_pure_tests()
  storage.test_surfaces = {}
  for _, scenario in ipairs({"full", "pause", "destroy"}) do
    local surface = game.create_surface("farming-production-slice-test-" .. scenario, {
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

    local ok, message = remote.call("factorio_farming", "debug_setup", surface.index,
      {left = 0, top = 0, right = 64, bottom = 16}, {x = -20, y = 8})
    truthy(ok, message or (scenario .. " integration setup failed"))
    storage.test_surfaces[scenario] = surface.index
  end
  storage.test_started_tick = game.tick
  storage.pause_index = 1
  storage.pause_until = nil
  storage.destroyed = false
  storage.replaced = false
  storage.visual_rebuild_started = false
end)

script.on_event(defines.events.on_tick, function(event)
  local snapshots = {}
  for scenario, surface_index in pairs(storage.test_surfaces) do
    snapshots[scenario] = remote.call("factorio_farming", "snapshot", surface_index)
  end
  if event.tick - storage.test_started_tick >= 11000 then
    write_result({passed = false, reason = "integration timeout", snapshots = snapshots})
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
      storage.test_surfaces.destroy, {x = -20, y = 8})
    truthy(replaced, replace_error or "replacement tractor failed")
    truthy(remote.call("factorio_farming", "debug_resume", storage.test_surfaces.destroy), "replacement resume failed")
    storage.replaced = true
  end

  if snapshots.full.job.state ~= "completed" or snapshots.pause.job.state ~= "completed" or
     snapshots.destroy.job.state ~= "completed" then return end

  if not storage.visual_rebuild_started then
    for scenario, snapshot in pairs(snapshots) do
      equal(snapshot.field.completed_area, 256, scenario .. " completed area")
      equal(snapshot.field.total_area, 1024, scenario .. " field area")
      equal(snapshot.job.machine_id, nil, scenario .. " completed job machine claim")
      equal(snapshot.job.has_claim, false, scenario .. " completed job lane claim")
      equal(snapshot.machine.job_id, nil, scenario .. " completed machine assignment")
    end
    equal(snapshots.full.pending_path_count, 0, "completed jobs pending paths")
    remote.call("factorio_farming", "clear_visuals", storage.test_surfaces.full)
    local cleared = remote.call("factorio_farming", "snapshot", storage.test_surfaces.full)
    equal(cleared.visual_count, 0, "visual clear hook")
    equal(cleared.field.completed_area, 256, "visual clear changed authoritative progress")
    remote.call("factorio_farming", "rebuild_visuals", storage.test_surfaces.full)
    storage.visual_rebuild_started = true
    storage.visual_rebuild_tick = event.tick
    return
  end

  if event.tick <= storage.visual_rebuild_tick then return end
  truthy(snapshots.full.visual_count >= 4, "visual rebuild did not restore projections")
  equal(snapshots.full.field.completed_area, 256, "visual rebuild changed authoritative progress")
  write_result({
    passed = true,
    tick = event.tick,
    completed_area = snapshots.full.field.completed_area,
    total_area = snapshots.full.field.total_area,
    visual_count = snapshots.full.visual_count,
    pure_tests = "passed",
    integration = "passed",
    pause_resume_checkpoints = 3,
    destruction_replacement = "passed",
    save_load = "passed during initial travel"
  })
  script.on_event(defines.events.on_tick, nil)
end)
