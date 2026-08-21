# Factorio Farming

Factorio Farming models agriculture as physical field work whose machinery, timing, and storage constraints create an automation problem.

## Language

**MVP wheat loop**:
The first complete playable crop cycle for one field and one tractor: cultivate, sow, grow, harvest, and store wheat.
_Avoid_: Second vertical slice, crop demo

**Field**:
A player-defined area on which field operations and crop growth are tracked.
_Avoid_: Plot, farm tile

**Field operation**:
A bounded kind of work performed across a field, such as cultivation, sowing, or harvesting.
_Avoid_: Action, task

**Crop cycle**:
The ordered progression from prepared field through sowing and growth to harvest and storage.
_Avoid_: Farming lifecycle, production recipe

**Growth stage**:
A visible maturity state of a crop between sowing and harvest readiness.
_Avoid_: Growth level, phase

**Implement**:
The equipment or capability that enables a tractor to perform a particular field operation.
_Avoid_: Tool, attachment

**Wheat yield**:
The deterministic quantity of wheat produced by harvesting authoritative crop coverage.
_Avoid_: Reward, output score

**Storage container**:
The designated Factorio inventory that accepts harvested wheat from the field job.
_Avoid_: Warehouse, output chest
