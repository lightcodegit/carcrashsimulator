extends SceneTree
# Launcher path rules are the part that can silently break a release: the wrong
# executable name, a stale saved path, or a mods folder computed for the
# launcher's own user:// instead of the game's. The UI itself is covered by the
# exported-build smoke run; this test keeps the contract testable without a
# window or a second Godot instance.

var fails := 0
const LauncherCore := preload("res://launcher/scripts/launcher_core.gd")
const ROOT := "user://launcher_test"
# A GitHub API answer fixture: two valid releases (one with both platform
# zips, one Windows-only) and one tagless entry that must be skipped.
const RELEASES_JSON := """[
	{"tag_name": "v0.1.6", "assets": [
		{"name": "car-crash-simulator-windows.zip", "browser_download_url": "https://example/win6.zip", "size": 111111111},
		{"name": "car-crash-simulator-linux.zip", "browser_download_url": "https://example/linux6.zip", "size": 99999999}
	]},
	{"tag_name": "v0.1.5", "assets": [
		{"name": "car-crash-simulator-windows.zip", "browser_download_url": "https://example/win5.zip", "size": 100000000}
	]},
	{"draft": true}
]"""

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func mkdir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)

func touch(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("")
		file.close()

func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func version_of(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("config/version="):
			return trimmed.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""

func _initialize() -> void:
	# The launcher must ship the same version as the game it starts, otherwise
	# the released zip contains a launcher from another release.
	var game_version := version_of("res://project.godot")
	var launcher_version := version_of("res://launcher/project.godot")
	check(game_version != "" and game_version == launcher_version,
		"launcher version matches the game (%s vs %s)" % [launcher_version, game_version])
	check(FileAccess.file_exists("res://launcher/project.godot"), "the launcher is a standalone project")
	# The product name lands in the window title and in the launcher's own
	# user:// folder (app_userdata/<project name>); the shipped binary is
	# "Car Crash Launcher", so the project must not carry the longer name.
	check(FileAccess.get_file_as_string("res://launcher/project.godot").contains(
		"config/name=\"Car Crash Launcher\""), "the launcher project is named Car Crash Launcher")
	check(FileAccess.get_file_as_string("res://launcher/scripts/launcher.gd").contains(
		"\"Car Crash Launcher v\""), "the window title shows the launcher name")
	check(FileAccess.get_file_as_string("res://launcher/project.godot").contains(
		"run/main_scene=\"res://scenes/launcher.tscn\""),
		"the launcher project starts its own scene")
	# The scene belongs to the nested launcher project: its "res://scripts/..."
	# paths resolve against launcher/, not against this project, so loading it
	# here would look for res://scripts/launcher.gd. Check the wiring on disk
	# instead; the launcher project boots on its own in the build smoke run.
	var scene_path := "res://launcher/scenes/launcher.tscn"
	check(FileAccess.file_exists(scene_path), "the launcher scene exists")
	var scene := FileAccess.get_file_as_string(scene_path)
	check(scene.contains("path=\"res://scripts/launcher.gd\""), "the launcher scene names its script")
	var ui_script := "res://launcher/scripts/launcher.gd"
	check(FileAccess.file_exists(ui_script), "the launcher UI script exists")
	check(FileAccess.get_file_as_string(ui_script).contains("extends Control"),
		"the launcher UI script is a Control script")
	# Settings travel through the launcher config and use real toggle controls:
	# close-on-play and the startup version check are player choices, not
	# hard-coded behavior.
	check(FileAccess.get_file_as_string(ui_script).contains("close_on_play"),
		"the launcher has a close-on-play setting")
	check(FileAccess.get_file_as_string(ui_script).contains("fetch_on_start"),
		"the launcher has a startup version-check setting")
	check(FileAccess.get_file_as_string(ui_script).contains("CheckButton"),
		"the settings use toggle controls")

	# Isolated fake layout: launcher/, game/, parent/ and a saved path.
	var launcher_dir := ROOT.path_join("launcher")
	var game_dir := launcher_dir.path_join("game")
	mkdir(launcher_dir)
	mkdir(game_dir)
	var exe_name: String = LauncherCore.GAME_NAMES[0]
	var same_dir := launcher_dir.path_join(exe_name)
	var nested := game_dir.path_join(exe_name)
	var parent := launcher_dir.get_base_dir().path_join(exe_name)
	touch(nested)
	check(LauncherCore.find_game(launcher_dir) == nested, "the game is found in a game/ subfolder")
	remove(nested)
	touch(same_dir)
	check(LauncherCore.find_game(launcher_dir) == same_dir, "the game is found next to the launcher")
	remove(same_dir)
	touch(parent)
	check(LauncherCore.find_game(launcher_dir) == parent, "the game is found one level up")
	remove(parent)
	check(LauncherCore.find_game(launcher_dir) == "", "no game means an empty path")
	var saved_dir := ROOT.path_join("saved")
	mkdir(saved_dir)
	var saved := saved_dir.path_join("custom_game.exe")
	touch(saved)
	check(LauncherCore.find_game(launcher_dir, saved) == saved, "a valid saved path wins")
	check(LauncherCore.find_game(launcher_dir, saved_dir.path_join("missing.exe")) == "",
		"a stale saved path is ignored")
	remove(saved)

	# The launcher keeps its state in the OS user locations, never next to the
	# exe: installed versions must survive launcher updates and read-only
	# install directories.
	var data := LauncherCore.ensure_launcher_data_dir()
	check(not data.is_empty(), "the launcher data folder resolves in the system")
	check(DirAccess.dir_exists_absolute(LauncherCore.versions_root(data)), "the versions folder is created")
	check(DirAccess.dir_exists_absolute(LauncherCore.downloads_root(data)), "the downloads folder is created")

	# Installed versions: only folders with a game executable count, newest
	# first, numeric part compare (v0.1.10 sorts after v0.1.9, not by letters).
	var v9 := LauncherCore.version_dir(data, "v0.1.9")
	var v10 := LauncherCore.version_dir(data, "v0.1.10")
	var broken := LauncherCore.version_dir(data, "v0.1.8")
	mkdir(v9)
	mkdir(v10)
	mkdir(broken)
	touch(v9.path_join(exe_name))
	touch(v10.path_join(exe_name))
	var installed: Array = LauncherCore.installed_versions(data)
	check(installed.size() == 2 and installed[0] == "v0.1.10" and installed[1] == "v0.1.9",
		"installed versions list newest first with a numeric compare (%s)" % str(installed))
	check(LauncherCore.installed_versions(ROOT.path_join("missing_data")) == [],
		"a missing data folder has no versions")

	# A version wrapped in a single folder (a repacked archive) still resolves.
	var wrapped := LauncherCore.version_dir(data, "v0.1.7")
	mkdir(wrapped.path_join("inner"))
	touch(wrapped.path_join("inner").path_join(exe_name))
	check(LauncherCore.version_exe(wrapped) == wrapped.path_join("inner").path_join(exe_name),
		"a version wrapped in one folder still yields the executable")

	# A downloaded release zip extracts into a runnable version layout.
	var extracted := ROOT.path_join("extracted")
	check(LauncherCore.extract_zip("res://tests/fixtures/fake_version.zip", extracted),
		"a release zip extracts into the version folder")
	check(FileAccess.get_file_as_string(extracted.path_join("extra").path_join("notes.txt")) == "nested file",
		"nested entries extract with their folders")
	check(LauncherCore.version_exe(extracted) == extracted.path_join(exe_name),
		"the extracted layout is recognized as an installed version")
	check(not LauncherCore.extract_zip("res://tests/fixtures/missing.zip", extracted),
		"a missing archive fails the install")

	# The release list from GitHub is parsed without any network: tags with
	# assets, and the platform asset picked by its exact name.
	var releases: Array = LauncherCore.parse_releases(RELEASES_JSON)
	check(releases.size() == 2 and String(releases[0].get("tag", "")) == "v0.1.6",
		"the release list parses tags and skips tagless entries")
	var win_asset: Dictionary = LauncherCore.asset_for_platform(releases[0], "Windows")
	check(String(win_asset.get("name", "")) == "car-crash-simulator-windows.zip",
		"the Windows asset is picked by name")
	check(String(LauncherCore.asset_for_platform(releases[0], "macOS").get("name", "")) == "car-crash-simulator-linux.zip",
		"the Linux asset serves other platforms")
	check(LauncherCore.asset_for_platform(releases[1], "macOS").is_empty(),
		"a release without an asset for the platform is not installable")
	check(LauncherCore.parse_releases("not json") == [], "a broken API answer yields no releases")

	# Source mode: the launcher run from the editor starts the parent project.
	var menu := launcher_dir.get_base_dir().path_join("scenes").path_join("main_menu.tscn")
	var project := launcher_dir.get_base_dir().path_join("project.godot")
	mkdir(project.get_base_dir().path_join("scenes"))
	touch(project)
	touch(menu)
	check(LauncherCore.find_source_root(launcher_dir) == launcher_dir.get_base_dir(),
		"the parent project is detected")
	var command: Dictionary = LauncherCore.resolve_command(launcher_dir, data, "", "", "", true, "godot_test")
	check(String(command.get("exe", "")) == "godot_test", "source mode uses the editor executable")
	check(bool(command.get("source", false)), "source mode is marked as source")
	var args: PackedStringArray = command.get("args", PackedStringArray())
	check(args.size() == 2 and args[0] == "--path" and args[1] == launcher_dir.get_base_dir(),
		"source mode passes --path to the project")
	# A stale exported binary next to the launcher (exports land in the project
	# root, see .gitignore) must not shadow the live project in the editor.
	touch(same_dir)
	var editor_command: Dictionary = LauncherCore.resolve_command(launcher_dir, data, "", "", "", true, "godot_test")
	check(bool(editor_command.get("source", false)),
		"in the editor the live project wins over a stray exported binary")
	check(LauncherCore.resolve_command(launcher_dir, data, "", "", "", false).get("source", true) == false,
		"outside the editor the binary next to the launcher is the game")
	# A version selected in the UI is the player's explicit choice and beats
	# both the source project and the binary next to the launcher.
	var selected: Dictionary = LauncherCore.resolve_command(launcher_dir, data, "", "", "v0.1.10", true, "godot_test")
	check(String(selected.get("version", "")) == "v0.1.10"
		and String(selected.get("target", "")) == v10.path_join(exe_name),
		"the selected installed version wins over source and side-by-side")
	# A selection whose files vanished falls through instead of breaking PLAY.
	var stale_sel: Dictionary = LauncherCore.resolve_command(launcher_dir, data, "", "", "v0.1.6", false)
	check(String(stale_sel.get("target", "")) == same_dir,
		"a missing selected version falls back to the found game")
	remove(same_dir)
	remove(menu)
	check(LauncherCore.find_source_root(launcher_dir) == "", "a folder without the game scene is not a source root")
	remove(project)

	# A manually configured source path overrides auto-detection and works even
	# outside the editor; an empty path keeps source mode off (the default).
	check(LauncherCore.validate_source_path("") == "", "an empty source path is disabled by default")
	var custom_root := launcher_dir.get_base_dir().path_join("custom_src")
	mkdir(custom_root.path_join("scenes"))
	touch(custom_root.path_join("project.godot"))
	touch(custom_root.path_join("scenes").path_join("main_menu.tscn"))
	check(LauncherCore.validate_source_path(custom_root) == custom_root,
		"a valid source path is accepted")
	check(LauncherCore.validate_source_path(launcher_dir) == "",
		"a folder without a project is rejected")
	var custom_cmd: Dictionary = LauncherCore.resolve_command(launcher_dir, data, "", custom_root, "", false)
	check(bool(custom_cmd.get("source", false)) and String(custom_cmd.get("target", "")) == custom_root,
		"a configured source path works without the editor")
	remove(custom_root.path_join("scenes").path_join("main_menu.tscn"))
	remove(custom_root.path_join("project.godot"))
	DirAccess.remove_absolute(custom_root.path_join("scenes"))
	DirAccess.remove_absolute(custom_root)

	# Removing an installed version deletes its files, and a crafted tag can
	# never escape the versions root.
	var doomed := LauncherCore.version_dir(data, "v0.1.9")
	mkdir(doomed.path_join("inner"))
	touch(doomed.path_join("inner").path_join("payload.bin"))
	check(LauncherCore.remove_version(data, "v0.1.9"), "an installed version is removed")
	check(not DirAccess.dir_exists_absolute(doomed), "the removed version folder is gone with its files")
	check(not LauncherCore.remove_version(data, "../evil"), "a path-escape tag is refused")
	check(not LauncherCore.remove_version(data, "..\\evil"), "a backslash tag is refused")
	check(not LauncherCore.remove_version(data, "v0.1.99"), "a missing version is not removed")

	# The mods path must belong to the game's user-data folder, not the
	# launcher's differently named one.
	var mods: String = LauncherCore.mods_dir()
	check(mods.get_file() == LauncherCore.MODS_SUBDIR, "the mods path ends with mods")
	check(mods.get_base_dir().get_file() == LauncherCore.GAME_PROJECT_NAME,
		"the mods path belongs to the game user folder (%s)" % mods)
	var created: String = LauncherCore.ensure_mods_dir()
	check(created == mods and DirAccess.dir_exists_absolute(created), "the mods folder is created")
	mkdir(created.path_join("pack_a"))
	mkdir(created.path_join("pack_b"))
	mkdir(created.path_join("not_a_pack"))
	touch(created.path_join("pack_a").path_join("mod.json"))
	touch(created.path_join("pack_b").path_join("mod.json"))
	check(LauncherCore.count_mods(created) == 2, "only folders with mod.json count as mods")
	check(LauncherCore.count_mods(created.path_join("missing")) == 0, "a missing mods folder has no mods")

	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
