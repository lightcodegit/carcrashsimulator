extends Control
# Standalone launcher window. A separate Godot project (launcher/) keeps the
# game build a single self-contained binary, while this executable manages the
# game itself: installed versions live in the launcher's own data folder in
# the OS user locations, new ones download from GitHub Releases, and PLAY runs
# the selected version (or a game found next to the launcher).
#
# Visual language mirrors the game's UiTheme: dark glass panels, amber accent
# with depth (bottom border + hover glow), procedural checkboxes, system
# fonts with real weights. Layout: sidebar navigation + scrollable content.

const LauncherCore := preload("res://scripts/launcher_core.gd")

# ---- palette (mirrors UiTheme) ----
const BG := Color(0.04, 0.045, 0.06)
const BG_TOP := Color(0.07, 0.075, 0.10)
const PANEL := Color(0.045, 0.05, 0.065, 0.80)
const PANEL_CARD := Color(0.115, 0.12, 0.145, 0.96)
const PANEL_HOVER := Color(0.12, 0.125, 0.15, 0.92)
const AMBER := Color(0.96, 0.62, 0.13)
const AMBER_HI := Color(1.0, 0.74, 0.26)
const AMBER_DEEP := Color(0.78, 0.47, 0.07)
const AMBER_SOFT := Color(0.96, 0.62, 0.13, 0.45)
const TEXT := Color(0.95, 0.96, 0.98)
const DIM := Color(0.63, 0.67, 0.73)
const FAINT := Color(0.45, 0.49, 0.55)
const LINE := Color(0.85, 0.87, 0.92, 0.22)
const GOOD := Color(0.42, 0.88, 0.55)
const BAD := Color(0.95, 0.32, 0.24)
const BAD_HI := Color(1.0, 0.45, 0.36)

var _ru := true
var _close_on_play := true
var _fetch_on_start := true
var _always_on_top := false
var _notify_on_download := true
var _auto_select_latest := true
var _launch_args := ""
var _source_path := ""
var _settings_open := false
var _data_dir := ""
var _saved_game := ""
var _selected_version := ""
var _install_error := ""
var _installed: Array = []
var _available: Array = []
var _list_failed := false
var _downloading := false
var _extracting := false
var _download_tag := ""
var _download_zip := ""
var _game_pid := -1
var _process_check_timer := 0.0
var _cfg := ConfigFile.new()
var _fonts: Dictionary = {}
var _tex_cache: Dictionary = {}

var _active_section := 0

var _ui_root: Control
var _dot: Label
var _status: Label
var _chip: PanelContainer
var _version_chip: PanelContainer
var _game_label: Label
var _mods_label: Label
var _play: Button
var _mods_btn: Button
var _folder_btn: Button
var _pick_btn: Button
var _exit_btn: Button
var _lang_btn: Button
var _lang_ru_btn: Button
var _lang_en_btn: Button
var _refresh_btn: Button
var _settings_toggle: Button
var _settings_box: VBoxContainer
var _installed_row: HBoxContainer
var _nav_buttons: Array[Button] = []
var _content_panels: Array[Control] = []
var _available_list: VBoxContainer
var _list_note: Label
var _row_progress: ProgressBar
var _dialog: FileDialog
var _http_list: HTTPRequest
var _http_get: HTTPRequest

func _ready() -> void:
	_ru = OS.get_locale_language() == "ru"
	get_window().min_size = Vector2i(900, 640)
	get_window().title = "Car Crash Launcher v" + _version()
	get_window().always_on_top = _always_on_top
	# Restore window geometry from the previous session.
	var w := int(_cfg.get_value("launcher", "window_w", 1200))
	var h := int(_cfg.get_value("launcher", "window_h", 800))
	var x := int(_cfg.get_value("launcher", "window_x", -1))
	var y := int(_cfg.get_value("launcher", "window_y", -1))
	get_window().size = Vector2i(maxi(w, 900), maxi(h, 640))
	if x >= 0 and y >= 0:
		get_window().position = Vector2i(x, y)
	_data_dir = LauncherCore.ensure_launcher_data_dir()
	_load_config()
	call_deferred("_build_ui")
	call_deferred("_refresh")
	call_deferred("_make_http_nodes")
	if _fetch_on_start:
		call_deferred("_fetch_releases")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var w := get_window()
		_cfg.set_value("launcher", "window_w", w.size.x)
		_cfg.set_value("launcher", "window_h", w.size.y)
		_cfg.set_value("launcher", "window_x", w.position.x)
		_cfg.set_value("launcher", "window_y", w.position.y)
		_save_cfg()
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
		if _play != null and not _play.disabled:
			_on_play()
		return
	if event.keycode == KEY_F5:
		_fetch_releases()
		return
	if event.ctrl_pressed and event.keycode >= KEY_1 and event.keycode <= KEY_4:
		_show_section(event.keycode - KEY_1)
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()

func _process(_delta: float) -> void:
	if not _downloading or _http_get == null:
		pass
	else:
		var done := _http_get.get_downloaded_bytes()
		var total := _http_get.get_body_size()
		var note := _t("Установка %s…" % _download_tag, "Installing %s…" % _download_tag)
		if total > 0:
			if _row_progress != null:
				_row_progress.max_value = total
				_row_progress.value = done
			note = _t(
				"Загрузка %s: %.0f из %.0f МБ" % [_download_tag, done / 1048576.0, total / 1048576.0],
				"Downloading %s: %.0f of %.0f MB" % [_download_tag, done / 1048576.0, total / 1048576.0])
		if _list_note.text != note:
			_list_note.text = note
			_list_note.add_theme_color_override("font_color", AMBER_HI)
	# Check if the launched game is still running (every ~2 seconds).
	if _game_pid > 0:
		_process_check_timer += _delta
		if _process_check_timer >= 2.0:
			_process_check_timer = 0.0
			if not _is_process_alive(_game_pid):
				_game_pid = -1
				_dot.add_theme_color_override("font_color", GOOD)
				_status.text = _t("ИГРА ЗАВЕРШЕНА", "GAME FINISHED")
				_status.add_theme_color_override("font_color", GOOD)
				_game_label.text = _t("Лаунчер готов к следующему запуску.",
					"The launcher is ready for the next launch.")
				_game_label.add_theme_color_override("font_color", DIM)

