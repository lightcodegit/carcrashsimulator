# Car Crash Simulator — план внедрения

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3D-песочница аварий в духе BeamNG: жёсткая рама + verlet-клетка кузова с пластической деформацией, 3 машины, 3 карты, HUD, слоу-мо.

**Architecture:** Рама — `RigidBody3D` с аркадным `custom_integrator`; кузов — `SoftShell` (точки FOLLOW/DYNAMIC: целые зоны следуют за рамой, повреждённые симулируются verlet с пластичностью и разрывом пружин). Все сцены — тонкие `.tscn`-корни, содержимое строится кодом (меню, HUD, карты, машина); никаких .tres и внешних ассетов.

**Tech Stack:** Godot 4.7.2 (`C:/Users/user/Desktop/Godot.exe`), GDScript, Forward+.

**Spec:** `docs/superpowers/specs/2026-10-29-car-crash-simulator-design.md`

## Global Constraints

- Только Godot 4.7.2 и штатный GDScript; без аддонов, ассетов, .tres (пресеты — код).
- Запуск из редактора (F5). Экспорт — не в scope.
- Звук, сеть, AI-движение, манекены — вне v1 (spec §11).
- `Engine.time_scale` менять только через autoload `TimeScale`.
- Тесты: pure-data — `--script` (SceneTree-режим, только RefCounted-логика); узловых узлов physics — harness-сцены, печатают `PASS`/`FAIL` и `quit(0/1)`.
- Бюджет: шаг симуляции клетки < 8 мс в среднем (smoke логирует).
- Координаты машины: **+X = вперёд**, Y вверх, Z вбок (левый борт z<0).
- Команды: `"C:/Users/user/Desktop/Godot.exe" --headless --path . <args>` из корня репо.
- После каждой задачи: `git add -A && git commit`.

**Отклонения от файлового списка спеки (осознанные):** `vehicle_controller.gd` + `car_base.tscn` объединены в `car_rig.gd` (сборка машины кодом, сцена не нужна); `resources/cars/*.tres` → `vehicle_db.gd` (пресеты кодом, без .tres); частицы CPUParticles3D вместо GPUParticles (determinism в headless, простой one-shot reposition); input-карта регистрируется рантаймом `InputRouter` вместо сериализации в `project.godot` (версионно-безопасно); карты — `map_db.gd` кодом вместо `scenes/maps/*.tscn`. Поведенческие требования спеки (§3–§10) покрыты без отклонений; звук/AI/экспорт — §11.

---

### Task 1: Каркас проекта, autoloads, harness-паттерн

**Files:**
- Create: `project.godot`, `.gitignore`
- Create: `scripts/autoload/GameContext.gd`, `scripts/autoload/TimeScale.gd`, `scripts/autoload/InputRouter.gd`
- Create: `scripts/ui/main_menu.gd`, `scenes/main_menu.tscn`
- Test: `tests/h_t1.tscn`, `tests/h_t1.gd`

**Interfaces:**
- Produces: `GameContext.car_id: String` / `.map_id: String` / `.select(car,map)`; `TimeScale.play_auto(factor: float, real_secs: float)`, `.set_hold(flag: bool)`; `InputRouter` регистрирует экшены: `throttle, brake, steer_left, steer_right, handbrake, slowmo, cam_cycle, respawn, pause`.

- [ ] **Step 1: `.gitignore` и `project.godot`**

`.gitignore`:
```
.godot/
*.tmp
```

`project.godot`:
```ini
config_version=5

[application]
config/name="Car Crash Simulator"
run/main_scene="res://scenes/main_menu.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[autoload]
GameContext="*res://scripts/autoload/GameContext.gd"
TimeScale="*res://scripts/autoload/TimeScale.gd"
InputRouter="*res://scripts/autoload/InputRouter.gd"

[display]
window/size/viewport_width=1600
window/size/viewport_height=900

[rendering]
anti_aliasing/quality/msaa_3d=2
```

- [ ] **Step 2: Autoloads**

`scripts/autoload/GameContext.gd`:
```gdscript
extends Node
var car_id := "sedan"
var map_id := "arena"
func select(c: String, m: String) -> void:
	car_id = c; map_id = m
```

`scripts/autoload/TimeScale.gd` (реальное время через `Time.get_ticks_msec`, delta процесса масштабирован):
```gdscript
extends Node
var _auto_until_ms := 0
var _held := false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
func play_auto(factor: float, real_secs: float) -> void:
	Engine.time_scale = factor
	_auto_until_ms = Time.get_ticks_msec() + int(real_secs * 1000.0)
func set_hold(flag: bool) -> void:
	_held = flag
	if flag: Engine.time_scale = 0.3
func _process(_d: float) -> void:
	if Engine.time_scale == 1.0: return
	if Time.get_ticks_msec() >= _auto_until_ms and not _held:
		Engine.time_scale = 1.0
```

`scripts/autoload/InputRouter.gd` — регистрация экшенов в рантайме (без сериализации input-карты в project.godot). Оси геймпада (`JoyAxis`): LEFT_X=0, LEFT_Y=1, LT=4, RT=5; кнопки: A=0, B=1, X=2, Y=3, Start=6:
```gdscript
extends Node
const ACTIONS := {
	"throttle":   {"keys": [[KEY_W], [KEY_UP]], "joy": [["motion", 5, 0.5]]},
	"brake":      {"keys": [[KEY_S], [KEY_DOWN]], "joy": [["motion", 4, 0.5]]},
	"steer_left": {"keys": [[KEY_A], [KEY_LEFT]], "joy": [["motion", 0, -0.5]]},
	"steer_right":{"keys": [[KEY_D], [KEY_RIGHT]], "joy": [["motion", 0, 0.5]]},
	"handbrake":  {"keys": [[KEY_SPACE]], "joy": [["button", 0]]},
	"slowmo":     {"keys": [[KEY_SHIFT]], "joy": [["button", 1]]},
	"cam_cycle":  {"keys": [[KEY_C]], "joy": [["button", 2]]},
	"respawn":    {"keys": [[KEY_R]], "joy": [["button", 3]]},
	"pause":      {"keys": [[KEY_ESCAPE]], "joy": [["button", 6]]},
}
func _ready() -> void:
	for name_v in ACTIONS:
		if not InputMap.has_action(name_v): InputMap.add_action(name_v)
		for kd in ACTIONS[name_v].keys:
			var e := InputEventKey.new(); e.physical_keycode = kd[0]
			InputMap.action_add_event(name_v, e)
		for jd in ACTIONS[name_v].joy:
			if jd[0] == "button":
				var b := InputEventJoypadButton.new(); b.button_index = jd[1]
				InputMap.action_add_event(name_v, b)
			else:
				var m := InputEventJoypadMotion.new(); m.axis = jd[1]; m.axis_value = jd[2]
				InputMap.action_add_event(name_v, m)
```


- [ ] **Step 3: Меню-заглушка + harness**

`scripts/ui/main_menu.gd` (в Task 11 станет полным; сейчас — чтобы main_scene грузился):
```gdscript
extends Control
func _ready() -> void:
	var l := Label.new(); l.text = "Car Crash Simulator"; add_child(l)
```

`scenes/main_menu.tscn`:
```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/ui/main_menu.gd" id="1"]
[node name="MainMenu" type="Control"]
anchors_preset = 15
script = ExtResource("1")
```

`tests/h_t1.gd` — шаблон physics-harness (переиспользуется во всех задачах):
```gdscript
extends Node
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)
func _physics_process(_dt: float) -> void:
	check(InputMap.has_action("throttle"), "throttle action registered")
	check(InputMap.action_get_events("handbrake").size() >= 2, "handbrake keys+pad")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
```

`tests/h_t1.tscn`:
```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/h_t1.gd" id="1"]
[node name="Test" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 4: Import + прогон harness (fail→pass)**

Run: `"C:/Users/user/Desktop/Godot.exe" --headless --path . --import`
Run: `"C:/Users/user/Desktop/Godot.exe" --headless --path . --quit-after 10 res://tests/h_t1.tscn`
Expected: `ALL PASS`, exit code 0. (До регистрации autoloads harness обязан упасть с FAIL — проверить порядок.)

- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(t1): Godot project scaffold, autoloads, input map, test harness pattern"`

---

### Task 2: VehicleParams + пресеты 3 машин

**Files:**
- Create: `scripts/core/vehicle_params.gd` (класс `VehicleParams`), `scripts/core/vehicle_db.gd` (`VehicleDB`)
- Test: `tests/t2_params.gd`

**Interfaces:**
- Produces:
  - `VehicleParams` (Resource-класс, создаётся кодом): поля `car_id: String`, `mass, accel_max, vmax_kmh, brake_decel, steer_rate_deg, grip: float`, `length, width, height, gc, body_h, roof_h, cab_x0, cab_x1: float`, `sections, ring_points: int`, `k_struct, k_anchor, break_strain: float`, `shell_color: Color`, метод `collider_size() -> Vector3`.
  - `VehicleDB.get_params(id: String) -> VehicleParams` — глобальный class_name, ключи `"sedan","pickup","sport"`.

- [ ] **Step 1: Тест (script-mode)**

`tests/t2_params.gd`:
```gdscript
extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)
func _initialize() -> void:
	for id in ["sedan", "pickup", "sport"]:
		var p = VehicleDB.get_params(id)
		check(p != null, "%s exists" % id)
		check(p.mass > 500 and p.vmax_kmh > 100, "%s sane stats" % id)
		check(p.body_h + p.roof_h + p.gc == p.height or absf(p.body_h + p.roof_h + p.gc - p.height) < 0.01, "%s height consistent" % id)
		check(p.cab_x1 > p.cab_x0, "%s cabin ordered" % id)
		check(p.sections >= 16 and p.ring_points == 16, "%s cage resolution" % id)
		check(p.break_strain > 0.1 and p.break_strain < 0.5, "%s strain range" % id)
	check(VehicleDB.get_params("sedan").break_strain < VehicleDB.get_params("pickup").break_strain, "sedan crumples easier than pickup")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
```
Run: `... --headless --path . --script res://tests/t2_params.gd` → Expected: FAIL `vehicle_params.gd` не найден.

- [ ] **Step 2: Реализация**

