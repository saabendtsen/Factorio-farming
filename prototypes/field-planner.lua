data:extend({
  {
    type = "selection-tool",
    name = "farming-field-planner",
    localised_name = {"item-name.farming-field-planner"},
    localised_description = {"item-description.farming-field-planner"},
    icon = "__base__/graphics/icons/deconstruction-planner.png",
    icon_size = 64,
    flags = {"only-in-cursor", "spawnable", "not-stackable"},
    subgroup = "tool",
    order = "c[automated-construction]-z[farming-field-planner]",
    stack_size = 1,
    always_include_tiles = true,
    select = {
      border_color = {0.25, 0.85, 0.25},
      cursor_box_type = "entity",
      mode = {"any-tile"}
    },
    alt_select = {
      border_color = {0.85, 0.25, 0.25},
      cursor_box_type = "not-allowed",
      mode = {"nothing"}
    }
  }
})
