class_name GameVersion
extends RefCounted
## Semantic app version helpers used by UI and CI smoke tests.

const MAJOR: int = 0
const MINOR: int = 1
const PATCH: int = 0


static func as_string() -> String:
	return "%d.%d.%d" % [MAJOR, MINOR, PATCH]


static func is_compatible_with(required_major: int) -> bool:
	return MAJOR == required_major
