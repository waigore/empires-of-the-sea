class_name MapPlayFirstContact
extends RefCounted
## Human first contact with Tribes: a Tribe is contacted only by non-unknown
## tile visibility in its provinces; sea-reachable colonial intel alone does
## not count (wiki: diplomacy § first contact). Rival courts use
## MapPlayTribeContact against their own charts; this pass is the crown's
## app-layer discovery with a herald toast (REQ-P3-01).


static func sync(play: PlaySession) -> Array[int]:
	var contacted: Array[int] = []
	# The observer has no human court to open first contact for; rival courts
	# keep the relations seeded at setup (wiki: game-setup § Human/AI slots).
	if play.observer_mode:
		return contacted
	if play.diplomacy == null or play.world == null:
		return contacted
	for tribe: int in FactionCatalog.tribe_ids():
		if play.diplomacy.has_relation(play.player_faction, tribe):
			continue
		if not _sees_tribe(play, tribe):
			continue
		play.diplomacy.ensure_relation(play.player_faction, tribe, play.turn)
		play.diplomacy.touch(play.player_faction, tribe, "firstContact")
		contacted.append(tribe)
	if not contacted.is_empty():
		var names: PackedStringArray = []
		for tribe: int in contacted:
			names.append(FactionCatalog.name_of(tribe))
		play.hud.toast("First contact: %s" % ", ".join(names))
	return contacted


static func _sees_tribe(play: PlaySession, tribe: int) -> bool:
	for region_index: int in play.visibility_by_region.keys():
		var visibility: VisibilityModel = play.visibility_by_region[region_index]
		if visibility == null or visibility.model == null:
			continue
		for province: ProvinceState in visibility.model.provinces:
			if province.owner != tribe:
				continue
			if visibility.province_visibility(province.id) != VisibilityModel.Level.UNKNOWN:
				return true
	return false
