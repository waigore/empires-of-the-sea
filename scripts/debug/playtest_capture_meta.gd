class_name PlaytestCaptureMeta
extends RefCounted
## Session parameters every playtest capture carries (issue #1393): map seed,
## turn/year, crown, build/commit and platform. Pure — reads PlaySession and
## never writes rules state (REQ-P3-03).

const UNKNOWN: String = "unknown"


## One metadata bag for an artifact or the report header. A null session still
## answers a complete bag, so a capture taken before the chart mounts never
## writes a half-shaped report.
static func build(play: PlaySession, stamp: String = "") -> Dictionary:
	var meta: Dictionary = {
		"timestamp": stamp if not stamp.is_empty() else stamp_now(),
		"seed": 0,
		"turn": 0,
		"year": 0,
		"crown": UNKNOWN,
		"crown_id": -1,
		"region": UNKNOWN,
		"build": GameVersion.as_string(),
		"commit": commit_label(),
		"platform": platform_label(),
	}
	if play == null:
		return meta
	meta["seed"] = play.map_seed
	meta["turn"] = play.turn
	meta["year"] = TurnTime.year_for_turn(play.turn)
	meta["crown_id"] = play.player_faction
	meta["crown"] = crown_name(play)
	meta["region"] = region_label(play.region_index)
	return meta


## The crown the player holds; the full-AI observer holds no seat.
static func crown_name(play: PlaySession) -> String:
	if play == null:
		return UNKNOWN
	if play.observer_mode:
		return "Observer"
	return FactionCatalog.name_of(play.player_faction)


static func region_label(index: int) -> String:
	if index < 0 or index >= FactionCatalog.REGION_LABELS.size():
		return UNKNOWN
	return FactionCatalog.REGION_LABELS[index]


## Exported builds bake a short SHA; editor/dev runs say so plainly.
static func commit_label() -> String:
	return BuildIdentity.GIT_SHA if BuildIdentity.is_baked() else "dev"


static func platform_label() -> String:
	return PlaytestPlatform.label()


## UTC, so a report filed from any timezone names the same moment.
static func stamp_now() -> String:
	return Time.get_datetime_string_from_system(true)


## Filesystem-safe session folder: `session-2026-11-23-051317-seed1500`.
static func session_dir_name(seed: int, stamp: String) -> String:
	var clean: String = stamp.replace(":", "").replace("T", "-").replace(" ", "-")
	return "session-%s-seed%d" % [clean, seed]
