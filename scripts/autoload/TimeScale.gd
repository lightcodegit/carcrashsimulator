extends Node
# Только ручное слоу-мо (Shift / кнопка B). Автоматического замедления на удар нет:
# игра не должна останавливаться или растягивать время без команды игрока.
var _held := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_hold(flag: bool) -> void:
	if _held == flag: return
	_held = flag
	Engine.time_scale = 0.3 if flag else 1.0
