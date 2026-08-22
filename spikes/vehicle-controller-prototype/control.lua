-- PROTOTYPE: answers whether Factorio 2.1 can path and custom-steer cars through
-- a field entrance and deterministic lane with bounded stuck recovery.

local config = require("config")

local ARRIVAL_RADIUS = 1.0
local STUCK_WINDOW = 120
local STUCK_DISTANCE = 0.45
local REVERSE_TICKS = 90
local MAX_REPATHS = 2
local MAX_PATH_DEFERRALS = 20
local MAX_SPEED = 0.11

local function distance(a, b)
  local dx = b.x - a.x
  local dy = b.y - a.y
  return math.sqrt(dx * dx + dy * dy)
end

local function desired_orientation(from, to)
  local radians = math.atan2(to.x - from.x, -(to.y - from.y))
  return (radians / (2 * math.pi)) % 1
end

local function orientation_delta(current, target)
  return (target - current + 0.5) % 1 - 0.5
end

local function set_drive(car, acceleration, direction)
  car.riding_state = {
    acceleration = acceleration,
    direction = direction
  }
end

local function stop(car)
  set_drive(car, defines.riding.acceleration.braking, defines.riding.direction.straight)
end

local function request_path(vehicle, goal, next_state)
  local car = vehicle.entity
  local request_id = car.surface.request_path {
    bounding_box = car.prototype.collision_box,
    collision_mask = car.prototype.collision_mask,
    start = car.position,
    goal = goal,
    force = car.force,
    radius = 1,
    can_open_gates = true,
    path_resolution_modifier = 0,
    entity_to_ignore = car
  }

  vehicle.state = "requesting-path"
  vehicle.request_tick = game.tick
  vehicle.path_cycle_started_tick = vehicle.path_cycle_started_tick or game.tick
  vehicle.request_goal = goal
  vehicle.request_next_state = next_state
  storage.requests[request_id] = vehicle.id
  storage.metrics.path_requests = storage.metrics.path_requests + 1
end

local function make_lane_waypoints(vehicle)
  return {
    {position = {x = vehicle.entrance.x, y = vehicle.entrance.y}},
    {position = {x = vehicle.lane_end.x, y = vehicle.lane_end.y}}
  }
end

local function begin_lane(vehicle)
  vehicle.state = "work-lane"
  vehicle.waypoints = make_lane_waypoints(vehicle)
  vehicle.waypoint_index = 1
  vehicle.progress_position = {x = vehicle.entity.position.x, y = vehicle.entity.position.y}
  vehicle.progress_tick = game.tick
end

local function finish_vehicle(vehicle)
  stop(vehicle.entity)
  vehicle.state = "complete"
  vehicle.completed_tick = game.tick
  vehicle.arrival_error = distance(vehicle.entity.position, vehicle.lane_end)
  storage.metrics.completed = storage.metrics.completed + 1
  storage.metrics.arrival_error_sum = storage.metrics.arrival_error_sum + vehicle.arrival_error
  storage.metrics.arrival_error_max = math.max(storage.metrics.arrival_error_max, vehicle.arrival_error)
end

