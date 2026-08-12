extends CharacterBody2D
## 修尔 — 暗属性精灵角色控制器
## 基础机动：待机、高速悬行、二段跳、地面瞬移、空中冲刺
## 手感特性：土狼时间、跳跃输入缓存、可变跳跃高度、起手收手过渡

# === 纹理资源 ===
const IDLE_TEXTURE := preload("res://assets/characters/xiuer/xiuer-video-replica-idle-v2-enhanced.png")
const MOVE_TEXTURE := preload("res://assets/characters/xiuer/xiuer-video-move-loop-v1.png")
const JUMP_TEXTURE := preload("res://assets/characters/xiuer/xiuer-idle-motion-jump-v1.png")

# === 图集参数 ===
const CELL_SIZE := Vector2(512.0, 512.0)
const MOVE_CELL_SIZE := Vector2(512.0, 512.0)
const DISPLAY_SCALE := 0.32
const MOVE_DISPLAY_SCALE := DISPLAY_SCALE

# === 动画时序 ===
const IDLE_FRAME_DURATION := 0.10
const MOVE_FRAME_DURATION := 1.0 / 12.0
const START_TRANSITION_DURATION := 0.08
const STOP_TRANSITION_DURATION := 0.08

# === 运动参数 ===
const MOVE_SPEED := 500.0
const JUMP_SPEED := -620.0
const SECOND_JUMP_SPEED := -590.0
const GRAVITY := 1550.0
const MAX_FALL_SPEED := 780.0
const MAX_JUMPS := 2

# === 手感参数 ===
const COYOTE_TIME := 0.10
const JUMP_BUFFER_TIME := 0.12
const JUMP_CUT_GRAVITY_MULTIPLIER := 2.5

# === 瞬移参数 ===
const TELEPORT_DISTANCE := 300.0
const AIR_DASH_DISTANCE := 240.0
const TELEPORT_DURATION := 0.24
const TELEPORT_COOLDOWN := 0.62

# === 活动边界（与原验证场景一致）===
const STAGE_LEFT := 128.0
const STAGE_RIGHT := 832.0

# === 图集注册补偿 ===
const IDLE_Y_OFFSETS := [0.0, 0.0, 0.0, 42.0, 48.0, 42.0]
const MOVE_LOOP_FRAME_COUNT := 121
const MOVE_ATLAS_COLUMNS := 11

enum MotionState { IDLE, START, MOVE, STOP, JUMP, TELEPORT }

@onready var _sprite: Sprite2D = $Sprite

# --- 状态 ---
var _state := MotionState.IDLE
var _frame_index := 0
var _frame_clock := 0.0
var _facing := 1.0
var _transition_timer := 0.0

# --- 跳跃 ---
var _jumps_used := 0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _jump_held := false

# --- 瞬移 ---
var _teleport_clock := 0.0
var _teleport_cooldown := 0.0
var _teleport_direction := 1.0
var _teleport_origin := Vector2.ZERO
var _teleport_target := Vector2.ZERO
var _teleport_moved := false
var _teleport_started_airborne := false
var _teleport_saved_vertical_speed := 0.0
var _air_dash_used := false
var _afterimages: Array[Sprite2D] = []


func _ready() -> void:
	_sprite.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	_enter_state(MotionState.IDLE)


func _physics_process(delta: float) -> void:
	# 计时器递减
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	_teleport_cooldown = maxf(0.0, _teleport_cooldown - delta)

	var axis := Input.get_axis("move_left", "move_right")

	# 跳跃输入缓存
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	_jump_held = Input.is_action_pressed("jump")

	# 瞬移输入
	var can_air_dash := not is_on_floor() and not _air_dash_used
	if _state != MotionState.TELEPORT and (is_on_floor() or can_air_dash) and Input.is_action_just_pressed("dash") and _teleport_cooldown <= 0.0:
		_start_teleport(axis)

	# 跳跃尝试（土狼时间 + 输入缓存）
	if _state != MotionState.TELEPORT and _jump_buffer_timer > 0.0:
		_try_jump()

	# 状态逻辑
	if _state == MotionState.TELEPORT:
		_update_teleport(delta, axis)
	else:
		_update_state_from_input(axis, delta)
		_update_velocity(axis)
		_update_animation(delta)
		_apply_gravity(delta)

	move_and_slide()
	_handle_floor_contact(delta)
	_update_sprite_transform()
	# 保持角色在活动区域内
	position.x = clampf(position.x, STAGE_LEFT, STAGE_RIGHT)


func _update_sprite_transform() -> void:
	# 统一管理精灵 scale / rotation，避免各状态函数重复设置
	match _state:
		MotionState.TELEPORT:
			_sprite.rotation = 0.0
			var teleport_scale := DISPLAY_SCALE if _teleport_started_airborne else MOVE_DISPLAY_SCALE
			_sprite.scale = Vector2(teleport_scale, teleport_scale)
		MotionState.JUMP, MotionState.IDLE:
			_sprite.rotation = 0.0
			_sprite.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
		_: # START, MOVE, STOP
			_sprite.rotation = 0.0
			_sprite.scale = Vector2(MOVE_DISPLAY_SCALE, MOVE_DISPLAY_SCALE)


