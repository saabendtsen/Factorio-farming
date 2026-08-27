local field_module = require("scripts.field")

local visuals = {}
-- Both scheduler visits and rectangle draws are bounded per tick across every
-- dirty field. Dirty identities live in a persistent FIFO, so tick cost never
-- depends on the total number of fields waiting behind the current work.
local MAX_PROJECTIONS_PER_TICK = 8
local MAX_FIELDS_PER_TICK = 8
local IMPLEMENT_OVERLAY_SPECS = {
  cultivation = {badge_sprite = "item/iron-gear-wheel", tint = {0.55, 0.24, 0.08, 0.92}},
  sowing = {badge_sprite = "item/wood", tint = {0.20, 0.75, 0.25, 0.92}},
  harvesting = {badge_sprite = "item/steel-chest", tint = {0.95, 0.65, 0.08, 0.92}}
}
local PIXELS_PER_TILE = 32
local WIDTH_BAR_SPRITE_PIXELS = 10

local function enqueue(state, field_id)
  if state.visual_queued[field_id] then return end
  state.visual_queued[field_id] = true
  state.visual_queue_next[field_id] = nil
  if state.visual_queue_tail then
    state.visual_queue_next[state.visual_queue_tail] = field_id
  else
    state.visual_queue_head = field_id
  end
  state.visual_queue_tail = field_id
end

local function dequeue(state)
  local field_id = state.visual_queue_head
  if not field_id then return nil end
  state.visual_queue_head = state.visual_queue_next[field_id]
  if not state.visual_queue_head then state.visual_queue_tail = nil end
  state.visual_queue_next[field_id] = nil
  state.visual_queued[field_id] = nil
  return field_id
end