`scripts/core/vehicle_params.gd`:
```gdscript
class_name VehicleParams
extends Resource
@export var car_id := ""
@export var mass := 1300.0
@export var accel_max := 7.0
@export var vmax_kmh := 160.0
@export var brake_decel := 22.0
@export var steer_rate_deg := 38.0
@export var grip := 8.0
@export var length := 4.4
@export var width := 1.8
@export var height := 1.45
@export var gc := 0.32
@export var body_h := 0.70
@export var roof_h := 0.43
@export var cab_x0 := -1.0
@export var cab_x1 := 0.9
@export var sections := 20
@export var ring_points := 16
@export var k_struct := 1.0
@export var k_anchor := 1.2
@export var break_strain := 0.22
@export var shell_color := Color.RED
func collider_size() -> Vector3:
	return Vector3(length * 0.92, height - 0.12, width * 0.9)
```

`scripts/core/vehicle_db.gd` (пресеты инвариант высоты соблюдают: `gc+body_h+roof_h == height`):
```gdscript
class_name VehicleDB
extends RefCounted

static func get_params(id: String) -> VehicleParams:
	var p := VehicleParams.new()
	p.car_id = id
	match id:
		"sedan":
			p.mass = 1300; p.accel_max = 7.0; p.vmax_kmh = 160; p.brake_decel = 22
			p.steer_rate_deg = 38; p.grip = 8.0
			p.length = 4.4; p.width = 1.8; p.height = 1.45; p.gc = 0.32
			p.body_h = 0.70; p.roof_h = 0.43; p.cab_x0 = -1.0; p.cab_x1 = 0.9
			p.sections = 20; p.k_struct = 1.0; p.k_anchor = 1.2
			p.break_strain = 0.22; p.shell_color = Color(0.78, 0.18, 0.16)
		"pickup":
			p.mass = 1900; p.accel_max = 6.0; p.vmax_kmh = 140; p.brake_decel = 18
			p.steer_rate_deg = 30; p.grip = 6.0
			p.length = 5.2; p.width = 2.0; p.height = 1.9; p.gc = 0.45
			p.body_h = 0.95; p.roof_h = 0.50; p.cab_x0 = -1.6; p.cab_x1 = -0.1
			p.sections = 22; p.k_struct = 1.3; p.k_anchor = 1.6
			p.break_strain = 0.28; p.shell_color = Color(0.16, 0.35, 0.72)
		"sport":
			p.mass = 1050; p.accel_max = 11.0; p.vmax_kmh = 210; p.brake_decel = 26
			p.steer_rate_deg = 42; p.grip = 9.0
			p.length = 4.2; p.width = 1.9; p.height = 1.15; p.gc = 0.22
			p.body_h = 0.52; p.roof_h = 0.41; p.cab_x0 = -0.9; p.cab_x1 = 0.5
			p.sections = 18; p.k_struct = 0.8; p.k_anchor = 1.0
			p.break_strain = 0.16; p.shell_color = Color(0.85, 0.75, 0.2)
		_:
			return null
	return p
```

- [ ] **Step 3: Прогон:** `--script res://tests/t2_params.gd` → Expected: `ALL PASS`.
- [ ] **Step 4: Commit** `"feat(t2): vehicle params + sedan/pickup/sport presets"`

---

### Task 3: ShellBuilder — генерация клетки кузова (чистая функция)

**Files:**
- Create: `scripts/core/shell_spec.gd` (`ShellSpec`, `Spring`, `Zone`, `SpringType`)
- Create: `scripts/core/shell_builder.gd`
- Test: `tests/t3_builder.gd`

**Interfaces:**
- Consumes: `VehicleParams` (Task 2).
- Produces:
  - `ShellSpec.points: Array[Vector3]` (локальные координаты), `.zones: Array[int]` (по Zone), `.springs: Array[Spring]`, `.triangles: PackedInt32Array` (плоский idx3), `.chassis_nodes: Array[Vector3]` (10 локальных точек рамы), `.zone_spring_totals: Array[int]` (пружин на Zone).
  - `Spring`: поля `a: int`, `b: int`, `rest: float`, `type: int` (`SpringType.STRUCT/SHEAR/BEND/ANCHOR`), `anchor: int` (-1 или индекс chassis-ноды), `zone: int`.
  - `Zone` enum: `REAR=0, LEFT=1, RIGHT=2, ROOF=3, FRONT=4`.
  - `ShellBuilder.build(p: VehicleParams) -> ShellSpec` (static).

- [ ] **Step 1: Тест (script-mode)**

`tests/t3_builder.gd`:
```gdscript
extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)
func _initialize() -> void:
	var SB := preload("res://scripts/core/shell_builder.gd")
	for id in ["sedan", "pickup", "sport"]:
		var p = VehicleDB.get_params(id)
		var spec = SB.build(p)
		var n_pts := p.sections * p.ring_points + 2
		check(spec.points.size() == n_pts, "%s point count %d == %d" % [id, spec.points.size(), n_pts])
		check(spec.points.size() >= 288 and spec.points.size() <= 420, "%s in budget" % id)
		check(spec.springs.size() > 1200, "%s spring count %d" % [id, spec.springs.size()])
		var ok_idx := true; var ok_rest := true; var n_anchor := 0
		for s in spec.springs:
			if s.type == 3:
				if s.anchor < 0 or s.anchor >= spec.chassis_nodes.size(): ok_idx = false
				var d_a := spec.points[s.a].distance_to(spec.chassis_nodes[s.anchor])
				if s.rest <= 0.001 or absf(s.rest - d_a) > 0.001: ok_rest = false
				n_anchor += 1
			else:
				if s.a < 0 or s.b < 0 or s.a >= n_pts or s.b >= n_pts: ok_idx = false
				if s.rest <= 0.001 or absf(s.rest - spec.points[s.a].distance_to(spec.points[s.b])) > 0.001: ok_rest = false
		check(ok_idx, "%s spring indices valid" % id)
		check(ok_rest, "%s rest lengths match geometry" % id)
		check(n_anchor >= n_pts * 0.4 and n_anchor <= n_pts, "%s anchor coverage" % id)
		check(spec.triangles.size() % 3 == 0 and spec.triangles.size() > n_pts * 3, "%s triangulated" % id)
		var finite := true
		for pt in spec.points: if not pt.is_finite(): finite = false
		check(finite, "%s points finite" % id)
		for z in range(5): check(spec.zone_spring_totals[z] > 0, "%s zone %d has springs" % [id, z])
		check(spec.chassis_nodes.size() == 10, "%s chassis nodes" % id)
		# геометрия: cabin-секции выше body: максимальная y ближе к центру, чем к носу
		check(spec.zones[0] == 0, "%s tail point is REAR zone" % id)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
```
Run → Expected: FAIL (модули не существуют).

- [ ] **Step 2: `scripts/core/shell_spec.gd`**

```gdscript
class_name SpringType
enum T { STRUCT, SHEAR, BEND, ANCHOR }
class_name Zone
enum Z { REAR, LEFT, RIGHT, ROOF, FRONT }

class_name Spring extends RefCounted
var a := 0
var b := 0
var rest := 0.0
var type := 0
var anchor := -1
var zone := 0

class_name ShellSpec extends RefCounted
var points: Array[Vector3] = []
var zones: Array[int] = []
var springs: Array = []            # Spring[]
var triangles := PackedInt32Array()
var chassis_nodes: Array[Vector3] = []
var zone_spring_totals: Array[int] = [0, 0, 0, 0, 0]
```

- [ ] **Step 3: `scripts/core/shell_builder.gd`**

Кольцевая клетка: S сечений-эллипсов по P точек, кабина — blend верхних точек во второй эллипс; нос/хвост — радиальные точки. Пружины: ring (STRUCT), longitudinal (STRUCT), diagonal (SHEAR), vertical/floor brace (BEND), nose/tail radial (STRUCT), anchor→ближайшая chassis-нода (ANCHOR, `b = -1`).

```gdscript
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
	spec.points.append(Vector3(half_l + 0.15, body_cy, 0)); spec.zones.append(Zone.FRONT)
	var tail_idx := spec.points.size()
	spec.points.append(Vector3(-half_l - 0.15, body_cy, 0)); spec.zones.append(Zone.REAR)
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
		if ty == SpringType.ANCHOR:
			sp.rest = spec.points[ai].distance_to(spec.chassis_nodes[anchor])
		else:
			sp.rest = spec.points[ai].distance_to(spec.points[bi])
		sp.zone = spec.zones[ai]
		spec.springs.append(sp)
		spec.zone_spring_totals[sp.zone] += 1
	for s in S:
		for i in P:
			add.call(s * P + i, s * P + (i + 1) % P, SpringType.STRUCT, -1)
			if s < S - 1:
				add.call(s * P + i, (s + 1) * P + i, SpringType.STRUCT, -1)
				add.call(s * P + i, (s + 1) * P + (i + 1) % P, SpringType.SHEAR, -1)
		if s % 2 == 0:
			add.call(s * P + 0, s * P + P / 2, SpringType.BEND, -1)
			add.call(s * P + P / 4, s * P + P * 3 / 4, SpringType.BEND, -1)
	for i in P:
		add.call(nose_idx, (S - 1) * P + i, SpringType.STRUCT, -1)
		add.call(tail_idx, i, SpringType.STRUCT, -1)
	for s in S:
		for i in [0, P / 4, P / 2, P * 3 / 4]:
			var pi := s * P + i
			add.call(pi, -1, SpringType.ANCHOR, _nearest_node(spec.chassis_nodes, spec.points[pi]))
	for pi in [nose_idx, tail_idx]:
		add.call(pi, -1, SpringType.ANCHOR, _nearest_node(spec.chassis_nodes, spec.points[pi]))
	# 4) триангуляция (замкнутая поверхность, обмотка наружу)
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
	if x > half_l * 0.7: return Zone.FRONT
	if x < -half_l * 0.7: return Zone.REAR
	if cs > 0.3 and blend > 0.5: return Zone.ROOF
	return Zone.RIGHT if sn > 0.0 else Zone.LEFT

static func _nearest_node(nodes: Array[Vector3], pt: Vector3) -> int:
	var best := 0; var bd := INF
	for k in nodes.size():
		var d := nodes[k].distance_squared_to(pt)
		if d < bd: bd = d; best = k
	return best
```

