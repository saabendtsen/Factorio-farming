local tractor = table.deepcopy(data.raw.car.car)
tractor.name = "farming-tractor"
tractor.localised_name = {"entity-name.farming-tractor"}
tractor.localised_description = {"entity-description.farming-tractor"}
tractor.minable = {mining_time = 0.5, result = "car"}
tractor.max_health = 600
tractor.inventory_size = 20
tractor.energy_source = {type = "void"}

data:extend({tractor})
