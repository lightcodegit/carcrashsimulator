extends SceneTree
# Photo gallery logic on real files: newest-first order, deletion and thumbnails.
# Run: godot --headless --path . --script res://tests/d_gallery.gd
var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _write_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

func _make_shot(idx: int) -> void:
	var img := Image.create(160, 90, false, Image.FORMAT_RGB8)
	img.fill(Color(idx % 2, 0.5, 0.3))
	img.save_png("user://photos/photo_%04d.png" % idx)

func _initialize() -> void:
	DirAccess.remove_absolute("user://photos")
	# save_png does not create the parent dir — same trap the photo mode hit
	var d := DirAccess.open("user://")
	d.make_dir("photos")
	for idx in [3, 1, 12, 2]: _make_shot(idx)

	var list := PhotoGallery.list_photos()
	check(list.size() == 4, "all four shots are listed (%d)" % list.size())
	check(list[0].ends_with("photo_0012.png"), "the newest shot comes first (%s)" % list[0].get_file())
	check(list[3].ends_with("photo_0001.png"), "the oldest comes last (%s)" % list[3].get_file())

	# A foreign file in the folder is not a gallery shot and does not break the
	# numbering or the order.
	# Files renamed by hand parse as index 0 and would jump to the front of the
	# list; the gallery recognizes only well-formed photo_NNNN.png names.
	_write_file("user://photos/photo_readme.png")
	_write_file("user://photos/photo_.png")
	list = PhotoGallery.list_photos()
	check(list.size() == 4, "a stray file is not listed (%d)" % list.size())
	check(list[0].ends_with("photo_0012.png"), "a hand-renamed file does not jump to the front (%s)" % list[0].get_file())

	# Thumbnail: decoded, downscaled into the gallery box, and never null.
	var tex := PhotoGallery.thumbnail(list[0])
	check(tex != null, "a thumbnail is built")
	if tex != null:
		check(tex.get_width() <= PhotoGallery.THUMB_W and tex.get_height() <= PhotoGallery.THUMB_H,
			"the thumbnail fits the gallery box (%dx%d)" % [tex.get_width(), tex.get_height()])
	check(PhotoGallery.thumbnail("user://photos/nope.png") == null, "a missing file gives no thumbnail")

	check(not PhotoGallery.delete_photo("user://no-such/file.png"), "deleting outside the folder is refused")
	check(PhotoGallery.delete_photo(list[0]), "deleting a shot works")
	list = PhotoGallery.list_photos()
	check(list.size() == 3 and not list[0].ends_with("photo_0012.png"),
		"the deleted shot left the list (%d)" % list.size())
	check(not FileAccess.file_exists("user://photos/photo_0012.png"), "the file is really gone")

	DirAccess.remove_absolute("user://photos")
	if fails == 0: print("ALL PASS")
	else: print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