func _version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# Best-effort check whether a spawned game process is still running. Used to
# flip the status back to ready when the game window is closed.
func _is_process_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	if OS.get_name() == "Windows":
		var output: Array = []
		OS.execute("tasklist", PackedStringArray(["/FI", "PID eq %d" % pid, "/NH"]), output, true)
		var text := "\n".join(output)
		return str(pid) in text
	var code := OS.execute("kill", PackedStringArray(["-0", str(pid)]), [], true)
	return code == 0

func _launcher_dir() -> String:
	var dir := ProjectSettings.globalize_path("res://")
	while dir.ends_with("/") or dir.ends_with("\\"):
		dir = dir.substr(0, dir.length() - 1)
	return dir

func _t(ru: String, en: String) -> String:
	return ru if _ru else en

# ---- config ----

func _cfg_path() -> String:
	return _data_dir.path_join("launcher.cfg")

func _save_cfg() -> void:
	if _data_dir.is_empty():
		return
	_cfg.set_value("launcher", "game_path", _saved_game)
	_cfg.set_value("launcher", "version", _selected_version)
	_cfg.set_value("launcher", "close_on_play", _close_on_play)
	_cfg.set_value("launcher", "fetch_on_start", _fetch_on_start)
	_cfg.set_value("launcher", "always_on_top", _always_on_top)
	_cfg.set_value("launcher", "notify_on_download", _notify_on_download)
	_cfg.set_value("launcher", "auto_select_latest", _auto_select_latest)
	_cfg.set_value("launcher", "launch_args", _launch_args)
	_cfg.set_value("launcher", "source_path", _source_path)
	_cfg.set_value("launcher", "language", "ru" if _ru else "en")
	var err := _cfg.save(_cfg_path())
	if err != OK:
		push_warning("Could not save launcher settings")

func _load_config() -> void:
	if _data_dir.is_empty():
		return
	if _cfg.load(_cfg_path()) != OK:
		return
	_saved_game = String(_cfg.get_value("launcher", "game_path", ""))
	_selected_version = String(_cfg.get_value("launcher", "version", ""))
	_close_on_play = bool(_cfg.get_value("launcher", "close_on_play", true))
	_fetch_on_start = bool(_cfg.get_value("launcher", "fetch_on_start", true))
	_always_on_top = bool(_cfg.get_value("launcher", "always_on_top", false))
	_notify_on_download = bool(_cfg.get_value("launcher", "notify_on_download", true))
	_auto_select_latest = bool(_cfg.get_value("launcher", "auto_select_latest", true))
	_launch_args = String(_cfg.get_value("launcher", "launch_args", ""))
	_source_path = String(_cfg.get_value("launcher", "source_path", ""))
	var lang := String(_cfg.get_value("launcher", "language", ""))
	if lang == "ru":
		_ru = true
	elif lang == "en":
		_ru = false
	# Auto-select the newest installed version when nothing was explicitly
	# chosen, so PLAY works out of the box after the first install.
	if _selected_version.is_empty() and _auto_select_latest and not OS.has_feature("editor"):
		_installed = LauncherCore.installed_versions(_data_dir)
		if not _installed.is_empty():
			_selected_version = String(_installed[0])

# ---- UI building ----

