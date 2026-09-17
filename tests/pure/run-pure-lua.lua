-- Standalone driver for the engine-free specs.
--
-- The Factorio integration harness is serialized and slow, so the pure
-- arithmetic behind the scale characterization is also runnable on its own with
-- any Lua 5.2+ interpreter:
--
--   lua tests/pure/run-pure-lua.lua
--
-- It loads the production modules that carry no game-API dependency and runs
-- the same spec files the test mod runs during its pure-test pass, so a green
-- run here and a green run inside Factorio assert exactly the same behaviour.

local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]pure[/\\]") or "."

local function load_module(relative)
  local path = root .. "/" .. relative
  local chunk, message = loadfile(path)
  if not chunk then error("could not load " .. path .. ": " .. tostring(message), 0) end
  return chunk()
end

local failures = 0
local checks = 0

local assertions = {}

function assertions.fail(message)
  failures = failures + 1
  io.write("  FAIL  " .. message .. "\n")
end

function assertions.equal(actual, expected, message)
  checks = checks + 1
  if actual ~= expected then
    assertions.fail(message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

function assertions.truthy(value, message)
  checks = checks + 1
  if not value then assertions.fail(message) end
end

local specs = {
  {name = "scale ledger", module = "scripts/scale_ledger.lua", spec = "tests/factorio-farming-tests/scale_ledger_spec.lua"}
}

for _, entry in ipairs(specs) do
  io.write("=== " .. entry.name .. " ===\n")
  local before = failures
  local ok, message = pcall(function()
    load_module(entry.spec)(load_module(entry.module), assertions)
  end)
  if not ok then
    failures = failures + 1
    io.write("  ERROR " .. tostring(message) .. "\n")
  elseif failures == before then
    io.write("  PASS  " .. entry.name .. "\n")
  end
end

io.write(string.format("\n%d checks, %d failures\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
