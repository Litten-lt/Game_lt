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
const U_CHARGE_IN_TIME := 0.40
const U_FADE_OUT_TIME := 0.16
const U_HIDDEN_TIME := 0.10
const U_REAPPEAR_HOLD_TIME := 1.00
const U_GROUND_FIRE_FRAME_TIME := 1.0 / 9.0
const U_GROUND_FIRE_SCALE := 0.36
# The Sprite2D remains centered. For the 1085x264 export, an authored floor
# origin at y=216 becomes a centered texture offset of 132-216 = -84.
const U_GROUND_FIRE_CENTERED_OFFSET_Y := -84.0
# Put Xiaoguang at the leading edge; the long flame strip trails behind her.
const U_GROUND_FIRE_LEAD_OFFSET_X := -420.0
const U_POSE_TRANSITION_TIME := 0.28
const U_POSE_HOLD_TIME := 0.18
const U_DURATION := U_CHARGE_IN_TIME + U_FADE_OUT_TIME + U_HIDDEN_TIME + U_REAPPEAR_HOLD_TIME + U_POSE_TRANSITION_TIME + U_POSE_HOLD_TIME
const U_DISTANCE := 480.0
const U_COOLDOWN := 2.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var dash_dust: Sprite2D = $DashDust
@onready var u_ground_fire: Sprite2D = $UGroundFire
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
var u_time := 0.0
var u_cooldown := 0.0
var u_teleported := false
var u_locked_facing := 1.0
var u_charge_frames: Array[Texture2D] = []
var u_reappear_charge_frames: Array[Texture2D] = []
var u_pose_frames: Array[Texture2D] = []
var u_afterimages_spawned := false
var u_ground_fire_frames: Array[Texture2D] = []

func _ready() -> void:
	animations = {
		"idle": [_load_frames("idle", 8), 8.0, true],
		"walk": [_load_frames("walk", 12), 8.0, true],
		"run": [_load_frames("run", 11), 12.0, true],
		"jump": [_load_frames("jump", 17), 12.0, false],
		"dash": [_load_frames("dash", 17), 14.0, false],
	}
	u_charge_frames = _load_frames("u_skill_charge", 9)
	u_reappear_charge_frames = _load_frames("u_skill_reappear_charge", 9)
	u_pose_frames = _load_frames("u_skill_pose", 6)
	u_ground_fire_frames = _load_effect_frames("u_skill/ground_fire", 8)
	assert(u_charge_frames.size() == 9 and u_reappear_charge_frames.size() == 9 and u_pose_frames.size() == 6 and u_ground_fire_frames.size() == 8)
	for animation_name in animations:
		assert(not (animations[animation_name][0] as Array).is_empty())
	sprite.texture = (animations["idle"][0] as Array)[0]
	dash_dust.texture = load("res://assets/characters/xiaoguang/effects/dash_dust.png")
	dash_dust.top_level = true
	dash_dust.visible = false
	u_ground_fire.visible = false
	jump_floor_y = global_position.y

func _physics_process(delta: float) -> void:
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	u_cooldown = maxf(0.0, u_cooldown - delta)
	var axis := Input.get_axis("move_left", "move_right")
	# A U skill locks its starting direction and all normal controls. Only the
	# regular L dash may cancel it.
	if u_time <= 0.0 and absf(axis) > 0.01:
		facing = signf(axis)

	if u_time > 0.0 and Input.is_action_just_pressed("dash") and dash_time <= 0.0 and dash_cooldown <= 0.0:
		_cancel_u_skill()
		_start_dash()
	elif Input.is_action_just_pressed("skill_u") and u_time <= 0.0 and dash_time <= 0.0 and u_cooldown <= 0.0 and is_on_floor():
		_start_u_skill()
	elif Input.is_action_just_pressed("dash") and dash_time <= 0.0 and u_time <= 0.0 and dash_cooldown <= 0.0:
		_start_dash()

	if u_time > 0.0:
		_update_u_skill(delta)
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

	if u_time > 0.0:
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
	# U skill owns its frame timing directly in _update_u_skill().
	if u_time <= 0.0:
		_advance_animation(delta)

func _start_u_skill() -> void:
	u_locked_facing = facing
	u_time = U_DURATION
	u_cooldown = U_COOLDOWN
	u_teleported = false
	u_afterimages_spawned = false
	u_ground_fire.visible = false
	velocity = Vector2.ZERO
	current_animation = "u_skill"
	frame_index = 0
	frame_time = 0.0

