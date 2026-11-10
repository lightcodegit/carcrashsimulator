extends Node3D
# The marking must share its plane with nothing. A Kenney plate is a trough of three
# levels (in local coordinates: grass y=0.0, asphalt y=0.1, white stripes y=0.2), so
# it is exactly the world heights that matter:
# 1) the road surface is lifted above the map floor but not above the kerb;
# 2) the white stripe is clearly above its own asphalt (10 cm — a real kerb);
# 3) no horizontal face of any asset coincides with the floor plane within
#    2 mm — that is precisely what made the flicker when plates were sunk by half their height.
const SEG := "road"          # only road* segments count as road
var _fails := 0
var _arch_seen := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

static func _tris(mesh: Mesh, surface: int) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	if idx.is_empty():
		for q in range(0, verts.size() - 2, 3):
			out.append(verts[q]); out.append(verts[q + 1]); out.append(verts[q + 2])
	else:
		for k in range(0, idx.size() - 2, 3):
			out.append(verts[idx[k]]); out.append(verts[idx[k + 1]]); out.append(verts[idx[k + 2]])
	return out

# World heights of the top horizontal faces of the surface named name_key.
static func _horiz(mesh: Mesh, tr: Transform3D, name_key: String) -> Array[float]:
	var ys: Array[float] = []
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat == null or mat.resource_name != name_key: continue
		var f := _tris(mesh, s)
		for q in range(0, f.size() - 2, 3):
			var a := tr * f[q]
			var b := tr * f[q + 1]
			var d := tr * f[q + 2]
			var n := (b - a).cross(d - a) + (d - a).cross(b - d) + (b - d).cross(a - b)
			if absf(n.y) > 0.9 * n.length(): ys.append(maxf(a.y, maxf(b.y, d.y)))
	return ys

# Minimum world height of the segment's road surface — the same rule by which MapDB
# places it. Horizontal faces will not do: on a ramp the only horizontal road face is
# the top platform at 2.6 m, while the approach is sloped.
static func _road_min(p: MeshInstance3D) -> float:
	var got := INF
	for s in p.mesh.get_surface_count():
		var mat := p.mesh.surface_get_material(s)
		if mat == null or mat.resource_name != "road": continue
		var v: PackedVector3Array = p.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for q in v: got = minf(got, (p.global_transform * q).y)
	return got

static func _kits(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null and String(mesh.resource_path).begins_with("res://assets/racing/"):
			out.append(mi)
	for c in n.get_children():
		_kits(c, out)

# World coordinate of the plate's road axis along its transverse axis. For roadStart it
# is not at the plate centre (6.3 instead of the usual 5.0), and plain placement without
# that correction drags the arch's white line 1.3 m sideways — the report "crooked lines
# at the start of Big City". The arch is compared with a neighbouring plate: the axes must
# match.
static func _lateral_center(p: MeshInstance3D) -> float:
	var cx := 0.0
	var n := 0
	for s in p.mesh.get_surface_count():
		var mat := p.mesh.surface_get_material(s)
		if mat == null or mat.resource_name != "road": continue
		for v in (p.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			cx += v.x
			n += 1
	if n == 0: return INF
	var w: Vector3 = p.global_transform * Vector3(cx / float(n), 0.1, 10.0)
	return w.dot(p.global_transform.basis.x.normalized())

func _ready() -> void:
	await get_tree().process_frame
	for id in MapDB.ids():
		var m: Dictionary = MapDB.build(id)
		var root: Node3D = m.root
		add_child(root)
		await get_tree().physics_frame
		var kits: Array = []
		_kits(root, kits)
		# the map floor is the main flicker source: no asset face may lie exactly in its
		# plane
		var on_floor := 0
		for mi in kits:
			var p := mi as MeshInstance3D
			for s in ["road", "grey", "grass"]:
				for y in _horiz(p.mesh, p.global_transform, s):
					if absf(y - MapDefs.FLOOR_Y) < 0.0005: on_floor += 1
		check(on_floor == 0, "%s: no asset face landed in the floor plane (%d)" % [id, on_floor])
		var plates := 0
		var lifted := 0
		var proud := 0
		for mi in kits:
			var p := mi as MeshInstance3D
			if not String(p.mesh.resource_path.get_file().get_basename()).begins_with(SEG): continue
			var lo := _road_min(p)
			if not is_finite(lo): continue
			plates += 1
			# The road surface lies 1–10 mm ABOVE the physical ground: less and the faces
			# coincide and flicker, more and the wheels visually sink into the road.
			if lo > MapDefs.FLOOR_Y + 0.0005 and lo < MapDefs.FLOOR_Y + 0.010: lifted += 1
			for g in _horiz(p.mesh, p.global_transform, "grey"):
				if g - lo > 0.05 and g - lo < 0.30: proud += 1
		if id != "void":
			check(plates > 5, "%s: road segments %d" % [id, plates])
			check(lifted == plates, "%s: every plate's surface is lifted above the floor (%d of %d)" % [id, lifted, plates])
			check(proud > 10, "%s: the white marking is above its own asphalt (%d faces)" % [id, proud])
		else:
			check(plates == 0, "void: no road segments (%d)" % plates)
		var arches := 0
		var seen := 0
		for mi in kits:
			var p := mi as MeshInstance3D
			if String(p.mesh.resource_path.get_file().get_basename()) != "roadStart": continue
			seen += 1
			var best: MeshInstance3D = null
			var bd := INF
			for mi2 in kits:
				var q := mi2 as MeshInstance3D
				if String(q.mesh.resource_path.get_file().get_basename()) != "roadStraightLong": continue
				# only plates with the same transverse axis may be compared: by the ring the
				# plates are rotated, and their "transverse coordinate" is computed in a
				# different direction
				if absf(p.global_transform.basis.x.dot(q.global_transform.basis.x)) < 0.99: continue
				var d: float = p.global_position.distance_to(q.global_position)
				if d < bd: bd = d; best = q
			if best == null: continue
			var la := _lateral_center(p)
			var lb := _lateral_center(best)
			if not is_finite(la) or not is_finite(lb): continue
			if absf(la - lb) > 0.15:
				arches += 1
				print("  %s: arch at %.2f, neighbouring plate at %.2f (offset %.2f m)" % [
					id, la, lb, la - lb])
		_arch_seen += seen
		check(arches == 0, "%s: the start arches stand on the street axis (%d with an offset)" % [id, arches])
		root.queue_free()
		await get_tree().process_frame
	# "zero with an offset" means nothing if not a single arch ever came into view
	check(_arch_seen > 0, "start arches were covered by the check at all (%d)" % _arch_seen)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
