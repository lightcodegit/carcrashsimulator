class_name GameManager
extends Node3D

var car: CarRig
var hud: HUD
var camera: CameraRig
var effects: EffectsDirector
var _spawn := Transform3D.IDENTITY
var _bounds := AABB(Vector3(-160, -30, -160), Vector3(320, 70, 320))
var _top_crash := 0.0
var _crashes := 0
var _paused := false
var _flip := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Esc и «в меню» должны работать и на паузе
	_setup_env()
	var m: Dictionary = MapDB.build(GameContext.map_id)
	_spawn = m.spawn
	_bounds = m.bounds
	add_child(m.root)
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params(GameContext.car_id), get_world_3d())
	car.respawn(_spawn)
	effects = EffectsDirector.new()
	add_child(effects)
	effects.attach(car)
	camera = CameraRig.new()
	add_child(camera)
	camera.setup(car)
	camera.make_current()
	hud = HUD.new()
	add_child(hud)
	hud.bind(car)
	hud.menu_requested.connect(_to_menu)
	car.impact.connect(_on_impact)

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# физическое небо вместо процедурного: рассеяние Рэлея, диск солнца и правильный
	# градиент у горизонта — именно оно даёт машинам и асфальту правдоподобные отражения
	var ps := PhysicalSkyMaterial.new()
	ps.turbidity = 4.0
	ps.sun_disk_scale = 2.0
	ps.mie_eccentricity = 0.75      # рассеяние вперёд: солнце даёт тёплую дымку у горизонта
	ps.use_debanding = true
	sky.sky_material = ps
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.sky = sky
	# небо как источник рассеянного света и отражений: иначе кузова в тени почти чёрные
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	# экранный непрямой свет вытаскивает из черноты то, что не освещено солнцем напрямую:
	# припаркованные машины в тени домов были главным источником жалобы на темноту
	env.ssil_enabled = true
	env.ssil_intensity = 1.25
	env.ssil_radius = 6.0
	# дымка даёт глубину и прячет границу прорисовки на 620-метровой трассе
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.85)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.25
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_angular_distance = 0.55     # мягкая граница тени, а не бритвенная
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 150, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.78, 0.85, 1.0)
	add_child(fill)

# Никакого баннера «УДАР» и автоматического слоу-мо: игра не должна останавливаться.
# Удар уходит только в компактный журнал телеметрии и в лёгкий шейк камеры.
func _on_impact(speed_kmh: float, _point: Vector3, _normal: Vector3) -> void:
	_crashes += 1
	_top_crash = maxf(_top_crash, speed_kmh)
	hud.log_impact(speed_kmh)
	hud.set_crash_stats(_crashes, _top_crash)
	camera.add_trauma(clampf(speed_kmh / 160.0, 0.12, 0.55))

func _physics_process(dt: float) -> void:
	if _paused: return
	TimeScale.set_hold(Input.is_action_pressed("slowmo"))
	var pos := car.chassis.global_position
	if pos.y < -60.0 or not _bounds.has_point(pos):
		_respawn_now()
		hud.show_tip("вылет за пределы — рестарт")
		return
	# на настоящей подвеске машина может остаться на крыше и уже не поедет: подсказываем выход
	_flip = 0.0 if car.chassis.global_basis.y.y > -0.2 else _flip + dt
	if _flip > 1.0: hud.show_tip("машина на крыше — R для рестарта")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not _paused)
	elif _paused:
		return
	elif event.is_action_pressed("respawn"):
		_respawn_now()
	elif event.is_action_pressed("cam_cycle"):
		camera.cycle_mode()

func _respawn_now() -> void:
	_flip = 0.0
	car.respawn(_spawn)
	hud.show_tip("")
	TimeScale.set_hold(false)

func _set_paused(v: bool) -> void:
	_paused = v
	if v: TimeScale.set_hold(false)
	get_tree().paused = v
	hud.process_mode = Node.PROCESS_MODE_ALWAYS if v else Node.PROCESS_MODE_INHERIT
	hud.set_paused(v)

func _to_menu() -> void:
	get_tree().paused = false
	_paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