func _update_state_from_input(axis: float, delta: float) -> void:
	if absf(axis) > 0.01:
		_facing = signf(axis)
		_sprite.flip_h = _facing < 0.0

	if _state == MotionState.JUMP:
		return

	match _state:
		MotionState.IDLE:
			if absf(axis) > 0.01:
				_enter_state(MotionState.START)
		MotionState.START:
			_transition_timer -= delta
			if _transition_timer <= 0.0:
				_enter_state(MotionState.MOVE)
			if absf(axis) <= 0.01:
				_enter_state(MotionState.STOP)
		MotionState.MOVE:
			if absf(axis) <= 0.01:
				_enter_state(MotionState.STOP)
		MotionState.STOP:
			_transition_timer -= delta
			if _transition_timer <= 0.0:
				_enter_state(MotionState.IDLE)
			if absf(axis) > 0.01:
				_enter_state(MotionState.START)


func _update_velocity(axis: float) -> void:
	# 输入响应直接：起手/收手只是动画过渡，不延迟水平控制
	match _state:
		MotionState.START, MotionState.MOVE:
			velocity.x = _facing * MOVE_SPEED
		MotionState.STOP, MotionState.IDLE:
			velocity.x = 0.0
		MotionState.JUMP:
			velocity.x = axis * MOVE_SPEED
		MotionState.TELEPORT:
			velocity.x = 0.0


func _apply_gravity(delta: float) -> void:
	# 跳跃状态下即使 is_on_floor() 仍为真（起跳首帧），也必须施加重力，
	# 否则 velocity.y 会被归零导致跳不起来。
	if is_on_floor() and _state != MotionState.JUMP:
		velocity.y = 0.0
		return
	var gravity := GRAVITY
	# 可变跳跃高度：松开跳键且仍在上升时，重力加倍，实现短跳
	if not _jump_held and velocity.y < 0.0:
		gravity *= JUMP_CUT_GRAVITY_MULTIPLIER
	velocity.y = minf(velocity.y + gravity * delta, MAX_FALL_SPEED)


func _handle_floor_contact(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = COYOTE_TIME
		_jumps_used = 0
		_air_dash_used = false
		if _state == MotionState.JUMP:
			var axis := Input.get_axis("move_left", "move_right")
			if absf(axis) > 0.01:
				_enter_state(MotionState.MOVE)
			else:
				_enter_state(MotionState.IDLE)
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)


func _try_jump() -> void:
	if _jumps_used == 0 and (is_on_floor() or _coyote_timer > 0.0):
		# 首跳（含土狼时间窗口）
		_jumps_used = 1
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		velocity.y = JUMP_SPEED
		_enter_state(MotionState.JUMP)
	elif _jumps_used == 1 and not is_on_floor():
		# 二段跳
		_jumps_used = 2
		_jump_buffer_timer = 0.0
		velocity.y = SECOND_JUMP_SPEED
		_enter_state(MotionState.JUMP)


func _update_animation(delta: float) -> void:
	if _state == MotionState.JUMP:
		_update_jump_animation()
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
		MotionState.START, MotionState.MOVE, MotionState.STOP:
			_frame_index = (_frame_index + 1) % MOVE_LOOP_FRAME_COUNT
			_set_move_frame(_frame_index)
		MotionState.JUMP, MotionState.TELEPORT:
			pass


func _enter_state(next_state: MotionState) -> void:
	_state = next_state
	_frame_clock = 0.0
	match _state:
		MotionState.IDLE:
			_frame_index = 0
			_set_idle_frame(0)
		MotionState.START:
			_transition_timer = START_TRANSITION_DURATION
			_frame_index = 0
			_set_move_frame(0)
		MotionState.MOVE:
			_frame_index = 0
			_set_move_frame(0)
		MotionState.STOP:
			_transition_timer = STOP_TRANSITION_DURATION
			# 保持当前移动帧继续播放，作为收手过渡
			_set_move_frame(_frame_index % MOVE_LOOP_FRAME_COUNT)
		MotionState.JUMP:
			_frame_index = 0
			_set_jump_frame(0)
		MotionState.TELEPORT:
			_frame_index = clampi(_frame_index, 0, MOVE_LOOP_FRAME_COUNT - 1)
			_set_move_frame(_frame_index)


func _set_idle_frame(frame: int) -> void:
	_sprite.texture = IDLE_TEXTURE
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(Vector2(frame % 3, frame / 3) * CELL_SIZE, CELL_SIZE)
	_sprite.position = Vector2(0.0, IDLE_Y_OFFSETS[frame] * DISPLAY_SCALE)