func _build_ui() -> void:
	if _ui_root == null:
		_ui_root = Control.new()
		_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ui_root)
	for child in _ui_root.get_children():
		_ui_root.remove_child(child)
		child.queue_free()
	_dialog = null
	_nav_buttons.clear()
	_content_panels.clear()

	_add_background()

	# Use a VBoxContainer as the root layout — more reliable than manual anchors
	# for container nodes in exported builds.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	_ui_root.add_child(vbox)

	# Top bar.
	var topbar := PanelContainer.new()
	topbar.custom_minimum_size = Vector2(0, 52)
	topbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topbar.add_theme_stylebox_override("panel", _style(PANEL, LINE, 0, 20, 10))
	vbox.add_child(topbar)
	var toprow := HBoxContainer.new()
	toprow.add_theme_constant_override("separation", 16)
	topbar.add_child(toprow)
	if ResourceLoader.exists("res://assets/logo.svg"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/logo.svg") as Texture2D
		logo.custom_minimum_size = Vector2(32, 32)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toprow.add_child(logo)
	toprow.add_child(_label("CAR CRASH LAUNCHER", 16, TEXT, 800))
	var grow_top := Control.new()
	grow_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toprow.add_child(grow_top)
	toprow.add_child(_label("v" + _version(), 12, FAINT))
	var sep := ColorRect.new()
	sep.color = LINE
	sep.custom_minimum_size = Vector2(1, 20)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toprow.add_child(sep)
	_lang_btn = _button("EN" if _ru else "RU", false)
	_lang_btn.custom_minimum_size = Vector2(52, 28)
	_lang_btn.pressed.connect(_on_language)
	toprow.add_child(_lang_btn)

	# Body: sidebar + content.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	vbox.add_child(body)

	# Sidebar rail.
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(170, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_stylebox_override("panel", _style(PANEL, LINE, 0, 12, 16))
	body.add_child(sidebar)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	sidebar.add_child(nav)
	nav.add_child(_gap(8))
	_build_nav_item(nav, _t("ИГРАТЬ", "PLAY"), 0)
	_build_nav_item(nav, _t("ВЕРСИИ", "VERSIONS"), 1)
	_build_nav_item(nav, _t("МОДЫ", "MODS"), 2)
	_build_nav_item(nav, _t("НАСТРОЙКИ", "SETTINGS"), 3)
	var nav_spring := Control.new()
	nav_spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_spring)
	nav.add_child(_rule())
	nav.add_child(_gap(8))
	_build_nav_item(nav, _t("ВЫХОД", "EXIT"), 4, true)

	# Content area.
	var content_wrap := PanelContainer.new()
	content_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wrap_style := _style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	wrap_style.content_margin_left = 24
	wrap_style.content_margin_right = 24
	wrap_style.content_margin_top = 20
	wrap_style.content_margin_bottom = 20
	content_wrap.add_theme_stylebox_override("panel", wrap_style)
	body.add_child(content_wrap)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_wrap.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	# Panel 0: Home.
	var home := VBoxContainer.new()
	home.add_theme_constant_override("separation", 14)
	content.add_child(home)
	_content_panels.append(home)
	_build_home_panel(home)

	# Panel 1: Versions.
	var versions := VBoxContainer.new()
	versions.add_theme_constant_override("separation", 12)
	content.add_child(versions)
	_content_panels.append(versions)
	_build_versions_panel(versions)

	# Panel 2: Mods.
	var mods := VBoxContainer.new()
	mods.add_theme_constant_override("separation", 12)
	content.add_child(mods)
	_content_panels.append(mods)
	_build_mods_panel(mods)

	# Panel 3: Settings.
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	content.add_child(settings)
	_content_panels.append(settings)
	_build_settings_panel(settings)

	_show_section(_active_section)

	_dialog = FileDialog.new()
	_dialog.title = _t("Выберите исполняемый файл игры", "Select the game executable")
	_dialog.ok_button_text = _t("ВЫБРАТЬ", "SELECT")
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray([
		"*.exe,*.x86_64,*.AppImage,*.sh ; " + _t("Исполняемый файл игры", "Game executable"),
		"* ; " + _t("Все файлы", "All files"),
	])
	_dialog.file_selected.connect(_on_game_selected)
	_ui_root.add_child(_dialog)

func _build_nav_item(nav: VBoxContainer, text: String, index: int, danger := false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 42)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_override("font", _font(700 if index == 0 else 600))
	btn.add_theme_font_size_override("font_size", 15 if index == 0 else 14)
	btn.add_theme_color_override("font_color", AMBER if index == 0 else TEXT)
	btn.add_theme_color_override("font_hover_color", AMBER_HI if index == 0 else Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", AMBER if index == 0 else TEXT)
	btn.add_theme_color_override("font_focus_color", AMBER if index == 0 else TEXT)
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0, 0, 0, 0)
	norm.set_corner_radius_all(8)
	norm.content_margin_left = 16
	norm.content_margin_right = 12
	norm.content_margin_top = 10
	norm.content_margin_bottom = 10
	var hover := norm.duplicate() as StyleBoxFlat
	hover.bg_color = PANEL_HOVER
	hover.border_width_left = 3
	hover.border_color = AMBER if index == 0 else AMBER_SOFT
	var active := norm.duplicate() as StyleBoxFlat
	active.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.12)
	active.border_width_left = 3
	active.border_color = AMBER
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", active)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", norm)
	btn.pressed.connect(func() -> void: _on_nav(index))
	_nav_buttons.append(btn)
	nav.add_child(btn)

func _show_section(index: int) -> void:
	_active_section = index
	# Guard against freed nodes: during a language switch the old children are
	# queued for deletion and may still report as valid for one frame.
	var valid_panels: Array[Control] = []
	for panel in _content_panels:
		if is_instance_valid(panel) and panel.is_inside_tree():
			valid_panels.append(panel)
	_content_panels = valid_panels
	for i in _content_panels.size():
		var panel := _content_panels[i]
		panel.visible = i == index
		if i == index:
			panel.modulate = Color(1, 1, 1, 0)
			var tw := create_tween()
			tw.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var valid_nav: Array[Button] = []
	for btn in _nav_buttons:
		if is_instance_valid(btn) and btn.is_inside_tree():
			valid_nav.append(btn)
	_nav_buttons = valid_nav
	for i in _nav_buttons.size():
		var btn := _nav_buttons[i]
		var active := i == index
		btn.add_theme_color_override("font_color", AMBER if (active or i == 0) else TEXT)
		btn.add_theme_color_override("font_hover_color", AMBER_HI if (active or i == 0) else Color.WHITE)
		if active:
			var active_style := StyleBoxFlat.new()
			active_style.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.12)
			active_style.set_corner_radius_all(8)
			active_style.border_width_left = 3
			active_style.border_color = AMBER
			active_style.content_margin_left = 16
			active_style.content_margin_right = 12
			active_style.content_margin_top = 10
			active_style.content_margin_bottom = 10
			btn.add_theme_stylebox_override("normal", active_style)
		else:
			var norm := StyleBoxFlat.new()
			norm.bg_color = Color(0, 0, 0, 0)
			norm.set_corner_radius_all(8)
			norm.content_margin_left = 16
			norm.content_margin_right = 12
			norm.content_margin_top = 10
			norm.content_margin_bottom = 10
			btn.add_theme_stylebox_override("normal", norm)
	if index == 4:
		get_tree().quit()

func _on_nav(index: int) -> void:
	_show_section(index)

func _build_home_panel(column: BoxContainer) -> void:
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", _style(PANEL, LINE, 14, 24, 20))
	column.add_child(hero)
	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 10)
	hero.add_child(hero_box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	hero_box.add_child(top)
	_dot = _label("●", 16, GOOD)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_dot)
	_status = _label("", 20, TEXT, 700)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_status)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spring)
	_chip = _make_chip(_t("ИСХОДНИКИ", "SOURCE"), AMBER_HI)
	_chip.visible = false
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_chip)
	_version_chip = _make_chip("", GOOD)
	_version_chip.visible = false
	_version_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_version_chip)

	_game_label = _label("", 13, DIM, 400, true)
	hero_box.add_child(_game_label)
	_mods_label = _label("", 13, FAINT)
	hero_box.add_child(_mods_label)

	_play = _button(_t("ИГРАТЬ", "PLAY"), true)
	_play.custom_minimum_size = Vector2(0, 56)
	_play.pressed.connect(_on_play)
	hero_box.add_child(_play)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_mods_btn = _button(_t("МОДЫ", "MODS"), false)
	_folder_btn = _button(_t("ПАПКА ИГРЫ", "GAME FOLDER"), false)
	_pick_btn = _button(_t("ВЫБРАТЬ ИГРУ", "SELECT GAME"), false)
	_mods_btn.pressed.connect(_on_mods)
	_folder_btn.pressed.connect(_on_folder)
	_pick_btn.pressed.connect(_on_pick)
	_folder_btn.tooltip_text = _t(
		"Папка лаунчера: здесь лежат установленные версии игры",
		"The launcher folder: installed game versions live here")
	for button in [_mods_btn, _folder_btn, _pick_btn]:
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)

