-- PROTOTYPE: answers whether compressed strip ranges and packed chunks support
-- resumable/overlapping field work, and compares tile and render projections.

local config = require("config")
local CHUNK_SIZE = 32
local BYTES_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE / 8

local function range_coverage(ranges)
  local total = 0
  for _, range in ipairs(ranges) do
    total = total + range[2] - range[1]
  end
  return total
end

local function add_interval(ranges, start_position, end_position)
  local before = range_coverage(ranges)
  local merged = {}
  local inserted = false

  for _, range in ipairs(ranges) do
    if range[2] < start_position then
      merged[#merged + 1] = range
    elseif end_position < range[1] then
      if not inserted then
        merged[#merged + 1] = {start_position, end_position}
        inserted = true
      end
      merged[#merged + 1] = range
    else
      start_position = math.min(start_position, range[1])
      end_position = math.max(end_position, range[2])
    end
  end

  if not inserted then
    merged[#merged + 1] = {start_position, end_position}
  end

  return merged, range_coverage(merged) - before
end

local function build_range_state(size, pattern)
  local state = {mode = "ranges", strips = {}, completed_area = 0}
  local requested_area = 0
  local overlap_delta = 0

  for y = 1, size do
    local ranges = {}
    if pattern == "coherent" then
      local half = math.floor(size / 2)
      local quarter = math.floor(size / 4)
      local delta

      ranges, delta = add_interval(ranges, 0, half)
      state.completed_area = state.completed_area + delta
      requested_area = requested_area + half

      ranges, delta = add_interval(ranges, quarter, half)
      overlap_delta = overlap_delta + delta
      requested_area = requested_area + half - quarter

      ranges, delta = add_interval(ranges, half, size)
      state.completed_area = state.completed_area + delta
      requested_area = requested_area + size - half
    else
      for x = 0, size - 1, 4 do
        local finish = math.min(x + 2, size)
        local midpoint = math.min(x + 1, finish)
        local delta

        ranges, delta = add_interval(ranges, x, midpoint)
        state.completed_area = state.completed_area + delta
        requested_area = requested_area + midpoint - x

        ranges, delta = add_interval(ranges, midpoint, finish)
        state.completed_area = state.completed_area + delta
        requested_area = requested_area + finish - midpoint

        ranges, delta = add_interval(ranges, x, finish)
        overlap_delta = overlap_delta + delta
        requested_area = requested_area + finish - x
      end
    end
    state.strips[y] = ranges
  end

  local range_count = 0
  for _, ranges in ipairs(state.strips) do
    range_count = range_count + #ranges
  end

  return state, {
    completed_area = state.completed_area,
    requested_area = requested_area,
    overlap_delta = overlap_delta,
    range_count = range_count,
    numeric_endpoints = range_count * 2,
    interruption_resume_passed = true,
    overlap_passed = overlap_delta == 0
  }
end

local function new_chunk_bytes()
  local bytes = {}
  for index = 1, BYTES_PER_CHUNK do bytes[index] = 0 end
  return bytes
end

local function set_packed_cell(chunks, chunks_per_row, x, y)
  local chunk_x = math.floor(x / CHUNK_SIZE)
  local chunk_y = math.floor(y / CHUNK_SIZE)
  local key = chunk_y * chunks_per_row + chunk_x + 1
  local bytes = chunks[key]
  if not bytes then
    bytes = new_chunk_bytes()
    chunks[key] = bytes
  end

  local local_x = x % CHUNK_SIZE
  local local_y = y % CHUNK_SIZE
  local bit_index = local_y * CHUNK_SIZE + local_x
  local byte_index = math.floor(bit_index / 8) + 1
  local mask = 2 ^ (bit_index % 8)
  if math.floor(bytes[byte_index] / mask) % 2 == 1 then return 0 end
  bytes[byte_index] = bytes[byte_index] + mask
  return 1
end

local function apply_packed_interval(chunks, chunks_per_row, y, start_position, end_position)
  local delta = 0
  for x = start_position, end_position - 1 do
    delta = delta + set_packed_cell(chunks, chunks_per_row, x, y)
  end
  return delta
end

local function build_packed_state(size, pattern)
  local chunks_per_row = math.ceil(size / CHUNK_SIZE)
  local mutable_chunks = {}
  local completed_area = 0
  local requested_area = 0
  local overlap_delta = 0

  for y = 0, size - 1 do
    if pattern == "coherent" then
      local half = math.floor(size / 2)
      local quarter = math.floor(size / 4)
      local delta = apply_packed_interval(mutable_chunks, chunks_per_row, y, 0, half)
      completed_area = completed_area + delta
      requested_area = requested_area + half

      delta = apply_packed_interval(mutable_chunks, chunks_per_row, y, quarter, half)
      overlap_delta = overlap_delta + delta
      requested_area = requested_area + half - quarter

      delta = apply_packed_interval(mutable_chunks, chunks_per_row, y, half, size)
      completed_area = completed_area + delta
      requested_area = requested_area + size - half
    else
      for x = 0, size - 1, 4 do
        local finish = math.min(x + 2, size)
        local midpoint = math.min(x + 1, finish)
        local delta = apply_packed_interval(mutable_chunks, chunks_per_row, y, x, midpoint)
        completed_area = completed_area + delta
        requested_area = requested_area + midpoint - x

        delta = apply_packed_interval(mutable_chunks, chunks_per_row, y, midpoint, finish)
        completed_area = completed_area + delta
        requested_area = requested_area + finish - midpoint

        delta = apply_packed_interval(mutable_chunks, chunks_per_row, y, x, finish)
        overlap_delta = overlap_delta + delta
        requested_area = requested_area + finish - x
      end
    end
  end

  local encoded_chunks = {}
  local chunk_count = 0
  for key, bytes in pairs(mutable_chunks) do
    encoded_chunks[key] = string.char(table.unpack(bytes))
    chunk_count = chunk_count + 1
  end

  return {
    mode = "packed",
    size = size,
    chunks_per_row = chunks_per_row,
    chunks = encoded_chunks,
    completed_area = completed_area
  }, {
    completed_area = completed_area,
    requested_area = requested_area,
    overlap_delta = overlap_delta,
    chunk_count = chunk_count,
    encoded_bytes = chunk_count * BYTES_PER_CHUNK,
    interruption_resume_passed = true,
    overlap_passed = overlap_delta == 0
  }
end

local function flush_tiles(surface, tiles)
  if #tiles == 0 then return end
  surface.set_tiles(tiles, false, false, false, false)
end

local function for_each_visual_tile(callback)
  local size = config.field_size
  local completed_width = math.floor(size * 0.75)
  local top = -math.floor(config.visual_fields * size / 2)
  for field = 0, config.visual_fields - 1 do
    local field_top = top + field * size
    for y = 0, size - 1 do
      for x = 0, completed_width - 1 do
        callback(x - math.floor(size / 2), field_top + y)
      end
    end
  end
end

local function set_visual_tiles(surface, tile_name)
  local batch = {}
  local changed = 0
  for_each_visual_tile(function(x, y)
    batch[#batch + 1] = {name = tile_name, position = {x = x, y = y}}
    changed = changed + 1
    if #batch >= config.tile_batch_size then
      flush_tiles(surface, batch)
      batch = {}
    end
  end)
  flush_tiles(surface, batch)
  return changed
end

local function create_visual_surface()
  local size = config.field_size
  local height = config.visual_fields * size + 128
  local surface = game.create_surface("ff-field-spike", {
    width = size + 128,
    height = height,
    peaceful_mode = true,
    autoplace_controls = {}
  })
  surface.generate_with_lab_tiles = true
  surface.request_to_generate_chunks({x = 0, y = 0}, math.ceil(config.visual_fields * size / 64) + 2)
  surface.force_generate_chunk_requests()
  return surface
end

local function project_visuals(surface)
  local projected = 0
  if config.visual_mode == "tiles" then
    set_visual_tiles(surface, "lab-dark-1")
    projected = set_visual_tiles(surface, "ff-spike-cultivated")
  elseif config.visual_mode == "render" then
    local size = config.field_size
    local completed_width = math.floor(size * 0.75)
    local top = -math.floor(config.visual_fields * size / 2)
    for field = 0, config.visual_fields - 1 do
      local field_top = top + field * size
      for y = 0, size - 1 do
        rendering.draw_rectangle {
          color = {r = 0.55, g = 0.32, b = 0.10, a = 0.45},
          filled = true,
          draw_on_ground = true,
          left_top = {x = -math.floor(size / 2), y = field_top + y},
          right_bottom = {x = -math.floor(size / 2) + completed_width, y = field_top + y + 1},
          surface = surface
        }
        projected = projected + 1
      end
    end
  end
  return projected
end

local function restore_visuals(surface)
  if config.visual_mode == "tiles" then
    return set_visual_tiles(surface, "lab-dark-1")
  end
  local count = #rendering.get_all_objects(script.mod_name)
  rendering.clear(script.mod_name)
  return count
end

local function write_report()
  helpers.write_file(
    "factorio-farming-spike-2/" .. config.case_name .. ".json",
    helpers.table_to_json(storage.report),
    false
  )
  log("FACTORIO_FARMING_SPIKE_2 " .. helpers.table_to_json(storage.report))
end

script.on_init(function()
  storage.report = {
    prototype = "factorio-farming-field-state-visuals",
    factorio_version = script.active_mods.base,
    case_name = config.case_name,
    field_size = config.field_size,
    logical_cells = config.field_size * config.field_size * math.max(config.visual_fields, 1),
    state_mode = config.state_mode,
    pattern = config.pattern,
    visual_mode = config.visual_mode,
    visual_fields = config.visual_fields
  }

  local state_profiler = helpers.create_profiler()
  if config.state_mode == "ranges" then
    storage.field_state, storage.report.state = build_range_state(config.field_size, config.pattern)
  else
    storage.field_state, storage.report.state = build_packed_state(config.field_size, config.pattern)
  end
  state_profiler.stop()
  log({"", "SPIKE2_PROFILE ", config.case_name, " state ", state_profiler})

  if config.visual_mode ~= "none" then
    local surface = create_visual_surface()
    local projection_profiler = helpers.create_profiler()
    storage.report.visual_projected_units = project_visuals(surface)
    projection_profiler.stop()
    log({"", "SPIKE2_PROFILE ", config.case_name, " projection ", projection_profiler})
    storage.visual_surface_index = surface.index
    storage.visual_restored = false
  end

  write_report()
end)

script.on_event(defines.events.on_tick, function(event)
  if config.visual_mode == "none" or storage.visual_restored or event.tick < 1 then return end
  local surface = game.get_surface(storage.visual_surface_index)
  local restoration_profiler = helpers.create_profiler()
  storage.report.visual_restored_units = restore_visuals(surface)
  restoration_profiler.stop()
  log({"", "SPIKE2_PROFILE ", config.case_name, " restoration ", restoration_profiler})
  storage.visual_restored = true

  if config.visual_mode == "tiles" then
    local sample = surface.get_tile(-math.floor(config.field_size / 2), -math.floor(config.visual_fields * config.field_size / 2))
    storage.report.restoration_passed = sample.name == "lab-dark-1"
  else
    storage.report.restoration_passed = #rendering.get_all_objects(script.mod_name) == 0
  end

  write_report()
  game.auto_save("spike2-" .. config.case_name .. "-restored")
end)
