# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
extends SceneTree
## Renders the Asset Library icon, docs/asset-library/icon.svg, to icon.png at 256 x 256 pixels.
## The Asset Library needs a direct link to a square PNG or JPEG image, so the PNG is committed
## next to its SVG source. With [code]--check[/code] it writes nothing and fails unless the
## committed PNG has the same pixels as a fresh render.
##
##   godot --headless --path . -s res://tools/asset_library/render_icon.gd [-- --check]

const SOURCE := "res://docs/asset-library/icon.svg"
const TARGET := "res://docs/asset-library/icon.png"
const SIZE := 256


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args().has("--check")))


func _run(check: bool) -> int:
	var svg := FileAccess.get_file_as_string(SOURCE)
	if svg.is_empty():
		printerr("%s is missing or empty" % SOURCE)
		return 1
	var image := Image.new()
	if image.load_svg_from_string(svg, float(SIZE) / 128.0) != OK:
		printerr("%s does not load as an SVG" % SOURCE)
		return 1
	if image.get_width() != SIZE or image.get_height() != SIZE:
		printerr("%s renders at %dx%d, not %dx%d" % [SOURCE, image.get_width(), image.get_height(), SIZE, SIZE])
		return 1
	image.convert(Image.FORMAT_RGBA8)
	var path := ProjectSettings.globalize_path(TARGET)
	if not check:
		if image.save_png(path) != OK:
			printerr("could not write %s" % TARGET)
			return 1
		print("Wrote %s (%dx%d) from %s." % [TARGET, SIZE, SIZE, SOURCE])
		return 0
	var committed := Image.load_from_file(path)
	if committed == null:
		printerr("%s is missing: run this script without --check" % TARGET)
		return 1
	committed.convert(Image.FORMAT_RGBA8)
	if committed.get_size() != image.get_size() or committed.get_data() != image.get_data():
		printerr("%s does not match %s: run this script without --check and commit the PNG" % [TARGET, SOURCE])
		return 1
	print("%s matches %s." % [TARGET, SOURCE])
	return 0
