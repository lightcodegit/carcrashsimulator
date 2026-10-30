class_name GameManager
extends Node3D

var car: CarRig
var hud: HUD
var camera: CameraRig
var damage: DamageModel
var effects: EffectsDirector
var _spawn := Transform3D.IDENTITY
var _top_crash := 0.0
var _crashes := 0
var _paused := false

func _ready() -> void:
	_setup_env()
	var m: Dictionary = MapDB.build(GameContext.map_id)
	_spawn = m.spawn
	add_child(m.root)
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params(GameContext.car_id), get_world_3d())
	damage = DamageModel.new()
	damage.bind_shell(car.shell)
	car.respawn(_spawn)
	effects = EffectsDirector.new()
	add_child(effects)
	effects.attach(car, damage)
	camera = CameraRig.new()
	add_child(camera)
	camera.setup(car)
	camera.make_current()
	hud = HUD.new()
	add_child(hud)
	hud.bind(car, damage)
	car.impact.connect(_on_impact)
	damage.zone_hp_changed.connect(func(_z: int, _h: float): car.shell.set_zone_hp(damage.hp_array()))

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var p := ProceduralSkyMaterial.new()
	p.sky_top_color = Color(0.35, 0.55, 0.85)
	p.sky_horizon_color = Color(0.75, 0.78, 0.82)
	sky.sky_material = p
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

func _on_impact(speed_kmh: float, _point: Vector3, _normal: Vector3) -> void:
	_crashes += 1
	_top_crash = maxf(_top_crash, speed_kmh)
	hud.show_crash(speed_kmh)
	camera.add_trauma(clampf(speed_kmh / 90.0, 0.2, 1.0))
	if speed_kmh > 60.0:
		TimeScale.play_auto(0.3, 1.2)

func _physics_process(_dt: float) -> void:
	TimeScale.set_hold(Input.is_action_pressed("slowmo"))
	var pos := car.chassis.global_position
	if pos.y < -60.0 or pos.length() > 400.0:
		_respawn_now()
		hud.show_tip("вылет за пределы — рестарт")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("respawn"):
		_respawn_now()
	elif event.is_action_pressed("cam_cycle"):
		camera.cycle_mode()
	elif event.is_action_pressed("pause"):
		_set_paused(not _paused)

func _respawn_now() -> void:
	car.respawn(_spawn)
	damage.reset()
	hud.show_tip("")
	car.shell.set_zone_hp([100.0, 100.0, 100.0, 100.0, 100.0])
	TimeScale.set_hold(false)

func _set_paused(v: bool) -> void:
	_paused = v
	get_tree().paused = v
	hud.process_mode = Node.PROCESS_MODE_ALWAYS if v else Node.PROCESS_MODE_INHERIT
	hud.set_paused(v)