Для ANCHOR-пружин `b == -1` — рантайм (Task 4) трактует её как «точка a ↔ chassis-нода `anchor`». В тесте Step 1 условие `ok_idx` для anchor-пружин проверяет `s.anchor >= 0` и не читает `s.b`; `ok_rest` для anchor считает расстояние до `spec.chassis_nodes[s.anchor]` (в тестовой выборке это уже учтено веткой `type == 3`).

- [ ] **Step 4: Прогон:** `--script res://tests/t3_builder.gd` → Expected: `ALL PASS`.

- [ ] **Step 4: Прогон:** `--script res://tests/t3_builder.gd` → Expected: `ALL PASS` (после правок из примечаний).
- [ ] **Step 5: Commit** `"feat(t3): parametric shell cage builder"`

---

### Task 4: SoftShell — verlet-симуляция клетки (FOLLOW/DYNAMIC, пластичность, разрыв)

**Files:**
- Create: `scripts/core/soft_shell.gd`
- Test: `tests/t4_shell.gd` (script-mode: chassis = plain Node3D, шаг вызывается вручную)

**Interfaces:**
- Consumes: `ShellSpec`, `Spring`, `Zone`, `VehicleParams`.
- Produces (`SoftShell extends Node3D`):
  - `setup(spec: ShellSpec, chassis: Node3D, params: VehicleParams) -> void` — chassis может быть Node3D (тесты) или RigidBody3D (игра); скорость шасси: `velocity_getter: Callable -> Array[Vector3]` (опционально; default — zeros).
  - сигналы: `spring_burst(zone: int)`, `plastic_event(zone: int, world_pos: Vector3, energy: float)`.
  - `sim_step(dt: float) -> float` — один физика-шаг (внутри 2 substep), возвращает мс; вызывается из `_physics_process` и тестами.
  - `apply_impact(world_pos: Vector3, dir: Vector3, speed_ms: float) -> void` (Task 5 реализует столкновение с миром; здесь — wake + crush).
  - `broken_by_zone: Array[int]`, `get_broken_total() -> int`, `dyn_count() -> int`, `point_world(i) -> Vector3`.
  - `reset() -> void` (полный сброс повреждений, respawn), `set_zone_hp(hp: Array[float])`.
  - константы: `SUBSTEPS=2, RELAX=3, DAMP=0.985, MAX_PT_SPEED=25.0, YIELD=0.05, YIELD_C=0.08, SLEEP_FRAMES=90`.

- [ ] **Step 1: Тест**

`tests/t4_shell.gd` (script-mode; chassis = plain Node3D в identity, шаг вызывается вручную):
```gdscript
extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _make_shell(chassis: Node3D) -> SoftShell:
	var p = VehicleDB.get_params("sedan")
	var spec = ShellBuilder.build(p)
	var shell := SoftShell.new()
	shell.setup(spec, chassis, p)
	return shell

func _initialize() -> void:
	var chassis := Node3D.new()
	var sh := _make_shell(chassis)
	check(sh.dyn_count() == 0, "A1 idle dynamic zero")
	for f in 120: sh.sim_step(1.0 / 60.0)
	check(sh.get_broken_total() == 0, "A2 idle nothing breaks")
	check(sh.get_sim_ms_avg() < 8.0, "A3 sim step under 8ms (%.2f)" % sh.get_sim_ms_avg())

	# B) удар в нос на 20 m/s: wake, пластичность, разрыв, монотонность по энергии
	var bursts := [0]
	sh.spring_burst.connect(func(z): bursts[0] += 1)
	sh.apply_impact(Vector3(2.35, 0.8, 0), Vector3(-1, 0, 0), 20.0)
	check(sh.dyn_count() > 20, "B1 impact wakes points (%d)" % sh.dyn_count())
	for f in 240: sh.sim_step(1.0 / 60.0)
	var finite := true
	for i in sh.point_count():
		if not sh.point_world(i).is_finite(): finite = false
	check(finite, "B2 no NaN after impact")
	check(sh.broken_by_zone[Zone.FRONT] >= 8, "B3 front springs burst (%d)" % sh.broken_by_zone[Zone.FRONT])
	check(sh.broken_by_zone[Zone.ROOF] * 2 <= sh.broken_by_zone[Zone.FRONT], "B4 damage localized to front")
	var sh2 := _make_shell(chassis)
	sh2.apply_impact(Vector3(2.35, 0.8, 0), Vector3(-1, 0, 0), 40.0)
	for f in 120: sh2.sim_step(1.0 / 60.0)
	check(sh2.broken_by_zone[Zone.FRONT] > sh.broken_by_zone[Zone.FRONT], "B5 stronger impact more damage (%d > %d)" % [sh2.broken_by_zone[Zone.FRONT], sh.broken_by_zone[Zone.FRONT]])

	# C) reset
	sh.reset()
	check(sh.get_broken_total() == 0 and sh.dyn_count() == 0, "C1 reset clears damage")

	# D) саг без пола: анкеры держат клетку
	var sh3 := _make_shell(chassis)
	sh3.apply_impact(Vector3(0, 1.0, 0), Vector3(0, 1, 0), 5.0)
	for f in 600: sh3.sim_step(1.0 / 60.0)
	var min_y := INF
	for i in sh3.point_count(): min_y = minf(min_y, sh3.point_world(i).y)
	check(min_y > 0.15 * 1.45, "D1 cage hangs above sag limit (min_y=%.2f)" % min_y)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Прогон** `--script res://tests/t4_shell.gd` → Expected: FAIL (`SoftShell` не существует).

- [ ] **Step 3: Реализация `scripts/core/soft_shell.gd`**

