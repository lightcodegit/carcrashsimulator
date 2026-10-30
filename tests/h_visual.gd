extends Node3D
# НЕ headless: --path . --fixed-fps 60 --quit-after 700 res://tests/h_visual.tscn
var _frame := 0
var gm: GameManager
var _impacts := 0

func _ready() -> void:
	GameContext.select("sport", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	await get_tree().process_frame
	gm.car.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void: _impacts += 1)

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 5: Input.action_press("throttle")
	if _frame in [60, 150, 200, 260, 330, 420]:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tests/out/v%d.png" % _frame)
	if _frame == 421:
		Input.action_release("throttle")
		print("VIS done impacts=%d dents=%d depth=%.3f deform=%.2f" % [
			_impacts, gm.car.body.dent_count, gm.car.body.max_depth, gm.car.body.deformation()])
		get_tree().quit(0)
