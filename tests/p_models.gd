extends Node3D
var _f := 0
func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100); cs.shape = box
	body.add_child(cs); add_child(body); body.position = Vector3(0, -1, 0)
	var we := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new(); var p := ProceduralSkyMaterial.new()
	p.sky_top_color = Color(0.35, 0.55, 0.85); p.sky_horizon_color = Color(0.75, 0.78, 0.82)
	sky.sky_material = p; env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true
	add_child(sun)
	var ids := ["sedan", "pickup", "sport"]
	for i in 3:
		var car := CarRig.new(); add_child(car)
		car.build(VehicleDB.get_params(ids[i]), get_world_3d())
		car.respawn(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-4 + i * 4, 0.8, 0)))
	for c in get_children():
		var rig := c as CarRig
		if rig == null or rig.body == null: continue
		print("MODEL %s L=%.2f W=%.2f H=%.2f wheel_r=%.2f verts=%d tris=%d wheels=%d front=%d" % [
			rig.params.car_id, rig.params.length, rig.params.width, rig.params.height,
			rig.body.wheel_radius, rig.body.vertex_count(), rig.body.triangle_count(),
			rig.body.wheels.size(), rig.body.front_wheels.size()])
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(11, 3.0, 11)
	cam.look_at(Vector3(0, 0.7, 0), Vector3.UP); cam.make_current()

func _process(_d: float) -> void:
	_f += 1
	if _f == 10:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/out/models.png")
		get_tree().quit(0)