```gdscript
class_name SoftShell
extends Node3D

signal spring_burst(zone: int)
signal plastic_event(zone: int, world_pos: Vector3, energy: float)

const SUBSTEPS := 2
const RELAX := 3
const DAMP := 0.985
const MAX_PT_SPEED := 25.0
const YIELD := 0.05
const YIELD_C := 0.08
const SLEEP_FRAMES := 90
const GRAVITY := Vector3(0, -9.8, 0)

var spec: ShellSpec
var params: VehicleParams
var chassis: Node3D
var velocity_getter := Callable()          # -> Vector3 линейная скорость шасси

var _pos: Array[Vector3] = []
var _prev: Array[Vector3] = []
var _rest_local: Array[Vector3] = []
var _dyn: Array[bool] = []
var _still: Array[int] = []
var _adj: Array = []                      # Array[PackedInt32Array] spring indices per point
var _spring_on: PackedByteArray = PackedByteArray()
var _spring_rest: PackedFloat64Array = PackedFloat64Array()
var broken_by_zone: Array[int] = [0, 0, 0, 0, 0]
var _dyn_count := 0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _zone_hp: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0]
var _sim_ms_sum := 0.0
var _sim_frames := 0
var space_state: PhysicsDirectSpaceState3D   # задаёт CarRig/тест; null => коллизий с миром нет (Task 5)

func setup(s: ShellSpec, ch: Node3D, p: VehicleParams) -> void:
	spec = s; chassis = ch; params = p
	_pos.resize(s.points.size()); _prev.resize(s.points.size())
	_rest_local.assign(s.points); _dyn.resize(s.points.size()); _still.resize(s.points.size())
	_adj.clear()
	for i in s.points.size(): _adj.append(PackedInt32Array()); _dyn[i] = false; _still[i] = 0
	_spring_on.resize(s.springs.size()); _spring_on.fill(1)
	_spring_rest.resize(s.springs.size())
	for k in s.springs.size():
		_spring_rest[k] = s.springs[k].rest
		_adj[s.springs[k].a].append(k)
		if s.springs[k].b >= 0: _adj[s.springs[k].b].append(k)
	broken_by_zone = [0, 0, 0, 0, 0]; _dyn_count = 0
	_mesh = MeshInstance3D.new(); add_child(_mesh)
	_mat = StandardMaterial3D.new()
	_mat.metallic = 0.55; _mat.roughness = 0.35
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _mat
	_rebuild_mesh()

func _physics_process(dt: float) -> void:
	sim_step(dt)

func sim_step(dt: float) -> float:
	var t0 := Time.get_ticks_usec()
	if _dyn_count > 0 and chassis != null:
		var h := dt / float(SUBSTEPS)
		for s in SUBSTEPS:
			_integrate(h)
			for it in RELAX: _relax()
			_collide_world(h)
			_plasticity_and_break()
		_nan_guard()
		_sleep_check()
	_rebuild_mesh()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_sim_ms_sum += ms; _sim_frames += 1
	return ms

func _nan_guard() -> void:
	for i in spec.points.size():
		if _dyn[i] and not _pos[i].is_finite():
			push_warning("SoftShell NaN: resetting dynamic points")
			for k in spec.points.size():
				if _dyn[k]:
					_pos[k] = _chassis_xform() * _rest_local[k]
					_prev[k] = _pos[k]
			return

func get_sim_ms_avg() -> float:
	return _sim_ms_sum / maxf(1.0, float(_sim_frames))

func _chassis_xform() -> Transform3D:
	return chassis.global_transform

func _pt(i: int) -> Vector3:
	if _dyn[i]: return _pos[i]
	return _chassis_xform() * _rest_local[i]

func _wake(i: int, base_vel: Vector3) -> void:
	if _dyn[i]: return
	_dyn[i] = true; _dyn_count += 1; _still[i] = 0
	_pos[i] = _chassis_xform() * _rest_local[i]
	_prev[i] = _pos[i] - base_vel / 60.0 / float(SUBSTEPS)

func _point_vel_at(r_local: Vector3) -> Vector3:
	if not velocity_getter.is_valid(): return Vector3.ZERO
	return velocity_getter.call()

func apply_impact(world_pos: Vector3, dir: Vector3, speed_ms: float) -> void:
	var R := 0.7 + minf(speed_ms, 40.0) * 0.012
	var crush_vel := minf(8.0, speed_ms * 0.35)
	var v_ch := _point_vel_at(Vector3.ZERO)
	var R2 := R * R
	for i in spec.points.size():
		var wp := _pt(i)
		if wp.distance_squared_to(world_pos) > R2: continue
		_wake(i, v_ch - dir * crush_vel)
		# уже dynamic до вызова: добавить inward-компоненту через сдвиг prev
		if _dyn[i] and _still[i] > 0:
			_prev[i] += dir * crush_vel / 120.0
		elif not _dyn[i]:
			pass  # _wake только что поставил _prev с нужной скоростью
	var n := int(crush_vel * 4.0) + 1
	for k in min(n, 6):
		plastic_event.emit(zone_at(world_pos), world_pos, speed_ms * 0.02)

func zone_at(world_pos: Vector3) -> int:
	var local := _chassis_xform().affine_inverse() * world_pos
	var half_l := params.length * 0.5
	if local.x > half_l * 0.7: return Zone.FRONT
	if local.x < -half_l * 0.7: return Zone.REAR
	return Zone.ROOF if local.y > params.gc + params.body_h else (Zone.RIGHT if local.z > 0 else Zone.LEFT)

func _integrate(h: float) -> void:
	var h2 := h * h
	for i in spec.points.size():
		if not _dyn[i]: continue
		var v := (_pos[i] - _prev[i]) * DAMP
		if v.length() > MAX_PT_SPEED * h: v = v.normalized() * MAX_PT_SPEED * h
		_prev[i] = _pos[i]
		_pos[i] += v + GRAVITY * h2

func _anchor_target(k: int) -> Vector3:
	var sp = spec.springs[k]
	return _chassis_xform() * spec.chassis_nodes[sp.anchor]

func _relax() -> void:
	for k in spec.springs.size():
		if _spring_on[k] == 0: continue
		var sp = spec.springs[k]
		var pa := _pt(sp.a)
		var pb: Vector3
		if sp.type == SpringType.ANCHOR: pb = _anchor_target(k)
		else: pb = _pt(sp.b)
		var delta := pb - pa
		var len := delta.length()
		if len < 1e-6: continue
		var rest := _spring_rest[k]
		var kk: float
		match sp.type:
			SpringType.STRUCT: kk = 0.9 * params.k_struct
			SpringType.SHEAR: kk = 0.6 * params.k_struct
			SpringType.BEND: kk = 0.35
			_: kk = minf(1.0, 0.95 * params.k_anchor)
		kk = minf(kk, 1.0)
		var corr := delta * (1.0 - rest / len) * kk
		if sp.type == SpringType.ANCHOR:
			if _dyn[sp.a]: _pos[sp.a] += corr
		elif _dyn[sp.a] and _dyn[sp.b]:
			_pos[sp.a] += corr * 0.5; _pos[sp.b] -= corr * 0.5
		elif _dyn[sp.a]: _pos[sp.a] += corr
		elif _dyn[sp.b]: _pos[sp.b] -= corr

func _break_strain_for(ty: int) -> float:
	match ty:
		SpringType.ANCHOR: return params.break_strain * 1.8
		SpringType.SHEAR: return params.break_strain * 1.15
		SpringType.BEND: return params.break_strain
		_: return params.break_strain

func _plasticity_and_break() -> void:
	for k in spec.springs.size():
		if _spring_on[k] == 0: continue
		var sp = spec.springs[k]
		var pa := _pt(sp.a)
		var pb: Vector3 = _anchor_target(k) if sp.type == SpringType.ANCHOR else _pt(sp.b)
		var len := pa.distance_to(pb)
		var rest := _spring_rest[k]
		var strain := (len - rest) / maxf(rest, 1e-6)
		if strain > _break_strain_for(sp.type):
			_spring_on[k] = 0
			broken_by_zone[sp.zone] += 1
			spring_burst.emit(sp.zone)
			if _dyn[sp.a] == false and sp.type != SpringType.ANCHOR: _wake(sp.a, _point_vel_at(Vector3.ZERO))
			if sp.b >= 0 and not _dyn[sp.b]: _wake(sp.b, _point_vel_at(Vector3.ZERO))
			continue
		if strain > YIELD or strain < -YIELD_C:
			_spring_rest[k] = lerpf(rest, len, 0.85)   # пластичность: вмятина остаётся
			if randi() % 8 == 0:
				plastic_event.emit(sp.zone, (pa + pb) * 0.5, absf(strain))

func _collide_world(_h: float) -> void:
	pass  # реализуется в Task 5

func _sleep_check() -> void:
	for i in spec.points.size():
		if not _dyn[i]: continue
		var v := (_pos[i] - _prev[i]) * 120.0
		if v.length() < 0.04:
			_still[i] += 1
			if _still[i] >= SLEEP_FRAMES:
				_rest_local[i] = _chassis_xform().affine_inverse() * _pos[i]
				_dyn[i] = false; _dyn_count -= 1
		else:
			_still[i] = 0

func _rebuild_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := params.shell_color
	for t in range(spec.triangles.size() / 3):
		for v in 3:
			var i: int = spec.triangles[t * 3 + v]
			st.set_color(base.lerp(Color(0.16, 0.14, 0.13), 1.0 - _zone_hp[spec.zones[i]] / 100.0))
			st.add_vertex(_pt(i))
	st.generate_normals()
	st.index()
	_mesh.mesh = st.commit()

func point_count() -> int: return spec.points.size()
func point_world(i: int) -> Vector3: return _pt(i)
func dyn_count() -> int: return _dyn_count
func get_broken_total() -> int:
	var s := 0
	for z in broken_by_zone: s += z
	return s

func reset() -> void:
	for i in spec.points.size(): _dyn[i] = false; _still[i] = 0; _rest_local[i] = spec.points[i]
	_dyn_count = 0
	_spring_on.fill(1)
	for k in spec.springs.size(): _spring_rest[k] = spec.springs[k].rest
	broken_by_zone = [0, 0, 0, 0, 0]
	_zone_hp = [100.0, 100.0, 100.0, 100.0, 100.0]
	_rebuild_mesh()

func set_zone_hp(hp: Array[float]) -> void:
	_zone_hp = hp
```

Примечания к реализации:
- `_wake(i, base_vel)` для уже-dynamic точки — no-op; inward-ускорение такой точке даёт ветка с `_prev[i] +=` в `apply_impact`.
- `velocity_getter` CarRig выставит в Task 6 как `func(): return chassis.linear_velocity`.
- `plastic_event` при ударе эмитится n раз сразу — effects (Task 8) вешает на это искры; `energy = speed_ms * 0.02`.
- Тест B использует identity-трансформ шасси; `world_pos = (2.35, 0.8, 0)` — зона FRONT, радиус ≈0.94 ловит nose и передние ring-точки.

- [ ] **Step 4: Прогон** → Expected: `ALL PASS` (B5 монотонность — при необходимости поднять `crush_vel` cap или R, но менять константы только с обоснованием в коммите).
- [ ] **Step 5: Commit** `"feat(t4): SoftShell verlet with plasticity, break, sleep, dynamic mesh"`

---

### Task 5: Столкновение клетки с миром (rays + push-out)

**Files:**
- Modify: `scripts/core/soft_shell.gd` (реализовать `_collide_world`, поле `space_state`)
- Test: `tests/h_t5.tscn` + `tests/h_t5.gd` (physics-harness: нужен реальный World3D)

**Interfaces:**
- Consumes: `SoftShell.sim_step`, `apply_impact`.
- Produces: `SoftShell.space_state: PhysicsDirectSpaceState3D` (присваивает CarRig/game_manager; если null — коллизий нет). Поведение: динамическая точка, пересекающая препятствие (луч prev→pos) или оказавшаяся ниже hit-поверхности (нисходящий зонд 0.15 м), выталкивается в `position + normal * 0.01`; нормальная составляющая скорости гасится (restitution 0.2), касательная сохраняется ×0.85 (трение).

- [ ] **Step 1: Harness-тест**

`tests/h_t5.gd`:
```gdscript
extends Node
var _fails := 0
var _frame := 0
var shell: SoftShell
var chassis: Node3D
var floor_top_y := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	# пол: верх y=0
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40); cs.shape = box
	body.add_child(cs); body.global_position = Vector3(0, -0.5, 0)
	add_child(body)
	# тонкая стена: грань x=6.0 (центр 6.1, толщина 0.2) — тест свип-луча на «дырявых» объектах
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.2, 4, 8); wcs.shape = wbox
	wall.add_child(wcs); wall.global_position = Vector3(6.1, 2, 0)
	add_child(wall)
	await get_tree().process_frame
	shell = SoftShell.new()
	var p = VehicleDB.get_params("sedan")
	add_child(shell); add_child((chassis := Node3D.new()))
	# шасси: нос (local x=2.35) в 5.95 — ровно перед стеной
	chassis.global_position = Vector3(3.6, 2.5, 0)
	shell.setup(ShellBuilder.build(p), chassis, p)
	shell.space_state = get_world_3d().direct_space_state
	# dir — outward normal стены (от стены к машине) = -X; точки полетят +X (внутрь стены)
	shell.apply_impact(Vector3(6.0, 3.17, 0), Vector3(-1, 0, 0), 15.0)
	# и вниз к полу: dir = +Y (нормаль пола), точки полетят -Y
	shell.apply_impact(chassis.global_position + Vector3(0, 0.13, 0), Vector3(0, 1, 0), 30.0)

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 240:
		var below_floor := 0; var behind_wall := 0
		for i in shell.point_count():
			var wp := shell.point_world(i)
			if wp.y < floor_top_y - 0.02: below_floor += 1
			if wp.x > 6.25: behind_wall += 1
			if not wp.is_finite(): check(false, "NaN at %d" % i); break
		check(below_floor == 0, "no point under floor (%d)" % below_floor)
		check(behind_wall == 0, "no point through wall (%d)" % behind_wall)
		check(shell.broken_by_zone[Zone.FRONT] > 0, "wall crash damaged front (%d)" % shell.broken_by_zone[Zone.FRONT])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
```
`tests/h_t5.tscn`: корень `Node` + скрипт (тот же паттерн, что `h_t1.tscn`, путь `res://tests/h_t5.gd`).

- [ ] **Step 2: Прогон** → Expected: FAIL (точки проходят сквозь пол/стену: `_collide_world` пустой).

- [ ] **Step 3: Реализация**

