extends Node3D
# Каринка обязана оставаться картинкой: главная жалоба игроков была «машины чёрные»,
# а починить это можно и случайно — например, сменив движок рендера. therefore полосы
# кадра измеряются численно (никто не смотрит в PNG).
#
# headless GPU не имеет, там проверка пропускается и печатает NOTE. Для подбора
# компенсаций есть переменные окружения BGEN / SKYENERGY / AMBIENT.
const BANDS := [
	# [имя, y от, y до, минимальная яркость, максимальная]
	["НЕБО", 0.00, 0.22, 0.30, 0.85],
	["ЦЕНТР", 0.40, 0.60, 0.40, 0.85],
	["ЗЕМЛЯ", 0.80, 1.00, 0.18, 0.60],
]
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _live() -> bool:
	return DisplayServer.get_name() != "headless"

func _ready() -> void:
	if not _live():
		print("NOTE: живой рендер недоступен — проверка яркости кадра пропущена")
		print("ALL PASS")
		get_tree().quit(0)
		return
	GameContext.select("sport", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	var bg := float(OS.get_environment("BGEN"))
	if bg > 0.0: gm._env.background_energy_multiplier = bg
	var se := float(OS.get_environment("SKYENERGY"))
	if se > 0.0: gm._env.sky.sky_material.energy_multiplier = se
	var ae := float(OS.get_environment("AMBIENT"))
	if ae > 0.0: gm._env.ambient_light_energy = ae
	for _i in 90:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var h := img.get_height()
	var w := img.get_width()
	print("RENDER method=%s size=%s" % [RenderingServer.get_current_rendering_method(), str(img.get_size())])
	for band in BANDS:
		var sum := Vector3.ZERO
		var n := 0
		var clipped := 0
		var y0 := int(h * float(band[1]))
		var y1 := int(h * float(band[2]))
		var y := y0
		while y < y1:
			var x := 0
			while x < w:
				var c := img.get_pixel(x, y)
				sum += Vector3(c.r, c.g, c.b)
				if c.r > 0.99 and c.g > 0.99 and c.b > 0.99: clipped += 1
				n += 1
				x += 4
			y += 4
		var m := sum / maxf(float(n), 1.0)
		var l := 0.2126 * m.x + 0.7152 * m.y + 0.0722 * m.z
		# оттенок: небо обязано быть синим, а не серым — иначе свет от него тоже съехал
		var blueish := m.z > m.x
		print("LUM %s: r=%.3f g=%.3f b=%.3f яркость=%.3f выжжено=%d%%" % [
			band[0], m.x, m.y, m.z, l, int(100.0 * float(clipped) / maxf(float(n), 1.0))])
		check(l >= float(band[3]), "%s: полоса не чёрная (%.3f < %.3f)" % [band[0], l, float(band[3])])
		check(l <= float(band[4]), "%s: полоса не выжжена (%.3f > %.3f)" % [band[0], l, float(band[4])])
		check(float(clipped) / maxf(float(n), 1.0) < 0.25, "%s: не больше четверти пикселей в клиппинге" % band[0])
		if band[0] == "НЕБО": check(blueish, "небо синее, а не серое (r=%.3f b=%.3f)" % [m.x, m.z])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
