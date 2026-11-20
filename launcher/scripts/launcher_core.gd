extends RefCounted
# UI-free launcher logic: find the game, manage installed game versions, build
# the command line, and locate the folders the game and the launcher use.
# Keeping this separate from launcher.gd makes every rule testable headlessly
# from the main project's test runner.

const GAME_NAMES: Array[String] = [
	"Car Crash Simulator.exe",
	"car-crash-simulator.exe",
	"Car Crash Simulator.x86_64",
]
const GAME_PROJECT_NAME := "Car Crash Simulator"
const MODS_SUBDIR := "mods"
const VERSIONS_SUBDIR := "versions"
const DOWNLOADS_SUBDIR := "downloads"
# The release workflow packs exactly these asset names per platform.
const ASSET_NAMES := {
	"Windows": "car-crash-simulator-windows.zip",
	"macOS": "car-crash-simulator-linux.zip",
}
const RELEASES_URL := "https://api.github.com/repos/lightcodegit/carcrashsimulator/releases?per_page=30"
const HTTP_HEADERS := [
	"User-Agent: CarCrashLauncher",
	"Accept: application/vnd.github+json",
]

# ------------------------------------------------------------------ folders

# The launcher's own data folder lives in the OS user locations, never next to
# the executable: installed game versions must survive launcher updates and
# read-only install directories, and a folder beside the exe gives none of
# that. Every writable state (config, versions, downloads) lives here.
static func launcher_data_dir() -> String:
	match OS.get_name():
		"Windows":
			var base := OS.get_environment("APPDATA")
			if base.is_empty():
				base = OS.get_environment("USERPROFILE")
			if base.is_empty():
				return ""
			return base.path_join("Car Crash Launcher")
		"macOS":
			var home := OS.get_environment("HOME")
			if home.is_empty():
				return ""
			return home.path_join("Library").path_join("Application Support") \
				.path_join("Car Crash Launcher")
		_:
			var data := OS.get_environment("XDG_DATA_HOME")
			if data.is_empty():
				var home := OS.get_environment("HOME")
				if home.is_empty():
					return ""
				data = home.path_join(".local").path_join("share")
			return data.path_join("car-crash-launcher")

static func ensure_launcher_data_dir() -> String:
	var dir := launcher_data_dir()
	if dir.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir.path_join(VERSIONS_SUBDIR))
	DirAccess.make_dir_recursive_absolute(dir.path_join(DOWNLOADS_SUBDIR))
	return dir

static func versions_root(data_dir: String) -> String:
	return data_dir.path_join(VERSIONS_SUBDIR)

static func downloads_root(data_dir: String) -> String:
	return data_dir.path_join(DOWNLOADS_SUBDIR)

static func version_dir(data_dir: String, tag: String) -> String:
	return versions_root(data_dir).path_join(tag)

# ------------------------------------------------------------------ versions

static func installed_versions(data_dir: String) -> Array:
	var tags: Array = []
	var access := DirAccess.open(versions_root(data_dir))
	if access == null:
		return tags
	for folder in access.get_directories():
		if not version_exe(versions_root(data_dir).path_join(String(folder))).is_empty():
			tags.append(String(folder))
	tags.sort_custom(func(a: String, b: String) -> bool: return tag_newer(a, b))
	return tags

# Find the game executable inside an extracted version: at the root (the way
# the release zip is packed) or inside a single wrapper folder, if an archive
# ever gets repacked that way.
static func version_exe(dir: String) -> String:
	for name in GAME_NAMES:
		var candidate := dir.path_join(name)
		if FileAccess.file_exists(candidate):
			return candidate
	var access := DirAccess.open(dir)
	if access != null:
		var subdirs := access.get_directories()
		if subdirs.size() == 1:
			var inner := dir.path_join(String(subdirs[0]))
			for name in GAME_NAMES:
				var nested := inner.path_join(name)
				if FileAccess.file_exists(nested):
					return nested
	return ""

# Delete an installed version. The tag is a folder name shown in the UI:
# refuse anything that could escape the versions root ("..", separators,
# absolute paths) — a crafted name must never delete outside the data folder.
static func remove_version(data_dir: String, tag: String) -> bool:
	if tag.is_empty() or tag == "." or tag == ".." or "/" in tag or "\\" in tag \
			or tag.is_absolute_path():
		return false
	var dir := version_dir(data_dir, tag)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	_remove_tree(dir)
	return not DirAccess.dir_exists_absolute(dir)