В `soft_shell.gd` заменить пустой `_collide_world` (поле `space_state` уже объявлено в Task 4):
```gdscript
func _collide_world(h: float) -> void:
	if space_state == null: return
	for i in spec.points.size():
		if not _dyn[i]: continue
		# 1) свип prev -> pos против мира
		if space_state != null and _pos[i] != _prev[i]:
			var q := PhysicsRayQueryParameters3D.create(_prev[i], _pos[i])
			q.collide_with_bodies = true; q.collide_with_areas = false
			var hit := space_state.intersect_ray(q)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				_pos[i] = hit.position + n * 0.01
				var v := _pos[i] - _prev[i]
				var vn := n * v.dot(n)
				_prev[i] = _pos[i] - (v - vn * 1.2) * 0.85   # погасить нормаль, оставить касательную
				continue
		# 2) зонд вниз (точка уже внутри/под поверхностью после push-out)
		var q2 := PhysicsRayQueryParameters3D.create(_pos[i] + Vector3(0, 0.05, 0), _pos[i] - Vector3(0, 0.2, 0))
		q2.collide_with_bodies = true
		var hit2 := space_state.intersect_ray(q2)
		if not hit2.is_empty() and hit2.normal.y > 0.3:
			_pos[i].y = hit2.position.y + 0.01
			var v2 := _pos[i] - _prev[i]
			_prev[i] = _pos[i] - Vector3(v2.x * 0.9, -maxf(0.0, -v2.y) * 0.2, v2.z * 0.9)
```
Семантика: (1) — скоростное проникновение (луч prev→pos ловит тонкие стены до пересечения); (2) — статичное (саг/выталкивание). `1.2/0.85/0.9/0.2` — демпфирование и трение; константы оставить как есть, тюнинг — только в Task 12 с замером.

- [ ] **Step 4: Прогон harness:** `... --quit-after 400 res://tests/h_t5.tscn` → `ALL PASS`. Повторить t4 (`--script res://tests/t4_shell.gd`): там `space_state == null` → коллизии нет, тест обязан остаться зелёным.
- [ ] **Step 5: Commit** `"feat(t5): shell world collision via sweep rays + down probe"`

---

### Task 6: CarRig — рама, аркадный контроллер, связь удара с клеткой

**Files:**
- Create: `scripts/core/car_rig.gd`
- Test: `tests/h_t6.tscn` + `tests/h_t6.gd`

**Interfaces:**
- Consumes: `SoftShell`, `ShellBuilder`, `VehicleDB/VehicleParams`.
- Produces (`CarRig extends Node3D`):
  - `build(params: VehicleParams, world: World3D) -> void` — создаёт chassis/коллайдер/колёса/shell.
  - поля: `chassis: RigidBody3D`, `shell: SoftShell`, `params: VehicleParams`, `heading: float`.
  - методы: `speed_kmh() -> float`, `is_airborne() -> bool`, `respawn(tf: Transform3D) -> void`, `reset_damage()` (через shell.reset()).
  - сигналы: `impact(speed_kmh: float, point: Vector3, normal: Vector3)`, `crash_input_dump` — нет; только impact.
  - контроллер: custom_integrator, +X вперёд; `Input.is_action_*` читает сам.

- [ ] **Step 1: Тест-харнес**

`tests/h_t6.gd`:
```gdscript
extends Node
var _fails := 0
var _frame := 0
var car: CarRig

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200); cs.shape = box
	body.add_child(cs); body.global_position = Vector3(0, -0.5, 0)
	add_child(body)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))

func _physics_process(_dt: float) -> void:
	_frame += 1
	# фаза 1: разгон 4 с
	if _frame == 5: Input.action_press("throttle")
	if _frame == 245:
		check(car.speed_kmh() > 0.7 * 160 and car.speed_kmh() < 1.1 * 160,
			"reach ~vmax (%.1f km/h)" % car.speed_kmh())
		check(absf(car.chassis.global_position.z) < 3.0, "straight-line drift small")
		Input.action_release("throttle"); Input.action_press("brake")
	if _frame == 365:
		Input.action_release("brake")
		check(car.speed_kmh() < 80.0, "braked below 80 (%.1f)" % car.speed_kmh())
	# фаза 2: рулёжка на средней скорости
	if _frame == 370: Input.action_press("steer_left")
	if _frame == 410:
		check(car.heading > deg_to_rad(12.0), "steered left (%.0f deg)" % rad_to_deg(car.heading))
		Input.action_release("steer_left")
	if _frame == 415: Input.action_press("throttle")
	# фаза 3: ручник-дрифт
	if _frame == 425: Input.action_press("handbrake"); Input.action_press("steer_right")
	if _frame == 485:
		var vel := car.chassis.linear_velocity
		var fwd := Vector3(cos(car.heading), 0, -sin(car.heading))
		var lat := vel - fwd * vel.dot(fwd)
		check(lat.length() > 2.0, "handbrake induces lateral slip (%.1f)" % lat.length())
	if _frame == 500:
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Прогон** → Expected: FAIL (CarRig нет).

- [ ] **Step 3: Реализация `scripts/core/car_rig.gd`**

```gdscript
class_name CarRig
extends Node3D

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)

var params: VehicleParams
var chassis: RigidBody3D
var shell: SoftShell
var heading := 0.0
var _prev_speed := 0.0
var _grounded := true
var _was_in_contact := false
var _susp := [0.0, 0.0, 0.0, 0.0]
var _visual: Node3D
var _wheel_pivots: Array[Node3D] = []
var _wheel_meshes: Array[MeshInstance3D] = []

func build(p: VehicleParams, world: World3D) -> void:
	params = p
	chassis = RigidBody3D.new()
	chassis.mass = p.mass
	chassis.custom_integrator = true
	chassis.contact_monitor = true
	chassis.max_contacts_reported = 8
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = p.collider_size()
	col.shape = shape
	chassis.add_child(col)
	add_child(chassis)
	_visual = Node3D.new()
	chassis.add_child(_visual)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.08, 0.08, 0.08)
	for i in 4:
		var piv := Node3D.new()
		var mi := MeshInstance3D.new()
		var geo := CylinderMesh.new()
		geo.height = 0.26; geo.top_radius = 0.34; geo.bottom_radius = 0.34
		mi.mesh = geo; mi.material_override = wmat
		mi.rotation_z = PI * 0.5
		piv.add_child(mi); _visual.add_child(piv)
		_wheel_pivots.append(piv); _wheel_meshes.append(mi)
	var wx := params.length * 0.32
	var wz := (params.width - 0.5) * 0.5
	_wheel_pivots[0].position = Vector3(wx, 0, wz)
	_wheel_pivots[1].position = Vector3(wx, 0, -wz)
	_wheel_pivots[2].position = Vector3(-wx, 0, wz)
	_wheel_pivots[3].position = Vector3(-wx, 0, -wz)
	shell = SoftShell.new()
	add_child(shell)
	shell.setup(ShellBuilder.build(p), chassis, p)
	shell.velocity_getter = func() -> Vector3: return chassis.linear_velocity
	shell.space_state = world.direct_space_state

func respawn(tf: Transform3D) -> void:
	heading = tf.basis.get_euler().y
	chassis.global_transform = tf
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	_was_in_contact = false
	_visual.rotation = Vector3.ZERO
	shell.reset()

func speed_kmh() -> float:
	return chassis.linear_velocity.length() * 3.6

func is_airborne() -> bool:
	return not _grounded

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var vel := state.linear_velocity
	vel += Vector3(0, -9.8, 0) * dt            # custom_integrator отключает штатную гравитацию
	var contacts := state.get_contact_count()
	if contacts > 0 and not _was_in_contact and _prev_speed > 8.0:
		var n := Vector3.ZERO
		for c in contacts: n += state.get_contact_normal(c)
		n = n.normalized() if n.length_squared() > 0.01 else -vel.normalized()
		var point := chassis.global_position - n * 0.3
		impact.emit(_prev_speed, point, n)
		shell.apply_impact(point, n, _prev_speed / 3.6)
	_was_in_contact = contacts > 0
	_grounded = contacts > 0
	if _grounded:
		var fwd := Vector3(cos(heading), 0.0, -sin(heading))
		var right := Vector3(sin(heading), 0.0, cos(heading))
		var vf := vel.dot(fwd)
		var vl := vel.dot(right)
		var vmax := params.vmax_kmh / 3.6
		var throttle := Input.get_action_strength("throttle") - Input.get_action_strength("brake")
		if throttle > 0.0:
			vf += params.accel_max * (1.0 - 0.75 * clampf(vf / vmax, 0.0, 1.0)) * throttle * dt
		elif throttle < 0.0:
			if vf > 0.5: vf = maxf(vf - params.brake_decel * dt, 0.0)
			else: vf += params.accel_max * 0.35 * throttle * dt
		vf = clampf(vf, -vmax * 0.12, vmax)
		var hand := Input.is_action_pressed("handbrake")
		vl *= exp(-dt * (1.6 if hand else params.grip))
		var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		var sf := clampf(1.25 - absf(vf) / vmax * 1.05, 0.22, 1.0)
		heading += deg_to_rad(params.steer_rate_deg) * steer * sf * dt * (1.0 if vf >= 0.0 else -1.0)
		vel = fwd * vf + right * vl + Vector3(0.0, vel.y, 0.0)
	state.linear_velocity = vel
	state.angular_velocity = Vector3.ZERO
	state.transform.basis = Basis(Vector3.UP, heading)
	_prev_speed = vel.length() * 3.6