func _build_versions_panel(column: BoxContainer) -> void:
	var installed_card := PanelContainer.new()
	installed_card.add_theme_stylebox_override("panel", _style(PANEL, LINE, 12, 18, 14))
	column.add_child(installed_card)
	var installed_box := VBoxContainer.new()
	installed_box.add_theme_constant_override("separation", 8)
	installed_card.add_child(installed_box)
	installed_box.add_child(_label(_t("УСТАНОВЛЕННЫЕ", "INSTALLED"), 11, DIM, 700))
	_installed_row = HBoxContainer.new()
	_installed_row.add_theme_constant_override("separation", 6)
	installed_box.add_child(_installed_row)

	var releases_card := PanelContainer.new()
	releases_card.add_theme_stylebox_override("panel", _style(PANEL, LINE, 12, 18, 14))
	column.add_child(releases_card)
	var releases_box := VBoxContainer.new()
	releases_box.add_theme_constant_override("separation", 8)
	releases_card.add_child(releases_box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	releases_box.add_child(head)
	head.add_child(_label(_t("ДОСТУПНЫЕ НА GITHUB", "AVAILABLE ON GITHUB"), 11, DIM, 700))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	_refresh_btn = _button(_t("ОБНОВИТЬ", "REFRESH"), false)
	_refresh_btn.custom_minimum_size = Vector2(0, 28)
	_refresh_btn.pressed.connect(_fetch_releases)
	head.add_child(_refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	releases_box.add_child(scroll)
	_available_list = VBoxContainer.new()
	_available_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_available_list)

	_list_note = _label("", 12, FAINT, 400, true)
	releases_box.add_child(_list_note)

func _build_mods_panel(column: BoxContainer) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(PANEL, LINE, 12, 18, 14))
	column.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_label(_t("МОДЫ МАШИН", "CAR MODS"), 13, TEXT, 700))
	_mods_label = _label("", 13, FAINT)
	box.add_child(_mods_label)
	var open_btn := _button(_t("ОТКРЫТЬ ПАПКУ МОДОВ", "OPEN MODS FOLDER"), false)
	open_btn.custom_minimum_size = Vector2(0, 40)
	open_btn.pressed.connect(_on_mods)
	box.add_child(open_btn)
	var hint := _label(_t("Положите mod.json в папку mods внутри папки модов игры, затем нажмите «МОДЫ» на главной.",
		"Drop mod.json into the mods folder inside the game's mods folder, then use MODS on the home screen."),
		12, FAINT, 400, true)
	box.add_child(hint)

func _build_settings_panel(column: BoxContainer) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(PANEL, LINE, 12, 18, 14))
	column.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)

	var close_check := _check(_t("Закрывать лаунчер после запуска игры",
		"Close the launcher after starting the game"))
	close_check.button_pressed = _close_on_play
	close_check.toggled.connect(_on_close_on_play_toggled)
	rows.add_child(close_check)

	var fetch_check := _check(_t("Проверять список версий при запуске",
		"Fetch the version list on start"))
	fetch_check.button_pressed = _fetch_on_start
	fetch_check.toggled.connect(_on_fetch_on_start_toggled)
	rows.add_child(fetch_check)

	var ontop_check := _check(_t("Всегда поверх других окон",
		"Keep the launcher window on top"))
	ontop_check.button_pressed = _always_on_top
	ontop_check.toggled.connect(_on_always_on_top_toggled)
	rows.add_child(ontop_check)

	var notify_check := _check(_t("Уведомление при завершении загрузки",
		"Show a notification when a download finishes"))
	notify_check.button_pressed = _notify_on_download
	notify_check.toggled.connect(_on_notify_on_download_toggled)
	rows.add_child(notify_check)

	var autoselect_check := _check(_t("Автовыбор последней установленной версии",
		"Auto-select the newest installed version on start"))
	autoselect_check.button_pressed = _auto_select_latest
	autoselect_check.toggled.connect(_on_auto_select_latest_toggled)
	rows.add_child(autoselect_check)

	var args_row := HBoxContainer.new()
	args_row.add_theme_constant_override("separation", 8)
	rows.add_child(args_row)
	args_row.add_child(_label(_t("Аргументы запуска", "Launch arguments"), 14, DIM, 500))
	var args_input := LineEdit.new()
	args_input.text = _launch_args
	args_input.placeholder_text = _t("--verbose --resolution 1920x1080", "--verbose --resolution 1920x1080")
	args_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	args_input.add_theme_font_override("font", _font(400))
	args_input.add_theme_font_size_override("font_size", 13)
	args_input.add_theme_color_override("font_color", TEXT)
	args_input.add_theme_stylebox_override("normal", _style(PANEL, LINE, 6, 10, 6))
	args_input.add_theme_stylebox_override("focus", _style(PANEL, AMBER, 6, 10, 6))
	args_input.text_changed.connect(func(t: String) -> void: _launch_args = t; _save_cfg())
	args_row.add_child(args_input)

	# Source path: empty by default; set it to run the game from a checkout
	# without exporting. Validated against project.godot + main_menu.tscn.
	var src_row := HBoxContainer.new()
	src_row.add_theme_constant_override("separation", 8)
	rows.add_child(src_row)
	src_row.add_child(_label(_t("Путь к исходникам", "Source path"), 14, DIM, 500))
	var src_input := LineEdit.new()
	src_input.text = _source_path
	src_input.placeholder_text = _t("пусто — автоопределение отключено", "empty — auto-detect disabled")
	src_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src_input.add_theme_font_override("font", _font(400))
	src_input.add_theme_font_size_override("font_size", 13)
	src_input.add_theme_color_override("font_color", TEXT)
	src_input.add_theme_stylebox_override("normal", _style(PANEL, LINE, 6, 10, 6))
	src_input.add_theme_stylebox_override("focus", _style(PANEL, AMBER, 6, 10, 6))
	src_input.text_changed.connect(func(t: String) -> void: _source_path = t; _save_cfg(); _refresh())
	src_row.add_child(src_input)
	var browse_btn := _button(_t("ОБЗОР", "BROWSE"), false)
	browse_btn.custom_minimum_size = Vector2(90, 30)
	browse_btn.pressed.connect(func() -> void: _on_browse_source())
	src_row.add_child(browse_btn)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	rows.add_child(lang_row)
	lang_row.add_child(_label(_t("Язык", "Language"), 14, DIM, 500))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(spring)
	_lang_ru_btn = _button("RU", false)
	_lang_ru_btn.custom_minimum_size = Vector2(52, 28)
	_lang_ru_btn.disabled = _ru
	_lang_ru_btn.pressed.connect(func() -> void: _on_language_set(true))
	lang_row.add_child(_lang_ru_btn)
	_lang_en_btn = _button("EN", false)
	_lang_en_btn.custom_minimum_size = Vector2(52, 28)
	_lang_en_btn.disabled = not _ru
	_lang_en_btn.pressed.connect(func() -> void: _on_language_set(false))
	lang_row.add_child(_lang_en_btn)

	var about := _label(_t(
		"Папка лаунчера: %s" % _data_dir,
		"Launcher folder: %s" % _data_dir), 12, FAINT, 400, true)
	rows.add_child(about)

