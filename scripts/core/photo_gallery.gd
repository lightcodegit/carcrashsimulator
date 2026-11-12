class_name PhotoGallery
extends RefCounted
# Photos on disk (user://photos, written by photo mode and replay snapshots)
# without any UI: listing, deletion and a thumbnail for the menu grid. The menu
# section consumes these functions directly, and the headless test checks them
# against real files — nothing here needs a GPU or a live window.

const DIR := "user://photos"
# PNG decode is the expensive part (each shot is a few megabytes): the gallery
# loads thumbnails for a bounded tail, the rest is still reachable on disk.
const MAX_THUMBS := 24
const THUMB_W := 240
const THUMB_H := 135

# Paths of existing photo_NNNN.png, newest first by the number in the name.
# A file renamed by hand without a number is ignored: guessing the order of
# unnumbered shots would make deletion a gamble.
static func list_photos() -> Array[String]:
	var d := DirAccess.open(DIR)
	var out: Array[String] = []
	if d == null: return out
	var by_index := {}
	for f in d.get_files():
		if not (f.begins_with("photo_") and f.ends_with(".png")): continue
		var num := f.trim_prefix("photo_").trim_suffix(".png")
		# A hand-renamed file (photo_readme.png) parses as 0 and would jump to the
		# front of the list; an unnumbered name is not a gallery shot.
		if not num.is_valid_int(): continue
		by_index[int(num)] = f
	var keys := by_index.keys()
	keys.sort()
	keys.reverse()

	for k in keys: out.append(DIR + "/" + String(by_index[k]))
	return out

# user://photos does not exist on a fresh profile until the first shot is
# taken: the open-folder action must know when it has nothing to open.
static func folder_exists() -> bool:
	return DirAccess.dir_exists_absolute(DIR)

static func delete_photo(path: String) -> bool:
	if not path.begins_with(DIR + "/"): return false
	return DirAccess.remove_absolute(path) == OK

# A decoded and downscaled snapshot: the menu never shows a full 4 MB texture.
static func thumbnail(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null: return null
	if img.is_compressed(): img.decompress()
	var k := minf(float(THUMB_W) / img.get_width(), float(THUMB_H) / img.get_height())
	if k < 1.0:
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)