func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in 4:
		var anchor := chassis.global_transform * _wheel_pivots[i].position + Vector3(0, 0.5, 0)
		var q := PhysicsRayQueryParameters3D.create(anchor, anchor + Vector3(0, -1.2, 0))
		q.exclude = [chassis.get_rid()]
		var hit := space.intersect_ray(q)
		var ext := 0.3 if hit.is_empty() else clampf(anchor.distance_to(hit.position) - 0.35, 0.0, 0.6)
		_susp[i] = lerpf(_susp[i], ext, 0.25)
		_wheel_meshes[i].position.y = -_susp[i]
	var pitch := ((_susp[0] + _susp[1]) - (_susp[2] + _susp[3])) * 0.15
	var roll := ((_susp[0] + _susp[2]) - (_susp[1] + _susp[3])) * 0.15
	_visual.rotation.z = lerpf(_visual.rotation.z, pitch, 0.15)
	_visual.rotation.x = lerpf(_visual.rotation.x, -roll, 0.15)
	var steer_vis := (Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")) * 0.5
	_wheel_pivots[0].rotation.y = steer_vis
	_wheel_pivots[1].rotation.y = steer_vis
```

Замечания:
- `respawn` вызывается после `build`; CarRig остаётся в identity, вся кинематика — на chassis.
- Wheel roll-анимация не делается (тёмные цилиндры, эффект нечитаем) — только подвес и поворот передних.
- Контакт «крыша о стену сверху» может ложно сдетонировать как удар при скорости — `_prev_speed > 8` приемлемо для v1.

- [ ] **Step 4: Прогон** `... --quit-after 600 res://tests/h_t6.tscn` → `ALL PASS`; t4 и t5 остаются зелёными (прогнать оба).
- [ ] **Step 5: Commit** `"feat(t6): CarRig arcade controller + impact wiring"`

---

### Task 7: Интеграция: сценарий краш-теста (спековский crash_scenario)

**Files:**
- Test: `tests/h_t7_crash.tscn` + `tests/h_t7_crash.gd`

**Interfaces:**
- Consumes: CarRig, SoftShell, VehicleDB.
- Produces: сценарий «седан разгоняется в бетонную стену», метрики: `impact_speed()`, `broken_total()`, `avg_sim_ms()` для приёмки.

- [ ] **Step 1: Тест**

`tests/h_t7_crash.gd`:
```gdscript
extends Node
var _fails := 0
var _frame := 0
var car: CarRig
var _last_impact := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200); cs.shape = box
	body.add_child(cs); body.global_position = Vector3(0, -0.5, 0)
	add_child(body)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 8, 30); wcs.shape = wbox
	wall.add_child(wcs); wall.global_position = Vector3(60, 4, 0)
	add_child(wall)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	car.impact.connect(func(s, _p, _n): _last_impact = s)

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 5: Input.action_press("throttle")
	if _frame == 550:
		Input.action_release("throttle")
		check(_last_impact > 40.0, "crashed at plausible speed (%.1f)" % _last_impact)
		check(_last_impact < 130.0, "impact speed not absurd (%.1f)" % _last_impact)
	if _frame == 650:
		check(car.chassis.linear_velocity.length() * 3.6 < 8.0, "car stopped (%.1f)" % (car.chassis.linear_velocity.length() * 3.6))
		check(car.shell.broken_by_zone[Zone.FRONT] >= 12, "front damage >=12 (%d)" % car.shell.broken_by_zone[Zone.FRONT])
		check(car.shell.get_broken_total() < car.shell.spec.springs.size() * 0.5, "damage is local, not total")
		var thru := 0
		for i in car.shell.point_count():
			if car.shell.point_world(i).x > 60.6: thru += 1
		check(thru == 0, "no shell points inside wall (%d)" % thru)
		var avg := car.shell.get_sim_ms_avg()
		check(avg < 8.0, "shell sim budget (%.2f ms)" % avg)
	if _frame == 900:
		check(car.shell.dyn_count() == 0, "damaged cage settles to sleep (%d)" % car.shell.dyn_count())
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Прогон** `... --quit-after 1000 res://tests/h_t7_crash.tscn`. Если B-метрики не сходятся — это тюнинг-точка: приоритет правок: `crush_vel`-коэффициент (0.35) > радиус `R` > `break_strain`. Любая правка констант — комментарием в commit.
- [ ] **Step 3: Commit** `"test(t7): spec crash scenario green"` (или `fix(t7): tune impact crush constants`)

---

### Task 8: DamageModel + EffectsDirector (искры/дым/огонь/стёкла)

**Files:**
- Create: `scripts/core/damage_model.gd`
- Create: `scripts/core/effects_director.gd`
- Test: `tests/t8_damage.gd` (script-mode)

**Interfaces:**
- Consumes: сигналы `SoftShell.spring_burst/plastic_event`, `CarRig.impact`.
- Produces:
  - `DamageModel extends RefCounted`: `setup(shell: SoftShell)` (подписывается), `hp(zone: int) -> float` (0..100), `worst_zone() -> int`, `is_totaled() -> bool`; сигналы нет — polling + `changed`-signal `zone_hp_changed(zone: int, hp: float)`, `totaled_changed(total: bool)`. Формула: `hp = 100 * clampf(1 - broken[zone] / (0.35 * spec.zone_spring_totals[zone]), 0, 1)`.
  - `EffectsDirector extends Node3D`: `attach(car: CarRig) -> void` — создаёт: spark-брастер (1 общий, one-shot по event), 5 дымных CPUParticles3D по зонам (locally к chassis, `amount` ∝ 100-hp, >60 hp → 0), огонь+Omnlight3D при min hp < 25 в worst zone, стекло-осколки на plastic_event ROOF/LEFT/RIGHT. Пороги искр — `impact >= 15`.

- [ ] **Step 1: Тест (script-mode)**

`tests/t8_damage.gd`:
```gdscript
extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)
func _initialize() -> void:
	var dm := DamageModel.new()
	var p = VehicleDB.get_params("sedan")
	var spec = ShellBuilder.build(p)
	# симулируем «порвано nпружин» без живого shell: DamageModel принимает counts напрямую
	dm.bind_spec(spec)
	check(dm.hp(Zone.FRONT) == 100.0, "F0 full hp")
	dm.report_breaks(Zone.FRONT, int(spec.zone_spring_totals[Zone.FRONT] * 0.35))
	check(dm.hp(Zone.FRONT) < 1.0, "F1 capacity maps to 0")
	dm.reset()
	dm.report_breaks(Zone.FRONT, int(spec.zone_spring_totals[Zone.FRONT] * 0.1))
	check(dm.hp(Zone.FRONT) > 65.0 and dm.hp(Zone.FRONT) < 80.0, "F2 10%% break ≈ 71 hp (%.1f)" % dm.hp(Zone.FRONT))
	dm.report_breaks(Zone.ROOF, int(spec.zone_spring_totals[Zone.ROOF] * 0.4))
	check(dm.worst_zone() == Zone.ROOF, "F3 worst zone")
	check(dm.is_totaled(), "F4 totaled when any zone hits zero")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Реализация `damage_model.gd`**

```gdscript
class_name DamageModel
extends RefCounted

signal zone_hp_changed(zone: int, hp: float)
signal totaled_changed(is_totaled_now: bool)

var _cap: Array[int] = [1, 1, 1, 1, 1]
var _broken: Array[int] = [0, 0, 0, 0, 0]
var _totaled := false

func bind_spec(spec: ShellSpec) -> void:
	_cap = spec.zone_spring_totals.duplicate()
	reset()

func reset() -> void:
	_broken = [0, 0, 0, 0, 0]
	_totaled = false

func bind_shell(shell: SoftShell) -> void:
	bind_spec(shell.spec)
	shell.spring_burst.connect(func(z): report_breaks(z, 1))

func report_breaks(zone: int, n: int) -> void:
	_broken[zone] += n
	zone_hp_changed.emit(zone, hp(zone))
	var was := _totaled
	_totaled = is_totaled()
	if was != _totaled: totaled_changed.emit(_totaled)

func hp(zone: int) -> float:
	return 100.0 * clampf(1.0 - float(_broken[zone]) / maxf(1.0, 0.35 * float(_cap[zone])), 0.0, 1.0)

func hp_array() -> Array[float]:
	return [hp(Zone.REAR), hp(Zone.LEFT), hp(Zone.RIGHT), hp(Zone.ROOF), hp(Zone.FRONT)]

func worst_zone() -> int:
	var w := Zone.REAR
	for z in 5:
		if hp(z) < hp(w): w = z
	return w

func is_totaled() -> bool:
	return hp(worst_zone()) <= 0.5
```

`bind_shell(shell)` — live-режим: подписка на `spring_burst` (по 1 пружине за сигнал). Связывает game_manager (Task 11). Respawn: `dm.reset(); car.respawn(tf)` (shell.reset отдельно не дергается — respawn его делает).

- [ ] **Step 3: Реализация `effects_director.gd`**

```gdscript
class_name EffectsDirector
extends Node3D

const ZONE_DIR := {
	Zone.FRONT: Vector3(1, 0, 0), Zone.REAR: Vector3(-1, 0, 0),
	Zone.LEFT: Vector3(0, 0, -1), Zone.RIGHT: Vector3(0, 0, 1), Zone.ROOF: Vector3(0, 1, 0),
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
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0); pm.spread = 30.0
	pm.initial_velocity_min = 1.5; pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -1.5, 0)
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	var q := QuadMesh.new(); q.size = Vector2(0.18, 0.18); q.material = m
	p.draw_pass_1 = q
	return p

func _on_impact(speed_kmh: float, point: Vector3, _normal: Vector3) -> void:
	if speed_kmh < 15.0: return
	_sparks.global_position = point
	_sparks.emitting = false
	_sparks.emitting = true

func _on_plastic(zone: int, world_pos: Vector3, _energy: float) -> void:
	if zone == Zone.ROOF or zone == Zone.LEFT or zone == Zone.RIGHT:
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
```

Замечания:
- `EffectsDirector` живёт на `chassis` (координаты зон локальны раме); `global_position` частиц работает поверх родительского трансформа.
- Связку CarRig↔DamageModel делает game_manager (Task 11): `dm.bind_shell(car.shell); effects.attach(car, dm)`.
- Для v1 «стекло» = серо-голубые осколки на plastic_event боковых/крышных зон; полигоны стёкол из меша не вычитаются (YAGNI).

- [ ] **Step 4: Прогон** t8 → `ALL PASS`.
- [ ] **Step 5: Commit** `"feat(t8): damage zones + particles effects"`

---

### Task 9: CameraRig (преследование/капот/орбита + шейк)

**Files:**
- Create: `scripts/core/camera_rig.gd`
- Test: `tests/h_t9.tscn` + `tests/h_t9.gd`

**Interfaces:**
- Consumes: `CarRig` (position/heading/speed), экшены `cam_cycle`, `slowmo`.
- Produces (`CameraRig extends Camera3D`): `setup(car: CarRig) -> void`; `cycle_mode() -> int` (0 chase→1 hood→2 orbit); `add_trauma(t: float)`; `mode() -> int`. Шейк: trauma² × смещение, декей 1.5/s. Slo-mo-глайдер здесь не живёт (TimeScale уже в Task 1;game_manager дёрнет его в Task 11).

- [ ] **Step 1: Тест**

`tests/h_t9.gd`:
```gdscript
extends Node
var _fails := 0
var _frame := 0
var car: CarRig
var cam: CameraRig

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200); cs.shape = box
	body.add_child(cs); body.global_position = Vector3(0, -0.5, 0)
	add_child(body)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	cam = CameraRig.new(); add_child(cam); cam.setup(car)
	make_current()

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 30:
		var d := cam.global_position.distance_to(car.chassis.global_position)
		check(d > 2.0 and d < 15.0, "chase distance %.1f" % d)
		check(cam.global_position.y > 0.3, "chase above ground")
	if _frame == 40: cam.cycle_mode()
	if _frame == 70:
		check(cam.mode() == 1, "hood mode")
		check(cam.global_position.distance_to(car.chassis.global_position) < 3.0, "hood close")
	if _frame == 80: cam.cycle_mode()
	if _frame == 90:
		check(cam.mode() == 2, "orbit mode")
		cam.cycle_mode()
		check(cam.mode() == 0, "wrap to chase")
	if _frame == 100:
		cam.add_trauma(1.0)
	if _frame == 110:
		var moved := cam.global_position.distance_to(car.chassis.global_position)
		check(moved > 0.0, "shake ran without NaN: finite=%s" % str(cam.global_position.is_finite()))
		check(cam.global_position.is_finite(), "finite after shake")
	if _frame == 120:
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Прогон** → Expected: FAIL (CameraRig нет).