func _add_background() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, BG_TOP)
	gradient.set_color(1, BG)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	var sky := TextureRect.new()
	sky.texture = texture
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(sky)

	if ResourceLoader.exists("res://assets/logo.svg"):
		var mark := TextureRect.new()
		mark.texture = load("res://assets/logo.svg") as Texture2D
		mark.modulate = Color(1, 1, 1, 0.035)
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		mark.offset_left = -360
		mark.offset_top = -360
		mark.offset_right = -20
		mark.offset_bottom = -20
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui_root.add_child(mark)

	var accent := ColorRect.new()
	accent.color = AMBER
	accent.anchor_right = 1.0
	accent.offset_bottom = 3.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(accent)

# ---- state ----

func _refresh() -> void:
	if _play == null or _data_dir.is_empty():
		return
	_installed = LauncherCore.installed_versions(_data_dir)
	var command := LauncherCore.resolve_command(_launcher_dir(), _data_dir, _saved_game,
		_source_path, _selected_version, OS.has_feature("editor"))
	var has := not command.is_empty()
	var source := has and bool(command.get("source", false))
	var version := String(command.get("version", ""))
	var target := String(command.get("target", ""))
	_play.disabled = not has
	_chip.visible = source
	if _version_chip != null:
		_version_chip.visible = not version.is_empty()
		if not version.is_empty():
			(_version_chip.get_child(0) as Label).text = version
	var mods := LauncherCore.mods_dir()
	var count := LauncherCore.count_mods(mods)
	if has:
		_dot.add_theme_color_override("font_color", GOOD)
		_status.text = _t("ГОТОВО К ЗАПУСКУ", "READY TO PLAY")
		_status.add_theme_color_override("font_color", GOOD)
	else:
		_dot.add_theme_color_override("font_color", BAD)
		_status.text = _t("ИГРА НЕ НАЙДЕНА", "GAME NOT FOUND")
		_status.add_theme_color_override("font_color", BAD)
	if not _install_error.is_empty():
		_game_label.text = _install_error
		_game_label.add_theme_color_override("font_color", BAD)
	elif source:
		_game_label.text = _t("Запуск из исходников: ", "Running from source: ") + target
		_game_label.add_theme_color_override("font_color", DIM)
	elif has and not version.is_empty():
		_game_label.text = version + " · " + target
		_game_label.add_theme_color_override("font_color", DIM)
	elif has:
		_game_label.text = target
		_game_label.add_theme_color_override("font_color", DIM)
	else:
		_game_label.text = _t(
			"Установите версию ниже или положите игру рядом с лаунчером.",
			"Install a version below or put the game next to the launcher.")
		_game_label.add_theme_color_override("font_color", DIM)
	_mods_label.text = _t("Установлено модов: %d" % count, "Mods installed: %d" % count)
	_mods_label.add_theme_color_override("font_color", DIM if count > 0 else FAINT)
	_rebuild_versions()

func _rebuild_versions() -> void:
	_row_progress = null
	for child in _installed_row.get_children():
		_installed_row.remove_child(child)
		child.queue_free()
	if _installed.is_empty():
		_installed_row.add_child(_label(
			_t("Нет установленных версий", "No versions installed"), 12, FAINT))
	else:
		for tag in _installed:
			_installed_row.add_child(_make_version_chip(String(tag)))

	for child in _available_list.get_children():
		_available_list.remove_child(child)
		child.queue_free()
	var busy := _downloading or _extracting
	if _available.is_empty():
		if busy:
			_list_note.text = _t("Установка %s…" % _download_tag, "Installing %s…" % _download_tag)
			_list_note.add_theme_color_override("font_color", AMBER_HI)
		else:
			_list_note.add_theme_color_override("font_color", FAINT)
			if _list_failed:
				_list_note.text = _t(
					"Список версий не получен — проверьте соединение и нажмите «Обновить».",
					"The version list failed to load — check the connection and press Refresh.")
			else:
				_list_note.text = _t(
					"Список версий с GitHub появится здесь.",
					"The GitHub version list will appear here.")
		return
	_list_note.text = ""
	for release in _available:
		_available_list.add_child(_make_release_row(release))

