class_name MapPlayCivilianFollow
extends RefCounted
## The one press that follows the court's pick: the sheet's gold line can name
## ground the crew's own orders cannot press (an estate away from the crew, a
## road or a railroad ahead of it), so the line carries a door to the surface
## that can (wiki: civilian-build-planner § Deferred seed; playtest-learnings
## § next targets; DR-20261117-06, DR-20261117-10). Presentation only: the door
## frames the ground and opens the sheet; it orders nothing, reserves nothing and
## spends nothing (REQ-P2-03, REQ-P5-06).
##
## The press travels as the panel's own action string — `follow_pick:<region>:
## <x>,<y>:<action>` — so the sheet needs no second signal and the map keeps one
## path for every civilian intent (REQ-P3-02).

const PREFIX: String = "follow_pick:"


## True when a civilian action string is a follow press rather than an order.
static func is_follow(action: String) -> bool:
	return action.begins_with(PREFIX)


## The press a pick's door files: the chart it lies on, the ground it names and
## the order the door can press there.
static func press(region: int, tile: Vector2i, action: String) -> String:
	return "%s%d:%d,%d:%s" % [PREFIX, region, tile.x, tile.y, action]


## Frames the pick's ground and opens the surface that can press it. Returns
## false when the chart or the province cannot be reached, so the caller can
## say so rather than leave the press silent (REQ-P5-05).
static func follow(play: PlaySession, press_text: String) -> bool:
	if play == null or play.world == null:
		return false
	var parts: PackedStringArray = press_text.trim_prefix(PREFIX).split(":")
	if parts.size() != 3:
		return false
	var xy: PackedStringArray = parts[1].split(",")
	if xy.size() != 2:
		return false
	var region: int = int(parts[0])
	var tile := Vector2i(int(xy[0]), int(xy[1]))
	var action: String = parts[2]
	var model: MapModel = play.world.region(region)
	if model == null or tile.x < 0 or tile.y < 0:
		return false
	var province: int = model.province_at(tile.x, tile.y)
	if province < 0:
		return false
	# The province door is the map's own: it swaps the chart, frames the ground
	# and opens the dossier a tap would have opened (REQ-P1-05).
	if not MapPlayProvinces.focus(play, region, province):
		return false
	# An estate is raised from the estates ledger, read for the province the
	# pick names; a road or a railroad is pressed from the province dossier
	# already open, whose rail block names the tile the pick names.
	if action == "build_improvement" and play.improvements != null:
		play.improvements.open(province)
	return true