- [ ] **Step 3: Реализация `scripts/core/camera_rig.gd`**

```gdscript
class_name CameraRig
extends Camera3D

var _car: CarRig
var _mode := 0
var _trauma := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.35
var _orbit_dist := 9.0
var _drag := false

func setup(car: CarRig) -> void:
	_car = car

func mode() -> int: return _mode
func cycle_mode() -> int:
	_mode = (_mode + 1) % 3
	return _mode
func add_trauma(t: float) -> void:
	_trauma = clampf(_trauma + t, 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if _mode != 2: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: _orbit_dist = clampf(_orbit_dist - 1.0, 3.0, 25.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _orbit_dist = clampf(_orbit_dist + 1.0, 3.0, 25.0)
	elif event is InputEventMouseMotion and _drag:
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.005, -0.3, 1.2)

func _process(dt: float) -> void:
	if _car == null: return
	_trauma = maxf(0.0, _trauma - dt * 1.5)
	var t := _trauma * _trauma
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.4 * t
	var target := _car.chassis.global_position
	var look := target + Vector3(0, 0.6, 0)
	match _mode:
		0:
			var fwd := _car.chassis.global_transform.basis.x
			var want := target - fwd * 8.0 + Vector3(0, 3.2, 0)
			# arm raycast
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(target + Vector3(0, 1.2, 0), want)
			q.collide_with_bodies = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty(): want = hit.position + (want - hit.position).normalized() * 0.5
			var w := 1.0 - exp(-dt * 10.0)
			global_position = global_position.lerp(want, w) + shake
			look_at_point(look)
		1:
			global_position = _car.chassis.global_transform * Vector3(0.2, params_hood_y(), 0) + shake * 0.3
			look_at_point(_car.chassis.global_transform * Vector3(10, 0.4, 0))
		2:
			var o := Vector3(cos(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), sin(_orbit_yaw) * cos(_orbit_pitch))
			global_position = target + o * _orbit_dist + shake
			look_at_point(look)

func params_hood_y() -> float:
	return _car.params.gc + _car.params.body_h + _car.params.roof_h * 0.55

func look_at_point(p: Vector3) -> void:
	if (p - global_position).length_squared() < 1e-6: return
	look_at(p, Vector3.UP)
```

- [ ] **Step 4: Прогон** → `ALL PASS` (t4/t5/t6/t7 прогнать заново — регрессий нет).
- [ ] **Step 5: Commit** `"feat(t9): camera rig with three modes and shake"`

---

### Task 10: Карты (арена / городок / трасса)

**Files:**
- Create: `scripts/maps/map_db.gd`
- Test: `tests/h_t10.tscn` + `tests/h_t10.gd`

**Interfaces:**
- Consumes: ничего (самодостаточен).
- Produces: `MapDB.build(id: String) -> Dictionary` — `{"root": Node3D, "spawn": Transform3D, "info": {"colliders": int, "has_ramp": bool}}`; ids: `arena|town|speedway`; верх пола везде y=0; спавн смотрит +X.

- [ ] **Step 1: Тест**

`tests/h_t10.gd`:
```gdscript
extends Node
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for id in ["arena", "town", "speedway"]:
		var m := MapDB.build(id)
		add_child(m.root)
		check(m.info.colliders > 10, "%s has colliders (%d)" % [id, m.info.colliders])
		check(m.info.has_ramp or id == "town", "%s ramp expectation" % id)
		await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var from := m.spawn.origin + Vector3(0, 2.0, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -3.0, 0)))
		check(not hit.is_empty(), "%s spawn over ground" % id)
		check(absf(hit.position.y - 0.0) < 0.06 or id == "town", "%s floor top y≈0 (%.2f)" % [id, hit.position.y])
		# спавн не внутри коллайдера: сфера r=1 на спавне чиста по верхним лучам 4 углов машины
		for dx in [-2.0, 2.0]:
			for dz in [-1.0, 1.0]:
				var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(m.spawn.origin + Vector3(dx, 2.5, dz), m.spawn.origin + Vector3(dx, 0.0, dz)))
				check(h2.is_empty() or h2.position.y < 0.06, "%s spawn clear at %s,%s" % [id, dx, dz])
		m.root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Прогон** → FAIL, нет MapDB.

- [ ] **Step 3: Реализация `scripts/maps/map_db.gd`**

```gdscript
class_name MapDB
extends RefCounted

static func _mat(color: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = rough
	return m

static func box(root: Node3D, pos: Vector3, size: Vector3, color: Color, rot: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.global_position = pos; body.global_basis = rot
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; body.add_child(cs)
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new()
	bm.size = size; bm.material = _mat(color); mi.mesh = bm
	body.add_child(mi)
	root.add_child(body)
	return body

static func build(id: String) -> Dictionary:
	match id:
		"arena": return _arena()
		"town": return _town()
		"speedway": return _speedway()
	return _arena()

static func _arena() -> Dictionary:
	var root := Node3D.new(); root.name = "Arena"
	box(root, Vector3(0, -0.25, 0), Vector3(200, 0.5, 200), Color(0.55, 0.55, 0.57))
	var wc := Color(0.35, 0.35, 0.38)
	box(root, Vector3(0, 4, -100), Vector3(200, 8, 1), wc)
	box(root, Vector3(0, 4, 100), Vector3(200, 8, 1), wc)
	box(root, Vector3(-100, 4, 0), Vector3(1, 8, 200), wc)
	box(root, Vector3(100, 4, 0), Vector3(1, 8, 200), wc)
	for p in [Vector3(60, 4, -10), Vector3(60, 4, 10)]:
		box(root, p, Vector3(0.8, 8, 0.8), Color(0.75, 0.7, 0.2))       # столбы
	for i in 3:
		box(root, Vector3(20 + i * 8, 0.7, -25), Vector3(0.4, 1.4, 8), Color(0.9, 0.3, 0.2))  # отбойники (тонкие — проверка свип-рея)
	box(root, Vector3(45, 1.35, 25), Vector3(14, 0.5, 8), Color(0.95, 0.8, 0.2), Basis(Vector3(0, 0, 1), -deg_to_rad(22)))  # рампа: подъём к +X
	box(root, Vector3(82, 1, 0), Vector3(3, 2, 3), Color(0.6, 0.2, 0.2))  # краш-блок
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}

static func _town() -> Dictionary:
	var root := Node3D.new(); root.name = "Town"
	box(root, Vector3(0, -0.25, 0), Vector3(300, 0.5, 300), Color(0.42, 0.42, 0.45))
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	for bx in 3:
		for bz in 3:
			var h := 8.0 + rng.randf() * 14.0
			box(root, Vector3(-48 + bx * 48, h * 0.5, -48 + bz * 48), Vector3(26, h, 26), Color(0.5, 0.52, 0.56))
	for x in range(-120, 130, 40):
		box(root, Vector3(x, 3, 16.5), Vector3(0.5, 6, 0.5), Color(0.2, 0.2, 0.22))   # фонари вдоль улицы z=24
	for k in 4:
		box(root, Vector3(-30 + k * 45, 0.75, 33.0), Vector3(4.2, 1.5, 1.9), Color(0.2, 0.35, 0.55))  # припаркованные «боксы»
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-120, 1.0, 24)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}

