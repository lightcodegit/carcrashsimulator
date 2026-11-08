extends Node3D
# Soak-проба: ищем прогрессирующее замедление — узлы, объекты физики, память
# и wall-clock темп тиков на длинной гонке по «бесконечности».
var gm: GameManager
var f := 0
var t0 := 0
var base_nodes := 0
var base_mem := 0

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameContext.select("sport", "endless")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().process_frame
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	f += 1
	if f == 600:
		t0 = Time.get_ticks_usec()
		base_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		base_mem = OS.get_static_memory_usage()
	if f > 600 and f % 3000 == 0:
		var span := float(Time.get_ticks_usec() - t0) / float(f - 600) / 1000.0
		var pr := Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
		var orph := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		print("SOAK f=%d tick=%.2fms nodes=%d(+%d) orphans=%d pairs=%d mem=%dKB" % [
			f, span, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - base_nodes,
			orph, pr, (OS.get_static_memory_usage() - base_mem) / 1024])
	if f == 9600: print("SOAK DONE"); get_tree().quit()