static func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		DirAccess.remove_absolute(path)
		return
	access.list_dir_begin()
	var entry := access.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if access.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = access.get_next()
	access.list_dir_end()
	DirAccess.remove_absolute(path)

# "v0.1.10" must beat "v0.1.9": the dot-separated parts compare as numbers,
# never as text.
static func tag_newer(a: String, b: String) -> bool:
	var pa := _tag_parts(a)
	var pb := _tag_parts(b)
	for i in maxi(pa.size(), pb.size()):
		var na := pa[i] if i < pa.size() else 0
		var nb := pb[i] if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false

static func _tag_parts(tag: String) -> PackedInt32Array:
	var clean := tag.trim_prefix("v").trim_prefix("V")
	var parts := PackedInt32Array()
	for chunk in clean.split("."):
		parts.append(chunk.to_int())
	return parts

# ------------------------------------------------------------------ github

# GitHub releases list -> [{tag, assets: [{name, url, size}]}]. Entries without
# a tag are skipped; nothing is downloaded here, so tests can feed a fixture.
static func parse_releases(json_text: String) -> Array:
	var parsed = JSON.parse_string(json_text)
	var releases: Array = []
	if parsed is Array:
		for entry in parsed:
			var tag := String(entry.get("tag_name", ""))
			if tag.is_empty():
				continue
			var assets: Array = []
			for asset in entry.get("assets", []):
				assets.append({
					"name": String(asset.get("name", "")),
					"url": String(asset.get("browser_download_url", "")),
					"size": int(asset.get("size", 0)),
				})
			releases.append({"tag": tag, "assets": assets})
	return releases

# The asset of this release for the platform we run on; {} when the release
# has no build for it.
static func asset_for_platform(release: Dictionary, platform: String) -> Dictionary:
	var want: String = ASSET_NAMES.get(platform, ASSET_NAMES["macOS"])
	for asset in release.get("assets", []):
		if String(asset.get("name", "")) == want:
			return asset
	return {}

