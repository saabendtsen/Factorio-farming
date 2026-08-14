local movement = {}

local CADENCE = 3
local ARRIVAL_RADIUS = 0.9
local STUCK_WINDOW = 120
local STUCK_DISTANCE = 0.4
local REVERSE_TICKS = 75
local MAX_RECOVERIES = 2
local MAX_SPEED = 0.11
local MAX_PATH_DEFERRALS = 20

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function distance(a, b)
  local dx = b.x - a.x
  local dy = b.y - a.y
  return math.sqrt(dx * dx + dy * dy)
end

local function entity_for(machine)
  if not machine or not machine.unit_number then return nil end
  local entity = game.get_entity_by_unit_number(machine.unit_number)
  if entity and entity.valid and entity.name == "farming-tractor" then return entity end
  return nil
end

local function set_drive(entity, acceleration, direction)
  entity.riding_state = {acceleration = acceleration, direction = direction}
end

function movement.stop(machine)
  local entity = entity_for(machine)
  if entity then
    set_drive(entity, defines.riding.acceleration.braking, defines.riding.direction.straight)
  end
end

local function desired_orientation(from, to)
  local radians = math.atan2(to.x - from.x, -(to.y - from.y))
  return (radians / (2 * math.pi)) % 1
end

local function orientation_delta(current, target)
  return (target - current + 0.5) % 1 - 0.5
end

local function queue_store()
  local root = storage.farming
  root.path_queue = root.path_queue or {}
  root.pending_paths = root.pending_paths or {}
  return root
end

function movement.queue(machine, goal, purpose, preserve_deferrals)
  local root = queue_store()
  machine.controller = machine.controller or {}
  machine.controller.state = "queued"
  machine.controller.goal = copy_position(goal)
  machine.controller.purpose = purpose
  if not preserve_deferrals then machine.controller.path_deferrals = 0 end
  machine.controller.progress_position = copy_position(machine.last_position)
  machine.controller.progress_tick = game.tick
  root.path_queue[#root.path_queue + 1] = {
    machine_id = machine.id,
    surface_index = machine.surface_index,
    generation = machine.generation,
    goal = copy_position(goal),
    purpose = purpose
  }
end

