extends Node2D

const GROUND_Y := 610.0
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
const BASE_SCALE := 0.72
const RUN_SCALE := 0.66
const AFTERIMAGE_INTERVAL := 0.045
const AFTERIMAGE_LIFETIME := 0.22

@onready var sprite: Sprite2D = $Sprite2D
@onready var dash_dust: Sprite2D = $DashDust
@onready var afterimage_layer: Node2D = $Afterimages
var animations: Dictionary = {}
var current_animation := "idle"
var frame_index := 0
var frame_time := 0.0
var velocity := Vector2.ZERO
var jumps_used := 0
var facing := 1.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_start_x := 0.0
var dash_target_x := 0.0
var dash_dust_origin := Vector2.ZERO
var afterimage_time := 0.0

func _ready() -> void:
	animations = {
		"idle": [_load_frames("idle", 8), 8.0, true],
		"walk": [_load_frames("walk", 12), 8.0, true],
		"run": [_load_frames("run", 11), 12.0, true],
		"jump": [_load_frames("jump", 17), 12.0, false],
		"dash": [_load_frames("dash", 17), 14.0, false],
	}
	for animation_name in animations:
		assert(not (animations[animation_name][0] as Array).is_empty())
	sprite.texture = (animations["idle"][0] as Array)[0]
	dash_dust.texture = load("res://assets/characters/xiaoguang/effects/dash_dust.png")
	dash_dust.visible = false

func _physics_process(delta: float) -> void:
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	var axis := Input.get_axis("move_left", "move_right")
	if absf(axis) > 0.01:
		facing = signf(axis)

	if Input.is_action_just_pressed("dash") and dash_time <= 0.0 and dash_cooldown <= 0.0:
		dash_time = DASH_DURATION
		dash_cooldown = DASH_COOLDOWN
		dash_start_x = sprite.position.x
		dash_target_x = clampf(dash_start_x + facing * DASH_DISTANCE, 210.0, 1070.0)
		dash_dust_origin = Vector2(dash_start_x - facing * 78.0, GROUND_Y - 2.0)
		afterimage_time = 0.0
		velocity.x = 0.0
		velocity.y = 0.0
		_set_animation("dash")

	if dash_time > 0.0:
		dash_time = maxf(0.0, dash_time - delta)
		velocity.x = 0.0
		var progress := 1.0 - dash_time / DASH_DURATION
		# 前 28% 蓄力，中间 44% 锁定姿势并位移，最后 28% 恢复。
		var move_progress := clampf((progress - 0.28) / 0.44, 0.0, 1.0)
		move_progress = 1.0 - pow(1.0 - move_progress, 3.0)
		sprite.position.x = lerpf(dash_start_x, dash_target_x, move_progress)
		dash_dust.visible = progress >= 0.28 and progress < 0.78
		dash_dust.position = dash_dust_origin
		dash_dust.scale = Vector2(-0.72 if facing > 0.0 else 0.72, 0.72)
		dash_dust.modulate.a = clampf((0.78 - progress) / 0.18, 0.0, 1.0)
		if progress >= 0.28 and progress < 0.72:
			afterimage_time -= delta
			if afterimage_time <= 0.0:
				afterimage_time = AFTERIMAGE_INTERVAL
				_spawn_afterimage()
	else:
		dash_dust.visible = false
		if Input.is_action_just_pressed("jump") and jumps_used < MAX_JUMPS:
			jumps_used += 1
			velocity.y = JUMP_VELOCITY
			_set_animation("jump")
		var running := Input.is_key_pressed(KEY_SHIFT) and absf(axis) > 0.01
		var target_speed := axis * (RUN_SPEED if running else WALK_SPEED)
		var accel := GROUND_ACCEL if _is_on_ground() else AIR_ACCEL
		velocity.x = move_toward(velocity.x, target_speed, accel * delta)
		velocity.y += GRAVITY * delta

	sprite.position += velocity * delta
	sprite.position.x = clampf(sprite.position.x, 210.0, 1070.0)
	if sprite.position.y >= GROUND_Y:
		sprite.position.y = GROUND_Y
		velocity.y = 0.0
		jumps_used = 0

	if dash_time > 0.0:
		_set_animation("dash")
	elif not _is_on_ground():
		_set_animation("jump")
	elif absf(axis) > 0.01:
		_set_animation("run" if Input.is_key_pressed(KEY_SHIFT) else "walk")
	else:
		_set_animation("idle")
	_update_visual_scale(delta)
	_advance_animation(delta)

func _is_on_ground() -> bool:
	return sprite.position.y >= GROUND_Y - 0.1 and velocity.y >= 0.0

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
	sprite.flip_h = false

func _spawn_afterimage() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.position = sprite.position
	ghost.scale = sprite.scale
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.texture_filter = sprite.texture_filter
	ghost.modulate = Color(0.48, 0.72, 0.95, 0.48)
	ghost.z_index = 0
	afterimage_layer.add_child(ghost)
	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_property(ghost, "position:x", ghost.position.x - facing * 22.0, AFTERIMAGE_LIFETIME)
	tween.chain().tween_callback(ghost.queue_free)

func _advance_animation(delta: float) -> void:
	var data: Array = animations[current_animation]
	var frames: Array = data[0]
	var fps: float = data[1]
	if current_animation == "jump":
		_update_jump_frame(frames)
		return
	if current_animation == "dash" and dash_time > 0.0:
		var dash_progress := 1.0 - dash_time / DASH_DURATION
		if dash_progress < 0.28:
			# 蓄力：0-6 帧。
			frame_index = clampi(int(dash_progress / 0.28 * 7.0), 0, 6)
		elif dash_progress < 0.72:
			# 位移：固定在低身冲刺姿势，跳过带截断灰尘的第 8 帧。
			frame_index = 10
		else:
			# 恢复：15-16 帧。
			frame_index = clampi(15 + int((dash_progress - 0.72) / 0.28 * 2.0), 15, 16)
		sprite.texture = frames[frame_index]
		return
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
		var height_left := maxf(0.0, GROUND_Y - sprite.position.y)
		if height_left > 70.0:
			frame_index = 9
		else:
			frame_index = clampi(10 + int((70.0 - height_left) / 70.0 * 6.0), 10, 16)
	sprite.texture = frames[frame_index]

func _load_frames(folder: String, count: int) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index in range(count):
		var texture := load("res://assets/characters/xiaoguang/animations/%s/frame_%03d.png" % [folder, index]) as Texture2D
		if texture:
			frames.append(texture)
	return frames
