extends Node2D

const IDLE_TEXTURE := preload("res://assets/characters/liulan/xiuer-video-replica-idle-v2-enhanced.png")
const MOVE_TEXTURE := preload("res://assets/characters/liulan/xiuer-regal-glide-loop-v3.png")
const JUMP_TEXTURE := preload("res://assets/characters/liulan/xiuer-idle-motion-jump-v1.png")
const CELL_SIZE := Vector2(512.0, 512.0)
const MOVE_CELL_SIZE := Vector2(896.0, 896.0)
const BASE_POSITION := Vector2(480.0, 365.0)
const DISPLAY_SCALE := 0.32
const MOVE_DISPLAY_SCALE := 0.27
const IDLE_FRAME_DURATION := 0.10
const MOVE_FRAME_DURATION := 0.06
const MOVE_SPEED := 500.0
const STAGE_LEFT := 128.0
const STAGE_RIGHT := 832.0
const IDLE_Y_OFFSETS := [0.0, 0.0, 0.0, 42.0, 48.0, 42.0]
const MOVE_LOOP_FRAME_COUNT := 5
const JUMP_SPEED := -620.0
const SECOND_JUMP_SPEED := -590.0
const GRAVITY := 1550.0
const MAX_FALL_SPEED := 780.0
const MAX_JUMPS := 2
const TELEPORT_DISTANCE := 300.0
const AIR_DASH_DISTANCE := 240.0
const TELEPORT_DURATION := 0.24
const TELEPORT_COOLDOWN := 0.62

enum MotionState { IDLE, START, MOVE, STOP, JUMP, TELEPORT }

var _character: Sprite2D
var _state := MotionState.IDLE
var _frame_index := 0
var _frame_clock := 0.0
var _horizontal_speed := 0.0
var _facing := 1.0
var _teleport_clock := 0.0
var _teleport_cooldown := 0.0
var _teleport_direction := 1.0
var _teleport_origin := Vector2.ZERO
var _teleport_target := Vector2.ZERO
var _teleport_moved := false
var _afterimages: Array[Sprite2D] = []
var _vertical_speed := 0.0
var _jumps_used := 0
var _on_ground := true
var _jump_anim_clock := 0.0
var _air_dash_used := false
var _teleport_started_airborne := false
var _teleport_saved_vertical_speed := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("d7deea"))
	_character = Sprite2D.new()
	_character.centered = true
	_character.region_enabled = true
	_character.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_character.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	_character.position = BASE_POSITION
	add_child(_character)
	_enter_state(MotionState.IDLE)
	queue_redraw()


