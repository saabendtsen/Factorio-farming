local field = {}

local EXPECTED_LONG = 64
local EXPECTED_SHORT = 16
local WORK_WIDTH = 4

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

  local lane
  if axis == "x" then
    lane = {left = bounds.left, top = bounds.top + 6, right = bounds.right, bottom = bounds.top + 10}
  else
    lane = {left = bounds.left + 6, top = bounds.top, right = bounds.left + 10, bottom = bounds.bottom}
  end

  local strips = {}
  for index = 1, EXPECTED_SHORT do strips[index] = {} end
  local chunk_representations = {}
  if horizontal then
    chunk_representations["0:0"] = "ranges"
    chunk_representations["1:0"] = "ranges"
  else
    chunk_representations["0:0"] = "ranges"
    chunk_representations["0:1"] = "ranges"
  end

  return {
    id = id,
    surface_index = surface_index,
    bounds = bounds,
    entrance = copy_position(entrance),
    axis = axis,
    direction = direction,
    lane = lane,
    area = EXPECTED_LONG * EXPECTED_SHORT,
    lane_area = EXPECTED_LONG * WORK_WIDTH,
    completed_area = 0,
    representation = "ranges",
    chunk_representations = chunk_representations,
    strips = strips,
    generation = 1
  }
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

function field.commit(work_field, rectangle)
  local clipped = {
    left = clamp(math.floor(rectangle.left), work_field.lane.left, work_field.lane.right),
    top = clamp(math.floor(rectangle.top), work_field.lane.top, work_field.lane.bottom),
    right = clamp(math.ceil(rectangle.right), work_field.lane.left, work_field.lane.right),
    bottom = clamp(math.ceil(rectangle.bottom), work_field.lane.top, work_field.lane.bottom)
  }
  if clipped.right <= clipped.left or clipped.bottom <= clipped.top then return 0 end

  local delta = 0
  if work_field.axis == "x" then
    for y = clipped.top, clipped.bottom - 1 do
      local strip_index = y - work_field.bounds.top + 1
      local local_first = clipped.left - work_field.bounds.left
      local local_last = clipped.right - work_field.bounds.left
      local strip_delta
      work_field.strips[strip_index], strip_delta = add_interval(work_field.strips[strip_index], local_first, local_last)
      delta = delta + strip_delta
    end
  else
    for x = clipped.left, clipped.right - 1 do
      local strip_index = x - work_field.bounds.left + 1
      local local_first = clipped.top - work_field.bounds.top
      local local_last = clipped.bottom - work_field.bounds.top
      local strip_delta
      work_field.strips[strip_index], strip_delta = add_interval(work_field.strips[strip_index], local_first, local_last)
      delta = delta + strip_delta
    end
  end
  work_field.completed_area = work_field.completed_area + delta
  return delta
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
    return {x = work_field.bounds.left + cursor, y = work_field.entrance.y}
  end
  return {x = work_field.entrance.x, y = work_field.bounds.top + cursor}
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
  local lane_strip_start = work_field.axis == "x" and
    work_field.lane.top - work_field.bounds.top + 1 or
    work_field.lane.left - work_field.bounds.left + 1
  local ranges = work_field.strips[lane_strip_start]
  for _, interval in ipairs(ranges) do
    if work_field.axis == "x" then
      rectangles[#rectangles + 1] = {
        left = work_field.bounds.left + interval[1], top = work_field.lane.top,
        right = work_field.bounds.left + interval[2], bottom = work_field.lane.bottom
      }
    else
      rectangles[#rectangles + 1] = {
        left = work_field.lane.left, top = work_field.bounds.top + interval[1],
        right = work_field.lane.right, bottom = work_field.bounds.top + interval[2]
      }
    end
  end
  return rectangles
end

field.constants = {long = EXPECTED_LONG, short = EXPECTED_SHORT, work_width = WORK_WIDTH}
field._add_interval = add_interval

return field
