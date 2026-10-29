class_name ShellBuilder
extends RefCounted

static func build(p: VehicleParams) -> ShellSpec:
	var spec := ShellSpec.new()
	var S := p.sections; var P := p.ring_points
	var half_l := p.length * 0.5
	var body_cy := p.gc + p.body_h * 0.5
	var body_ry := p.body_h * 0.5
	var body_rz := p.width * 0.5
	var cab_cy := p.gc + p.body_h + p.roof_h * 0.4
	var cab_ry := p.roof_h * 0.62
	var cab_rz := p.width * 0.5 * 0.84
	# 1) точки + зоны
	for s in S:
		var x := -half_l + float(s) / (S - 1) * p.length
		var taper := clampf(1.0 - pow(absf(x) / half_l, 4.0) * 0.35, 0.6, 1.0)
		var blend := _cabin_blend(x, p.cab_x0, p.cab_x1)
		for i in P:
			var th := float(i) / P * TAU
			var cs := cos(th); var sn := sin(th)
			var y := body_cy + body_ry * cs * taper
			var z := body_rz * sn * taper
			if cs > 0.0:
				y = lerp(y, cab_cy + cab_ry * cs, blend)
				z = lerp(z, cab_rz * sn, blend)
			spec.points.append(Vector3(x, maxf(y, p.gc * 0.4), z))
			spec.zones.append(_zone_for(x, cs, sn, blend, half_l))
	var nose_idx := spec.points.size()
	spec.points.append(Vector3(half_l + 0.15, body_cy, 0)); spec.zones.append(Zones.FRONT)
	var tail_idx := spec.points.size()
	spec.points.append(Vector3(-half_l - 0.15, body_cy, 0)); spec.zones.append(Zones.REAR)
	# 2) chassis ноды (мишени анкеров)
	spec.chassis_nodes = [
		Vector3(half_l * 0.84, p.gc * 0.3, body_rz * 0.7), Vector3(half_l * 0.84, p.gc * 0.3, -body_rz * 0.7),
		Vector3(-half_l * 0.84, p.gc * 0.3, body_rz * 0.7), Vector3(-half_l * 0.84, p.gc * 0.3, -body_rz * 0.7),
		Vector3(half_l * 0.84, p.gc + p.body_h * 0.8, 0.0), Vector3(-half_l * 0.84, p.gc + p.body_h * 0.8, 0.0),
		Vector3(0.0, p.gc * 0.3, 0.0), Vector3(0.0, p.gc + p.body_h * 0.85, 0.0),
		Vector3(p.cab_x0 + (p.cab_x1 - p.cab_x0) * 0.5, p.gc + p.body_h + p.roof_h * 0.8, 0.0),
		Vector3(half_l * 0.4, p.gc + p.body_h * 0.5, 0.0)]
	# 3) пружины
	var add := func(ai: int, bi: int, ty: int, anchor: int):
		var sp := Spring.new()
		sp.a = ai; sp.b = bi; sp.type = ty; sp.anchor = anchor
		if ty == Spring.ANCHOR:
			sp.rest = spec.points[ai].distance_to(spec.chassis_nodes[anchor])
		else:
			sp.rest = spec.points[ai].distance_to(spec.points[bi])
		sp.zone = spec.zones[ai]
		spec.springs.append(sp)
		spec.zone_spring_totals[sp.zone] += 1
	for s in S:
		for i in P:
			add.call(s * P + i, s * P + (i + 1) % P, Spring.STRUCT, -1)
			if s < S - 1:
				add.call(s * P + i, (s + 1) * P + i, Spring.STRUCT, -1)
				add.call(s * P + i, (s + 1) * P + (i + 1) % P, Spring.SHEAR, -1)
				add.call(s * P + (i + 1) % P, (s + 1) * P + i, Spring.SHEAR, -1)
		if s % 2 == 0:
			add.call(s * P + 0, s * P + P / 2, Spring.BEND, -1)
			add.call(s * P + P / 4, s * P + P * 3 / 4, Spring.BEND, -1)
	for i in P:
		add.call(nose_idx, (S - 1) * P + i, Spring.STRUCT, -1)
		add.call(tail_idx, i, Spring.STRUCT, -1)
	for s in S:
		for i: int in [0, P / 4, P / 2, P * 3 / 4]:
			var pi := s * P + i
			add.call(pi, -1, Spring.ANCHOR, _nearest_node(spec.chassis_nodes, spec.points[pi]))
	for pd: int in [nose_idx, tail_idx]:
		add.call(pd, -1, Spring.ANCHOR, _nearest_node(spec.chassis_nodes, spec.points[pd]))
	# 4) триангуляция (замкнутая поверхность)
	for s in S - 1:
		for i in P:
			var a0 := s * P + i; var b0 := s * P + (i + 1) % P
			var a1 := (s + 1) * P + i; var b1 := (s + 1) * P + (i + 1) % P
			spec.triangles.append_array([a0, a1, b1, a0, b1, b0])
	for i in P:
		var j := (i + 1) % P
		spec.triangles.append_array([nose_idx, (S - 1) * P + j, (S - 1) * P + i])
		spec.triangles.append_array([tail_idx, j, i])
	return spec

static func _cabin_blend(x: float, x0: float, x1: float) -> float:
	var ramp := 0.45
	if x >= x0 and x <= x1: return 1.0
	var d := minf(absf(x - x0), absf(x - x1))
	return clampf(1.0 - d / ramp, 0.0, 1.0)

static func _zone_for(x: float, cs: float, sn: float, blend: float, half_l: float) -> int:
	if x > half_l * 0.7: return Zones.FRONT
	if x < -half_l * 0.7: return Zones.REAR
	if cs > 0.3 and blend > 0.5: return Zones.ROOF
	return Zones.RIGHT if sn > 0.0 else Zones.LEFT

static func _nearest_node(nodes: Array[Vector3], pt: Vector3) -> int:
	var best := 0; var bd := INF
	for k in nodes.size():
		var d := nodes[k].distance_squared_to(pt)
		if d < bd: bd = d; best = k
	return best