func _make_version_chip(tag: String) -> Button:
	var selected := tag == _selected_version
	var chip := Button.new()
	chip.text = tag
	chip.focus_mode = Control.FOCUS_ALL
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.custom_minimum_size = Vector2(96, 32)
	chip.add_theme_font_override("font", _font(700 if selected else 500))
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_color_override("font_color", BG if selected else TEXT)
	chip.add_theme_color_override("font_hover_color", BG if selected else AMBER_HI)
	chip.add_theme_color_override("font_pressed_color", BG if selected else TEXT)
	chip.add_theme_color_override("font_focus_color", BG if selected else TEXT)
	chip.add_theme_stylebox_override("normal",
		_style(AMBER if selected else PANEL, Color.TRANSPARENT if selected else LINE, 8, 14, 6))
	chip.add_theme_stylebox_override("hover",
		_style(AMBER_HI if selected else PANEL_HOVER, Color.TRANSPARENT if selected else AMBER, 8, 14, 6))
	chip.add_theme_stylebox_override("pressed",
		_style(AMBER_DEEP if selected else PANEL, Color.TRANSPARENT if selected else AMBER, 8, 14, 6))
	chip.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, AMBER, 8, 14, 6))
	chip.pressed.connect(func() -> void: _on_version_picked(tag))
	return chip

func _make_release_row(release: Dictionary) -> Control:
	var tag := String(release.get("tag", ""))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _style(PANEL, LINE, 10, 14, 10))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var name_label := _label(tag, 15, TEXT, 600)
	name_label.custom_minimum_size = Vector2(100, 0)
	box.add_child(name_label)
	var asset: Dictionary = LauncherCore.asset_for_platform(release, OS.get_name())
	var size_text := ""
	if not asset.is_empty():
		var size_mb := float(asset.get("size", 0)) / 1048576.0
		size_text = ("≈%.0f МБ" % size_mb) if _ru else ("~%.0f MB" % size_mb)
	var size_label := _label(size_text, 12, FAINT)
	size_label.tooltip_text = _t(
		"Размер архива с GitHub; распакованная версия занимает больше.",
		"The GitHub archive size; the unpacked version is larger.")
	box.add_child(size_label)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spring)
	var busy := _downloading or _extracting
	if busy and tag == _download_tag:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(140, 8)
		bar.show_percentage = false
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", _style(PANEL, LINE, 4, 0, 0))
		bar.add_theme_stylebox_override("fill", _style(AMBER, Color.TRANSPARENT, 4, 0, 0))
		box.add_child(bar)
		_row_progress = bar
	elif busy:
		box.add_child(_label(_t("ОЖИДАНИЕ", "WAITING"), 11, FAINT, 600))
	elif tag in _installed:
		box.add_child(_label(_t("УСТАНОВЛЕНА", "INSTALLED"), 11, GOOD, 700))
		var remove_btn := _danger_button(_t("УДАЛИТЬ", "DELETE"))
		remove_btn.custom_minimum_size = Vector2(120, 30)
		remove_btn.pressed.connect(func() -> void: _on_remove(tag))
		box.add_child(remove_btn)
	elif asset.is_empty():
		box.add_child(_label(_t("НЕТ СБОРКИ", "NO BUILD"), 11, FAINT))
	else:
		var install := _button(_t("УСТАНОВИТЬ", "INSTALL"), false)
		install.custom_minimum_size = Vector2(130, 30)
		var url := String(asset.get("url", ""))
		install.pressed.connect(func() -> void: _on_install(tag, url))
		box.add_child(install)
	return row

# ---- actions ----

func _on_play() -> void:
	var command := LauncherCore.resolve_command(_launcher_dir(), _data_dir, _saved_game,
		_source_path, _selected_version, OS.has_feature("editor"))
	if command.is_empty():
		_refresh()
		return
	var exe := String(command["exe"])
	LauncherCore.prepare_game(exe)
	var args: PackedStringArray = command.get("args", PackedStringArray())
	# Append user-configured launch arguments.
	if not _launch_args.is_empty():
		for arg in _launch_args.split(" ", false):
			args.append(arg)
	var pid := OS.create_process(exe, args, false)
	if pid <= 0:
		_install_error = _t("Не удалось запустить игру: ", "Could not start the game: ") + exe
		_refresh()
		return
	if _close_on_play:
		get_tree().quit()
		return
	_game_pid = pid
	_process_check_timer = 0.0
	_dot.add_theme_color_override("font_color", GOOD)
	_status.text = _t("ИГРА ЗАПУЩЕНА", "GAME STARTED")
	_status.add_theme_color_override("font_color", GOOD)
	_game_label.text = _t("Лаунчер остаётся открытым · ", "The launcher stays open · ") + exe
	_game_label.add_theme_color_override("font_color", DIM)

func _on_mods() -> void:
	var dir := LauncherCore.ensure_mods_dir()
	if dir.is_empty():
		_status.text = _t("НЕ УДАЛОСЬ НАЙТИ ПАПКУ МОДОВ", "COULD NOT FIND THE MODS FOLDER")
		_status.add_theme_color_override("font_color", BAD)
		return
	if OS.shell_open(dir) != OK:
		_status.text = _t("НЕ УДАЛОСЬ ОТКРЫТЬ ПАПКУ МОДОВ", "COULD NOT OPEN THE MODS FOLDER")
		_status.add_theme_color_override("font_color", BAD)
		return
	_refresh()

func _on_folder() -> void:
	if _data_dir.is_empty():
		_status.text = _t("НЕ УДАЛОСЬ НАЙТИ ПАПКУ ЛАУНЧЕРА", "COULD NOT FIND THE LAUNCHER FOLDER")
		_status.add_theme_color_override("font_color", BAD)
		return
	if OS.shell_open(_data_dir) != OK:
		_status.text = _t("НЕ УДАЛОСЬ ОТКРЫТЬ ПАПКУ ЛАУНЧЕРА", "COULD NOT OPEN THE LAUNCHER FOLDER")
		_status.add_theme_color_override("font_color", BAD)