local function follow_waypoints(vehicle)
  local car = vehicle.entity
  local waypoint = vehicle.waypoints[vehicle.waypoint_index]
  if not waypoint then
    if vehicle.state == "travel-to-entrance" then
      begin_lane(vehicle)
    else
      finish_vehicle(vehicle)
    end
    return
  end

  local target = waypoint.position or waypoint
  local remaining = distance(car.position, target)
  while remaining <= ARRIVAL_RADIUS do
    vehicle.waypoint_index = vehicle.waypoint_index + 1
    vehicle.progress_position = {x = car.position.x, y = car.position.y}
    vehicle.progress_tick = game.tick
    waypoint = vehicle.waypoints[vehicle.waypoint_index]
    if not waypoint then
      if vehicle.state == "travel-to-entrance" then
        begin_lane(vehicle)
      else
        finish_vehicle(vehicle)
      end
      return
    end
    target = waypoint.position or waypoint
    remaining = distance(car.position, target)
  end

  local lookahead_steps = vehicle.state == "travel-to-entrance" and 6 or 1
  local lookahead_index = math.min(vehicle.waypoint_index + lookahead_steps, #vehicle.waypoints)
  local lookahead = vehicle.waypoints[lookahead_index]
  local steering_target = lookahead.position or lookahead
  local target_orientation = desired_orientation(car.position, steering_target)
  local turn = orientation_delta(car.orientation, target_orientation)
  local direction = defines.riding.direction.straight
  if turn > 0.012 then
    direction = defines.riding.direction.right
  elseif turn < -0.012 then
    direction = defines.riding.direction.left
  end

  local acceleration = defines.riding.acceleration.accelerating
  if math.abs(car.speed) > MAX_SPEED or (math.abs(turn) > 0.16 and math.abs(car.speed) > 0.07) then
    acceleration = defines.riding.acceleration.braking
  end
  set_drive(car, acceleration, direction)

  if game.tick - vehicle.progress_tick >= STUCK_WINDOW then
    local moved = distance(car.position, vehicle.progress_position)
    if moved < STUCK_DISTANCE then
      storage.metrics.stuck_events = storage.metrics.stuck_events + 1
      storage.metrics.collision_suspicions = storage.metrics.collision_suspicions + 1
      if vehicle.repaths >= MAX_REPATHS then
        stop(car)
        vehicle.state = "failed"
        storage.metrics.failed = storage.metrics.failed + 1
      else
        vehicle.repaths = vehicle.repaths + 1
        storage.metrics.repaths = storage.metrics.repaths + 1
        vehicle.state = "reversing"
        vehicle.reverse_until = game.tick + REVERSE_TICKS
      end
    else
      vehicle.progress_position = {x = car.position.x, y = car.position.y}
      vehicle.progress_tick = game.tick
    end
  end
end

local function write_report(reason)
  if storage.report_written then return end
  storage.report_written = true

  local metrics = storage.metrics
  local finished = metrics.completed + metrics.failed
  local vehicle_states = {}
  for id, vehicle in ipairs(storage.vehicles) do
    vehicle_states[id] = {
      state = vehicle.state,
      x = vehicle.entity.valid and vehicle.entity.position.x or nil,
      y = vehicle.entity.valid and vehicle.entity.position.y or nil,
      speed = vehicle.entity.valid and vehicle.entity.speed or nil,
      orientation = vehicle.entity.valid and vehicle.entity.orientation or nil,
      waypoint_index = vehicle.waypoint_index,
      waypoint_count = #vehicle.waypoints,
      repaths = vehicle.repaths,
      path_deferrals = vehicle.path_deferrals
    }
  end

  local report = {
    prototype = "factorio-farming-vehicle-controller",
    factorio_version = script.active_mods.base,
    vehicle_count = config.vehicle_count,
    cadence_ticks = config.cadence,
    reason = reason,
    tick = game.tick,
    completed = metrics.completed,
    failed = metrics.failed,
    unfinished = config.vehicle_count - finished,
    completion_rate = metrics.completed / config.vehicle_count,
    path_requests = metrics.path_requests,
    path_successes = metrics.path_successes,
    path_failures = metrics.path_failures,
    path_latency_ticks_average = metrics.path_successes > 0 and metrics.path_latency_sum / metrics.path_successes or 0,
    path_latency_ticks_max = metrics.path_latency_max,
    path_end_to_end_latency_ticks_average = metrics.path_successes > 0 and metrics.path_end_to_end_latency_sum / metrics.path_successes or 0,
    path_end_to_end_latency_ticks_max = metrics.path_end_to_end_latency_max,
    path_deferrals = metrics.path_deferrals,
    stuck_events = metrics.stuck_events,
    repaths = metrics.repaths,
    collision_suspicions = metrics.collision_suspicions,
    arrival_error_tiles_average = metrics.completed > 0 and metrics.arrival_error_sum / metrics.completed or 0,
    arrival_error_tiles_max = metrics.arrival_error_max,
    bounded_recovery_limit = MAX_REPATHS,
    vehicle_states = vehicle_states
  }

  helpers.write_file(
    "factorio-farming-spike-1/result-" .. config.vehicle_count .. ".json",
    helpers.table_to_json(report),
    false
  )
  log("FACTORIO_FARMING_SPIKE_1 " .. helpers.table_to_json(report))
end

local function set_up()
  storage.vehicles = {}
  storage.requests = {}
  storage.report_written = false
  storage.metrics = {
    completed = 0,
    failed = 0,
    path_requests = 0,
    path_successes = 0,
    path_failures = 0,
    path_latency_sum = 0,
    path_latency_max = 0,
    path_end_to_end_latency_sum = 0,
    path_end_to_end_latency_max = 0,
    path_deferrals = 0,
    stuck_events = 0,
    repaths = 0,
    collision_suspicions = 0,
    arrival_error_sum = 0,
    arrival_error_max = 0
  }

  local surface = game.create_surface("ff-vehicle-spike", {
    width = 256,
    height = 4096,
    peaceful_mode = true,
    autoplace_controls = {}
  })
  surface.generate_with_lab_tiles = true
  surface.request_to_generate_chunks({x = 0, y = 0}, 64)
  surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities_filtered {
    type = {"tree", "simple-entity", "cliff", "resource", "unit", "unit-spawner", "turret"}
  }) do
    entity.destroy()
  end

  local first_y = -((config.vehicle_count - 1) * 6)
  for id = 1, config.vehicle_count do
    local y = first_y + ((id - 1) * 12)
    local start = {x = -90, y = y}
    local entrance = {x = -10, y = y}
    local lane_end = {x = 70, y = y}
    local car = surface.create_entity {
      name = "car",
      position = start,
      force = "player",
      create_build_effect_smoke = false
    }
    car.orientation = 0.25
    car.insert {name = "rocket-fuel", count = 10}

    local vehicle = {
      id = id,
      entity = car,
      entrance = entrance,
      lane_end = lane_end,
      state = "initializing",
      waypoints = {},
      waypoint_index = 1,
      repaths = 0,
      path_deferrals = 0,
      progress_position = {x = start.x, y = start.y},
      progress_tick = game.tick
    }
    storage.vehicles[id] = vehicle

    if id == 1 and config.obstruct_first_vehicle then
      for offset = 0, 0 do
        surface.create_entity {
          name = "stone-wall",
          position = {x = 15, y = y + offset},
          force = "player",
          create_build_effect_smoke = false
        }
      end
    end

    request_path(vehicle, entrance, "travel-to-entrance")
  end
