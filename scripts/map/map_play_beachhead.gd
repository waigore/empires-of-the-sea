class_name MapPlayBeachhead
extends RefCounted
## The Beachhead mission on the fleet dossier: eligible hostile coasts, the
## landing note, and the order that marks a site (wiki: ships-and-naval
## § Missions and Movement). Rules stay in NavalTransport; this only drives the
## PlaySession views (REQ-P3-02, REQ-P3-03).


## The court's war query, so only a declared enemy's coast can be marked.
static func hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(play.diplomacy, a, b)


## One row per hostile coast bordering the squadron's sea zone.
static func rows(play: PlaySession, fleet: FleetState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if fleet == null or fleet.owner != play.player_faction or fleet.moved:
		return rows
	for province_id: int in NavalTransport.hostile_coasts(play.model, fleet, hostile(play)):
		rows.append({
			"province": province_id,
			"name": play.model.province_name(province_id),
		})
	return rows


## Dossier line for a pending or ready landing site.
static func note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction or not fleet.has_beachhead():
		return ""
	var place: String = play.model.province_name(fleet.beachhead_province)
	if NavalTransport.beachhead_ready(fleet, play.turn):
		if fleet.embarked_army < 0:
			return "Beachhead at %s — ready, but no troops are aboard." % place
		return "Beachhead at %s — land the troops this turn." % place
	if fleet.beachhead_turn == play.turn:
		return "Beachhead at %s — the landing opens next turn." % place
	return "The beachhead at %s has lapsed." % place


## Marks a beachhead from the dossier's coast list.
static func establish(play: PlaySession, fleet: FleetState, province_id: int) -> void:
	var result: Dictionary = NavalTransport.establish_beachhead(
		play.model, fleet, province_id, play.turn, hostile(play)
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "That coast cannot be marked.")))
		return
	play.hud.toast(
		"Beachhead marked at %s — the troops may land next turn."
		% String(result.get("name", "the coast"))
	)
	refresh(play, fleet)


## Rebuilds the dossier without deselecting the squadron.
static func refresh(play: PlaySession, fleet: FleetState) -> void:
	MapPlayFleets.show_dossier(play, fleet)
	MapPlayFleets.refresh_options(play, fleet)