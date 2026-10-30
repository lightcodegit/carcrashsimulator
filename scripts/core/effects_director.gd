class_name EffectsDirector
extends Node3D
# Отклик на удар без состояния урона: искры и пыль в точке контакта.
# Никаких зон, HP, дыма и огня — кузов теперь просто мнётся (DentBody).

var _sparks: CPUParticles3D
var _dust: CPUParticles3D
var _spark_until := 0

func attach(car: CarRig) -> void:
	_sparks = _mk_particles(Color(1.0, 0.82, 0.35), 42, 0.9)
	_dust = _mk_particles(Color(0.62, 0.6, 0.58, 0.5), 26, 2.0)
	add_child(_sparks)
	add_child(_dust)
	if get_parent(): get_parent().remove_child(self)
	car.chassis.add_child(self)
	position = Vector3.ZERO
	car.impact.connect(_on_impact)

func _mk_particles(color: Color, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 42.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.albedo_texture = _soft_dot()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = m
	p.mesh = q
	return p

func _soft_dot() -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 32; gt.height = 32
	return gt

func _on_impact(speed_kmh: float, point: Vector3, _normal: Vector3) -> void:
	if speed_kmh < 15.0: return
	var now := Time.get_ticks_msec()
	if now < _spark_until: return
	_spark_until = now + 80
	_sparks.global_position = point
	_dust.global_position = point
	_sparks.amount = int(clampf(speed_kmh * 0.4, 12.0, 64.0))
	_dust.amount = int(clampf(speed_kmh * 0.22, 8.0, 40.0))
	for p in [_sparks, _dust]:
		p.emitting = false
		p.emitting = true
