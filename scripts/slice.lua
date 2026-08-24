local field_module = require("scripts.field")
local movement = require("scripts.movement")
local visuals = require("scripts.visuals")

local slice = {}
local load_recovery_needed = false
local profile = nil
local start_lane
local complete_job
local finish_lane
local commit_work
local start_next_operation

local WHEAT_ITEM = "farming-wheat"
local STORAGE_RADIUS = 32

local function operation_implement(machine, operation_name)
  local implement = machine and machine.implements and machine.implements[operation_name]
  if not implement or implement.work_width ~= field_module.constants.work_width then
    return nil, "The tractor does not have a compatible " .. tostring(operation_name) .. " implement."
  end
  return implement
end

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local transitions = {
  waiting = {reserved = true},
  reserved = {travelling = true, paused = true, failed = true},
  travelling = {working = true, paused = true, failed = true},
  working = {completed = true, paused = true, failed = true},
  paused = {travelling = true, working = true, failed = true},
  failed = {travelling = true, working = true},
  completed = {}
}

function slice.transition(job, next_state)
  if job.state == next_state then return true end
  if not transitions[job.state] or not transitions[job.state][next_state] then
    return false, "Invalid job transition from " .. tostring(job.state) .. " to " .. tostring(next_state) .. "."
  end
  job.state = next_state
  return true
end

local function ensure_root()
  storage.farming = storage.farming or {}
  local root = storage.farming
  if root.schema_version ~= 2 then field_module.migrate_storage(root) end
  root.next_field_id = root.next_field_id or 1
  root.next_machine_id = root.next_machine_id or 1
  root.next_job_id = root.next_job_id or 1
  root.surfaces = root.surfaces or {}
  root.path_queue = root.path_queue or {}
  root.pending_paths = root.pending_paths or {}
  root.visual_dirty = root.visual_dirty or {}
  root.visuals = root.visuals or {}
  root.destroy_registrations = root.destroy_registrations or {}
  return root
end

local function surface_state(surface_index)
  local root = ensure_root()
  root.surfaces[surface_index] = root.surfaces[surface_index] or {}
  return root.surfaces[surface_index]
end

local function notify(player, message)
  local formatted = {"", "[Factorio Farming] ", message}
  if player and player.valid then player.print(formatted) else game.print(formatted) end
end

local function create_machine(surface, force, position)
  local root = ensure_root()
  local state = surface_state(surface.index)
  local existing = state.machine
  if existing and movement.entity(existing) then return existing end

  local spawn = surface.find_non_colliding_position("farming-tractor", position, 16, 0.5)
  if not spawn then return nil, "No safe position was found for the farming tractor." end
  local entity = surface.create_entity({
    name = "farming-tractor",
    position = spawn,
    force = force,
    create_build_effect_smoke = false
  })
  if not entity then return nil, "The farming tractor could not be created." end
  local machine = {
    id = root.next_machine_id,
    surface_index = surface.index,
    unit_number = entity.unit_number,
    generation = 1,
    capability = {work_width = 4},
    implements = {
      cultivation = {work_width = 4},
      sowing = {work_width = 4},
      harvesting = {work_width = 4}
    },
    job_id = nil,
    last_position = {x = entity.position.x, y = entity.position.y},
    controller = {state = "idle", recoveries = 0}
  }
  root.next_machine_id = root.next_machine_id + 1
  state.machine = machine
  local registration = script.register_on_object_destroyed(entity)
  root.destroy_registrations[registration] = surface.index
  return machine
end

local function lane_target(work_field)
  if work_field.axis == "x" then
    return {
      x = work_field.direction == 1 and work_field.bounds.right or work_field.bounds.left,
      y = (work_field.lane.top + work_field.lane.bottom) / 2
    }
  end
  return {
    x = (work_field.lane.left + work_field.lane.right) / 2,
    y = work_field.direction == 1 and work_field.bounds.bottom or work_field.bounds.top
  }
end