# Extract a downloaded release zip into dest_dir. Directory entries are
# skipped, ".." is never followed, and one failed entry fails the whole
# install: a half-written version must not look installed.
static func extract_zip(zip_path: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var ok := true
	for entry in reader.get_files():
		var name := String(entry)
		if name.ends_with("/") or name.begins_with("/") or ".." in name:
			continue
		var target := dest_dir.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			ok = false
			break
		file.store_buffer(reader.read_file(name))
		file.close()
	reader.close()
	return ok

# ------------------------------------------------------------------ resolve

# A saved path wins only while it still points at a file. Otherwise look next to
# the launcher, in a game/ subfolder, and one level up (a launcher unpacked into
# the game folder but started from a subdirectory).
static func find_game(launcher_dir: String, saved: String = "") -> String:
	if not saved.is_empty() and FileAccess.file_exists(saved):
		return saved
	var dirs: Array[String] = [launcher_dir, launcher_dir.path_join("game")]
	var parent := launcher_dir.get_base_dir()
	if not parent.is_empty() and parent != launcher_dir:
		dirs.append(parent)
	for dir in dirs:
		for name in GAME_NAMES:
			var candidate := dir.path_join(name)
			if FileAccess.file_exists(candidate):
				return candidate
	return ""

# Running the launcher from the editor: the game lives one folder up. Launching
# the editor executable with --path starts that project without opening the
# editor UI, so development does not need an exported game next to the launcher.
static func find_source_root(launcher_dir: String) -> String:
	var root := launcher_dir.get_base_dir()
	if root.is_empty() or root == launcher_dir:
		return ""
	var project := root.path_join("project.godot")
	var menu := root.path_join("scenes").path_join("main_menu.tscn")
	if FileAccess.file_exists(project) and FileAccess.file_exists(menu):
		return root
	return ""

# What PLAY runs, in order:
#   1. a version selected in the UI (the player's explicit choice);
#   2. a manually configured source path — the developer's override, used even
#      outside the editor so a custom checkout can be started without an export;
#   3. in the editor, the live source project next to the launcher — exports
#      land in the repository root (see .gitignore), and a stale binary found
#      there must not shadow the project the developer is actually running;
#   4. a game found next to the launcher / one level up / by a saved path —
#      the release zip still ships both executables side by side.
static func resolve_command(launcher_dir: String, data_dir: String, saved: String,
		source_path: String, selected_version: String, allow_source: bool,
		editor_exe: String = "") -> Dictionary:
	if not selected_version.is_empty():
		var installed := version_exe(version_dir(data_dir, selected_version))
		if not installed.is_empty():
			return {
				"exe": installed,
				"args": PackedStringArray(),
				"target": installed,
				"source": false,
				"version": selected_version,
			}
	# A manually configured source path wins over auto-detection: the player
	# chose it, so it is not a guess about the launcher's neighbourhood.
	var configured_root := _validate_source_root(source_path)
	if not configured_root.is_empty():
		var exe := editor_exe if (allow_source and not editor_exe.is_empty()) else OS.get_executable_path()
		if exe.is_empty():
			exe = OS.get_executable_path()
		if not exe.is_empty():
			return {
				"exe": exe,
				"args": PackedStringArray(["--path", configured_root]),
				"target": configured_root,
				"source": true,
				"version": "",
			}
	if allow_source:
		var root := find_source_root(launcher_dir)
		var exe := editor_exe if not editor_exe.is_empty() else OS.get_executable_path()
		if not root.is_empty() and not exe.is_empty():
			return {
				"exe": exe,
				"args": PackedStringArray(["--path", root]),
				"target": root,
				"source": true,
				"version": "",
			}
	var game := find_game(launcher_dir, saved)
	if not game.is_empty():
		return {"exe": game, "args": PackedStringArray(), "target": game, "source": false, "version": ""}
	return {}

# A source path is usable only when it actually is a Godot project with a
# main menu scene. Returns the normalized path, or "" when it is not.
static func validate_source_path(path: String) -> String:
	return _validate_source_root(path)

static func _validate_source_root(path: String) -> String:
	var root := path.strip_edges()
	if root.is_empty():
		return ""
	while root.ends_with("/") or root.ends_with("\\"):
		root = root.substr(0, root.length() - 1)
	var project := root.path_join("project.godot")
	var menu := root.path_join("scenes").path_join("main_menu.tscn")
	if FileAccess.file_exists(project) and FileAccess.file_exists(menu):
		return root
	return ""

# ------------------------------------------------------------------ mods

# The game and the launcher have different project names, so user:// is not
# shared. The game stores mods under the user-data folder named by its project
# name; these are the OS locations Godot uses for that name.
static func user_data_dir() -> String:
	match OS.get_name():
		"Windows":
			var appdata := OS.get_environment("APPDATA")
			if appdata.is_empty():
				appdata = OS.get_environment("USERPROFILE")
				if appdata.is_empty():
					return ""
			return appdata.path_join("Godot").path_join("app_userdata").path_join(GAME_PROJECT_NAME)
		"macOS":
			var home_mac := OS.get_environment("HOME")
			if home_mac.is_empty():
				return ""
			var mac_base := home_mac.path_join("Library").path_join("Application Support")
			return mac_base.path_join("Godot").path_join("app_userdata").path_join(GAME_PROJECT_NAME)
		_:
			var data := OS.get_environment("XDG_DATA_HOME")
			if data.is_empty():
				var home_linux := OS.get_environment("HOME")
				if home_linux.is_empty():
					return ""
				data = home_linux.path_join(".local").path_join("share")
			return data.path_join("godot").path_join("app_userdata").path_join(GAME_PROJECT_NAME)

static func mods_dir() -> String:
	var base := user_data_dir()
	return base.path_join(MODS_SUBDIR) if not base.is_empty() else ""

static func ensure_mods_dir() -> String:
	var dir := mods_dir()
	if dir.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	return dir

static func count_mods(mods: String) -> int:
	var access := DirAccess.open(mods)
	if access == null:
		return 0
	var count := 0
	for folder in access.get_directories():
		var file := mods.path_join(String(folder)).path_join("mod.json")
		if FileAccess.file_exists(file):
			count += 1
	return count

# Unix archives lose the executable bit more often than Windows ones. chmod is
# best effort: a failure is worth a warning, not a refusal to start the game.
static func prepare_game(path: String) -> void:
	if OS.get_name() == "Windows" or DirAccess.dir_exists_absolute(path):
		return
	var code := OS.execute("chmod", PackedStringArray(["+x", path]), [], true)
	if code != 0:
		push_warning("Could not mark the game executable: " + path)