func _on_pick() -> void:
	# On Windows, use the native file dialog instead of Godot's built-in one:
	# the native dialog matches the OS look, remembers the last folder, and
	# integrates with the shell (quick access, recent places, etc.).
	if OS.get_name() == "Windows":
		var path := _native_file_picker()
		if not path.is_empty():
			_on_game_selected(path)
		return
	if _dialog == null:
		return
	_dialog.popup_centered_ratio(0.72)

# Shows the Windows OpenFileDialog via PowerShell and returns the selected path
# (empty string if cancelled or unavailable). Runs synchronously.
func _on_browse_source() -> void:
	if OS.get_name() == "Windows":
		var path := _native_folder_picker()
		if not path.is_empty():
			_source_path = path
			_save_cfg()
			_build_ui()
			_refresh()
		return
	# Fallback: nothing on non-Windows for now.

func _native_folder_picker() -> String:
	var initial := _data_dir.replace("\\", "\\\\")
	var ps := "Add-Type -AssemblyName System.Windows.Forms; " + \
		"$d = New-Object System.Windows.Forms.FolderBrowserDialog; " + \
		"$d.Description = 'Select the game source folder'; " + \
		"$d.SelectedPath = '" + initial + "'; " + \
		"if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $d.SelectedPath }"
	var output: Array = []
	var exit_code := OS.execute("powershell", PackedStringArray(["-NoProfile", "-WindowStyle", "Hidden", "-Command", ps]), output, true)
	if exit_code == 0 and output.size() > 0:
		var path := String(output[0]).strip_edges()
		if not path.is_empty() and not LauncherCore.validate_source_path(path).is_empty():
			return path
	return ""

func _native_file_picker() -> String:
	var initial := _data_dir.replace("\\", "\\\\")
	var ps := (
		"Add-Type -AssemblyName System.Windows.Forms; " +
		"$d = New-Object System.Windows.Forms.OpenFileDialog; " +
		"$d.Title = 'Select the game executable'; " +
		"$d.Filter = 'Game executable (*.exe;*.x86_64)|*.exe;*.x86_64|All files (*.*)|*.*'; " +
		"$d.InitialDirectory = '%s'; " +
		"if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $d.FileName }"
	) % initial
	var output: Array = []
	var exit_code := OS.execute("powershell", PackedStringArray(["-NoProfile", "-WindowStyle", "Hidden", "-Command", ps]), output, true)
	if exit_code == 0 and output.size() > 0:
		var path := String(output[0]).strip_edges()
		if not path.is_empty() and FileAccess.file_exists(path):
			return path
	return ""

func _on_game_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		_install_error = _t("Файл игры не найден: ", "Game file not found: ") + path
		_refresh()
		return
	_saved_game = path
	_selected_version = ""
	_install_error = ""
	_save_cfg()
	_refresh()

func _on_version_picked(tag: String) -> void:
	_selected_version = "" if tag == _selected_version else tag
	_install_error = ""
	_save_cfg()
	_refresh()

func _on_remove(tag: String) -> void:
	if _downloading or _extracting or _data_dir.is_empty():
		return
	if not LauncherCore.remove_version(_data_dir, tag):
		_install_error = _t("Не удалось удалить версию ", "Could not remove the version ") + tag
		_refresh()
		return
	if _selected_version == tag:
		var remaining: Array = LauncherCore.installed_versions(_data_dir)
		if not OS.has_feature("editor") and not remaining.is_empty():
			_selected_version = String(remaining[0])
		else:
			_selected_version = ""
	_install_error = ""
	_save_cfg()
	_refresh()

func _on_language() -> void:
	_ru = not _ru
	_save_cfg()
	call_deferred("_rebuild_after_language")

func _on_language_set(ru: bool) -> void:
	if _ru == ru:
		return
	_ru = ru
	_save_cfg()
	call_deferred("_rebuild_after_language")

func _rebuild_after_language() -> void:
	_build_ui()
	_refresh()
	if _play != null:
		_play.grab_focus()

func _on_close_on_play_toggled(pressed: bool) -> void:
	_close_on_play = pressed
	_save_cfg()

func _on_fetch_on_start_toggled(pressed: bool) -> void:
	_fetch_on_start = pressed
	_save_cfg()

func _on_always_on_top_toggled(pressed: bool) -> void:
	_always_on_top = pressed
	get_window().always_on_top = pressed
	_save_cfg()

func _on_notify_on_download_toggled(pressed: bool) -> void:
	_notify_on_download = pressed
	_save_cfg()

func _on_auto_select_latest_toggled(pressed: bool) -> void:
	_auto_select_latest = pressed
	_save_cfg()

# ---- github ----

func _make_http_nodes() -> void:
	if _http_list == null:
		_http_list = HTTPRequest.new()
		_http_list.timeout = 15.0
		_http_list.request_completed.connect(_on_list_completed)
		add_child(_http_list)
	if _http_get == null:
		_http_get = HTTPRequest.new()
		_http_get.timeout = 0.0
		_http_get.request_completed.connect(_on_download_completed)
		add_child(_http_get)

func _fetch_releases() -> void:
	if _http_list == null or _data_dir.is_empty():
		return
	_refresh_btn.disabled = true
	var err := _http_list.request(LauncherCore.RELEASES_URL,
		PackedStringArray(LauncherCore.HTTP_HEADERS))
	if err != OK:
		_refresh_btn.disabled = false
		_list_failed = true
		_available.clear()
		_refresh()

func _on_list_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_refresh_btn.disabled = false
	_list_failed = result != HTTPRequest.RESULT_SUCCESS or response_code != 200
	_available = [] if _list_failed else LauncherCore.parse_releases(body.get_string_from_utf8())
	_refresh()

