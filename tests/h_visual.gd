extends Node3D
# НЕ headless: --path . --fixed-fps 60 --quit-after 700 res://tests/h_visual.tscn
var _frame := 0
var gm: GameManager

func _ready() -> void:
	GameContext.select("sport", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	await get_tree().process_frame

func _physics_process(_dt: float) -> void:
	_frame += 1
	# слоу-мо задано в РЕАЛЬНЫХ секундах, а headless с --fixed-fps идёт ~1000 кадров/с:
	# фиксируем масштаб, иначе замер привязывается к скорости машины-хоста
	Engine.time_scale = 1.0
	if _frame == 5: Input.action_press("throttle")
	if _frame in [60, 150, 200, 215, 240, 300]:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tests/out/v%d.png" % _frame)
	if _frame == 301:
		Input.action_release("throttle")
		print("VIS done impact_seen=%s dents=%d depth=%.3f deform=%.2f" % [
			str(gm.car._recent_speed > 28), gm.car.body.dent_count, gm.car.body.max_depth, gm.car.body.deformation()])
		get_tree().quit(0)
