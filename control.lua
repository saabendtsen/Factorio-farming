local slice = require("scripts.slice")

script.on_init(slice.on_init)
script.on_load(slice.on_load)
script.on_configuration_changed(slice.on_configuration_changed)

script.on_event(defines.events.on_player_selected_area, slice.on_selected_area)
script.on_event(defines.events.on_script_path_request_finished, slice.on_path_finished)
script.on_event(defines.events.on_object_destroyed, slice.on_object_destroyed)
script.on_event(defines.events.on_tick, slice.on_tick)

commands.add_command("farming-slice-setup", "Create or reuse the slice tractor and field planner.", function(command)
  local player = game.get_player(command.player_index)
  if player then slice.setup(player) end
end)

commands.add_command("farming-slice-pause", "Pause the active slice job.", function(command)
  local player = game.get_player(command.player_index)
  if player then slice.pause(player) end
end)

commands.add_command("farming-slice-resume", "Resume the paused or failed slice job.", function(command)
  local player = game.get_player(command.player_index)
  if player then slice.resume(player) end
end)

remote.add_interface("factorio_farming", {
  debug_setup = slice.debug_setup,
  debug_pause = slice.debug_pause,
  debug_resume = slice.debug_resume,
  debug_destroy_tractor = slice.debug_destroy_tractor,
  debug_replace_tractor = slice.debug_replace_tractor,
  snapshot = slice.snapshot,
  debug_profile_start = slice.debug_profile_start,
  debug_profile_stop = slice.debug_profile_stop,
  clear_visuals = slice.clear_visuals,
  rebuild_visuals = slice.rebuild_visuals
})