func _on_install(tag: String, url: String) -> void:
	if _downloading or _extracting or url.is_empty() or _data_dir.is_empty():
		return
	var zip_path := LauncherCore.downloads_root(_data_dir).path_join(tag + ".zip")
	DirAccess.remove_absolute(zip_path)
	_http_get.download_file = zip_path
	_download_tag = tag
	_download_zip = zip_path
	_install_error = ""
	var err := _http_get.request(url, PackedStringArray(["User-Agent: CarCrashLauncher"]))
	if err != OK:
		_install_error = _t("Не удалось начать загрузку ", "Could not start the download ") + tag
		_refresh()
		return
	_downloading = true
	_refresh()

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_install_error = _t("Не удалось скачать архив релиза ", "Could not download the release archive ") + _download_tag
		_cleanup_zip()
		_refresh()
		return
	_extracting = true
	_refresh()
	await get_tree().process_frame
	var dest := LauncherCore.version_dir(_data_dir, _download_tag)
	if not LauncherCore.extract_zip(_download_zip, dest):
		_extracting = false
		_install_error = _t("Не удалось распаковать архив ", "Could not extract the archive ") + _download_tag
		_cleanup_zip()
		_refresh()
		return
	DirAccess.remove_absolute(_download_zip)
	_extracting = false
	_selected_version = _download_tag
	_save_cfg()
	_refresh()
	if _notify_on_download:
		_status.text = _t("ВЕРСИЯ УСТАНОВЛЕНА: %s" % _download_tag, "VERSION INSTALLED: %s" % _download_tag)
		_status.add_theme_color_override("font_color", GOOD)

func _cleanup_zip() -> void:
	if not _download_zip.is_empty():
		DirAccess.remove_absolute(_download_zip)

# ---- primitives ----

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

func _font(weight: int) -> SystemFont:
	if not _fonts.has(weight):
		var font := SystemFont.new()
		font.font_names = PackedStringArray([
			"Segoe UI Variable Display", "Segoe UI", "Inter", "Roboto",
			"DejaVu Sans", "Liberation Sans",
		])
		font.font_weight = weight
		_fonts[weight] = font
	return _fonts[weight] as SystemFont

func _label(text: String, size: int, color: Color, weight := 400, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font(weight))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _make_chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		_style(Color(AMBER.r, AMBER.g, AMBER.b, 0.10), AMBER, 8, 10, 4))
	chip.add_child(_label(text, 11, color, 700))
	return chip

func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _font(700 if primary else 600))
	button.add_theme_font_size_override("font_size", 24 if primary else 14)
	button.add_theme_color_override("font_color", BG if primary else TEXT)
	button.add_theme_color_override("font_hover_color", BG if primary else AMBER_HI)
	button.add_theme_color_override("font_pressed_color", BG if primary else TEXT)
	button.add_theme_color_override("font_focus_color", BG if primary else TEXT)
	button.add_theme_color_override("font_disabled_color", FAINT)
	var border := Color.TRANSPARENT if primary else LINE
	button.add_theme_stylebox_override("normal",
		_style(AMBER if primary else PANEL, border, 10, 20, 12))
	button.add_theme_stylebox_override("hover",
		_style(AMBER_HI if primary else PANEL_HOVER, Color.TRANSPARENT if primary else AMBER, 10, 20, 12))
	button.add_theme_stylebox_override("pressed",
		_style(AMBER_DEEP if primary else PANEL, Color.TRANSPARENT if primary else AMBER, 10, 20, 12))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, AMBER, 10, 20, 12))
	button.add_theme_stylebox_override("disabled", _style(PANEL, LINE, 10, 20, 12))
	return button

func _danger_button(text: String) -> Button:
	var button := _button(text, false)
	button.add_theme_color_override("font_color", BAD)
	button.add_theme_color_override("font_hover_color", BAD_HI)
	button.add_theme_color_override("font_pressed_color", BAD)
	button.add_theme_color_override("font_focus_color", BAD)
	button.add_theme_stylebox_override("normal", _style(PANEL, BAD, 10, 20, 12))
	button.add_theme_stylebox_override("hover", _style(PANEL_HOVER, BAD, 10, 20, 12))
	button.add_theme_stylebox_override("pressed", _style(PANEL, BAD, 10, 20, 12))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, BAD, 10, 20, 12))
	return button

func _check(text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.focus_mode = Control.FOCUS_ALL
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	check.add_theme_font_override("font", _font(500))
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_color_override("font_color", TEXT)
	check.add_theme_color_override("font_hover_color", AMBER_HI)
	check.add_theme_color_override("font_pressed_color", TEXT)
	check.add_theme_color_override("font_focus_color", TEXT)
	check.add_theme_icon_override("checked", _check_tex(true))
	check.add_theme_icon_override("unchecked", _check_tex(false))
	return check

func _check_tex(checked: bool) -> ImageTexture:
	var sz := 22
	var key := "check_%d" % int(checked)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in sz:
		for x in sz:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var qx := absf(p.x - 11.0) - 6.0
			var qy := absf(p.y - 11.0) - 6.0
			var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - 5.0
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			if checked:
				var col := AMBER
				var d1 := _seg_dist(p, Vector2(5.5, 11.5), Vector2(9.5, 15.5))
				var d2 := _seg_dist(p, Vector2(9.5, 15.5), Vector2(17.0, 6.5))
				if minf(d1, d2) < 2.4:
					col = Color(0.98, 0.98, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
			else:
				var inner_d := Vector2(maxf(qx + 1.5, 0.0), maxf(qy + 1.5, 0.0)).length() + minf(maxf(qx + 1.5, qy + 1.5), 0.0) - 3.5
				var inner_a := clampf(0.5 - inner_d, 0.0, 1.0)
				var col := Color(0.07, 0.075, 0.09) if inner_a >= 0.5 else Color(0.72, 0.76, 0.82)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length()

func _style(bg: Color, border: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	if border.a > 0.0:
		style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style