extends CharacterBody2D

@export var target_path: NodePath
@export_range(0.0, 2000.0, 10.0) var detection_radius := 420.0
@export_range(0.0, 300.0, 1.0) var move_speed := 72.0
@export_range(0.0, 300.0, 1.0) var stop_distance := 76.0

const GRAVITY := 1450.0
const ANIMATION_FPS := 8.0
const FRAME_COUNTS := {
	"idle": 32,
	"crawl": 32,
}

@onready var sprite: Sprite2D = $Sprite2D

var target: CharacterBody2D
var animations: Dictionary = {}
var current_animation := "idle"
var frame_index := 0
var frame_time := 0.0


func _ready() -> void:
	target = get_node_or_null(target_path) as CharacterBody2D
	animations = {
		"idle": _load_frames("idle", FRAME_COUNTS.idle),
		"crawl": _load_frames("crawl", FRAME_COUNTS.crawl),
	}
	for animation_name in animations:
		assert(not (animations[animation_name] as Array).is_empty())
	sprite.texture = (animations.idle as Array)[0]


func _physics_process(delta: float) -> void:
	var should_chase := false
	if is_instance_valid(target):
		var horizontal_distance := absf(target.global_position.x - global_position.x)
		should_chase = horizontal_distance <= detection_radius and horizontal_distance > stop_distance
		if should_chase:
			var direction := signf(target.global_position.x - global_position.x)
			velocity.x = direction * move_speed
			sprite.flip_h = direction < 0.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)
	else:
		velocity.x = 0.0

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	move_and_slide()

	_set_animation("crawl" if should_chase else "idle")
	_advance_animation(delta)


func _set_animation(next_animation: String) -> void:
	if current_animation == next_animation:
		return
	current_animation = next_animation
	frame_index = 0
	frame_time = 0.0
	sprite.texture = (animations[current_animation] as Array)[0]


func _advance_animation(delta: float) -> void:
	var frames := animations[current_animation] as Array
	frame_time += delta
	while frame_time >= 1.0 / ANIMATION_FPS:
		frame_time -= 1.0 / ANIMATION_FPS
		frame_index = (frame_index + 1) % frames.size()
	sprite.texture = frames[frame_index]


func _load_frames(folder: String, count: int) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index in range(count):
		var path := "res://assets/monsters/rock_crown/animations/%s/frame_%03d.png" % [folder, index]
		var texture := load(path) as Texture2D
		if texture:
			frames.append(texture)
	return frames