func _update_u_skill(delta: float) -> void:
	# Never allow held movement input to turn the character during the skill.
	facing = u_locked_facing
	u_time = maxf(0.0, u_time - delta)
	velocity = Vector2.ZERO
	var elapsed := U_DURATION - u_time
	# Preserve every authored idle-to-charge transition frame.
	if elapsed < U_CHARGE_IN_TIME:
		frame_index = clampi(int(elapsed / U_CHARGE_IN_TIME * 9.0), 0, 8)
		sprite.visible = true
		sprite.modulate.a = 1.0
		sprite.texture = u_charge_frames[frame_index]
	# Hold the final charge pose, then dissolve through character afterimages.
	elif elapsed < U_CHARGE_IN_TIME + U_FADE_OUT_TIME:
		sprite.texture = u_charge_frames[8]
		if not u_afterimages_spawned:
			u_afterimages_spawned = true
			_spawn_u_charge_afterimages()
		var fade_elapsed := elapsed - U_CHARGE_IN_TIME
		sprite.modulate.a = 1.0 - fade_elapsed / U_FADE_OUT_TIME
	elif elapsed < U_CHARGE_IN_TIME + U_FADE_OUT_TIME + U_HIDDEN_TIME:
		if not u_teleported:
			u_teleported = true
			var motion := Vector2(facing * U_DISTANCE, 0.0)
			# Test the path first, then perform exactly the safe travel once.
			var collision := move_and_collide(motion, true)
			if collision:
				motion = collision.get_travel()
			move_and_collide(motion)
		sprite.visible = false
	else:
		sprite.visible = true
		sprite.modulate.a = 1.0
		var recovery_elapsed := elapsed - U_CHARGE_IN_TIME - U_FADE_OUT_TIME - U_HIDDEN_TIME
		# Reappear in the final charge pose and hold for exactly one second.
		if recovery_elapsed < U_REAPPEAR_HOLD_TIME:
			frame_index = clampi(int(recovery_elapsed / U_REAPPEAR_HOLD_TIME * float(u_reappear_charge_frames.size())), 0, u_reappear_charge_frames.size() - 1)
			sprite.texture = u_reappear_charge_frames[frame_index]
		else:
			var pose_elapsed := recovery_elapsed - U_REAPPEAR_HOLD_TIME
			frame_index = clampi(int(pose_elapsed / U_POSE_TRANSITION_TIME * 6.0), 0, 5) if pose_elapsed < U_POSE_TRANSITION_TIME else 5
			sprite.texture = u_pose_frames[frame_index]
		# Play the user-curated grounded sequence once when Xiaoguang reappears.
		var fire_duration := U_GROUND_FIRE_FRAME_TIME * float(u_ground_fire_frames.size())
		if recovery_elapsed < fire_duration:
			u_ground_fire.visible = true
			var fire_index := clampi(int(recovery_elapsed / U_GROUND_FIRE_FRAME_TIME), 0, u_ground_fire_frames.size() - 1)
			u_ground_fire.texture = u_ground_fire_frames[fire_index]
			# Align the exported y=216 floor anchor with the character's floor point.
			u_ground_fire.global_position = global_position
			u_ground_fire.offset.x = U_GROUND_FIRE_LEAD_OFFSET_X
			u_ground_fire.offset.y = U_GROUND_FIRE_CENTERED_OFFSET_Y
			u_ground_fire.scale = Vector2(U_GROUND_FIRE_SCALE * facing, U_GROUND_FIRE_SCALE)
			u_ground_fire.modulate = Color(1.15, 1.05, 1.05, 1.0)
		else:
			u_ground_fire.visible = false
	if u_time <= 0.0:
		u_ground_fire.visible = false
		sprite.visible = true
		sprite.modulate.a = 1.0
		current_animation = "idle"
		frame_index = 0

func _cancel_u_skill() -> void:
	u_time = 0.0
	u_teleported = false
	u_afterimages_spawned = false
	u_ground_fire.visible = false
	sprite.visible = true
	sprite.modulate = Color.WHITE
	velocity = Vector2.ZERO
	current_animation = "idle"
	frame_index = 0
	frame_time = 0.0

func _spawn_u_charge_afterimages() -> void:
	for index in range(3):
		var ghost := Sprite2D.new()
		ghost.texture = u_charge_frames[8]
		ghost.global_position = global_position + Vector2(-facing * float(index + 1) * 14.0, 0.0)
		ghost.scale = sprite.scale
		ghost.centered = sprite.centered
		ghost.offset = sprite.offset
		ghost.texture_filter = sprite.texture_filter
		ghost.modulate = Color(0.9, 0.25, 0.3, 0.34 - index * 0.07)
		ghost.z_index = -1
		get_tree().current_scene.add_child(ghost)
		var tween := ghost.create_tween().set_parallel(true)
		tween.tween_property(ghost, "modulate:a", 0.0, 0.20 + index * 0.035)
		tween.tween_property(ghost, "position:x", ghost.position.x - facing * 28.0, 0.20 + index * 0.035)
		tween.chain().tween_callback(ghost.queue_free)

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

func _load_effect_frames(folder: String, count: int) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index in range(count):
		var texture := load("res://assets/characters/xiaoguang/effects/%s/frame_%03d.png" % [folder, index]) as Texture2D
		if texture:
			frames.append(texture)
	return frames
