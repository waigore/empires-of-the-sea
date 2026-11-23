class_name PlaytestPlatform
extends RefCounted
## Platform answers the desktop capture mode needs (issue #1393). Kept under
## `scripts/platform/` so tooling never names an OS directly (RUB-P3-05).

const MOBILE_FEATURE: String = "mobile"


## Mobile is out of scope for capture v1.
static func is_desktop() -> bool:
	return not OS.has_feature(MOBILE_FEATURE)


## A drawable frame exists: headless CI has none, so a grab answers at once.
static func has_display() -> bool:
	return DisplayServer.get_name() != "headless"


## Human-readable OS line for a report: `Linux 24.04`.
static func label() -> String:
	return "%s %s" % [OS.get_name(), OS.get_version()]
