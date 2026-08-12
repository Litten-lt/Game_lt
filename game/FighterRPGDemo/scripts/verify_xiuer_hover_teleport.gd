extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait_frames(8)
	var main: Node = current_scene
	var player: CharacterBody2D = main.get_node("Xiuer")
	var start_x: float = player.position.x

	Input.action_press("move_right")
	await create_timer(0.35).timeout
	var moved_x: float = player.position.x
	if moved_x - start_x < 40.0:
		push_error("Hover movement did not move far enough")
		quit(1)
		return

	Input.action_release("move_right")
	var release_x: float = player.position.x
	await process_frame
	await process_frame
	if absf(player.position.x - release_x) > 1.0:
		push_error("Regal glide kept accelerating/decelerating after input release")
		quit(1)
		return

	player.call("_start_teleport", 1.0)
	var teleport_origin: Vector2 = player.get("_teleport_origin")
	var teleport_target: Vector2 = player.get("_teleport_target")
	await create_timer(0.11).timeout
	await create_timer(0.18).timeout
	var teleport_delta: float = teleport_target.x - teleport_origin.x
	if absf(player.position.x - teleport_target.x) > 2.0:
		push_error("Teleport did not finish at its target: current=%.1f target=%.1f state=%s" % [player.position.x, teleport_target.x, player.state_name()])
		quit(1)
		return

	print("XIUER_REGAL_GLIDE_TELEPORT_OK move=%.1f teleport=%.1f" % [moved_x - start_x, teleport_delta])
	quit()
