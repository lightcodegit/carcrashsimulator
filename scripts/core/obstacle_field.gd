class_name ObstacleField
extends RefCounted
# Реестр осевыровненных боксов карты: дешёвый аналитический барьер для verlet-клетки
# (rotate-объекты — рампы — сюда не попадают, их ловит свип-луч).

static var boxes: Array[Dictionary] = []

static func reset() -> void:
	boxes.clear()

static func add(center: Vector3, half: Vector3) -> void:
	boxes.append({"c": center, "h": half})

static func project_out(p: Vector3) -> Vector3:
	for _pass in 2:
		for b in boxes:
			var c: Vector3 = b["c"]
			var h: Vector3 = b["h"]
			var d := p - c
			if absf(d.x) <= h.x and absf(d.y) <= h.y and absf(d.z) <= h.z:
				var pen := Vector3(h.x - absf(d.x), h.y - absf(d.y), h.z - absf(d.z))
				var axis := 0
				if pen.y < pen[axis]: axis = 1
				if pen.z < pen[axis]: axis = 2
				var sgn := 1.0 if d[axis] >= 0.0 else -1.0
				p[axis] = c[axis] + sgn * (h[axis] + 0.02)
	return p

static func contains(p: Vector3) -> bool:
	for b in boxes:
		var d := p - (b["c"] as Vector3)
		var h: Vector3 = b["h"]
		if absf(d.x) <= h.x and absf(d.y) <= h.y and absf(d.z) <= h.z:
			return true
	return false
