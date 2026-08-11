extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _run() -> void:
	change_scene_to_file("res://idle_showcase.tscn")
	await _wait_frames(8)
	var showcase := current_scene
	var character := showcase.get_child(0) as Sprite2D
	var start_x := character.position.x

	Input.action_press("move_right")
	await create_timer(0.35).timeout
	var moved_x := character.position.x
	if moved_x - start_x < 40.0:
		push_error("Hover movement did not move far enough")
		quit(1)
		return

	Input.action_release("move_right")
	var release_x := character.position.x
	await process_frame
	await process_frame
	if absf(character.position.x - release_x) > 1.0:
		push_error("Regal glide kept accelerating/decelerating after input release")
		quit(1)
		return

	showcase.call("_start_teleport", 1.0)
	var teleport_origin: Vector2 = showcase.get("_teleport_origin")
	var teleport_target: Vector2 = showcase.get("_teleport_target")
	await create_timer(0.11).timeout
	await create_timer(0.18).timeout
	var teleport_delta := teleport_target.x - teleport_origin.x
	if absf(character.position.x - teleport_target.x) > 2.0:
		push_error("Teleport did not finish at its target: current=%.1f target=%.1f state=%s" % [character.position.x, teleport_target.x, showcase.call("_state_name")])
		quit(1)
		return

	print("XIUER_REGAL_GLIDE_TELEPORT_OK move=%.1f teleport=%.1f" % [moved_x - start_x, teleport_delta])
	quit()
