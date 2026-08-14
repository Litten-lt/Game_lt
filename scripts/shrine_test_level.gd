extends Node2D

const SEGMENT_WIDTH := 1280.0
const SEGMENT_COUNT := 4

@onready var player: CharacterBody2D = $NewSwordswoman
@onready var camera: Camera2D = $NewSwordswoman/Camera2D

func _ready() -> void:
	camera.limit_left = 0
	camera.limit_right = int(SEGMENT_WIDTH * SEGMENT_COUNT)
	camera.limit_top = 0
	camera.limit_bottom = 720
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0

