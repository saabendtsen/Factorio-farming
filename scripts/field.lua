local field = {}

local EXPECTED_LONG = 64
local EXPECTED_SHORT = 16
local WORK_WIDTH = 4
local SCHEMA_VERSION = 2
local GROWTH_TICKS = 60 * 60

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function coverage(ranges)
  local total = 0
  for _, interval in ipairs(ranges) do
    total = total + interval[2] - interval[1]
  end
  return total
end

local function add_interval(ranges, first, last)
  if last <= first then return ranges, 0 end

  local before = coverage(ranges)
  local merged = {}
  local inserted = false
  for _, interval in ipairs(ranges) do
    if interval[2] < first then
      merged[#merged + 1] = interval
    elseif last < interval[1] then
      if not inserted then
        merged[#merged + 1] = {first, last}
        inserted = true
      end
      merged[#merged + 1] = interval
    else
      first = math.min(first, interval[1])
      last = math.max(last, interval[2])
    end
  end
  if not inserted then merged[#merged + 1] = {first, last} end
  return merged, coverage(merged) - before
end

local function remove_interval(ranges, first, last)
  local kept = {}
  local removed = {}
  for _, interval in ipairs(ranges) do
    local overlap_first = math.max(interval[1], first)
    local overlap_last = math.min(interval[2], last)
    if overlap_last <= overlap_first then
      kept[#kept + 1] = {interval[1], interval[2]}
    else
      if interval[1] < overlap_first then kept[#kept + 1] = {interval[1], overlap_first} end
      removed[#removed + 1] = {overlap_first, overlap_last}
      if overlap_last < interval[2] then kept[#kept + 1] = {overlap_last, interval[2]} end
    end
  end
  return kept, coverage(ranges) - coverage(kept), removed
end

local function copy_ranges(strips)
  local copied = {}
  for index, ranges in ipairs(strips) do
    copied[index] = {}
    for range_index, interval in ipairs(ranges) do
      copied[index][range_index] = {interval[1], interval[2]}
    end
  end
  return copied
end

local function empty_strips()
  local strips = {}
  for index = 1, EXPECTED_SHORT do strips[index] = {} end
  return strips
end

local function strips_area(strips)
  local total = 0
  for _, ranges in ipairs(strips) do total = total + coverage(ranges) end
  return total
end

local function ranges_contain(ranges, first, last)
  for _, interval in ipairs(ranges) do
    if interval[1] <= first and interval[2] >= last then return true end
    if interval[1] > first then return false end
  end
  return false
end

local function valid_ranges(ranges)
  local previous_last = nil
  for _, interval in ipairs(ranges or {}) do
    if type(interval) ~= "table" or type(interval[1]) ~= "number" or type(interval[2]) ~= "number" or
       interval[1] < 0 or interval[2] > EXPECTED_LONG or interval[1] >= interval[2] or
       (previous_last and previous_last >= interval[1]) then return false end
    previous_last = interval[2]
  end
  return true
end

local function operation(work_field, name)
  return work_field.operations and work_field.operations[name]
end

local function sync_cultivation_compatibility(work_field)
  local cultivated = operation(work_field, "cultivation")
  work_field.strips = cultivated.strips
  work_field.completed_area = cultivated.area
end

function field.normalize_selection(area)
  local left = math.floor(math.min(area.left_top.x, area.right_bottom.x))
  local top = math.floor(math.min(area.left_top.y, area.right_bottom.y))
  local right = math.ceil(math.max(area.left_top.x, area.right_bottom.x))
  local bottom = math.ceil(math.max(area.left_top.y, area.right_bottom.y))
  local width = right - left
  local height = bottom - top
  if not ((width == EXPECTED_LONG and height == EXPECTED_SHORT) or
          (width == EXPECTED_SHORT and height == EXPECTED_LONG)) then
    return nil, "Field must be exactly 64 by 16 tiles."
  end
  return {left = left, top = top, right = right, bottom = bottom}
end

local function squared_distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

function field.create(id, surface_index, bounds, player_position)
  local horizontal = bounds.right - bounds.left == EXPECTED_LONG
  local center_x = (bounds.left + bounds.right) / 2
  local center_y = (bounds.top + bounds.bottom) / 2
  local first_entrance
  local second_entrance
  local axis

  if horizontal then
    first_entrance = {x = bounds.left, y = center_y}
    second_entrance = {x = bounds.right, y = center_y}
    axis = "x"
  else
    first_entrance = {x = center_x, y = bounds.top}
    second_entrance = {x = center_x, y = bounds.bottom}
    axis = "y"
  end

  local entrance = first_entrance
  if squared_distance(player_position, second_entrance) < squared_distance(player_position, first_entrance) then
    entrance = second_entrance
  end

  local direction = 1
  if (axis == "x" and entrance.x == bounds.right) or (axis == "y" and entrance.y == bounds.bottom) then
    direction = -1
  end

  local lanes = {}
  for lane_index = 1, EXPECTED_SHORT / WORK_WIDTH do
    local offset = (lane_index - 1) * WORK_WIDTH
    if axis == "x" then
      lanes[lane_index] = {
        left = bounds.left, top = bounds.top + offset,
        right = bounds.right, bottom = bounds.top + offset + WORK_WIDTH
      }
    else
      lanes[lane_index] = {
        left = bounds.left + offset, top = bounds.top,
        right = bounds.left + offset + WORK_WIDTH, bottom = bounds.bottom
      }
    end
  end

  local cultivated = {strips = empty_strips(), area = 0}
  local chunk_representations = {}
  local first_chunk_x = math.floor(bounds.left / 32)
  local last_chunk_x = math.floor((bounds.right - 1) / 32)
  local first_chunk_y = math.floor(bounds.top / 32)
  local last_chunk_y = math.floor((bounds.bottom - 1) / 32)
  for chunk_y = first_chunk_y, last_chunk_y do
    for chunk_x = first_chunk_x, last_chunk_x do
      chunk_representations[chunk_x .. ":" .. chunk_y] = "ranges"
    end
  end

  return {
    id = id,
    surface_index = surface_index,
    bounds = bounds,
    entrance = copy_position(entrance),
    axis = axis,
    base_direction = direction,
    direction = direction,
    lanes = lanes,
    lane_index = 1,
    lane = lanes[1],
    area = EXPECTED_LONG * EXPECTED_SHORT,
    lane_area = EXPECTED_LONG * WORK_WIDTH,
    completed_area = 0,
    representation = "ranges",
    chunk_representations = chunk_representations,
    strips = cultivated.strips,
    operations = {
      cultivation = cultivated,
      sowing = {strips = empty_strips(), area = 0},
      harvesting = {strips = empty_strips(), area = 0}
    },
    crops = {},
    schema_version = SCHEMA_VERSION,
    generation = 1
  }
end

function field.advance_lane(work_field)
  local next_index = work_field.lane_index + 1
  local next_lane = work_field.lanes[next_index]
  if not next_lane then return false end
  work_field.lane_index = next_index
  work_field.lane = next_lane
  work_field.direction = next_index % 2 == 1 and work_field.base_direction or -work_field.base_direction
  work_field.generation = work_field.generation + 1
  return true
end

function field.headland_waypoints(work_field)
  if work_field.lane_index <= 1 then return {} end
  local previous_lane = work_field.lanes[work_field.lane_index - 1]
  local lane = work_field.lane
  local previous_center
  local next_center
  local edge
  local outward

  if work_field.axis == "x" then
    previous_center = (previous_lane.top + previous_lane.bottom) / 2
    next_center = (lane.top + lane.bottom) / 2
    edge = work_field.direction == -1 and work_field.bounds.right or work_field.bounds.left
    outward = work_field.direction == -1 and 1 or -1
    return {
      {x = edge + outward * 2, y = previous_center},
      {x = edge + outward * 3.5, y = previous_center + 1},
      {x = edge + outward * 3.5, y = next_center - 1},
      {x = edge + outward * 2, y = next_center},
      {x = edge, y = next_center}
    }
  end

  previous_center = (previous_lane.left + previous_lane.right) / 2
  next_center = (lane.left + lane.right) / 2
  edge = work_field.direction == -1 and work_field.bounds.bottom or work_field.bounds.top
  outward = work_field.direction == -1 and 1 or -1
  return {
    {x = previous_center, y = edge + outward * 2},
    {x = previous_center + 1, y = edge + outward * 3.5},
    {x = next_center - 1, y = edge + outward * 3.5},
    {x = next_center, y = edge + outward * 2},
    {x = next_center, y = edge}
  }
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function clipped_rectangle(work_field, rectangle)
  local clipped = {
    left = clamp(math.floor(rectangle.left), work_field.bounds.left, work_field.bounds.right),
    top = clamp(math.floor(rectangle.top), work_field.bounds.top, work_field.bounds.bottom),
    right = clamp(math.ceil(rectangle.right), work_field.bounds.left, work_field.bounds.right),
    bottom = clamp(math.ceil(rectangle.bottom), work_field.bounds.top, work_field.bounds.bottom)
  }
  if clipped.right <= clipped.left or clipped.bottom <= clipped.top then return nil end
  return clipped
end

local function local_range(work_field, strip_index, clipped)
  if work_field.axis == "x" then
    return clipped.left - work_field.bounds.left, clipped.right - work_field.bounds.left
  end
  return clipped.top - work_field.bounds.top, clipped.bottom - work_field.bounds.top
end

local function each_strip(work_field, clipped, callback)
  if work_field.axis == "x" then
    for y = clipped.top, clipped.bottom - 1 do callback(y - work_field.bounds.top + 1) end
  else
    for x = clipped.left, clipped.right - 1 do callback(x - work_field.bounds.left + 1) end
  end
end

local function add_coverage(work_field, target, clipped)
  local added = empty_strips()
  local delta = 0
  each_strip(work_field, clipped, function(strip_index)
    local first, last = local_range(work_field, strip_index, clipped)
    local before = copy_ranges({target.strips[strip_index]})[1]
    local merged, strip_delta = add_interval(target.strips[strip_index], first, last)
    target.strips[strip_index] = merged
    if strip_delta > 0 then
      -- An existing interval may split a candidate, so retain only the
      -- uncovered pieces for a crop record rather than the merged shape.
      local cursor_start = first
      for _, interval in ipairs(before) do
        if interval[2] <= cursor_start then
          -- already behind the candidate
        elseif interval[1] >= last then
          break
        else
          if interval[1] > cursor_start then
            added[strip_index][#added[strip_index] + 1] = {cursor_start, math.min(interval[1], last)}
          end
          cursor_start = math.max(cursor_start, interval[2])
          if cursor_start >= last then break end
        end
      end
      if cursor_start < last then added[strip_index][#added[strip_index] + 1] = {cursor_start, last} end
      delta = delta + strip_delta
    end
  end)
  target.area = target.area + delta
  return delta, added
end

local function remove_coverage(work_field, target, clipped)
  local delta = 0
  each_strip(work_field, clipped, function(strip_index)
    local first, last = local_range(work_field, strip_index, clipped)
    local kept, strip_delta = remove_interval(target.strips[strip_index], first, last)
    target.strips[strip_index] = kept
    delta = delta + strip_delta
  end)
  target.area = target.area - delta
  return delta
end

local function rectangle_is_covered(work_field, target, clipped)
  local valid = true
  each_strip(work_field, clipped, function(strip_index)
    local first, last = local_range(work_field, strip_index, clipped)
    if not ranges_contain(target.strips[strip_index], first, last) then valid = false end
  end)
  return valid
end

local function add_crop_record(work_field, strips, sow_tick)
  local area = strips_area(strips)
  if area == 0 then return end
  work_field.crops[#work_field.crops + 1] = {
    strips = strips,
    area = area,
    sow_tick = sow_tick,
    ready_tick = sow_tick + GROWTH_TICKS,
    generation = work_field.generation
  }
end

local function remove_crop_coverage(work_field, clipped)
  local retained = {}
  for _, crop in ipairs(work_field.crops) do
    local removed = 0
    each_strip(work_field, clipped, function(strip_index)
      local first, last = local_range(work_field, strip_index, clipped)
      local kept, strip_delta = remove_interval(crop.strips[strip_index], first, last)
      crop.strips[strip_index] = kept
      removed = removed + strip_delta
    end)
    crop.area = crop.area - removed
    if crop.area > 0 then retained[#retained + 1] = crop end
  end
  work_field.crops = retained
end

local function ready_crop_coverage(work_field, tick)
  local ready = {strips = empty_strips(), area = 0}
  for _, crop in ipairs(work_field.crops) do
    if crop.ready_tick <= tick then
      for strip_index, ranges in ipairs(crop.strips) do
        for _, interval in ipairs(ranges) do
          local merged, delta = add_interval(ready.strips[strip_index], interval[1], interval[2])
          ready.strips[strip_index] = merged
          ready.area = ready.area + delta
        end
      end
    end
  end
  return ready
end

function field.commit_operation(work_field, name, rectangle, tick, transferred_area)
  local target = operation(work_field, name)
  local clipped = clipped_rectangle(work_field, rectangle)
  if not target or not clipped then return 0 end
  if name == "sowing" and not rectangle_is_covered(work_field, operation(work_field, "cultivation"), clipped) then return 0 end
  if name == "harvesting" then
    if not rectangle_is_covered(work_field, operation(work_field, "sowing"), clipped) then return 0 end
    if not rectangle_is_covered(work_field, ready_crop_coverage(work_field, tick or 0), clipped) then return 0 end
    local requested_area = (clipped.right - clipped.left) * (clipped.bottom - clipped.top)
    if transferred_area ~= requested_area then return 0 end
  end

  local delta, added = add_coverage(work_field, target, clipped)
  if name == "sowing" and delta > 0 then
    remove_coverage(work_field, operation(work_field, "harvesting"), clipped)
    add_crop_record(work_field, added, tick or 0)
  elseif name == "harvesting" and delta > 0 then
    remove_coverage(work_field, operation(work_field, "sowing"), clipped)
    remove_crop_coverage(work_field, clipped)
  end
  if name == "cultivation" then sync_cultivation_compatibility(work_field) end
  return delta
end

function field.commit(work_field, rectangle)
  return field.commit_operation(work_field, "cultivation", rectangle)
end

function field.operation_area(work_field, name)
  local target = operation(work_field, name)
  return target and target.area or 0
end

function field.lifecycle(work_field, tick)
  local cultivated = field.operation_area(work_field, "cultivation")
  local sown = field.operation_area(work_field, "sowing")
  local harvested = field.operation_area(work_field, "harvesting")
  if cultivated == 0 then return "uncultivated" end
  if cultivated < work_field.area then return "cultivating" end
  if sown == 0 then return "prepared" end
  if harvested > 0 then return "harvesting" end
  if sown < cultivated then return "sowing" end
  for _, crop in ipairs(work_field.crops) do
    if crop.ready_tick > (tick or 0) then return "growing" end
  end
  return "ready"
end

function field.next_uncovered(work_field)
  local representative = work_field.axis == "x" and
    work_field.strips[work_field.lane.top - work_field.bounds.top + 1] or
    work_field.strips[work_field.lane.left - work_field.bounds.left + 1]
  local cursor = work_field.direction == 1 and 0 or EXPECTED_LONG

  if work_field.direction == 1 then
    for _, interval in ipairs(representative) do
      if interval[1] > cursor then break end
      cursor = math.max(cursor, interval[2])
    end
  else
    for index = #representative, 1, -1 do
      local interval = representative[index]
      if interval[2] < cursor then break end
      cursor = math.min(cursor, interval[1])
    end
  end

  if (work_field.direction == 1 and cursor >= EXPECTED_LONG) or
     (work_field.direction == -1 and cursor <= 0) then return nil end
  if work_field.axis == "x" then
    return {x = work_field.bounds.left + cursor, y = (work_field.lane.top + work_field.lane.bottom) / 2}
  end
  return {x = (work_field.lane.left + work_field.lane.right) / 2, y = work_field.bounds.top + cursor}
end

function field.work_rectangle(work_field, from_position, to_position, final)
  if work_field.axis == "x" then
    local first = math.min(from_position.x, to_position.x)
    local last = math.max(from_position.x, to_position.x)
    if final then last = last + 1 end
    return {left = first, top = work_field.lane.top, right = last, bottom = work_field.lane.bottom}
  end
  local first = math.min(from_position.y, to_position.y)
  local last = math.max(from_position.y, to_position.y)
  if final then last = last + 1 end
  return {left = work_field.lane.left, top = first, right = work_field.lane.right, bottom = last}
end

function field.completed_rectangles(work_field)
  local rectangles = {}
  local function ranges_equal(first, second)
    if #first ~= #second then return false end
    for index, interval in ipairs(first) do
      if interval[1] ~= second[index][1] or interval[2] ~= second[index][2] then return false end
    end
    return true
  end

  local group_start = 1
  while group_start <= #work_field.strips do
    local ranges = work_field.strips[group_start]
    local group_end = group_start
    while group_end < #work_field.strips and ranges_equal(ranges, work_field.strips[group_end + 1]) do
      group_end = group_end + 1
    end
    for _, interval in ipairs(ranges) do
      if work_field.axis == "x" then
        rectangles[#rectangles + 1] = {
          left = work_field.bounds.left + interval[1],
          top = work_field.bounds.top + group_start - 1,
          right = work_field.bounds.left + interval[2],
          bottom = work_field.bounds.top + group_end
        }
      else
        rectangles[#rectangles + 1] = {
          left = work_field.bounds.left + group_start - 1,
          top = work_field.bounds.top + interval[1],
          right = work_field.bounds.left + group_end,
          bottom = work_field.bounds.top + interval[2]
        }
      end
    end
    group_start = group_end + 1
  end
  return rectangles
end

function field.claim_lane(work_field, job_id, machine_id)
  local claim = work_field.lane_claim
  if claim then
    return claim.job_id == job_id and claim.machine_id == machine_id
  end
  work_field.lane_claim = {lane = work_field.lane_index, job_id = job_id, machine_id = machine_id}
  return true
end

function field.release_lane(work_field, job_id)
  local claim = work_field.lane_claim
  if not claim then return true end
  if claim.job_id ~= job_id then return false end
  work_field.lane_claim = nil
  return true
end

local function valid_legacy_field(work_field)
  local bounds = work_field and work_field.bounds
  if type(bounds) ~= "table" or type(bounds.left) ~= "number" or type(bounds.top) ~= "number" or
     type(bounds.right) ~= "number" or type(bounds.bottom) ~= "number" then return false end
  local width = bounds.right - bounds.left
  local height = bounds.bottom - bounds.top
  if not ((width == EXPECTED_LONG and height == EXPECTED_SHORT) or
          (width == EXPECTED_SHORT and height == EXPECTED_LONG)) then return false end
  if (work_field.axis == "x") ~= (width == EXPECTED_LONG) then return false end
  if type(work_field.strips) ~= "table" or #work_field.strips ~= EXPECTED_SHORT then return false end
  for index = 1, EXPECTED_SHORT do
    if not valid_ranges(work_field.strips[index]) then return false end
  end
  return type(work_field.completed_area) == "number" and work_field.completed_area == strips_area(work_field.strips)
end

local function pause_legacy_operation(state)
  local job = state.job
  if not job or job.state == "completed" then return end
  job.state = "paused"
  job.machine_id = nil
  job.lane_claim = nil
  job.recovery_required = true
  job.failure = nil
  job.paused_from = nil
  job.paused_motion = nil
  if state.machine then
    state.machine.job_id = nil
    state.machine.generation = (state.machine.generation or 0) + 1
    state.machine.controller = {state = "idle", recoveries = 0}
  end
end

-- Migrates only the former cultivation-only schema. Invalid records are kept
-- verbatim behind a fail-closed marker so a future repair can inspect them.
function field.migrate_storage(root)
  if not root then return false, "Missing farming storage." end
  if root.schema_version and root.schema_version >= SCHEMA_VERSION then return true end
  root.surfaces = root.surfaces or {}
  root.migration_failures = root.migration_failures or {}
  root.path_queue = {}
  root.pending_paths = {}
  root.outstanding_path_id = nil

  for surface_index, state in pairs(root.surfaces) do
    local legacy = state.field
    if legacy then
      if not valid_legacy_field(legacy) then
        state.field = {migration_failed = true, legacy_raw = legacy, surface_index = surface_index}
        root.migration_failures[surface_index] = "Malformed legacy field record."
        pause_legacy_operation(state)
      else
        local cultivated = {strips = copy_ranges(legacy.strips), area = legacy.completed_area}
        legacy.operations = {
          cultivation = cultivated,
          sowing = {strips = empty_strips(), area = 0},
          harvesting = {strips = empty_strips(), area = 0}
        }
        legacy.crops = {}
        legacy.schema_version = SCHEMA_VERSION
        legacy.strips = cultivated.strips
        legacy.completed_area = cultivated.area
        legacy.lane_claim = nil
        legacy.generation = (legacy.generation or 0) + 1
        pause_legacy_operation(state)
      end
    end
  end
  root.schema_version = SCHEMA_VERSION
  return true
end

field.constants = {long = EXPECTED_LONG, short = EXPECTED_SHORT, work_width = WORK_WIDTH, growth_ticks = GROWTH_TICKS}
field._add_interval = add_interval

return field
