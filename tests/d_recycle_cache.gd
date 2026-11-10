extends SceneTree
# The "endless" ribbon cache lives across map builds. Check: after recycle every
# remembered node belongs to the CURRENT root, otherwise the reposition would move
# into an already freed map.
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
		print("run %d: ribbons %d, freed %d, foreign %d" % [i, MapCircuit.rc_lines.size(), stale, foreign])
		# an empty cache is not "dirty", it is nothing to check
		if MapCircuit.rc_lines.size() < 3:
			print("FAIL: run %d: %d ribbons, the reposition did not build" % [i, MapCircuit.rc_lines.size()])
			fails += 1
		if stale + foreign > 0: fails += 1
		root.free()
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
