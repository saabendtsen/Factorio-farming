local slice = require("scripts.slice")

script.on_init(slice.on_init)
script.on_load(slice.on_load)
script.on_configuration_changed(slice.on_configuration_changed)

script.on_event(defines.events.on_player_selected_area, slice.on_selected_area)
script.on_event(defines.events.on_lua_shortcut, slice.on_lua_shortcut)
script.on_event(defines.events.on_player_created, slice.on_player_created)
script.on_event(defines.events.on_player_joined_game, slice.on_player_joined_game)
script.on_event("farming-setup", slice.on_setup_input)
script.on_event(defines.events.on_script_path_request_finished, slice.on_path_finished)
script.on_event(defines.events.on_object_destroyed, slice.on_object_destroyed)
script.on_event(defines.events.on_gui_click, slice.on_gui_click)
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
  debug_start_next_operation = slice.debug_start_next_operation,
  debug_queue_field = slice.debug_queue_field,
  contextual_status = slice.contextual_status,
  debug_destroy_tractor = slice.debug_destroy_tractor,
  debug_destroy_tractor_by_id = slice.debug_destroy_tractor_by_id,
  debug_retry_queued_field_job = slice.debug_retry_queued_field_job,
  debug_replace_tractor = slice.debug_replace_tractor,
  debug_add_tractor = slice.debug_add_tractor,
  debug_reset_tractor_implement_overlays = slice.debug_reset_tractor_implement_overlays,
  debug_seed_crop_stage = slice.debug_seed_crop_stage,
  debug_mark_visuals_dirty = slice.debug_mark_visuals_dirty,
  debug_player_setup = slice.debug_player_setup,
  debug_player_planner_selection = slice.debug_player_planner_selection,
  debug_player_start_selected_operation = slice.debug_player_start_selected_operation,
  snapshot = slice.snapshot,
  debug_profile_start = slice.debug_profile_start,
  debug_profile_stop = slice.debug_profile_stop,
  clear_visuals = slice.clear_visuals,
  rebuild_visuals = slice.rebuild_visuals
})