local function fail_job(state, reason, player)
  local job = state.job
  local machine = state.machine
  if job and job.state ~= "completed" then
    if transitions[job.state] and transitions[job.state].failed then slice.transition(job, "failed") else job.state = "failed" end
    job.failure = reason
    if state.field then field_module.release_lane(state.field, job.id) end
    job.machine_id = nil
    job.lane_claim = nil
  end
  if machine then
    movement.stop(machine)
    machine.job_id = nil
    machine.generation = machine.generation + 1
    movement.invalidate(machine)
  end
  notify(player, reason)
end

local function begin_travel(state)
  local job = state.job
  local machine = state.machine
  machine.controller.recoveries = 0
  slice.transition(job, "travelling")
  movement.queue(machine, state.field.entrance, "entrance")
end

local function reserve_job(state)
  local job = state.job
  local machine = state.machine
  if not job or not machine or job.state ~= "waiting" then return false end
  if not field_module.claim_lane(state.field, job.id, machine.id) then return false end
  job.machine_id = machine.id
  job.lane_claim = state.field.lane_index
  machine.job_id = job.id
  slice.transition(job, "reserved")
  return true
end

-- `reserved` means the lane and tractor are claimed but no path request is in
-- flight. Travel starts on the following controller tick so the state is a real,
-- observable, save-able phase rather than a transient step inside setup.
local function promote_reserved(root)
  local indexes = {}
  for index in pairs(root.surfaces) do indexes[#indexes + 1] = index end
  table.sort(indexes)
  for _, index in ipairs(indexes) do
    local state = root.surfaces[index]
    local job = state.job
    local machine = state.machine
    if job and machine and job.state == "reserved" and movement.entity(machine) then
      begin_travel(state)
    end
  end
end

local function create_field_job(surface_index, bounds, player_position)
  local root = ensure_root()
  local state = surface_state(surface_index)
  if state.field then return nil, "This surface already has a live farming field." end
  if not state.machine or not movement.entity(state.machine) then
    return nil, "Run /farming-slice-setup before defining the field."
  end

  local work_field = field_module.create(root.next_field_id, surface_index, bounds, player_position)
  root.next_field_id = root.next_field_id + 1
  local job = {
    id = root.next_job_id,
    field_id = work_field.id,
    machine_id = nil,
    state = "completed",
    operation = nil,
    lane_claim = nil,
    generation = 1,
    failure = nil
  }
  root.next_job_id = root.next_job_id + 1
  state.field = work_field
  state.job = job
  visuals.mark_dirty(work_field)
  return work_field
end

function slice.on_init()
  ensure_root()
end

function slice.on_configuration_changed()
  local root = ensure_root()
  for _, state in pairs(root.surfaces) do
    if state.field and not state.field.migration_failed then visuals.mark_dirty(state.field) end
  end
end

local function distance_squared(first, second)
  local x = first.x - second.x
  local y = first.y - second.y
  return x * x + y * y
end

local function destination_inventory(state)
  local field = state.field
  local entity = field and field.storage_unit_number and game.get_entity_by_unit_number(field.storage_unit_number)
  if (not entity or not entity.valid) and field and field.storage_position then
    local surface = game.get_surface(field.surface_index)
    local nearby = surface.find_entities_filtered({type = "container", position = field.storage_position, radius = 0.1})
    entity = nearby[1]
  end
  if entity and entity.valid then
    local inventory = entity.get_inventory(defines.inventory.chest) or entity.get_inventory(1)
    if inventory then return inventory, entity end
  end
  return nil
end

local function nearest_storage_container(work_field)
  local surface = game.get_surface(work_field.surface_index)
  local candidates = surface.find_entities_filtered({type = "container", position = work_field.entrance, radius = STORAGE_RADIUS})
  table.sort(candidates, function(first, second)
    local first_distance = distance_squared(first.position, work_field.entrance)
    local second_distance = distance_squared(second.position, work_field.entrance)
    if first_distance ~= second_distance then return first_distance < second_distance end
    return first.unit_number < second.unit_number
  end)
  return candidates[1]
end

local function designate_storage(state)
  local work_field = state.field
  local container = nearest_storage_container(work_field)
  if not container then return false, "Place a storage container within 32 tiles of the field entrance before harvesting." end
  work_field.storage_unit_number = container.unit_number
  work_field.storage_position = copy_position(container.position)
  return true
end

commit_work = function(state, rectangle)
  local job = state.job
  local operation_name = job.operation
  if operation_name ~= "harvesting" then
    local delta = field_module.commit_operation(state.field, operation_name, rectangle, game.tick)
    if operation_name == "sowing" and delta > 0 then
      state.field.next_growth_visual_tick = field_module.next_growth_tick(state.field, game.tick)
    end
    return delta
  end
  local inventory = destination_inventory(state)
  if not inventory then
    job.restart_from_work = true
    fail_job(state, "The designated storage container is missing or invalid. Ready wheat has been preserved.")
    return 0
  end
  local requested = field_module.rectangle_area(state.field, rectangle)
  if requested <= 0 then return 0 end
  if not field_module.operation_rectangle_is_uncovered(state.field, operation_name, rectangle) then return 0 end
  if not inventory.can_insert({name = WHEAT_ITEM, count = requested}) then
    job.restart_from_work = true
    fail_job(state, "The designated storage container cannot accept more wheat. Ready crops have been preserved.")
    return 0
  end
  local inserted = inventory.insert({name = WHEAT_ITEM, count = requested})
  if inserted ~= requested then
    job.restart_from_work = true
    fail_job(state, "Wheat transfer was incomplete. Ready crops have been preserved.")
    return 0
  end
  return field_module.commit_operation(state.field, operation_name, rectangle, game.tick, inserted)
end

function slice.on_load()
  load_recovery_needed = true
end

-- Path requests never survive a save. Every in-flight request is dropped and the
-- job is rebuilt from authoritative storage for its own phase, so a load is
-- always a fresh, bounded attempt rather than trusted stale controller state.
local function recover_loaded_state()
  if not load_recovery_needed then return end
  load_recovery_needed = false
  local root = ensure_root()
  root.path_queue = {}
  root.pending_paths = {}
  root.outstanding_path_id = nil

  local indexes = {}
  for index in pairs(root.surfaces) do indexes[#indexes + 1] = index end
  table.sort(indexes)
  for _, index in ipairs(indexes) do
    local state = root.surfaces[index]
    local job = state.job
    local machine = state.machine
    if job and machine and job.state ~= "completed" then
      if not movement.entity(machine) then
        if job.state ~= "failed" then
          fail_job(state, "The assigned tractor was missing after loading. Progress has been preserved.")
        end
      else
        machine.generation = machine.generation + 1
        job.generation = job.generation + 1
        machine.controller = machine.controller or {state = "idle", recoveries = 0}
        machine.controller.waypoints = nil
        machine.controller.waypoint_index = nil
        movement.stop(machine)

        if job.state == "reserved" or job.state == "travelling" then
          -- Re-enter the reserved phase; promote_reserved reissues the path.
          job.state = "reserved"
          machine.controller.state = "idle"
        elseif job.state == "working" then
          -- Re-derive lane motion from stored coverage, never from the saved
          -- controller position, so no uncovered tile is skipped.
          start_lane(state, true)
        elseif job.state == "paused" or job.state == "failed" then
          -- Stay stopped. Only an explicit resume may restart work.
          machine.controller.state = "paused"
        end
      end
    end
    if state.field then visuals.mark_dirty(state.field) end
  end
end

function slice.setup(player)
  local state = surface_state(player.surface.index)
  local machine, error_message = create_machine(player.surface, player.force, player.position)
  if not machine then notify(player, error_message); return false end

  local cursor = player.cursor_stack
  if cursor and cursor.valid then
    cursor.clear()
    cursor.set_stack({name = "farming-field-planner", count = 1})
    player.cursor_stack_temporary = true
  end
  if state.job and state.job.state == "failed" then
    notify(player, "Replacement tractor registered. Run /farming-slice-resume to continue.")
  else
    notify(player, "Tractor ready. Select one 64 by 16 tile field with the planner.")
  end
  return true
end

function slice.on_selected_area(event)
  if event.item ~= "farming-field-planner" then return end
  local player = game.get_player(event.player_index)
  local bounds, error_message = field_module.normalize_selection(event.area)
  if not bounds then notify(player, error_message); return end
  local work_field, create_error = create_field_job(event.surface.index, bounds, player.position)
  if not work_field then notify(player, create_error); return end
  surface_state(event.surface.index).job.player_index = event.player_index
  notify(player, "Field accepted. Use the contextual field action to start cultivation.")
  slice.show_contextual_action(player)
end

local function pause_state(state, player)
  local job = state.job
  local machine = state.machine
  if not job or job.state == "completed" or job.state == "failed" then
    notify(player, "There is no active farming job to pause.")
    return false
  end
  if job.state == "paused" then notify(player, "The farming job is already paused."); return true end
  local controller = machine.controller or {}
  job.paused_motion = {state = controller.state, purpose = controller.purpose}
  if controller.purpose == "lane-start" then
    job.paused_motion.remaining_waypoints = {}
    for index = controller.waypoint_index or 1, #(controller.waypoints or {}) do
      local waypoint = controller.waypoints[index].position or controller.waypoints[index]
      job.paused_motion.remaining_waypoints[#job.paused_motion.remaining_waypoints + 1] = copy_position(waypoint)
    end
  end
  if job.state == "working" and controller.state == "working" and controller.work_position then
    local entity = movement.entity(machine)
    if entity then
      local delta = commit_work(state,
        field_module.work_rectangle(state.field, machine.controller.work_position, entity.position, false))
      controller.work_position = copy_position(entity.position)
      if delta > 0 then visuals.mark_dirty(state.field) end
    end
  end
  job.paused_from = job.state
  job.generation = job.generation + 1
  machine.generation = machine.generation + 1
  slice.transition(job, "paused")
  movement.invalidate(machine)
  notify(player, "Farming job paused.")
  return true
end

function slice.pause(player)
  return pause_state(surface_state(player.surface.index), player)
end

local function resume_state(state, player)
  local job = state.job
  local machine = state.machine
  if state.field and state.field.migration_failed then
    notify(player, "This field migration failed and cannot be resumed.")
    return false
  end
  if not job or (job.state ~= "paused" and job.state ~= "failed") then
    notify(player, job and "The farming job is already active." or "There is no farming job to resume.")
    return false
  end
  if not machine or not movement.entity(machine) then
    notify(player, "Create a replacement tractor with /farming-slice-setup first.")
    return false
  end

  if not field_module.claim_lane(state.field, job.id, machine.id) then
    notify(player, "The current field-operation lane is already claimed.")
    return false
  end
  job.machine_id = machine.id
  job.lane_claim = state.field.lane_index
  job.failure = nil
  job.generation = job.generation + 1
  machine.job_id = job.id
  machine.generation = machine.generation + 1
  machine.controller.recoveries = 0
  if job.paused_from == "working" or job.restart_from_work then
    slice.transition(job, "working")
    local paused_motion = job.paused_motion or {}
    if paused_motion.purpose == "lane-start" then
      local next_position = field_module.next_uncovered_for(state.field, job.operation)
      if next_position then
        local remaining = paused_motion.remaining_waypoints
        movement.begin_lane_positioning(machine, next_position, remaining and #remaining > 0 and remaining or nil)
      else
        finish_lane(state)
      end
    elseif paused_motion.state == "aligning" then
      movement.begin_alignment(machine, lane_target(state.field))
    elseif paused_motion.state == "working" then
      start_lane(state, true)
    else
      start_lane(state)
    end
  else
    begin_travel(state)
  end
  job.paused_from = nil
  job.restart_from_work = nil
  job.paused_motion = nil
  notify(player, "Farming job resumed.")
  return true
end

function slice.resume(player)
  return resume_state(surface_state(player.surface.index), player)
end

function slice.contextual_status(surface_index)
  local state = surface_state(surface_index)
  if not state.field or not state.job then return nil end

  local machine = state.machine
  local machine_entity = machine and movement.entity(machine)
  local storage_inventory, storage_entity = destination_inventory(state)
  local eligible_storage = not storage_inventory and nearest_storage_container(state.field)
  if eligible_storage then storage_entity = eligible_storage end
  local requested_operation = state.job.state == "completed" and field_module.next_operation(state.field, game.tick) or nil
  local next_field_operation = requested_operation
  local unavailable_reason = nil
  if requested_operation and not machine_entity then
    next_field_operation = nil
    unavailable_reason = "The farming tractor is missing."
  elseif requested_operation and not operation_implement(machine, requested_operation) then
    next_field_operation = nil
    unavailable_reason = "The farming tractor lacks the required implement."
  elseif requested_operation == "harvesting" and not storage_inventory and not eligible_storage then
    next_field_operation = nil
    unavailable_reason = "Place a storage container within 32 tiles of the field entrance."
  end

  return {
    lifecycle = field_module.lifecycle(state.field, game.tick),
    vehicle = {
      name = "farming-tractor",
      unit_number = machine and machine.unit_number or nil,
      state = machine_entity and (state.job.state == "completed" and "ready" or state.job.state) or "missing"
    },
    storage = {
      name = "farming-storage-container",
      unit_number = storage_entity and storage_entity.unit_number or state.field.storage_unit_number,
      state = storage_inventory and "designated" or (eligible_storage and "eligible" or
        (state.field.storage_unit_number and "missing" or "unassigned"))
    },
    next_field_operation = next_field_operation,
    unavailable_reason = unavailable_reason
  }
end

start_next_operation = function(state, player)
  local job = state.job
  local machine = state.machine
  if not job or job.state ~= "completed" then
    notify(player, "The field already has an active operation.")
    return false
  end
  if not machine or not movement.entity(machine) then
    notify(player, "Create a replacement tractor with /farming-slice-setup first.")
    return false
  end
  local operation_name = field_module.next_operation(state.field, game.tick)
  if not operation_name then
    notify(player, "Crops are still growing; no field operation is ready.")
    return false
  end
  local implement, implement_error = operation_implement(machine, operation_name)
  if not implement then notify(player, implement_error); return false, implement_error end
  if operation_name == "harvesting" then
    local designated, message = designate_storage(state)
    if not designated then notify(player, message); return false end
  end
  field_module.begin_operation(state.field)
  job.operation = operation_name
  job.implement = operation_name
  job.state = "waiting"
  job.failure = nil
  job.generation = job.generation + 1
  if not reserve_job(state) then
    fail_job(state, "The field-operation lane could not be claimed.", player)
    return false
  end
  notify(player, "Tractor starting " .. operation_name .. ".")
  return true
end

function slice.show_contextual_action(player)
  local gui = player.gui.left
  local existing = gui.farming_field_action
  if existing then existing.destroy() end
  local status = slice.contextual_status(player.surface.index)
  if not status then return end
  local frame = gui.add({type = "frame", name = "farming_field_action", direction = "vertical", caption = "Farming field"})
  frame.add({type = "label", caption = "Status: " .. status.lifecycle})
  local vehicle = status.vehicle
  local vehicle_identity = vehicle.unit_number and ("#" .. vehicle.unit_number) or "unavailable"
  frame.add({type = "label", caption = "Vehicle: farming tractor " .. vehicle_identity .. " (" .. vehicle.state .. ")"})
  local storage = status.storage
  local storage_identity = storage.unit_number and ("#" .. storage.unit_number) or "none designated"
  frame.add({type = "label", caption = "Storage container: " .. storage_identity .. " (" .. storage.state .. ")"})
  if status.next_field_operation then
    frame.add({type = "button", name = "farming_field_primary_action", caption = "Start " .. status.next_field_operation})
  elseif status.vehicle.state == "ready" then
    frame.add({type = "label", caption = status.unavailable_reason or "Crops are growing"})
  else
    frame.add({type = "label", caption = "Field operation in progress"})
  end
end

function slice.on_gui_click(event)
  if event.element and event.element.valid and event.element.name == "farming_field_primary_action" then
    local player = game.get_player(event.player_index)
    if player then
      start_next_operation(surface_state(player.surface.index), player)
      slice.show_contextual_action(player)
    end
  end
end

start_lane = function(state, resume_work)
  local next_position = field_module.next_uncovered_for(state.field, state.job.operation)
  if not next_position then
    finish_lane(state)
    return
  end
  local machine = state.machine
  local entity = movement.entity(machine)
  if resume_work or movement.distance(entity.position, next_position) <= 1 then
    movement.begin_work(machine, lane_target(state.field), next_position)
  else
    movement.begin_lane_positioning(machine, next_position)
  end
end

complete_job = function(state)
  local job = state.job
  local machine = state.machine
  movement.stop(machine)
  slice.transition(job, "completed")
  field_module.release_lane(state.field, job.id)
  job.machine_id = nil
  job.lane_claim = nil
  machine.job_id = nil
  machine.controller.state = "idle"
  game.print({"", "[Factorio Farming] ", job.operation, " complete. Select the field to start its next operation."})
  local player = job.player_index and game.get_player(job.player_index)
  if player then slice.show_contextual_action(player) end
end

finish_lane = function(state)
  local job = state.job
  local machine = state.machine
  field_module.release_lane(state.field, job.id)
  job.lane_claim = nil

  if not field_module.advance_lane(state.field) then
    if field_module.next_uncovered_for(state.field, job.operation) == nil then complete_job(state)
    else fail_job(state, "Field operation stopped before exact completion.") end
    return
  end

  if not field_module.claim_lane(state.field, job.id, machine.id) then
    fail_job(state, "The next field-operation lane could not be claimed.")
    return
  end
  job.lane_claim = state.field.lane_index
  visuals.mark_dirty(state.field)
  movement.begin_lane_positioning(machine, field_module.next_uncovered_for(state.field, job.operation),
    field_module.headland_waypoints(state.field))
end

local function handle_outcome(state, outcome)
  if not outcome then return end
  local job = state.job
  local machine = state.machine
  if not job or not machine or machine.id ~= outcome.machine_id then return end
  if outcome.type == "failed" or outcome.type == "missing" then
    fail_job(state, outcome.reason or "The assigned tractor is no longer available.")
  elseif outcome.type == "arrived" and outcome.purpose == "entrance" and job.state == "travelling" then
    slice.transition(job, "working")
    movement.begin_alignment(machine, lane_target(state.field))
  elseif outcome.type == "aligned" and job.state == "working" then
    start_lane(state)
  elseif outcome.type == "arrived" and outcome.purpose == "lane-start" and job.state == "working" then
    movement.begin_work(machine, lane_target(state.field), field_module.next_uncovered_for(state.field, job.operation))
  elseif outcome.type == "progress" and job.state == "working" then
    local rectangle = job.operation == "harvesting" and
      field_module.next_uncovered_rectangle(state.field, job.operation) or
      field_module.work_rectangle(state.field, outcome.from, outcome.to, false)
    local delta = rectangle and commit_work(state, rectangle) or 0
    if delta > 0 then visuals.mark_dirty(state.field) end
  elseif outcome.type == "arrived" and outcome.purpose == "lane" and job.state == "working" then
    local rectangle = job.operation == "harvesting" and
      field_module.next_uncovered_rectangle(state.field, job.operation) or
      field_module.work_rectangle(state.field, outcome.from, outcome.to, true)
    local delta = commit_work(state, rectangle)
    if delta > 0 then visuals.mark_dirty(state.field) end
    -- Physical arrival can leave the final sub-tile rectangle behind the
    -- arrival radius. Commit only authoritative first-uncovered rectangles
    -- until that lane is exact; never sweep over already harvested coverage.
    while job.operation == "harvesting" and job.state == "working" do
      local remaining = field_module.next_uncovered_rectangle(state.field, job.operation)
      if not remaining then break end
      local remaining_delta = commit_work(state, remaining)
      if remaining_delta <= 0 then break end
      visuals.mark_dirty(state.field)
    end
    if field_module.next_uncovered_for(state.field, job.operation) == nil then finish_lane(state)
    else start_lane(state, true) end
  end
end

local function finish_arrived_harvest_lane(state)
  local job = state.job
  if not job or job.state ~= "working" or job.operation ~= "harvesting" then return end
  local machine = state.machine
  local entity = machine and movement.entity(machine)
  if not entity or movement.distance(entity.position, lane_target(state.field)) > 1 then return end
  while job.state == "working" do
    local rectangle = field_module.next_uncovered_rectangle(state.field, job.operation)
    if not rectangle then finish_lane(state); return end
    if commit_work(state, rectangle) <= 0 then return end
    visuals.mark_dirty(state.field)
  end
end

function slice.on_path_finished(event)
  local outcome = movement.on_path_finished(event)
  if not outcome then return end
  for _, state in pairs(ensure_root().surfaces) do
    if state.machine and state.machine.id == outcome.machine_id then handle_outcome(state, outcome); return end
  end
end

local function tick_body(event)
  recover_loaded_state()
  local root = ensure_root()
  promote_reserved(root)
  movement.process_path_queue(event.tick)
  local surface_indexes = {}
  for index in pairs(root.surfaces) do surface_indexes[#surface_indexes + 1] = index end
  table.sort(surface_indexes)
  local due = {}
  local active = 0
  for _, index in ipairs(surface_indexes) do
    local state = root.surfaces[index]
    if state.field and state.field.next_growth_visual_tick and event.tick >= state.field.next_growth_visual_tick then
      visuals.mark_dirty(state.field)
      state.field.next_growth_visual_tick = field_module.next_growth_tick(state.field, event.tick)
    end
    if state.machine and state.job and state.job.state ~= "paused" and state.job.state ~= "failed" and state.job.state ~= "completed" then
      active = active + 1
      if (event.tick + state.machine.id) % movement.constants.cadence == 0 then
        due[#due + 1] = state
      end
    end
  end
  table.sort(due, function(a, b) return a.machine.id < b.machine.id end)
  if #due > 0 then
    local selected = due[1]
    for _, candidate in ipairs(due) do
      if candidate.machine.id > (root.last_controller_machine_id or 0) then
        selected = candidate
        break
      end
    end
    root.last_controller_machine_id = selected.machine.id
    handle_outcome(selected, movement.update(selected.machine, event.tick))
    finish_arrived_harvest_lane(selected)
  end
  for _, index in ipairs(surface_indexes) do
    finish_arrived_harvest_lane(root.surfaces[index])
  end
  visuals.update()
  return active
end

function slice.on_tick(event)
  if not profile then
    tick_body(event)
    return
  end
  profile.sample.reset()
  local active = tick_body(event)
  profile.sample.stop()
  profile.count = profile.count + 1
  -- The sample is measured before this line, so logging never inflates it.
  log({"", "FARMING_PROFILE ", tostring(event.tick), " ", tostring(active), " ", profile.sample})
end

-- Profiling is a debug-only facility. It is off unless a harness turns it on and
-- costs one branch per tick otherwise.
function slice.debug_profile_start()
  profile = {sample = helpers.create_profiler(true), count = 0}
  return true
end

function slice.debug_profile_stop()
  local count = profile and profile.count or 0
  profile = nil
  return count
end

function slice.on_object_destroyed(event)
  local root = ensure_root()
  local surface_index = root.destroy_registrations[event.registration_number]
  if not surface_index then return end
  root.destroy_registrations[event.registration_number] = nil
  local state = root.surfaces[surface_index]
  if state and state.machine and state.machine.unit_number == event.useful_id then
    fail_job(state, "The assigned tractor was destroyed. Progress has been preserved.")
  end
end

function slice.debug_setup(surface_index, bounds, tractor_position, start_operation)
  local surface = game.get_surface(surface_index)
  local machine, error_message = create_machine(surface, game.forces.player, tractor_position)
  if not machine then return false, error_message end
  local normalized, normalize_error = field_module.normalize_selection({
    left_top = {x = bounds.left, y = bounds.top},
    right_bottom = {x = bounds.right, y = bounds.bottom}
  })
  if not normalized then return false, normalize_error end
  local work_field, field_error = create_field_job(surface_index, normalized, tractor_position)
  if not work_field then return false, field_error end
  if start_operation == false then return true end
  return start_next_operation(surface_state(surface_index))
end

function slice.debug_start_next_operation(surface_index)
  return start_next_operation(surface_state(surface_index))
end

function slice.debug_pause(surface_index)
  return pause_state(surface_state(surface_index))
end

function slice.debug_resume(surface_index)
  return resume_state(surface_state(surface_index))
end

function slice.debug_destroy_tractor(surface_index)
  local state = surface_state(surface_index)
  local entity = state.machine and movement.entity(state.machine)
  if not entity then return false end
  entity.destroy({raise_destroy = true})
  return true
end

function slice.debug_replace_tractor(surface_index, position)
  local surface = game.get_surface(surface_index)
  local machine, error_message = create_machine(surface, game.forces.player, position)
  return machine ~= nil, error_message
end

function slice.snapshot(surface_index)
  local state = ensure_root().surfaces[surface_index]
  if not state then return nil end
  local work_field = state.field
  local job = state.job
  local machine = state.machine
  local storage_inventory = work_field and destination_inventory(state)
  return {
    field = work_field and {
      id = work_field.id,
      completed_area = work_field.completed_area,
      total_area = work_field.area,
      lane_area = work_field.lane_area,
      lane_index = work_field.lane_index,
      lane_count = #work_field.lanes,
      entrance = work_field.entrance,
      axis = work_field.axis,
      representation = work_field.representation,
      cultivated_area = field_module.operation_area(work_field, "cultivation"),
      sown_area = field_module.operation_area(work_field, "sowing"),
      harvested_area = field_module.operation_area(work_field, "harvesting"),
      lifecycle = field_module.lifecycle(work_field, game.tick),
      crop_count = #work_field.crops,
      direction = work_field.direction,
      storage_unit_number = work_field.storage_unit_number,
      stored_wheat = storage_inventory and storage_inventory.get_item_count("farming-wheat") or 0
    } or nil,
    job = job and {
      id = job.id,
      state = job.state,
      operation = job.operation,
      implement = job.implement,
      machine_id = job.machine_id,
      has_claim = job.lane_claim ~= nil,
      generation = job.generation,
      failure = job.failure
    } or nil,
    machine = machine and {
      id = machine.id,
      unit_number = machine.unit_number,
      valid = movement.entity(machine) ~= nil,
      job_id = machine.job_id,
      generation = machine.generation,
      controller_state = machine.controller.state,
      controller_goal = machine.controller.goal,
      recoveries = machine.controller.recoveries,
      position = movement.entity(machine) and {
        x = movement.entity(machine).position.x,
        y = movement.entity(machine).position.y
      } or nil,
      speed = movement.entity(machine) and movement.entity(machine).speed or nil,
      orientation = movement.entity(machine) and movement.entity(machine).orientation or nil
    } or nil,
    pending_path_count = ensure_root().outstanding_path_id and 1 or 0,
    visual_count = work_field and visuals.object_count(work_field.id) or 0
  }
end

function slice.clear_visuals(surface_index)
  local state = ensure_root().surfaces[surface_index]
  if state and state.field then visuals.clear(state.field.id) end
end

function slice.rebuild_visuals(surface_index)
  local state = ensure_root().surfaces[surface_index]
  if state and state.field then visuals.rebuild(state.field) end
end

return slice
