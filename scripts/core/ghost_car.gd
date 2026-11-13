class_name GhostCar
extends Node3D
# Translucent playback of the best lap: a lightweight visual twin of the
# player's car that follows the recorded path. No physics, no collision,
# no shadows — just a mesh the player compares their position against.
#
# The node hierarchy replicates the real car's (CarRig → DentBody → ModelRoot
# → model) so that a recorded chassis transform places the ghost's model
# exactly where the real car's model would be. DentBody's measurement statics
# are reused for the same reason: one measurement code, one visual size.

const GHOST_COLOR := Color(0.45, 0.75, 1.0, 0.30)

static var _ghost_mat: StandardMaterial3D

var _body_node: Node3D
var _root: Node3D
var _wheels: Array[MeshInstance3D] = []
var _front: Array[MeshInstance3D] = []
var _wheel_base_y: Array[float] = []
var _scale := 1.0

var _frames: Array = []
var _total := 0.0
var _t := 0.0
var _playing := false

func setup(p: VehicleParams) -> void:
	name = "GhostCar"
	_build(p)

func play(frames: Array) -> void:
	if frames.is_empty(): return
	_frames = frames
	_total = float(frames[frames.size() - 1]["t"])
	_t = 0.0
	_playing = true
	visible = true

func restart() -> void:
	# Sync to the player's new lap: back to the line, playing from t=0.
	_t = 0.0
	if not _frames.is_empty():
		_playing = true
		visible = true

func stop() -> void:
	_playing = false
	visible = false

func playing() -> bool:
	return _playing

func _process(dt: float) -> void:
	if not _playing or _frames.is_empty(): return
	if get_tree().paused: return
	_t += dt
	if _t >= _total:
		_t = _total   # hold at the finish until the player's next lap restarts it
	_apply(_t)

# Bracketing frames by binary search, then the same interpolation
# ReplayPlayer uses: lerped origin, slerped basis, lerped wheel poses.
func _apply(t: float) -> void:
	if _frames.is_empty() or _body_node == null: return
	var lo := 0
	var hi := _frames.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(_frames[mid]["t"]) <= t: lo = mid
		else: hi = mid - 1
	var a: Dictionary = _frames[lo]
	var b: Dictionary = _frames[mini(lo + 1, _frames.size() - 1)]
	var span := float(b["t"]) - float(a["t"])
	var w := 0.0 if span <= 1e-6 else clampf((t - float(a["t"])) / span, 0.0, 1.0)

	var pa: PackedFloat32Array = a["p"]
	var pb: PackedFloat32Array = b["p"]
	var org := Vector3(lerpf(pa[0], pb[0], w), lerpf(pa[1], pb[1], w), lerpf(pa[2], pb[2], w))
	var ba: PackedFloat32Array = a["b"]
	var bb: PackedFloat32Array = b["b"]
	var from := Basis(Vector3(ba[0], ba[1], ba[2]), Vector3(ba[3], ba[4], ba[5]), Vector3(ba[6], ba[7], ba[8]))
	var to := Basis(Vector3(bb[0], bb[1], bb[2]), Vector3(bb[3], bb[4], bb[5]), Vector3(bb[6], bb[7], bb[8]))
	global_transform = Transform3D(from.slerp(to, w), org)

	var wa: PackedFloat32Array = a["w"]
	var wb: PackedFloat32Array = b["w"]
	for i in _wheels.size():
		var o := i * 3
		if o + 2 >= wa.size() or o + 2 >= wb.size(): break
		var drop := lerpf(wa[o], wb[o], w)
		var steer := lerpf(wa[o + 1], wb[o + 1], w)
		var roll := wa[o + 2] + (wrapf(wb[o + 2] - wa[o + 2], -PI, PI) * w)
		_set_wheel(i, drop, steer, roll)

func _set_wheel(i: int, drop: float, steer: float, roll: float) -> void:
	if i >= _wheels.size(): return
	var w := _wheels[i]
	w.position.y = _wheel_base_y[i] - drop / _scale
	w.rotation = Vector3(roll, steer if _front.has(w) else 0.0, 0.0)

# ---- visual build -------------------------------------------------------------
# Same measurement and hierarchy math as CarRig.build + DentBody.setup, minus
# the deformable mesh, collision and paint. One measurement code = one size.

func _build(p: VehicleParams) -> void:
	visible = false   # no recording yet: the ghost is hidden until play()
	var ps: PackedScene = load(p.model)
	if ps == null:
		push_warning("GhostCar: model not found " + p.model)
		return
	var model: Node3D = ps.instantiate()
	DentBody.stretch_model(model, p.body_stretch)
	for c in model.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var nm := String(c.name).to_lower()
		if nm.begins_with("wheel"):
			_wheels.append(mi)
			if "front" in nm: _front.append(mi)
	var merged: AABB = DentBody._aabb_in(model)
	_scale = p.width / maxf(0.001, merged.size.x)
	var wb: Dictionary = DentBody._wheels_bounds(model)
	var wr: float = float(wb.r) * _scale
	if wr < 0.01: wr = 0.3 * _scale

	# body level: cancels the chassis's YAW_OFFSET and drops the wheels to zero
	_body_node = Node3D.new()
	_body_node.name = "GhostBody"
	_body_node.rotation.y = -PI * 0.5
	_body_node.position = Vector3(0, -wr, 0)
	add_child(_body_node)

	# root level: uniform scale + model's +Z forward → car's +X forward
	_root = Node3D.new()
	_root.name = "GhostRoot"
	_root.scale = Vector3.ONE * _scale
	_root.rotation.y = PI * 0.5
	_body_node.add_child(_root)
	_root.add_child(model)

	var ground: float = merged.position.y if not is_finite(float(wb.bottom)) else float(wb.bottom)
	model.position = Vector3(-merged.get_center().x, -ground, -merged.get_center().z)
	for w in _wheels:
		_wheel_base_y.append(w.position.y)
	_ghostify(model)

func _ghostify(model: Node3D) -> void:
	var mat := _material()
	for c in model.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null: continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)

# One shared material: the ghost is a silhouette, not a paint job.
static func _material() -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.albedo_color = GHOST_COLOR
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.emission_enabled = true
		_ghost_mat.emission = Color(0.2, 0.4, 0.8)
		_ghost_mat.emission_energy_multiplier = 0.35
		_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ghost_mat.roughness = 0.4
	return _ghost_mat
