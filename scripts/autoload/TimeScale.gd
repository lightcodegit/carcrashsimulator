extends Node
# Только ручное слоу-мо (Shift / кнопка B). Автоматического замедления на удар нет:
# игра не должна останавливаться или растягивать время без команды игрока.
var _held := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_hold(flag: bool) -> void:
	if _held == flag: return
	_held = flag
	# фактор замедления — настройка: кому-то 0.3 кажется гонками, кому-то — слайдом
	Engine.time_scale = clampf(Settings.slowmo, 0.05, 1.0) if flag else 1.0
