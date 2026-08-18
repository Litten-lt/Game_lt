extends CharacterBody2D

const WALK_SPEED := 150.0
const RUN_SPEED := 320.0
const GROUND_ACCEL := 1800.0
const AIR_ACCEL := 900.0
const GRAVITY := 1450.0
const JUMP_VELOCITY := -470.0
const MAX_JUMPS := 2
const DASH_DISTANCE := 260.0
const DASH_DURATION := 0.30
const DASH_COOLDOWN := 0.45
const BASE_SCALE := 0.36
const RUN_SCALE := 0.33
const AFTERIMAGE_INTERVAL := 0.045
const AFTERIMAGE_LIFETIME := 0.22
const ATTACK_FRAME_DURATIONS := [
	[0.06, 0.05, 0.04, 0.04, 0.07, 0.04, 0.05, 0.10],
	[0.08, 0.05, 0.04, 0.04, 0.04, 0.05, 0.08, 0.04, 0.05, 0.08],
	[0.12, 0.04, 0.04, 0.04, 0.04, 0.08, 0.05, 0.04, 0.07, 0.12],
]
const ATTACK_MOVE_SPEEDS := [185.0, 85.0, 625.0]
const ATTACK_MOVE_LAST_FRAMES := [5, 5, 5]
@onready var sprite: Sprite2D = $Sprite2D
@onready var dash_dust: Sprite2D = $DashDust
var animations: Dictionary = {}
var current_animation := "idle"
var frame_index := 0
var frame_time := 0.0
var jumps_used := 0
var facing := 1.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_start_x := 0.0
var dash_target_x := 0.0
var dash_dust_origin := Vector2.ZERO
var afterimage_time := 0.0
var jump_floor_y := 0.0
var attack_stage := 0
var attack_queued := false

func _ready() -> void:
	animations = {
		"idle": [_load_frames("idle", 8), 8.0, true],
		"walk": [_load_frames("walk", 12), 8.0, true],
		"run": [_load_frames("run", 11), 12.0, true],
		"jump": [_load_frames("jump", 17), 12.0, false],
		"dash": [_load_frames("dash", 17), 14.0, false],
		"attack_1": [_load_frames("attack_1", 8), 0.0, false],
		"attack_2": [_load_frames("attack_2", 10), 0.0, false],
		"attack_3": [_load_frames("attack_3", 10), 0.0, false],
	}
	for animation_name in animations:
		assert(not (animations[animation_name][0] as Array).is_empty())
	sprite.texture = (animations["idle"][0] as Array)[0]
	dash_dust.texture = load("res://assets/characters/xiaoguang/effects/dash_dust.png")
	dash_dust.top_level = true
	dash_dust.visible = false
	jump_floor_y = global_position.y

