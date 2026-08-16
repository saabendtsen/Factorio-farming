-- Selects which driver the test mod runs. The harness overwrites this file in
-- the staged mod directory for each Factorio invocation:
--   functional - fresh map, full acceptance flow
--   capture    - fresh map, drives one slice and saves it in each phase
--   replay     - loads a captured save and verifies or benchmarks it
return "functional"
