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


## Main-menu caption. Exported builds append short SHA + UTC `yyyyMMdd-HHmm`
## when `BuildIdentity` was baked at export time; editor/dev stays version-only.
static func format_menu_caption(version: String, sha: String, utc: String) -> String:
	if sha.is_empty() or utc.is_empty():
		return "version %s" % version
	return "version %s · %s · %s" % [version, sha, utc]


static func menu_caption() -> String:
	return format_menu_caption(as_string(), BuildIdentity.GIT_SHA, BuildIdentity.COMMIT_UTC)