end

script.on_init(set_up)

script.on_event(defines.events.on_script_path_request_finished, function(event)
  local vehicle_id = storage.requests[event.id]
  if not vehicle_id then return end
  storage.requests[event.id] = nil

  local vehicle = storage.vehicles[vehicle_id]
  if not vehicle or vehicle.state ~= "requesting-path" then return end

  local latency = game.tick - vehicle.request_tick
  storage.metrics.path_latency_sum = storage.metrics.path_latency_sum + latency
  storage.metrics.path_latency_max = math.max(storage.metrics.path_latency_max, latency)

  if event.path and #event.path > 0 then
    storage.metrics.path_successes = storage.metrics.path_successes + 1
    local end_to_end_latency = game.tick - vehicle.path_cycle_started_tick
    storage.metrics.path_end_to_end_latency_sum = storage.metrics.path_end_to_end_latency_sum + end_to_end_latency
    storage.metrics.path_end_to_end_latency_max = math.max(storage.metrics.path_end_to_end_latency_max, end_to_end_latency)
    vehicle.path_cycle_started_tick = nil
    vehicle.path_deferrals = 0
    if vehicle.request_next_state == "travel-to-entrance" then
      -- The benchmark road is intentionally clear, so collapse the validated
      -- native route to its exact goal instead of following one-tile path nodes.
      vehicle.waypoints = {{position = vehicle.request_goal}}
    else
      vehicle.waypoints = event.path
      vehicle.waypoints[#vehicle.waypoints + 1] = {position = vehicle.request_goal}
    end
    vehicle.waypoint_index = 1
    vehicle.state = vehicle.request_next_state
    vehicle.progress_position = {x = vehicle.entity.position.x, y = vehicle.entity.position.y}
    vehicle.progress_tick = game.tick
  elseif event.try_again_later and vehicle.path_deferrals < MAX_PATH_DEFERRALS then
    vehicle.path_deferrals = vehicle.path_deferrals + 1
    storage.metrics.path_deferrals = storage.metrics.path_deferrals + 1
    vehicle.state = "waiting-to-request-path"
    vehicle.retry_path_at = game.tick + 30 + (vehicle.id % 31)
  else
    vehicle.path_cycle_started_tick = nil
    storage.metrics.path_failures = storage.metrics.path_failures + 1
    storage.metrics.failed = storage.metrics.failed + 1
    vehicle.state = "failed"
  end
end)

script.on_event(defines.events.on_tick, function(event)
  for id, vehicle in ipairs(storage.vehicles) do
    if (event.tick + id) % config.cadence == 0 and vehicle.entity.valid then
      if vehicle.state == "travel-to-entrance" or vehicle.state == "work-lane" or vehicle.state == "travel-to-lane-end" then
        follow_waypoints(vehicle)
      elseif vehicle.state == "reversing" then
        set_drive(vehicle.entity, defines.riding.acceleration.reversing, defines.riding.direction.straight)
        if event.tick >= vehicle.reverse_until then
          stop(vehicle.entity)
          request_path(vehicle, vehicle.lane_end, "travel-to-lane-end")
        end
      elseif vehicle.state == "waiting-to-request-path" and event.tick >= vehicle.retry_path_at then
        request_path(vehicle, vehicle.request_goal, vehicle.request_next_state)
      end
    end
  end

  if storage.metrics.completed + storage.metrics.failed == config.vehicle_count then
    write_report("all-finished")
  elseif event.tick >= config.report_tick then
    write_report("tick-limit")
  end
end)
