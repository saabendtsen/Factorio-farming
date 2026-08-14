local field_module = require("scripts.field")
local movement = require("scripts.movement")
local visuals = require("scripts.visuals")

local slice = {}
local load_recovery_needed = false

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
  root.schema_version = root.schema_version or 1
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
  if player and player.valid then player.print({"", "[Factorio Farming] ", message}) end
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
  entity.insert({name = "rocket-fuel", count = 10})

  local machine = {
    id = root.next_machine_id,
    surface_index = surface.index,
    unit_number = entity.unit_number,
    generation = 1,
    capability = {work_width = 4},
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
    return {x = work_field.direction == 1 and work_field.bounds.right or work_field.bounds.left, y = work_field.entrance.y}
  end
  return {x = work_field.entrance.x, y = work_field.direction == 1 and work_field.bounds.bottom or work_field.bounds.top}
end

local function fail_job(state, reason, player)
  local job = state.job
  local machine = state.machine
  if job and job.state ~= "completed" then
    if transitions[job.state] and transitions[job.state].failed then slice.transition(job, "failed") else job.state = "failed" end
    job.failure = reason
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
  job.machine_id = machine.id
  job.lane_claim = {field_id = state.field.id, lane = 1}
  machine.job_id = job.id
  slice.transition(job, "reserved")
  begin_travel(state)
  return true
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
    state = "waiting",
    lane_claim = nil,
    generation = 1,
    failure = nil
  }
  root.next_job_id = root.next_job_id + 1
  state.field = work_field
  state.job = job
  reserve_job(state)
  visuals.mark_dirty(work_field)
  return work_field
end

function slice.on_init()
  ensure_root()
end

function slice.on_configuration_changed()
  local root = ensure_root()
  for _, state in pairs(root.surfaces) do
    if state.field then visuals.mark_dirty(state.field) end
  end
end

function slice.on_load()
  load_recovery_needed = true
end

local function recover_loaded_paths()
  if not load_recovery_needed then return end
  load_recovery_needed = false
  local root = ensure_root()
  root.path_queue = {}
  root.pending_paths = {}
  root.outstanding_path_id = nil
  for _, state in pairs(root.surfaces) do
    local job = state.job
    local machine = state.machine
    if job and machine and (job.state == "reserved" or job.state == "travelling") and movement.entity(machine) then
      machine.generation = machine.generation + 1
      job.generation = job.generation + 1
      job.state = "reserved"
      begin_travel(state)
    elseif job and machine and job.state == "working" and movement.entity(machine) then
      machine.generation = machine.generation + 1
      job.generation = job.generation + 1
      movement.begin_work(machine, lane_target(state.field))
    end
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
  notify(player, "Field accepted. Tractor travelling to its entrance.")
end

local function pause_state(state, player)
  local job = state.job
  local machine = state.machine
  if not job or job.state == "completed" or job.state == "failed" then
    notify(player, "There is no active farming job to pause.")
    return false
  end
  if job.state == "paused" then notify(player, "The farming job is already paused."); return true end
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
  if not job or (job.state ~= "paused" and job.state ~= "failed") then
    notify(player, job and "The farming job is already active." or "There is no farming job to resume.")
    return false
  end
  if not machine or not movement.entity(machine) then
    notify(player, "Create a replacement tractor with /farming-slice-setup first.")
    return false
  end

  job.machine_id = machine.id
  job.lane_claim = {field_id = state.field.id, lane = 1}
  job.failure = nil
  job.generation = job.generation + 1
  machine.job_id = job.id
  machine.generation = machine.generation + 1
  machine.controller.recoveries = 0
  local entity = movement.entity(machine)
  if movement.distance(entity.position, state.field.entrance) <= 1 then
    slice.transition(job, "working")
    movement.begin_work(machine, lane_target(state.field))
  else
    begin_travel(state)
  end
  notify(player, "Farming job resumed.")
  return true
end

function slice.resume(player)
  return resume_state(surface_state(player.surface.index), player)
end

local function complete_job(state)
  local job = state.job
  local machine = state.machine
  movement.stop(machine)
  slice.transition(job, "completed")
  job.machine_id = nil
  job.lane_claim = nil
  machine.job_id = nil
  machine.controller.state = "idle"
  game.print("[Factorio Farming] Lane complete: 256/1,024 tiles (25%).")
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
    movement.begin_work(machine, lane_target(state.field))
  elseif outcome.type == "progress" and job.state == "working" then
    local delta = field_module.commit(state.field, field_module.work_rectangle(state.field, outcome.from, outcome.to, false))
    if delta > 0 then visuals.mark_dirty(state.field) end
  elseif outcome.type == "arrived" and outcome.purpose == "lane" and job.state == "working" then
    local delta = field_module.commit(state.field, field_module.work_rectangle(state.field, outcome.from, outcome.to, true))
    if delta > 0 then visuals.mark_dirty(state.field) end
    if state.field.completed_area == state.field.lane_area then complete_job(state)
    else fail_job(state, "Lane stopped before exact completion.") end
  end
end

function slice.on_path_finished(event)
  local outcome = movement.on_path_finished(event)
  if not outcome then return end
  for _, state in pairs(ensure_root().surfaces) do
    if state.machine and state.machine.id == outcome.machine_id then handle_outcome(state, outcome); return end
  end
end

function slice.on_tick(event)
  recover_loaded_paths()
  movement.process_path_queue(event.tick)
  local root = ensure_root()
  local surface_indexes = {}
  for index in pairs(root.surfaces) do surface_indexes[#surface_indexes + 1] = index end
  table.sort(surface_indexes)
  local due = {}
  for _, index in ipairs(surface_indexes) do
    local state = root.surfaces[index]
    if state.machine and state.job and state.job.state ~= "paused" and state.job.state ~= "failed" and state.job.state ~= "completed" then
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
  end
  visuals.update()
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

function slice.debug_setup(surface_index, bounds, tractor_position)
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
  return true
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
  return {
    field = work_field and {
      id = work_field.id,
      completed_area = work_field.completed_area,
      total_area = work_field.area,
      lane_area = work_field.lane_area,
      entrance = work_field.entrance,
      axis = work_field.axis,
      representation = work_field.representation
    } or nil,
    job = job and {
      id = job.id,
      state = job.state,
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
