extends SceneTree
# Кэш лент «бесконечности» живёт между сборками карты. Проверка: после recycle все
# запомненные узлы принадлежат ТЕКУЩЕМУ корню, иначе переставка уезжала бы в
# уже освобождённую карту.
func _initialize() -> void:
	var fails := 0
	for i in 3:
		var m: Dictionary = MapDB.build("endless")
		var root: Node3D = m.root
		root.process_mode = Node.PROCESS_MODE_ALWAYS
		MapDB.recycle(root, 0.0, 20.0)
		MapDB.recycle(root, 400.0, 20.0)
		var stale := 0
		var foreign := 0
		for line in MapCircuit.rc_lines:
			for n in line:
				if not (n is Node): continue
				var n3 := n as Node3D
				if not is_instance_valid(n3): stale += 1; continue
				var p: Node = n3
				var reaches := false
				while p != null:
					if p == root: reaches = true; break
					p = p.get_parent()
				if not reaches: foreign += 1
		print("прогон %d: лент %d, освобождённых %d, чужих %d" % [i, MapCircuit.rc_lines.size(), stale, foreign])
		# пустой кэш — это не «грязно», а нечего проверять
		if MapCircuit.rc_lines.size() < 3:
			print("FAIL: прогон %d: лент %d, переставка не собралась" % [i, MapCircuit.rc_lines.size()])
			fails += 1
		if stale + foreign > 0: fails += 1
		root.free()
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
