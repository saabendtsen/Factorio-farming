-- The storage container is a real placeable container: the entity mines back
-- to its own item, that item places the entity again, and one always-enabled
-- prototype-stage recipe supplies it without debug commands. It stays a plain
-- `container`, so nearby vanilla chests remain valid storage containers.
local storage_container = table.deepcopy(data.raw.container["steel-chest"])
storage_container.name = "farming-storage-container"
storage_container.localised_name = {"entity-name.farming-storage-container"}
storage_container.localised_description = {"entity-description.farming-storage-container"}
storage_container.inventory_size = 10000
storage_container.minable = {mining_time = 0.2, result = "farming-storage-container"}

local storage_item = table.deepcopy(data.raw.item["steel-chest"])
storage_item.name = "farming-storage-container"
storage_item.localised_name = {"item-name.farming-storage-container"}
storage_item.localised_description = {"item-description.farming-storage-container"}
storage_item.place_result = "farming-storage-container"
storage_item.order = "a[items]-c[farming-storage-container]"

-- Deliberately flat: the MVP wheat loop has no economy, tiers or logistics, so the
-- recipe is one hand-craftable step that is enabled from the start.
local storage_recipe = {
  type = "recipe",
  name = "farming-storage-container",
  localised_name = {"item-name.farming-storage-container"},
  categories = {"crafting"},
  enabled = true,
  energy_required = 0.5,
  ingredients = {{type = "item", name = "iron-plate", amount = 8}},
  results = {{type = "item", name = "farming-storage-container", amount = 1}}
}

data:extend({storage_container, storage_item, storage_recipe})