function movement.invalidate(machine)
  movement.stop(machine)
  if machine.controller then machine.controller.state = "paused" end
  local root = queue_store()
  local kept = {}
  for _, request in ipairs(root.path_queue) do
    if request.machine_id ~= machine.id or request.generation == machine.generation then
      kept[#kept + 1] = request
    end
  end
  root.path_queue = kept
end

local function find_machine(machine_id, surface_index)
  local surface_state = storage.farming.surfaces[surface_index]
  local machine = surface_state and surface_state.machine
  if machine and machine.id == machine_id then return machine end
  return nil
end

function movement.process_path_queue(tick)
  local root = queue_store()
  if root.outstanding_path_id or #root.path_queue == 0 then return end

  local request = table.remove(root.path_queue, 1)
  local machine = find_machine(request.machine_id, request.surface_index)
  local entity = entity_for(machine)
  if not entity or machine.generation ~= request.generation then return end

  local request_id = entity.surface.request_path({
    bounding_box = entity.prototype.collision_box,
    collision_mask = entity.prototype.collision_mask,
    start = entity.position,
    goal = request.goal,
    force = entity.force,
    radius = ARRIVAL_RADIUS,
    can_open_gates = true,
    path_resolution_modifier = 0,
    entity_to_ignore = entity
  })
  root.pending_paths[request_id] = request
  root.outstanding_path_id = request_id
  machine.controller.state = "requesting"
  machine.controller.request_tick = tick
end

function movement.on_path_finished(event)
  local root = queue_store()
  local request = root.pending_paths[event.id]
  if not request then return nil end
  root.pending_paths[event.id] = nil
  if root.outstanding_path_id == event.id then root.outstanding_path_id = nil end

  local machine = find_machine(request.machine_id, request.surface_index)
  local entity = entity_for(machine)
  if not entity or machine.generation ~= request.generation or machine.controller.state ~= "requesting" then
    return nil
  end

  if event.path and #event.path > 0 then
    machine.controller.state = "following"
    machine.controller.purpose = request.purpose
    machine.controller.goal = request.goal
    machine.controller.waypoints = event.path
    machine.controller.waypoints[#machine.controller.waypoints + 1] = {position = request.goal}
    machine.controller.waypoint_index = 1
    machine.controller.progress_position = copy_position(entity.position)
    machine.controller.progress_tick = event.tick
    return {type = "path-ready", machine_id = machine.id}
  end

  if event.try_again_later and machine.controller.path_deferrals < MAX_PATH_DEFERRALS then
    machine.controller.path_deferrals = machine.controller.path_deferrals + 1
    machine.controller.state = "deferred"
    machine.controller.retry_tick = event.tick + 30
    return nil
  end

  movement.stop(machine)
  machine.controller.state = "failed"
  return {type = "failed", machine_id = machine.id, reason = "No path to the field entrance."}
end

function movement.begin_work(machine, target)
  local entity = entity_for(machine)
  if not entity then return false end
  machine.controller = machine.controller or {}
  machine.controller.state = "working"
  machine.controller.purpose = "lane"
  machine.controller.goal = copy_position(target)
  machine.controller.waypoints = {{position = copy_position(target)}}
  machine.controller.waypoint_index = 1
  machine.controller.work_position = copy_position(entity.position)
  machine.controller.progress_position = copy_position(entity.position)
  machine.controller.progress_tick = game.tick
  return true
end

function movement.begin_lane_positioning(machine, target)
  local entity = entity_for(machine)
  if not entity then return false end
  machine.controller = machine.controller or {}
  machine.controller.state = "positioning"
  machine.controller.purpose = "lane-start"
  machine.controller.goal = copy_position(target)
  machine.controller.waypoints = {{position = copy_position(target)}}
  machine.controller.waypoint_index = 1
  machine.controller.progress_position = copy_position(entity.position)
  machine.controller.progress_tick = game.tick
  return true
end

function movement.begin_alignment(machine, target)
  local entity = entity_for(machine)
  if not entity then return false end
  machine.controller = machine.controller or {}
  machine.controller.state = "aligning"
  machine.controller.purpose = "lane-align"
  machine.controller.goal = copy_position(target)
  machine.controller.progress_position = copy_position(entity.position)
  machine.controller.progress_tick = game.tick
  return true
end

local function start_recovery(machine, tick)
  local controller = machine.controller
  if controller.recoveries >= MAX_RECOVERIES then
    movement.stop(machine)
    controller.state = "failed"
    return {type = "failed", machine_id = machine.id, reason = "Tractor recovery limit reached."}
  end
  controller.recoveries = controller.recoveries + 1
  controller.state = "reversing"
  controller.reverse_until = tick + REVERSE_TICKS
  return nil
end

local function follow(machine, entity, tick)
  local controller = machine.controller
  local waypoint = controller.waypoints[controller.waypoint_index]
  if not waypoint then
    movement.stop(machine)
    controller.state = "arrived"
    return {type = "arrived", machine_id = machine.id, purpose = controller.purpose}
  end

  local target = waypoint.position or waypoint
  while waypoint do
    local remaining = distance(entity.position, target)
    local next_waypoint = controller.waypoints[controller.waypoint_index + 1]
    local passed = next_waypoint and distance(entity.position, next_waypoint.position or next_waypoint) + 0.1 < remaining
    if remaining > ARRIVAL_RADIUS and not passed then break end
    controller.waypoint_index = controller.waypoint_index + 1
    waypoint = controller.waypoints[controller.waypoint_index]
    if not waypoint then
      movement.stop(machine)
      controller.state = "arrived"
      local outcome = {type = "arrived", machine_id = machine.id, purpose = controller.purpose}
      if controller.purpose == "lane" then
        outcome.from = controller.work_position
        outcome.to = copy_position(controller.goal)
      end
      return outcome
    end
    target = waypoint.position or waypoint
  end

  local turn = orientation_delta(entity.orientation, desired_orientation(entity.position, target))
  local direction = defines.riding.direction.straight
  if turn > 0.012 then direction = defines.riding.direction.right
  elseif turn < -0.012 then direction = defines.riding.direction.left end

  local acceleration = defines.riding.acceleration.accelerating
  if math.abs(entity.speed) > MAX_SPEED or (math.abs(turn) > 0.16 and math.abs(entity.speed) > 0.07) then
    acceleration = defines.riding.acceleration.braking
  end
  set_drive(entity, acceleration, direction)

  if tick - controller.progress_tick >= STUCK_WINDOW then
    if distance(entity.position, controller.progress_position) < STUCK_DISTANCE then
      return start_recovery(machine, tick)
    end
    controller.progress_position = copy_position(entity.position)
    controller.progress_tick = tick
  end

  if controller.purpose == "lane" then
    local previous = controller.work_position
    controller.work_position = copy_position(entity.position)
    return {type = "progress", machine_id = machine.id, from = previous, to = copy_position(entity.position)}
  end
  return nil
end

local function align(machine, entity)
  local controller = machine.controller
  local turn = orientation_delta(entity.orientation, desired_orientation(entity.position, controller.goal))
  if math.abs(turn) <= 0.025 then
    movement.stop(machine)
    controller.state = "aligned"
    return {type = "aligned", machine_id = machine.id}
  end
  local direction = turn > 0 and defines.riding.direction.right or defines.riding.direction.left
  local acceleration = math.abs(entity.speed) > 0.055 and
    defines.riding.acceleration.braking or defines.riding.acceleration.accelerating
  set_drive(entity, acceleration, direction)
  if game.tick - controller.progress_tick >= STUCK_WINDOW then
    if distance(entity.position, controller.progress_position) < STUCK_DISTANCE then
      return start_recovery(machine, game.tick)
    end
    controller.progress_position = copy_position(entity.position)
    controller.progress_tick = game.tick
  end
  return nil
end

function movement.update(machine, tick)
  if (tick + machine.id) % CADENCE ~= 0 then return nil end
  local entity = entity_for(machine)
  if not entity then return {type = "missing", machine_id = machine.id} end
  machine.last_position = copy_position(entity.position)
  local controller = machine.controller or {}

  if controller.state == "following" or controller.state == "working" or controller.state == "positioning" then
    return follow(machine, entity, tick)
  elseif controller.state == "aligning" then
    return align(machine, entity)
  elseif controller.state == "reversing" then
    set_drive(entity, defines.riding.acceleration.reversing, defines.riding.direction.straight)
    if tick >= controller.reverse_until then
      movement.stop(machine)
      if controller.purpose == "entrance" then
        movement.queue(machine, controller.goal, "entrance")
      elseif controller.purpose == "lane-start" then
        movement.begin_lane_positioning(machine, controller.goal)
      elseif controller.purpose == "lane-align" then
        movement.begin_alignment(machine, controller.goal)
      else
        movement.begin_work(machine, controller.goal)
      end
    end
  elseif controller.state == "deferred" and tick >= controller.retry_tick then
    movement.queue(machine, controller.goal, controller.purpose, true)
  end
  return nil
end

function movement.entity(machine)
  return entity_for(machine)
end

function movement.distance(a, b)
  return distance(a, b)
end

movement.constants = {
  cadence = CADENCE,
  max_recoveries = MAX_RECOVERIES,
  max_path_requests_per_tick = 1,
  max_outstanding_paths = 1
}

return movement
