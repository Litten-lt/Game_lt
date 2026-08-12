extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _tap_jump() -> void:
	Input.action_press("jump")
	await process_frame
	Input.action_release("jump")
	await process_frame


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for _index in range(8):
		await process_frame
	var main: Node = current_scene
	var player: CharacterBody2D = main.get_node("Xiuer")
	var ground_y: float = player.position.y

	await _tap_jump()
	await create_timer(0.12).timeout
	var first_rise: float = ground_y - player.position.y
	if player.position.y >= ground_y - 20.0 or player.get("_jumps_used") != 1:
		push_error("First jump did not launch correctly")
		quit(1)
		return

	player.call("_try_jump")
	await process_frame
	var second_speed: float = player.velocity.y
	if player.get("_jumps_used") != 2 or second_speed >= -500.0:
		push_error("Second jump did not reset upward speed: jumps=%s speed=%.1f" % [player.get("_jumps_used"), second_speed])
		quit(1)
		return

	var dash_origin: Vector2 = player.position
	player.call("_start_teleport", 1.0)
	var dash_target: Vector2 = player.get("_teleport_target")
	await create_timer(0.27).timeout
	if absf(player.position.x - dash_target.x) > 3.0:
		push_error("Air dash did not reach its horizontal target")
		quit(1)
		return
	if absf(dash_target.y - dash_origin.y) > 0.5 or not player.get("_air_dash_used"):
		push_error("Air dash changed height or did not consume its air use")
		quit(1)
		return

	await create_timer(0.05).timeout
	var speed_before_third: float = player.velocity.y
	player.call("_try_jump")
	await process_frame
	var speed_after_third: float = player.velocity.y
	if player.get("_jumps_used") != 2 or speed_after_third < speed_before_third - 30.0:
		push_error("A third jump was incorrectly accepted")
		quit(1)
		return

	await create_timer(1.6).timeout
	if not player.is_on_floor() or absf(player.position.y - ground_y) > 0.5:
		push_error("Double jump did not land and reset cleanly: y=%.1f ground=%.1f state=%s" % [player.position.y, ground_y, player.state_name()])
		quit(1)
		return

	print("XIUER_DOUBLE_JUMP_OK rise=%.1f second_speed=%.1f" % [first_rise, second_speed])
	quit()
