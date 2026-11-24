class_name MapPlayPanelOrders
extends RefCounted
## Province-sheet order intents for the map screen (train, road, rail, muster,
## yard, build, raise). `MapPlayInput` keeps the public door; this home owns the
## sheet's press (REQ-P3-01, REQ-P3-02).


## File one province-panel action against the selected province.
static func apply(play: PlaySession, action: String) -> void:
	if play.campaign_over():
		return
	if play.turn_suspended:
		return
	# Auto holds the seat: the province sheet stays readable, but a press raises
	# no order (wiki: auto-mode § Read-only while it runs).
	if MapPlayAuto.blocks_orders(play):
		return
	if play.selected_province < 0:
		return
	var name: String = play.model.province_name(play.selected_province)
	# Any catalog type trains through the same intent; the rules gate each one.
	if action.begins_with("train_"):
		MapPlayTraining.train(play, action.trim_prefix("train_"))
		return
	if action.begins_with("road:"):
		MapPlayImprovements.build_road(play, _tile_of(action, "road:"))
		return
	if action.begins_with("rail:"):
		MapPlayImprovements.build_rail(play, _tile_of(action, "rail:"))
		return
	match action:
		"recruit":
			MapPlayArmies.open_muster(play)
		"shipyard":
			MapPlayFleetYard.open(play)
		"build":
			play.improvements.open(play.selected_province)
		"upgrade_town":
			MapPlayImprovements.upgrade_town(play, play.selected_province)
		"raise_wall":
			MapPlayImprovements.raise(
				play, play.region_index, play.selected_province,
				MapPlayImprovements.RAISE_WALL
			)
		"raise_ward":
			MapPlayImprovements.raise(
				play, play.region_index, play.selected_province,
				MapPlayImprovements.RAISE_WARD
			)
		_:
			play.hud.toast("Order noted in %s" % name)


## "<prefix><x>,<y>": the tile a dossier control names — the estate the Build
## road control roads, the road tile the rail block rails. (-1,-1) when the
## intent is malformed, so the rules refuse it plainly.
static func _tile_of(action: String, prefix: String) -> Vector2i:
	var parts: PackedStringArray = action.trim_prefix(prefix).split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
