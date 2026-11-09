class_name ChromeIcons
extends RefCounted
## The shell's antique medallion set (assets/art/icons), generated with the
## gameforge image pipeline (fal.ai), keyed to transparency and downsampled to
## 128 px sources. Buttons take the PNG through their native `icon` slot, so
## caption and pictogram share one layout and one touch target (REQ-P1-02,
## REQ-P1-05).

const ICON_DIR: String = "res://assets/art/icons/"
const DEFAULT_SIZE: int = 22
const SEPARATION: int = 7

static var _cache: Dictionary = {}


static func texture(icon_name: String) -> Texture2D:
	var path: String = ICON_DIR + icon_name + ".png"
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Sets `button`'s pictogram without touching its caption: existing callers keep
## setting `text`, and the icon scales from the 48 px source to `size` points.
static func apply(button: Button, icon_name: String, size: int = DEFAULT_SIZE) -> void:
	button.icon = texture(icon_name)
	button.add_theme_constant_override("icon_max_width", size)
	button.add_theme_constant_override("h_separation", SEPARATION)
