extends Node2D
## 主场景：地面、相机、背景绘制与调试状态显示

@onready var _player: CharacterBody2D = $Xiuer


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("d7deea"))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# 背景与地面
	draw_rect(Rect2(0, 0, 960, 540), Color("d7deea"))
	draw_rect(Rect2(0, 418, 960, 122), Color("c5cfdd"))
	draw_line(Vector2(0, 418), Vector2(960, 418), Color(0.36, 0.43, 0.55, 0.35), 1.0)

	# 标题与操作提示
	draw_string(ThemeDB.fallback_font, Vector2(28, 38), "修尔 · 王者悬行与二段跳验证 v8", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("283047"))
	draw_string(ThemeDB.fallback_font, Vector2(28, 66), "A/D高速悬行 · Space/K二段跳 · 空中L冲刺一次 · 土狼时间+跳跃缓存+可变跳高", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.25, 0.29, 0.40, 0.9))

	# 实时状态
	if _player and is_instance_valid(_player):
		draw_string(ThemeDB.fallback_font, Vector2(770, 38), "状态：%s" % _player.state_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("283047"))
