class_name LooseProp
extends RigidBody3D
# Лёгкий предмет на трассе, который сносит машина.
#
# Solver Godot при встрече двух axis-aligned коробок бьёт почти точно через центр
# масс, поэтому без добавки предмет не кувыркается, а едет перед бампером как отвал
# бульдозера. Дозаводим его моментом импульса вокруг поперечной оси — ровно тем,
# что в реальности даёт удар бампером выше основания.

const TUMBLE := 1.5          # безразмерный множитель момента: пилон крутится ~4-5 рад/с
const MIN_HIT_MS := 3.0      # медленное касание (машина просто стоит рядом) кувырка не даёт
const GROUP := "loose_prop"

var height_m := 1.0
# GameManager подставляет сюда приёмник пыли (EffectsDirector.on_prop_hit).
# Пузырь валидности проверяется: без приёмника предмет живёт ровно как раньше,
# поэтому харнесы, собирающие пропы сами (h_prop_knock), ничего не замечают.
var on_hit_fx := Callable()
var disturbed := false     # сбивался ли предмет с домашней позы в этом заезде
var _home := Transform3D.IDENTITY

func home() -> Transform3D: return _home

func _ready() -> void:
	add_to_group(GROUP)
	# домашнее положение снимаем уже в дереве: до этого глобальный трансформ ещё
	# не определён, а именно в него предмет должен возвращаться на «заново»
	_home = global_transform

# Рестарт возвращает сбитые предметы на место. Иначе за несколько заездов трасса
# загружается обломками, и машина может родиться внутри конуса: solver выталкивает
# её на несколько метров, и старт каждого заезда становится случайностью.
func restore() -> void:
	global_transform = _home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	disturbed = false
	reset_physics_interpolation()

func setup_tumble() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_hit)

func _on_hit(other: Node) -> void:
	var car := other as VehicleBody3D
	if car == null: return
	var v := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
	if v.length() < MIN_HIT_MS: return
	# I ≈ m·h²/3 для стержня относительно основания; ω = t/I
	apply_torque_impulse(Vector3.UP.cross(v.normalized()) * mass * height_m * height_m * TUMBLE)
	disturbed = true
	if on_hit_fx.is_valid(): on_hit_fx.call(global_position, v.length())
