class_name EffectsDirector
extends Node3D

const ZONE_DIR := {
	Zones.FRONT: Vector3(1, 0, 0), Zones.REAR: Vector3(-1, 0, 0),
	Zones.LEFT: Vector3(0, 0, -1), Zones.RIGHT: Vector3(0, 0, 1), Zones.ROOF: Vector3(0, 1, 0),
}

var _car: CarRig
var _damage: DamageModel
var _smoke: Array[CPUParticles3D] = []
var _fire: CPUParticles3D
var _fire_light: OmniLight3D
var _sparks: CPUParticles3D
var _shards: CPUParticles3D

func attach(car: CarRig, damage: DamageModel) -> void:
	_car = car; _damage = damage
	_sparks = _mk_particles(Color(1.0, 0.8, 0.3), 48, true)
	_shards = _mk_particles(Color(0.7, 0.85, 0.95), 24, true)
	_fire = _mk_particles(Color(1.0, 0.5, 0.1, 0.8), 64, false)
	add_child(_sparks); add_child(_shards); add_child(_fire)
	for z in 5:
		var s := _mk_particles(Color(0.25, 0.25, 0.25, 0.55), 120, false)
		s.lifetime = 2.4
		s.position = ZONE_DIR[z] * 0.45 + Vector3(0, 0.4, 0)
		_smoke.append(s); add_child(s)
	_fire_light = OmniLight3D.new()
	_fire_light.omni_range = 3.0
	_fire_light.light_color = Color(1.0, 0.45, 0.1)
	_fire_light.visible = false
	add_child(_fire_light)
	if get_parent(): get_parent().remove_child(self)
	car.chassis.add_child(self)
	position = Vector3.ZERO
	_car.shell.spring_burst.connect(func(_z): _refresh())
	_car.shell.plastic_event.connect(_on_plastic)
	_car.impact.connect(_on_impact)
	_refresh()

func _mk_particles(color: Color, amount: int, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = 1.4; p.one_shot = one_shot
	p.emitting = false; p.explosiveness = 0.9 if one_shot else 0.0
	p.local_coords = false
	p.direction = Vector3(0, 1, 0); p.spread = 30.0
	p.initial_velocity_min = 1.5; p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -1.5, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	var q := QuadMesh.new(); q.size = Vector2(0.18, 0.18); q.material = m
	p.mesh = q
	return p

var _spark_until := 0
var _shard_until := 0

func _on_impact(speed_kmh: float, point: Vector3, _normal: Vector3) -> void:
	if speed_kmh < 15.0: return
	if Time.get_ticks_msec() < _spark_until: return
	_spark_until = Time.get_ticks_msec() + 80
	_sparks.global_position = point
	_sparks.emitting = false
	_sparks.emitting = true

func _on_plastic(zone: int, world_pos: Vector3, _energy: float) -> void:
	if Time.get_ticks_msec() < _shard_until: return
	_shard_until = Time.get_ticks_msec() + 150
	if zone == Zones.ROOF or zone == Zones.LEFT or zone == Zones.RIGHT:
		_shards.global_position = world_pos
		_shards.emitting = false
		_shards.emitting = true

func _refresh() -> void:
	var hpz := _damage.hp_array()
	for i in _smoke.size():
		_smoke[i].emitting = hpz[i] < 60.0
		_smoke[i].amount = int(lerpf(10.0, 140.0, 1.0 - hpz[i] / 100.0))
	var w := _damage.worst_zone()
	var burning := _damage.hp(w) < 25.0
	_fire.emitting = burning
	_fire_light.visible = burning
	if burning:
		_fire.position = ZONE_DIR[w] * 0.6
		_fire_light.position = _fire.position