func _physics_process(delta: float) -> void:
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	var axis := Input.get_axis("move_left", "move_right")
	if absf(axis) > 0.01:
		if attack_stage == 0:
			facing = signf(axis)

	if Input.is_action_just_pressed("attack"):
		if attack_stage > 0:
			attack_queued = attack_stage < 3
		elif dash_time <= 0.0 and is_on_floor():
			_start_attack(1)

	if Input.is_action_just_pressed("dash") and attack_stage == 0 and dash_time <= 0.0 and dash_cooldown <= 0.0:
		_start_dash()

	if attack_stage > 0:
		_update_attack_motion(delta)
	elif dash_time > 0.0:
		_update_dash(delta)
	else:
		dash_dust.visible = false
		if is_on_floor():
			jumps_used = 0
			jump_floor_y = global_position.y
		if Input.is_action_just_pressed("jump") and jumps_used < MAX_JUMPS:
			jumps_used += 1
			velocity.y = JUMP_VELOCITY
			_set_animation("jump")
		var running := Input.is_key_pressed(KEY_SHIFT) and absf(axis) > 0.01
		var target_speed := axis * (RUN_SPEED if running else WALK_SPEED)
		velocity.x = move_toward(velocity.x, target_speed, (GROUND_ACCEL if is_on_floor() else AIR_ACCEL) * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta

	move_and_slide()
	if is_on_floor():
		jumps_used = 0
		jump_floor_y = global_position.y

	if attack_stage > 0:
		pass
	elif dash_time > 0.0:
		_set_animation("dash")
	elif not is_on_floor():
		_set_animation("jump")
	elif absf(axis) > 0.01:
		_set_animation("run" if Input.is_key_pressed(KEY_SHIFT) else "walk")
	else:
		_set_animation("idle")
	_update_visual_scale(delta)
	if attack_stage > 0:
		_advance_attack(delta)
	else:
		_advance_animation(delta)

func _start_attack(stage: int) -> void:
	attack_stage = stage
	attack_queued = false
	velocity = Vector2.ZERO
	_set_animation("attack_%d" % attack_stage)

func _update_attack_motion(delta: float) -> void:
	var last_move_frame: int = int(ATTACK_MOVE_LAST_FRAMES[attack_stage - 1])
	var move_speed: float = float(ATTACK_MOVE_SPEEDS[attack_stage - 1])
	var moving: bool = frame_index <= last_move_frame
	velocity.x = facing * move_speed if moving else 0.0
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

func _advance_attack(delta: float) -> void:
	var animation_data: Array = animations[current_animation] as Array
	var frames: Array = animation_data[0] as Array
	var durations: Array = ATTACK_FRAME_DURATIONS[attack_stage - 1] as Array
	frame_time += delta
	while frame_time >= float(durations[frame_index]):
		frame_time -= float(durations[frame_index])
		frame_index += 1
		if frame_index >= frames.size():
			if attack_queued and attack_stage < 3:
				_start_attack(attack_stage + 1)
				animation_data = animations[current_animation] as Array
				frames = animation_data[0] as Array
			else:
				attack_stage = 0
				attack_queued = false
				velocity.x = 0.0
				_set_animation("idle")
				animation_data = animations[current_animation] as Array
				frames = animation_data[0] as Array
			break
	sprite.texture = frames[frame_index]

func _start_dash() -> void:
	dash_time = DASH_DURATION
	dash_cooldown = DASH_COOLDOWN
	dash_start_x = global_position.x
	dash_target_x = dash_start_x + facing * DASH_DISTANCE
	dash_dust_origin = Vector2(dash_start_x - facing * 78.0, global_position.y - 2.0)
	afterimage_time = 0.0
	velocity = Vector2.ZERO
	_set_animation("dash")

func _update_dash(delta: float) -> void:
	dash_time = maxf(0.0, dash_time - delta)
	var progress := 1.0 - dash_time / DASH_DURATION
	var move_progress := clampf((progress - 0.28) / 0.44, 0.0, 1.0)
	move_progress = 1.0 - pow(1.0 - move_progress, 3.0)
	var desired_x := lerpf(dash_start_x, dash_target_x, move_progress)
	velocity = Vector2((desired_x - global_position.x) / maxf(delta, 0.0001), 0.0)
	dash_dust.visible = progress >= 0.28 and progress < 0.78
	dash_dust.global_position = dash_dust_origin
	dash_dust.scale = Vector2(-0.36 if facing > 0.0 else 0.36, 0.36)
	dash_dust.modulate.a = clampf((0.78 - progress) / 0.18, 0.0, 1.0)
	if progress >= 0.28 and progress < 0.72:
		afterimage_time -= delta
		if afterimage_time <= 0.0:
			afterimage_time = AFTERIMAGE_INTERVAL
			_spawn_afterimage()

func _set_animation(next_animation: String) -> void:
	if current_animation == next_animation:
		return
	current_animation = next_animation
	frame_index = 0
	frame_time = 0.0

func _update_visual_scale(delta: float) -> void:
	var target := RUN_SCALE if current_animation == "run" else BASE_SCALE
	var magnitude := move_toward(absf(sprite.scale.x), target, delta * 1.8)
	sprite.scale = Vector2(-magnitude if facing < 0.0 else magnitude, magnitude)

func _spawn_afterimage() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.global_position = global_position
	ghost.scale = sprite.scale
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.texture_filter = sprite.texture_filter
	ghost.modulate = Color(0.48, 0.72, 0.95, 0.48)
	ghost.z_index = -1
	get_tree().current_scene.add_child(ghost)
	var tween := ghost.create_tween().set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_property(ghost, "position:x", ghost.position.x - facing * 22.0, AFTERIMAGE_LIFETIME)
	tween.chain().tween_callback(ghost.queue_free)

func _advance_animation(delta: float) -> void:
	var data: Array = animations[current_animation]
	var frames: Array = data[0]
	if current_animation == "jump":
		_update_jump_frame(frames)
		return
	if current_animation == "dash" and dash_time > 0.0:
		var progress := 1.0 - dash_time / DASH_DURATION
		if progress < 0.28:
			frame_index = clampi(int(progress / 0.28 * 7.0), 0, 6)
		elif progress < 0.72:
			frame_index = 10
		else:
			frame_index = clampi(15 + int((progress - 0.72) / 0.28 * 2.0), 15, 16)
		sprite.texture = frames[frame_index]
		return
	var fps: float = data[1]
	frame_time += delta
	while frame_time >= 1.0 / fps:
		frame_time -= 1.0 / fps
		frame_index += 1
		if frame_index >= frames.size():
			frame_index = 0 if data[2] else frames.size() - 1
	sprite.texture = frames[frame_index]

func _update_jump_frame(frames: Array) -> void:
	if velocity.y < 0.0:
		var rise_ratio := clampf(1.0 - absf(velocity.y) / absf(JUMP_VELOCITY), 0.0, 1.0)
		frame_index = mini(8, int(rise_ratio * 9.0))
	else:
		var height_left := maxf(0.0, jump_floor_y - global_position.y)
		frame_index = 9 if height_left > 70.0 else clampi(10 + int((70.0 - height_left) / 70.0 * 6.0), 10, 16)
	sprite.texture = frames[frame_index]

func _load_frames(folder: String, count: int) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index in range(count):
		var texture := load("res://assets/characters/xiaoguang/animations/%s/frame_%03d.png" % [folder, index]) as Texture2D
		if texture:
			frames.append(texture)
	return frames