func _process(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	_teleport_cooldown = maxf(0.0, _teleport_cooldown - delta)
	var can_air_dash := not _on_ground and not _air_dash_used
	if _state != MotionState.TELEPORT and (_on_ground or can_air_dash) and Input.is_action_just_pressed("dash") and _teleport_cooldown <= 0.0:
		_start_teleport(axis)
	if _state != MotionState.TELEPORT and Input.is_action_just_pressed("jump"):
		_try_jump()

	if _state == MotionState.TELEPORT:
		_update_teleport(delta, axis)
	else:
		_update_state_from_input(axis)
		_update_velocity(delta, axis)
		_update_animation(delta)
		_character.position.x = clampf(_character.position.x + _horizontal_speed * delta, STAGE_LEFT, STAGE_RIGHT)
		_update_vertical_motion(delta, axis)
	_update_continuous_motion(delta)
	queue_redraw()


func _update_continuous_motion(delta: float) -> void:
	var moving := _state == MotionState.START or _state == MotionState.MOVE or _state == MotionState.STOP

	if _state == MotionState.TELEPORT:
		_character.rotation = 0.0
		var teleport_scale := DISPLAY_SCALE if _teleport_started_airborne else MOVE_DISPLAY_SCALE
		_character.scale = Vector2(teleport_scale, teleport_scale)
		return
	if _state == MotionState.JUMP:
		_character.rotation = 0.0
		_character.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
		return
	if not moving:
		_character.rotation = 0.0
		_character.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
		return

	# Breathing follows a five-frame out-and-back cape wave. Keep the world
	# anchor stable instead of adding procedural vertical bob.
	_character.position.y = BASE_POSITION.y
	_character.rotation = 0.0
	_character.scale = Vector2(MOVE_DISPLAY_SCALE, MOVE_DISPLAY_SCALE)


func _update_state_from_input(axis: float) -> void:
	if absf(axis) > 0.01:
		_facing = signf(axis)
		_character.flip_h = _facing < 0.0
	if _state == MotionState.JUMP:
		return

	match _state:
		MotionState.IDLE:
			if absf(axis) > 0.01:
				_enter_state(MotionState.START)
		MotionState.START, MotionState.MOVE:
			if absf(axis) <= 0.01:
				_enter_state(MotionState.STOP)
		MotionState.STOP:
			if absf(axis) > 0.01:
				_enter_state(MotionState.START)
		MotionState.TELEPORT:
			pass


func _update_velocity(delta: float, axis: float) -> void:
	# Input response is deliberately direct. The start/stop drawings are visual
	# transitions only and never delay horizontal control.
	var _unused_delta := delta
	match _state:
		MotionState.START, MotionState.MOVE:
			_horizontal_speed = _facing * MOVE_SPEED
		MotionState.STOP:
			_horizontal_speed = 0.0
		MotionState.JUMP:
			_horizontal_speed = axis * MOVE_SPEED
		MotionState.IDLE:
			_horizontal_speed = 0.0
		MotionState.TELEPORT:
			_horizontal_speed = 0.0


func _update_animation(delta: float) -> void:
	if _state == MotionState.JUMP:
		_update_jump_animation(delta)
		return
	_frame_clock += delta
	var duration := IDLE_FRAME_DURATION if _state == MotionState.IDLE else MOVE_FRAME_DURATION
	while _frame_clock >= duration:
		_frame_clock -= duration
		_advance_frame()


func _advance_frame() -> void:
	match _state:
		MotionState.IDLE:
			_frame_index = (_frame_index + 1) % 6
			_set_idle_frame(_frame_index)
		MotionState.START:
			_enter_state(MotionState.MOVE)
		MotionState.MOVE:
			_frame_index = (_frame_index + 1) % MOVE_LOOP_FRAME_COUNT
			_set_move_frame(_frame_index)
		MotionState.STOP:
			_enter_state(MotionState.IDLE)
		MotionState.JUMP:
			pass
		MotionState.TELEPORT:
			pass


func _enter_state(next_state: MotionState) -> void:
	_state = next_state
	_frame_clock = 0.0
	match _state:
		MotionState.IDLE:
			_frame_index = 0
			_set_idle_frame(0)
		MotionState.START:
			_frame_index = 0
			_set_move_frame(0)
		MotionState.MOVE:
			_frame_index = 0
			_set_move_frame(0)
		MotionState.STOP:
			_frame_index = MOVE_LOOP_FRAME_COUNT - 1
			_set_move_frame(_frame_index)
		MotionState.JUMP:
			_frame_index = 0
			_set_jump_frame(0)
		MotionState.TELEPORT:
			_frame_index = clampi(_frame_index, 0, MOVE_LOOP_FRAME_COUNT - 1)
			_set_move_frame(_frame_index)


func _set_idle_frame(frame: int) -> void:
	_character.material = null
	_character.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	_character.texture = IDLE_TEXTURE
	_character.region_enabled = true
	_character.region_rect = Rect2(Vector2(frame % 3, frame / 3) * CELL_SIZE, CELL_SIZE)
	_character.position.y = BASE_POSITION.y + IDLE_Y_OFFSETS[frame] * DISPLAY_SCALE


func _set_move_frame(frame: int) -> void:
	_character.material = null
	_character.scale = Vector2(MOVE_DISPLAY_SCALE, MOVE_DISPLAY_SCALE)
	_character.texture = MOVE_TEXTURE
	_character.region_enabled = true
	_character.region_rect = Rect2(Vector2(frame % 3, frame / 3) * MOVE_CELL_SIZE, MOVE_CELL_SIZE)
	# Five-frame regal glide: normal -> transition -> crest -> transition -> normal.
	_character.position.y = BASE_POSITION.y


func _set_jump_frame(frame: int) -> void:
	_character.material = null
	_character.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	_character.texture = JUMP_TEXTURE
	_character.region_enabled = true
	_character.region_rect = Rect2(Vector2(frame % 3, frame / 3) * CELL_SIZE, CELL_SIZE)


func _try_jump() -> void:
	if _jumps_used >= MAX_JUMPS:
		return
	_jumps_used += 1
	_on_ground = false
	_vertical_speed = JUMP_SPEED if _jumps_used == 1 else SECOND_JUMP_SPEED
	_jump_anim_clock = 0.0
	_enter_state(MotionState.JUMP)


func _update_jump_animation(delta: float) -> void:
	_jump_anim_clock += delta
	var next_frame := 0
	if _jump_anim_clock < 0.07:
		next_frame = 0
	elif _vertical_speed < -350.0:
		next_frame = 1
	elif _vertical_speed < -120.0:
		next_frame = 2
	elif _vertical_speed < 80.0:
		next_frame = 3
	elif _vertical_speed < 260.0:
		next_frame = 4
	else:
		next_frame = 5
	if next_frame != _frame_index:
		_frame_index = next_frame
		_set_jump_frame(_frame_index)


func _update_vertical_motion(delta: float, axis: float) -> void:
	if _on_ground:
		return
	_vertical_speed = minf(_vertical_speed + GRAVITY * delta, MAX_FALL_SPEED)
	_character.position.y += _vertical_speed * delta
	if _character.position.y < BASE_POSITION.y:
		return
	_character.position.y = BASE_POSITION.y
	_vertical_speed = 0.0
	_on_ground = true
	_jumps_used = 0
	_air_dash_used = false
	if absf(axis) > 0.01:
		_enter_state(MotionState.MOVE)
	else:
		_enter_state(MotionState.IDLE)


func _start_teleport(axis: float) -> void:
	_teleport_started_airborne = not _on_ground
	_teleport_saved_vertical_speed = _vertical_speed
	if _teleport_started_airborne:
		_air_dash_used = true
	_teleport_direction = signf(axis) if absf(axis) > 0.01 else _facing
	_facing = _teleport_direction
	_character.flip_h = _facing < 0.0
	_teleport_origin = _character.position
	var distance := AIR_DASH_DISTANCE if _teleport_started_airborne else TELEPORT_DISTANCE
	var target_y := _teleport_origin.y if _teleport_started_airborne else BASE_POSITION.y
	_teleport_target = Vector2(
		clampf(_teleport_origin.x + _teleport_direction * distance, STAGE_LEFT, STAGE_RIGHT),
		target_y
	)
	_teleport_clock = 0.0
	_teleport_cooldown = TELEPORT_COOLDOWN
	_teleport_moved = false
	_horizontal_speed = 0.0
	_enter_state(MotionState.TELEPORT)
	if _teleport_started_airborne:
		_set_jump_frame(1 if _teleport_saved_vertical_speed < 0.0 else 3)
	_create_afterimages()


func _update_teleport(delta: float, axis: float) -> void:
	_teleport_clock += delta
	var phase := clampf(_teleport_clock / TELEPORT_DURATION, 0.0, 1.0)

	if phase < 0.22:
		_character.visible = true
		_character.modulate = Color.WHITE
	elif phase < 0.48:
		_character.visible = true
		_character.modulate = Color(1.0, 1.0, 1.0, 1.0 - (phase - 0.22) / 0.26)
	elif phase < 0.70:
		_character.visible = false
		if not _teleport_moved:
			_character.position = _teleport_target
			_teleport_moved = true
	else:
		_character.visible = true
		_character.modulate = Color(1.0, 1.0, 1.0, (phase - 0.70) / 0.30)

	_update_afterimages(phase)
	if _teleport_clock >= TELEPORT_DURATION:
		_finish_teleport(axis)


func _create_afterimages() -> void:
	_clear_afterimages()
	for index in range(5):
		var ghost := Sprite2D.new()
		ghost.texture = _character.texture
		ghost.region_enabled = _character.region_enabled
		ghost.region_rect = _character.region_rect
		ghost.centered = true
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ghost.scale = _character.scale
		ghost.flip_h = _character.flip_h
		ghost.position = _teleport_origin - Vector2(_teleport_direction * (index + 1) * 18.0, index * 1.5)
		ghost.modulate = Color(0.42, 0.36, 0.56, 0.0)
		add_child(ghost)
		_afterimages.append(ghost)


func _update_afterimages(phase: float) -> void:
	for index in range(_afterimages.size()):
		var ghost := _afterimages[index]
		if phase < 0.16 or phase > 0.72:
			ghost.visible = false
			continue
		ghost.visible = true
		var fade := 1.0 - absf(phase - 0.40) / 0.32
		ghost.modulate.a = clampf(fade * (0.34 - index * 0.05), 0.0, 0.34)
		ghost.scale = _character.scale
		ghost.position.x = lerpf(
			_teleport_origin.x - _teleport_direction * (index + 1) * 22.0,
			_teleport_target.x - _teleport_direction * (index + 1) * 38.0,
			clampf((phase - 0.16) / 0.44, 0.0, 1.0)
		)


func _finish_teleport(axis: float) -> void:
	_character.position = _teleport_target
	_character.visible = true
	_character.modulate = Color.WHITE
	_clear_afterimages()
	if _teleport_started_airborne:
		_vertical_speed = _teleport_saved_vertical_speed
		_state = MotionState.JUMP
		_frame_clock = 0.0
		_set_jump_frame(1 if _vertical_speed < 0.0 else 3)
		_teleport_started_airborne = false
		return
	_character.position.y = BASE_POSITION.y
	if absf(axis) > 0.01:
		_enter_state(MotionState.MOVE)
	else:
		_enter_state(MotionState.IDLE)


func _clear_afterimages() -> void:
	for ghost in _afterimages:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_afterimages.clear()


func _state_name() -> String:
	match _state:
		MotionState.START:
			return "start"
		MotionState.MOVE:
			return "move"
		MotionState.STOP:
			return "stop"
		MotionState.JUMP:
			return "jump-%d" % _jumps_used
		MotionState.TELEPORT:
			return "teleport"
		_:
			return "idle"


func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("d7deea"))
	draw_rect(Rect2(0, 418, 960, 122), Color("c5cfdd"))
	draw_line(Vector2(0, 418), Vector2(960, 418), Color(0.36, 0.43, 0.55, 0.35), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(28, 38), "修尔 · 王者悬行与二段跳验证 v7", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("283047"))
	draw_string(ThemeDB.fallback_font, Vector2(28, 66), "A/D高速悬行 · Space/K二段跳 · 空中L冲刺一次 · 5帧闭环披风", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.25, 0.29, 0.40, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(770, 38), "状态：%s" % _state_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("283047"))