func _set_move_frame(frame: int) -> void:
	_sprite.texture = MOVE_TEXTURE
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(
		Vector2(frame % MOVE_ATLAS_COLUMNS, frame / MOVE_ATLAS_COLUMNS) * MOVE_CELL_SIZE,
		MOVE_CELL_SIZE
	)
	_sprite.position = Vector2.ZERO


func _set_jump_frame(frame: int) -> void:
	_sprite.texture = JUMP_TEXTURE
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(Vector2(frame % 3, frame / 3) * CELL_SIZE, CELL_SIZE)
	_sprite.position = Vector2.ZERO


func _update_jump_animation() -> void:
	# 按垂直速度分段切换跳跃帧（复用待机造型）
	var next_frame := 0
	if velocity.y < -350.0:
		next_frame = 1
	elif velocity.y < -120.0:
		next_frame = 2
	elif velocity.y < 80.0:
		next_frame = 3
	elif velocity.y < 260.0:
		next_frame = 4
	else:
		next_frame = 5
	if next_frame != _frame_index:
		_frame_index = next_frame
		_set_jump_frame(_frame_index)


func _start_teleport(axis: float) -> void:
	_teleport_started_airborne = not is_on_floor()
	_teleport_saved_vertical_speed = velocity.y
	if _teleport_started_airborne:
		_air_dash_used = true

	_teleport_direction = signf(axis) if absf(axis) > 0.01 else _facing
	_facing = _teleport_direction
	_sprite.flip_h = _facing < 0.0

	_teleport_origin = position
	var distance := AIR_DASH_DISTANCE if _teleport_started_airborne else TELEPORT_DISTANCE
	_teleport_target = Vector2(
		clampf(position.x + _teleport_direction * distance, STAGE_LEFT, STAGE_RIGHT),
		position.y
	)

	_teleport_clock = 0.0
	_teleport_cooldown = TELEPORT_COOLDOWN
	_teleport_moved = false
	velocity = Vector2.ZERO
	_enter_state(MotionState.TELEPORT)

	if _teleport_started_airborne:
		_set_jump_frame(1 if _teleport_saved_vertical_speed < 0.0 else 3)
	_create_afterimages()


func _update_teleport(delta: float, axis: float) -> void:
	_teleport_clock += delta
	var phase := clampf(_teleport_clock / TELEPORT_DURATION, 0.0, 1.0)

	if phase < 0.22:
		_sprite.visible = true
		_sprite.modulate = Color.WHITE
	elif phase < 0.48:
		_sprite.visible = true
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0 - (phase - 0.22) / 0.26)
	elif phase < 0.70:
		_sprite.visible = false
		if not _teleport_moved:
			position = _teleport_target
			_teleport_moved = true
	else:
		_sprite.visible = true
		_sprite.modulate = Color(1.0, 1.0, 1.0, (phase - 0.70) / 0.30)

	_update_afterimages(phase)
	if _teleport_clock >= TELEPORT_DURATION:
		_finish_teleport(axis)


func _finish_teleport(axis: float) -> void:
	position = _teleport_target
	_sprite.visible = true
	_sprite.modulate = Color.WHITE
	_clear_afterimages()

	if _teleport_started_airborne:
		velocity.y = _teleport_saved_vertical_speed
		velocity.x = 0.0
		_state = MotionState.JUMP
		_frame_clock = 0.0
		_set_jump_frame(1 if velocity.y < 0.0 else 3)
		_teleport_started_airborne = false
		return

	# 地面瞬移结束
	if absf(axis) > 0.01:
		_enter_state(MotionState.MOVE)
	else:
		_enter_state(MotionState.IDLE)


func _create_afterimages() -> void:
	_clear_afterimages()
	for index in range(5):
		var ghost := Sprite2D.new()
		ghost.texture = _sprite.texture
		ghost.region_enabled = _sprite.region_enabled
		ghost.region_rect = _sprite.region_rect
		ghost.centered = true
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ghost.scale = _sprite.scale
		ghost.flip_h = _sprite.flip_h
		ghost.position = _teleport_origin - Vector2(_teleport_direction * (index + 1) * 18.0, index * 1.5)
		ghost.modulate = Color(0.42, 0.36, 0.56, 0.0)
		# 加到父场景，避免残影跟随角色节点移动
		get_parent().add_child(ghost)
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
		ghost.scale = _sprite.scale
		ghost.position.x = lerpf(
			_teleport_origin.x - _teleport_direction * (index + 1) * 22.0,
			_teleport_target.x - _teleport_direction * (index + 1) * 38.0,
			clampf((phase - 0.16) / 0.44, 0.0, 1.0)
		)


func _clear_afterimages() -> void:
	for ghost in _afterimages:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_afterimages.clear()


func state_name() -> String:
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
