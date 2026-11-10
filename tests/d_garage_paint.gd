extends SceneTree
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/core/garage_profiles.gd"):
		check(false, "body-only garage appearance missing")
		quit(1)
		return
	var service = load("res://scripts/core/garage_profiles.gd").new()
	for id in VehicleDB.ids():
		service.select_vehicle(id)
		service.set_value("paint_color", [0.05, 0.9, 0.65])
		service.set_value("paint_metallic", 0.8)
		service.set_value("paint_roughness", 0.7)
		var p: VehicleParams = service.draft_params()
		var model: Node3D = load(p.model).instantiate()
		var body: MeshInstance3D = model.get_node("body")
		var src := body.mesh.surface_get_material(0) as StandardMaterial3D
		var original := src.albedo_texture.get_image()
		var bytes := original.get_data()
		Materials.apply_tree(model, "car")
		var wheel_mats: Array = []
		for node in model.get_children():
			if String(node.name).begins_with("wheel"):
				wheel_mats.append(node.get_active_material(0))
		load("res://scripts/core/materials.gd").call("apply_vehicle", model, p)
		var mat := body.get_active_material(0) as StandardMaterial3D
		var result := mat.albedo_texture.get_image()
		var changed := 0
		var protected_changes := 0
		var col := 3 if id == "pickup" else 6
		for y in original.get_height():
			for x in original.get_width():
				var painted := x >= col * 64 and x < (col + 1) * 64 and y >= 128 and y < 256
				if result.get_pixel(x, y) != original.get_pixel(x, y):
					if painted: changed += 1
					else: protected_changes += 1
		check(changed > 7000 and protected_changes == 0, id + " only painted palette pixels change")
		check(src.albedo_texture.get_image().get_data() == bytes, id + " imported texture immutable")
		var wi := 0
		for node in model.get_children():
			if String(node.name).begins_with("wheel"):
				check(node.get_active_material(0) == wheel_mats[wi], id + " wheels untouched")
				wi += 1
		var uvs: PackedVector2Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var painted_uv := 0
		var protected_uv := 0
		for uv in uvs:
			var is_paint := int(uv.x * 8) == col and int(uv.y * 4) == 1
			var pixel := Vector2i(clampi(int(uv.x * 512), 0, 511), clampi(int(uv.y * 512), 0, 511))
			if is_paint: painted_uv += 1
			else:
				protected_uv += 1
				check(result.get_pixelv(pixel) == original.get_pixelv(pixel), id + " window/light/trim UV protected")
			# the layer is shared now: R — metallic multiplier, G — clearcoat multiplier
			for pair in [[mat.metallic_texture, mat.metallic, 0.8, 0.15, 0], [mat.roughness_texture, mat.roughness, 0.7, 0.28, 1]]:
				var image: Image = pair[0].get_image()
				var px := image.get_pixel(int(uv.x * image.get_width()), int(uv.y * image.get_height()))
				var value: float = (px.r if int(pair[4]) == 0 else px.g) * pair[1]
				check(absf(value - float(pair[2] if is_paint else pair[3])) < 0.004, id + " finish follows body mask")
		check(painted_uv > 100 and protected_uv > 100, id + " actual geometry includes painted and protected UVs")
		var dent := DentBody.new()
		dent.setup(p.model, p)
		check(dent._mat.albedo_texture.get_image().get_data() == result.get_data(), id + " preview and deformable paint agree")
		check(dent._mat.vertex_color_use_as_albedo and dent._mat.cull_mode == BaseMaterial3D.CULL_DISABLED, id + " damage and double-sided rendering preserved")
		dent.reset()
		check(dent._mat.albedo_texture.get_image().get_data() == result.get_data(), id + " reset keeps paint")
		var untouched: Node3D = load(p.model).instantiate()
		Materials.apply_tree(untouched, "car")
		check(untouched.get_node("body").get_active_material(0).albedo_texture.get_image().get_data() == bytes, id + " parked/other cars unaffected")
		untouched.free()
		dent.free()
		model.free()
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
