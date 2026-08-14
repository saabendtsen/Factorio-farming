local field_module = require("scripts.field")

local visuals = {}
local MAX_PROJECTIONS_PER_TICK = 8

local function root()
  storage.farming.visuals = storage.farming.visuals or {}
  storage.farming.visual_dirty = storage.farming.visual_dirty or {}
  return storage.farming
end

local function destroy_objects(objects)
  for _, object in ipairs(objects or {}) do
    if object.valid then object.destroy() end
  end
end

function visuals.mark_dirty(work_field)
  root().visual_dirty[work_field.id] = work_field.surface_index
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
  for _, rectangle in ipairs(field_module.completed_rectangles(work_field)) do
    specs[#specs + 1] = rectangle_spec(rectangle, {0.45, 0.24, 0.08, 0.6}, true)
  end
  return specs
end

function visuals.update()
  local state = root()
  local field_id
  local surface_index
  for candidate = 1, storage.farming.next_field_id - 1 do
    if state.visual_dirty[candidate] then
      field_id = candidate
      surface_index = state.visual_dirty[candidate]
      break
    end
  end
  if not field_id then return end

  local surface_state = storage.farming.surfaces[surface_index]
  local work_field = surface_state and surface_state.field
  if not work_field or work_field.id ~= field_id then
    state.visual_dirty[field_id] = nil
    return
  end

  destroy_objects(state.visuals[field_id])
  state.visuals[field_id] = {}
  local surface = game.get_surface(surface_index)
  local specs = build_specs(work_field)
  for index = 1, math.min(#specs, MAX_PROJECTIONS_PER_TICK) do
    specs[index].surface = surface
    state.visuals[field_id][#state.visuals[field_id] + 1] = rendering.draw_rectangle(specs[index])
  end
  state.visual_dirty[field_id] = nil
end

function visuals.clear(field_id)
  local state = root()
  destroy_objects(state.visuals[field_id])
  state.visuals[field_id] = {}
end

function visuals.rebuild(work_field)
  visuals.clear(work_field.id)
  visuals.mark_dirty(work_field)
end

function visuals.object_count(field_id)
  local count = 0
  for _, object in ipairs(root().visuals[field_id] or {}) do
    if object.valid then count = count + 1 end
  end
  return count
end

visuals.max_projections_per_tick = MAX_PROJECTIONS_PER_TICK

return visuals
