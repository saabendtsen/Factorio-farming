local field_module = require("scripts.field")

local visuals = {}
-- Projection work is bounded per tick across every dirty field, not per field,
-- so an arbitrary number of live fields still costs a constant tick budget.
local MAX_PROJECTIONS_PER_TICK = 8

local function root()
  storage.farming.visuals = storage.farming.visuals or {}
  storage.farming.visual_dirty = storage.farming.visual_dirty or {}
  storage.farming.visual_builds = storage.farming.visual_builds or {}
  return storage.farming
end

-- Durable field identity is the only authority for a projection. The surface's
-- `state.field` alias merely names the field currently presented to the player
-- and must never decide what gets drawn.
local function live_field(field_id)
  local fields = storage.farming.fields
  local work_field = fields and fields[field_id]
  if not work_field then return nil end
  if work_field.id ~= field_id then return nil end
  if work_field.migration_failed then return nil end
  return work_field
end

local function destroy_objects(objects)
  for _, object in ipairs(objects or {}) do
    if object.valid then object.destroy() end
  end
end

-- Everything held per field is disposable: destroying it can never change
-- authoritative field state, so any interruption is resolved by throwing the
-- partial projection away and rebuilding from the field record.
local function discard(state, field_id)
  destroy_objects(state.visuals[field_id])
  state.visuals[field_id] = nil
  state.visual_builds[field_id] = nil
end

function visuals.mark_dirty(work_field)
  local state = root()
  state.visual_dirty[work_field.id] = work_field.surface_index
  state.visual_builds[work_field.id] = nil
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
  local crop_colors = {
    sown = {0.72, 0.58, 0.20, 0.45},
    growing = {0.20, 0.72, 0.25, 0.5},
    ready = {0.92, 0.78, 0.12, 0.6}
  }
  for _, crop in ipairs(work_field.crops) do
    local color = crop_colors[field_module.crop_stage(crop, game.tick)]
    for _, rectangle in ipairs(field_module.crop_rectangles(work_field, crop)) do
      specs[#specs + 1] = rectangle_spec(rectangle, color, true)
    end
  end
  return specs
end

-- Dirty fields are served in a deterministic rotation so no field can starve
-- behind a lower id that is re-marked every tick.
local function rotation(state)
  local ids = {}
  for field_id in pairs(state.visual_dirty) do ids[#ids + 1] = field_id end
  table.sort(ids)
  local cursor = state.visual_cursor or 0
  local start = 1
  for index, field_id in ipairs(ids) do
    if field_id > cursor then start = index; break end
    if index == #ids then start = 1 end
  end
  local ordered = {}
  for offset = 0, #ids - 1 do
    ordered[#ordered + 1] = ids[((start - 1 + offset) % #ids) + 1]
  end
  return ordered
end

-- Advances one field's projection by at most `budget` rectangles and returns
-- how much of the budget was consumed.
local function advance(state, field_id, budget)
  local work_field = live_field(field_id)
  if not work_field then
    -- Unknown or invalid field identity: drop the projection, never the caller.
    discard(state, field_id)
    state.visual_dirty[field_id] = nil
    return 0
  end
  local surface = game.get_surface(work_field.surface_index)
  if not surface or not surface.valid then
    discard(state, field_id)
    state.visual_dirty[field_id] = nil
    return 0
  end

  local build = state.visual_builds[field_id]
  if not build then
    discard(state, field_id)
    state.visuals[field_id] = {}
    build = {specs = build_specs(work_field), next_index = 1}
    state.visual_builds[field_id] = build
  end
  state.visuals[field_id] = state.visuals[field_id] or {}

  local objects = state.visuals[field_id]
  local last_index = math.min(#build.specs, build.next_index + budget - 1)
  for index = build.next_index, last_index do
    build.specs[index].surface = surface
    objects[#objects + 1] = rendering.draw_rectangle(build.specs[index])
  end
  local drawn = math.max(0, last_index - build.next_index + 1)
  build.next_index = last_index + 1
  if build.next_index > #build.specs then
    state.visual_dirty[field_id] = nil
    state.visual_builds[field_id] = nil
  end
  return drawn
end

function visuals.update()
  local state = root()
  local ordered = rotation(state)
  if #ordered == 0 then
    state.visual_cursor = 0
    return
  end
  local budget = MAX_PROJECTIONS_PER_TICK
  local last_touched = state.visual_cursor or 0
  for _, field_id in ipairs(ordered) do
    if budget <= 0 then break end
    local before = budget
    budget = budget - advance(state, field_id, budget)
    last_touched = field_id
    -- A field dropped for invalid identity consumes no budget, so the same tick
    -- keeps serving real fields instead of stalling on a dead id.
    if before == budget and state.visual_dirty[field_id] then break end
  end
  state.visual_cursor = last_touched
end

function visuals.clear(field_id)
  local state = root()
  discard(state, field_id)
  state.visuals[field_id] = {}
end

function visuals.rebuild(work_field)
  visuals.clear(work_field.id)
  visuals.mark_dirty(work_field)
end

-- Load, configuration change, and any other interruption resolve the same way:
-- throw every partial projection away and re-mark each live field, so nothing
-- stale can outlive the field record it was derived from.
function visuals.reset(fields)
  local state = root()
  for field_id in pairs(state.visuals) do discard(state, field_id) end
  for field_id in pairs(state.visual_builds) do discard(state, field_id) end
  state.visuals = {}
  state.visual_builds = {}
  state.visual_dirty = {}
  state.visual_cursor = 0
  for _, work_field in pairs(fields or {}) do
    if not work_field.migration_failed then visuals.mark_dirty(work_field) end
  end
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

visuals.max_projections_per_tick = MAX_PROJECTIONS_PER_TICK

return visuals
