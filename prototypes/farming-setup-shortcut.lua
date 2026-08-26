data:extend({
  {
    type = "shortcut",
    name = "farming-setup",
    order = "b[farming]-a[setup]",
    action = "lua",
    icon = "__base__/graphics/icons/car.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/car.png",
    small_icon_size = 64,
    localised_name = {"shortcut-name.farming-setup"},
    associated_control_input = "farming-setup"
  },
  {
    type = "custom-input",
    name = "farming-setup",
    key_sequence = "CONTROL + F",
    consuming = "none"
  }
})
