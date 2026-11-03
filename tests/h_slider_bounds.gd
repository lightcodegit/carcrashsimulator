extends Node
# Контракт ползунков: HSlider строится в ЕДИНИЦАХ НАСТРОЙКИ, а множитель показа
# перемножает уже границы (см. _build_slider: min*mul, max*mul). Если в таблице
# оставить display-единицы, диапазон разъезжается во много раз, и кламп настроек
# молча съедает всё движение ползунка: игрок двигает ручку, а значение упёрто.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var menu := preload("res://scripts/ui/settings_menu.gd")
	for row in menu.SLIDERS:
		var key := String(row[0])
		check(Settings.NUMS.has(key), "у ползунка %s есть граница в NUMS" % key)
		if not Settings.NUMS.has(key): continue
		var mul := float(row[6])
		# Таблица хранит РЕАЛЬНЫЕ единицы настройки: _build_slider умножает границы
		# на mul уже для показа, а refresh пишет ползунку value*mul.
		var lo := float(row[2])
		var hi := float(row[3])
		var wlo := float(Settings.NUMS[key][0])
		var whi := float(Settings.NUMS[key][1])
		check(lo >= wlo - 1e-12 and hi <= whi + 1e-12,
			"%s: ползунок просит %.5f..%.5f, разрешено %.5f..%.5f (mul=%.1f)" % [key, lo, hi, wlo, whi, mul])
		# шаг обязан укладываться в диапазон хотя бы 4 раза, иначе ручка крутится
		# между двумя значениями и настройка выглядит сломанной
		var steps := (hi - lo) / maxf(absf(float(row[4])), 1e-12)
		check(steps >= 4.0, "%s: шаг %.5f режет диапазон на %.1f части" % [key, float(row[4]), steps])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
