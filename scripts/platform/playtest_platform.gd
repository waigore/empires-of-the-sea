class_name PlaytestPlatform
extends RefCounted
## Platform answers the desktop capture mode needs (issue #1393). Kept under
## `scripts/platform/` so tooling never names an OS directly (RUB-P3-05).
## The feature probes themselves live in PlatformHost; this file keeps only the
## answers a capture report needs.

## Mobile is out of scope for capture v1.
static func is_desktop() -> bool:
	return not PlatformHost.is_mobile()


## Human-readable OS line for a report: `Linux 24.04`.
static func label() -> String:
	return PlatformHost.system_label()