local function root()
  local state = storage.farming
  state.visuals = state.visuals or {}
  state.visual_summaries = state.visual_summaries or {}
  state.visual_dirty = state.visual_dirty or {}
  state.visual_builds = state.visual_builds or {}
  state.machine_overlays = state.machine_overlays or {}
  state.visual_queued = state.visual_queued or {}
  state.visual_queue_next = state.visual_queue_next or {}
  if not state.visual_queue_initialized then
    -- Older saves only have the membership table. Reconstruct the disposable
    -- scheduler once, in durable field-id order; ordinary ticks stay O(1).
    state.visual_queued = {}
    state.visual_queue_next = {}
    state.visual_queue_head = nil
    state.visual_queue_tail = nil
    local ids = {}
    for field_id in pairs(state.visual_dirty) do ids[#ids + 1] = field_id end
    table.sort(ids)
    for _, field_id in ipairs(ids) do enqueue(state, field_id) end
    state.visual_queue_initialized = true
  end
  return state
end

-- Durable field identity is the only authority for a projection. The surface's
-- `state.field` alias merely names the field currently presented to the player.
local function live_field(field_id)
  local fields = storage.farming.fields
  local work_field = fields and fields[field_id]
  if not work_field or work_field.id ~= field_id or work_field.migration_failed then return nil end
  return work_field
end

local function destroy_objects(objects)
  for _, object in ipairs(objects or {}) do
    if object.valid then object.destroy() end
  end
end

local function destroy_machine_overlay(state, machine_id)
  local overlay = state.machine_overlays[machine_id]
  if overlay then destroy_objects(overlay.objects) end
  state.machine_overlays[machine_id] = nil
end

local function valid_object_count(objects)
  local count = 0
  for _, object in ipairs(objects or {}) do
    if object.valid then count = count + 1 end
  end
  return count
end

-- Machine overlays are attached rendering projections. Assignment and logical
-- implement profiles remain authoritative; these objects can always be thrown
-- away and reconstructed from machine.job_id -> job.operation.
function visuals.sync_machine(machine, job, entity)
  local state = root()
  local operation = machine and machine.job_id and job and job.machine_id == machine.id and
    job.state ~= "failed" and job.state ~= "completed" and job.operation or nil
  local spec = operation and IMPLEMENT_OVERLAY_SPECS[operation]
  local implement = spec and machine.implements and machine.implements[operation]
  local work_width = implement and implement.work_width
  local existing = machine and state.machine_overlays[machine.id]
  if existing and existing.operation == operation and existing.work_width == work_width and
     valid_object_count(existing.objects) == 2 and
     entity and entity.valid and existing.target_unit_number == entity.unit_number then
    return true
  end
  if machine then destroy_machine_overlay(state, machine.id) end
  if not machine or not spec or not work_width or not entity or not entity.valid then return false end

  local width_bar = rendering.draw_sprite({sprite = "utility/white_square", target = entity,
    orientation_target = entity, use_target_orientation = true, oriented_offset = {0, 1.8},
    surface = entity.surface, render_layer = "entity-info-icon",
    x_scale = work_width * PIXELS_PER_TILE / WIDTH_BAR_SPRITE_PIXELS, y_scale = 1.6, tint = spec.tint})
  local badge = rendering.draw_sprite({sprite = spec.badge_sprite, target = entity,
    orientation_target = entity, use_target_orientation = true, oriented_offset = {0, 0},
    surface = entity.surface, render_layer = "entity-info-icon", x_scale = 0.55, y_scale = 0.55})
  state.machine_overlays[machine.id] = {operation = operation, objects = {width_bar, badge},
    target_unit_number = entity.unit_number, badge_sprite = spec.badge_sprite, work_width = work_width}
  return true
end

function visuals.machine_overlay(machine_id)
  local overlay = root().machine_overlays[machine_id]
  if not overlay or valid_object_count(overlay.objects) ~= 2 then return nil end
  return {operation = overlay.operation, object_count = 2, work_width = overlay.work_width,
    target_unit_number = overlay.target_unit_number, badge_sprite = overlay.badge_sprite,
    object_ids = {overlay.objects[1].id, overlay.objects[2].id}}
end

function visuals.reset_machine_overlays(machines, jobs, surface_index)
  local state = root()
  local ids = {}
  for machine_id, machine in pairs(machines or {}) do
    if not surface_index or machine.surface_index == surface_index then ids[#ids + 1] = machine_id end
  end
  table.sort(ids)
  for _, machine_id in ipairs(ids) do destroy_machine_overlay(state, machine_id) end
  for _, machine_id in ipairs(ids) do
    local machine = machines[machine_id]
    local entity = machine.unit_number and game.get_entity_by_unit_number(machine.unit_number) or nil
    local job = machine.job_id and jobs and jobs[machine.job_id] or nil
    visuals.sync_machine(machine, job, entity)
  end
end

local function drop_dirty(state, field_id)
  destroy_objects(state.visuals[field_id])
  local build = state.visual_builds[field_id]
  if build then destroy_objects(build.objects) end
  state.visuals[field_id] = nil
  state.visual_summaries[field_id] = nil
  state.visual_builds[field_id] = nil
  state.visual_dirty[field_id] = nil
end

function visuals.mark_dirty(work_field)
  local state = root()
  state.visual_dirty[work_field.id] = work_field.surface_index
  local build = state.visual_builds[work_field.id]
  if build then build.rebuild_again = true end
  enqueue(state, work_field.id)
end

local function rectangle_spec(rectangle, color, filled, width)
  return {
    color = color,
    filled = filled,
    width = width,
    draw_on_ground = true,
    left_top = {rectangle.left, rectangle.top},
    right_bottom = {rectangle.right, rectangle.bottom}
  }
end

local function build_specs(work_field)
  local specs = {
    rectangle_spec(work_field.bounds, {0.25, 0.85, 0.25, 0.8}, false, 3),
    rectangle_spec(work_field.lane, {0.85, 0.72, 0.15, 0.22}, true),
    rectangle_spec({
      left = work_field.entrance.x - 0.5, top = work_field.entrance.y - 0.5,
      right = work_field.entrance.x + 0.5, bottom = work_field.entrance.y + 0.5
    }, {0.2, 0.65, 1, 0.8}, true)
  }
  local summary = {rectangle_counts = {
    base = 3, field_operation = 0, crop_growth = {sown = 0, growing = 0, ready = 0}
  }}
  for _, rectangle in ipairs(field_module.completed_rectangles(work_field)) do
    specs[#specs + 1] = rectangle_spec(rectangle, {0.45, 0.24, 0.08, 0.6}, true)
    summary.rectangle_counts.field_operation = summary.rectangle_counts.field_operation + 1
  end
  local crop_colors = {
    sown = {0.72, 0.58, 0.20, 0.45},
    growing = {0.20, 0.72, 0.25, 0.5},
    ready = {0.92, 0.78, 0.12, 0.6}
  }
  for _, crop in ipairs(work_field.crops) do
    local stage = field_module.crop_stage(crop, game.tick)
    for _, rectangle in ipairs(field_module.crop_rectangles(work_field, crop)) do
      specs[#specs + 1] = rectangle_spec(rectangle, crop_colors[stage], true)
      summary.rectangle_counts.crop_growth[stage] = summary.rectangle_counts.crop_growth[stage] + 1
    end
  end
  summary.rectangle_counts.total = #specs
  return specs, summary
end

local function begin_build(state, work_field)
  local specs, summary = build_specs(work_field)
  local build = {specs = specs, summary = summary, objects = {}, next_index = 1, rebuild_again = false}
  state.visual_builds[work_field.id] = build
  return build
end

-- Advances one field's double-buffered projection. The previous complete
-- projection remains visible until every new rectangle exists, then swaps
-- atomically. A dirty mark during the build schedules one later rebuild rather
-- than restarting this one, which guarantees forward progress.
local function advance(state, field_id, budget)
  local work_field = live_field(field_id)
  local surface = work_field and game.get_surface(work_field.surface_index)
  if not work_field or not surface or not surface.valid then
    drop_dirty(state, field_id)
    return 0, false
  end

  local build = state.visual_builds[field_id] or begin_build(state, work_field)
  local last_index = math.min(#build.specs, build.next_index + budget - 1)
  for index = build.next_index, last_index do
    build.specs[index].surface = surface
    local object = rendering.draw_rectangle(build.specs[index])
    object.visible = false
    build.objects[#build.objects + 1] = object
  end
  local drawn = math.max(0, last_index - build.next_index + 1)
  build.next_index = last_index + 1
  if build.next_index <= #build.specs then return drawn, true end

  for _, object in ipairs(build.objects) do object.visible = true end
  destroy_objects(state.visuals[field_id])
  state.visuals[field_id] = build.objects
  state.visual_summaries[field_id] = build.summary
  state.visual_builds[field_id] = nil
  if build.rebuild_again then
    state.visual_dirty[field_id] = work_field.surface_index
    return drawn, true
  end
  state.visual_dirty[field_id] = nil
  return drawn, false
end

function visuals.update()
  local state = root()
  local budget = MAX_PROJECTIONS_PER_TICK
  local visits = 0
  while budget > 0 and visits < MAX_FIELDS_PER_TICK do
    local field_id = dequeue(state)
    if not field_id then break end
    visits = visits + 1
    if state.visual_dirty[field_id] then
      local drawn, still_dirty = advance(state, field_id, budget)
      budget = budget - drawn
      if still_dirty then enqueue(state, field_id) end
    end
  end
end

function visuals.clear(field_id)
  local state = root()
  drop_dirty(state, field_id)
  state.visuals[field_id] = {}
end

function visuals.rebuild(work_field)
  visuals.clear(work_field.id)
  visuals.mark_dirty(work_field)
end

-- Reset work may scale with all fields, but it runs only at load/configuration
-- boundaries. It sorts once, then ordinary tick scheduling stays bounded.
function visuals.reset(fields, machines, jobs)
  local state = root()
  for field_id in pairs(state.visuals) do destroy_objects(state.visuals[field_id]) end
  for _, build in pairs(state.visual_builds) do destroy_objects(build.objects) end
  state.visuals = {}
  state.visual_summaries = {}
  state.visual_builds = {}
  state.visual_dirty = {}
  state.visual_queued = {}
  state.visual_queue_next = {}
  state.visual_queue_head = nil
  state.visual_queue_tail = nil
  state.visual_queue_initialized = true
  local overlay_ids = {}
  for machine_id in pairs(state.machine_overlays) do overlay_ids[#overlay_ids + 1] = machine_id end
  for _, machine_id in ipairs(overlay_ids) do destroy_machine_overlay(state, machine_id) end
  local ids = {}
  for field_id, work_field in pairs(fields or {}) do
    if not work_field.migration_failed then ids[#ids + 1] = field_id end
  end
  table.sort(ids)
  for _, field_id in ipairs(ids) do visuals.mark_dirty(fields[field_id]) end
  visuals.reset_machine_overlays(machines, jobs)
end

function visuals.is_dirty(field_id)
  return root().visual_dirty[field_id] ~= nil
end

function visuals.object_count(field_id)
  local count = 0
  for _, object in ipairs(root().visuals[field_id] or {}) do
    if object.valid then count = count + 1 end
  end
  return count
end

function visuals.summary(field_id)
  local summary = root().visual_summaries[field_id]
  if not summary then return nil end
  local counts = summary.rectangle_counts
  return {
    rectangle_counts = {
      base = counts.base,
      field_operation = counts.field_operation,
      total = counts.total,
      crop_growth = {sown = counts.crop_growth.sown, growing = counts.crop_growth.growing,
        ready = counts.crop_growth.ready}
    }
  }
end

visuals.max_projections_per_tick = MAX_PROJECTIONS_PER_TICK
visuals.max_fields_per_tick = MAX_FIELDS_PER_TICK

return visuals