static func _speedway() -> Dictionary:
	var root := Node3D.new(); root.name = "Speedway"
	box(root, Vector3(0, -0.25, 0), Vector3(700, 0.5, 300), Color(0.32, 0.32, 0.34))
	box(root, Vector3(280, 0.015, 0), Vector3(620, 0.03, 12), Color(0.15, 0.15, 0.17))   # асфальт (визуал тоньше коллайдера пола)
	for side in [-1, 1]:
		box(root, Vector3(280, 0.5, side * 7.0), Vector3(620, 1.0, 0.4), Color(0.8, 0.8, 0.85))
	box(root, Vector3(585, 3, 0), Vector3(1.5, 6, 30), Color(0.55, 0.2, 0.2))            # стена краш-теста
	box(root, Vector3(40, 1.0, 0), Vector3(10, 0.5, 10), Color(0.95, 0.8, 0.2), Basis(Vector3(0, 0, 1), -deg_to_rad(18)))
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-10, 1.0, 0)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}
```

Замечания:
- Рампа: поворот вокруг Z (forward +X, подъём носа = negative pitch = -22° вокруг Z); центр на (45, 1.35) — верхний край ~2.5 m.
- Спавн города — по улице z=24: buildings rows at z ∈ [-62..-34], [-14..14], [34..62]... проверено в тесте лучами.
- Асфальт speedway — визуальная подложка y=0.015 тоньше пола; машина не цепляет (height 0.03 < зазора подвески нет: коллайдер есть! Убрать CollisionShape у визуального бокса: `box_vis()` вариант без body — сделать отдельную статик-функцию).

Правка из замечания — часть спеки: добавить
```gdscript
static func box_vis(root: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new()
	bm.size = size; bm.material = _mat(color); mi.mesh = bm
	mi.global_position = pos
	root.add_child(mi)
	return mi
```
и в `_speedway` заменить `box(... Vector3(620, 0.03, 12) ...)` на `box_vis(...)`.

- [ ] **Step 4: Прогон** → `ALL PASS` (для town `has_ramp false`, тест уже так и ждёт).
- [ ] **Step 5: Commit** `"feat(t10): arena/town/speedway procedural maps"`

---

### Task 11: HUD + game_manager + финальное меню (полный флоу)

**Files:**
- Create: `scripts/ui/hud.gd`, `scripts/core/game_manager.gd`, `scripts/ui/main_menu.gd` (замена стаба)
- Create: `scenes/game.tscn`, `tests/h_t11.tscn` + `tests/h_t11.gd`

**Interfaces:**
- Consumes: всё предыдущее.
- Produces:
  - `HUD extends CanvasLayer`: `bind(car: CarRig, damage: DamageModel)`; `show_crash(kmh: float)`; `show_tip(text: String)`; апдейт каждую кадр: скорость км/ч, 5 полос HP, баннер CRASH (fade по реальному времени через `Time.get_ticks_msec`), TOTALLED.
  - `GameManager extends Node3D` (корень `game.tscn`): `_ready()` строит карту `GameContext.map_id`, машину `GameContext.car_id`, CameraRig, HUD, EffectsDirector, DamageModel; обрабатывает respawn/pause/slowmo/out-of-bounds; автослоу-мо при ударе >60; top-crash-счётчик в HUD.

- [ ] **Step 1: Тест полного флоу (9 комбинаций)**

`tests/h_t11.gd`:
```gdscript
extends Node
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for map_id in ["arena", "town", "speedway"]:
		for car_id in ["sedan", "pickup", "sport"]:
			GameContext.select(car_id, map_id)
			var gm: Node3D = load("res://scenes/game.tscn").instantiate()
			add_child(gm)
			for f in 30:
				await get_tree().physics_frame
			check(gm is GameManager, "%s/%s scene type" % [map_id, car_id])
			check(gm.car != null and gm.car.chassis != null, "%s/%s car built" % [map_id, car_id])
			check(gm.hud != null and gm.camera != null, "%s/%s hud+camera" % [map_id, car_id])
			# симулируем урон и respawn
			gm.damage.report_breaks(Zone.FRONT, 40)
			check(gm.damage.hp(Zone.FRONT) < 100.0, "%s/%s damage applied" % [map_id, car_id])
			Input.action_press("respawn")
			await get_tree().physics_frame
			Input.action_release("respawn")
			check(gm.damage.hp(Zone.FRONT) == 100.0, "%s/%s respawn restored hp" % [map_id, car_id])
			gm.queue_free()
			await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: `scripts/ui/hud.gd`**

```gdscript
class_name HUD
extends CanvasLayer

var _car: CarRig
var _damage: DamageModel
var _speed_label: Label
var _crash_label: Label
var _crash_until := 0
var _bars: Array[ProgressBar] = []
var _totaled_label: Label
var _tip_label: Label

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_speed_label = _label(Vector2(30, 30), 42)
	root.add_child(_speed_label)
	_crash_label = _label(Vector2(0, 120), 34)
	_crash_label.size = Vector2(1600, 50)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.modulate = Color(1, 0.85, 0.2)
	_crash_label.visible = false
	root.add_child(_crash_label)
	_totals_label_init(root)
	var hints := _label(Vector2(30, 820), 18)
	hints.text = "W/S газ/тормоз · A/D руль · Space ручник · Shift слоу-мо · C камера · R рестарт · Esc меню"
	root.add_child(hints)
	_tip_label = _label(Vector2(0, 700), 26)
	_tip_label.size = Vector2(1600, 40)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.visible = false
	root.add_child(_tip_label)
	var names := ["REAR", "L", "R", "ROOF", "F"]
	for i in 5:
		var b := ProgressBar.new()
		b.min_value = 0; b.max_value = 100
		b.custom_minimum_size = Vector2(150, 14)
		b.position = Vector2(30, 130 + i * 22)
		b.value = 100
		b.show_percentage = false
		var l := _label(Vector2(185, 128 + i * 22), 14)
		l.text = names[i]
		root.add_child(l); root.add_child(b)
		_bars.append(b)

var _totals_label: Label
func _totals_label_init(root: Control) -> void:
	_totals_label = _label(Vector2(0, 200), 40)
	_totals_label.size = Vector2(1600, 60)
	_totals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_totals_label.text = "TOTALLED"
	_totals_label.modulate = Color(1, 0.25, 0.2)
	_totals_label.visible = false
	root.add_child(_totals_label)

func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l

func bind(car: CarRig, damage: DamageModel) -> void:
	_car = car; _damage = damage
	damage.totaled_changed.connect(func(t: bool): _totals_label.visible = t)

func show_crash(kmh: float) -> void:
	_crash_label.text = "CRASH @ %d км/ч" % int(kmh)
	_crash_label.visible = true
	_crash_until = Time.get_ticks_msec() + 2500

func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip_label.visible = true

func _process(_dt: float) -> void:
	if _car == null: return
	_speed_label.text = "%d км/ч" % int(_car.speed_kmh())
	if _crash_label.visible and Time.get_ticks_msec() > _crash_until:
		_crash_label.visible = false
	if _damage != null:
		var hpz := _damage.hp_array()
		for i in 5:
			_bars[i].value = hpz[i]
			_bars[i].modulate = Color(0.3, 0.9, 0.4) if hpz[i] > 55 else (Color(0.95, 0.7, 0.2) if hpz[i] > 25 else Color(0.9, 0.25, 0.2))
```

- [ ] **Step 3: `scripts/core/game_manager.gd`**

```gdscript
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
	var map := MapDB.build(GameContext.map_id)
	_spawn = map.spawn
	add_child(map.root)
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
	TimeScale.set_hold(false)

func _set_paused(v: bool) -> void:
	_paused = v
	get_tree().paused = v
	hud.process_mode = Node.PROCESS_MODE_ALWAYS if v else Node.PROCESS_MODE_INHERIT
```

(`TimeScale.set_hold` идемпотентен и сам возвращает 1.0 при отжатии — Task 1. В не-paused режиме HUD наследует паузу дерева — это ожидаемо.)

- [ ] **Step 4: `scenes/game.tscn` + финальный `main_menu.gd`**

`scenes/game.tscn`:
```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/core/game_manager.gd" id="1"]
[node name="Game" type="Node3D"]
script = ExtResource("1")
```

`scripts/ui/main_menu.gd` (полная замена стаба Task 1):
```gdscript
extends Control

const CARS := [["Седан", "sedan"], ["Пикап", "pickup"], ["Спорткар", "sport"]]
const MAPS := [["Арена", "arena"], ["Городок", "town"], ["Трасса", "speedway"]]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5; col.anchor_right = 0.5
	col.offset_left = -220; col.offset_right = 220
	col.offset_top = 120; col.offset_bottom = 620
	add_child(col)
	var t := Label.new()
	t.text = "CAR CRASH SIMULATOR"
	t.add_theme_font_size_override("font_size", 46)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var car_opt := OptionButton.new()
	for c in CARS: car_opt.add_item(c[0])
	var map_opt := OptionButton.new()
	for m in MAPS: map_opt.add_item(m[0])
	col.add_child(car_opt); col.add_child(map_opt)
	var start := Button.new(); start.text = "Старт"
	start.pressed.connect(func() -> void:
		GameContext.select(CARS[car_opt.selected][1], MAPS[map_opt.selected][1])
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	col.add_child(start)
	var hint := Label.new()
	hint.text = "WASD/стрелки · Space ручник · Shift слоу-мо · C камера · R рестарт"
	hint.add_theme_font_size_override("font_size", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
```

- [ ] **Step 5: Прогон** `--quit-after 900 res://tests/h_t11.tscn` → `ALL PASS`; полный прогон t2–t10 без регрессий.
- [ ] **Step 6: Commit** `"feat(t11): HUD, game flow, main menu, full 9-combo harness"`

---

### Task 12: Визуальная приёмка + полировка

**Files:**
- Create: `tests/h_visual.tscn` + `tests/h_visual.gd`, `README.md`
- Modify: константы тюнинга (если скриншоты покажут проблемы)

**Interfaces:** Consumes всё. Produces: 6 PNG в `tests/out/` + финальный зелёный прогон.

- [ ] **Step 1: Скриншот-раннер**

`tests/h_visual.gd`:
```gdscript
extends Node
# НЕ headless: --path . --quit-after 900 res://tests/h_visual.tscn
var _frame := 0
var car: CarRig

func _ready() -> void:
	var gm: Node3D = load("res://scenes/game.tscn").instantiate()
	GameContext.select("sport", "speedway")
	add_child(gm)
	await get_tree().process_frame
	car = gm.car

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 5: Input.action_press("throttle")
	if _frame == 150: Input.action_release("throttle")
	if _frame in [140, 200, 230, 300, 420]:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("res://tests/out")
		img.save_png("res://tests/out/v%d.png" % _frame)
```
(PNG пишутся только с живым рендером; при пустом окне на Windows скриншот всё равно валиден.)

- [ ] **Step 2: Прогнать, посмотреть** каждый PNG: кузов виден, катится, вмятина после 200-230, HUD читается. Если вмятина нечитаемая/машина «дырявая» — тюнинг по приоритету: `crush_vel*` в `apply_impact`, `R`-радиус, `break_strain`, плотность сэмплинга `sections`. Каждая правка — с замером до/после и коммитом `tune(...)`.
- [ ] **Step 3: `README.md`**: как открыть в Godot, клавиши, структура, как запустить тесты (команды).
- [ ] **Step 4: Финальный зелёный прогон** всех смоуков (t2,t3,t4,t8 + h_t1,t5,t6,t7,t9,t10,t11) — таблица результатов в коммите.
- [ ] **Step 5: Commit** `"test(t12): visual acceptance green, README"`
- [ ] **Step 6: Ручная приёмка пользователем**: F5 в Godot.exe, проехать/врезаться на всех 3 машинах; фидбек → таск тюнинга при необходимости.







