local storage_container = table.deepcopy(data.raw.container["steel-chest"])
storage_container.name = "farming-storage-container"
storage_container.localised_name = {"entity-name.farming-storage-container"}
storage_container.localised_description = {"entity-description.farming-storage-container"}
storage_container.inventory_size = 10000

data:extend({storage_container})
