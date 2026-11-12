class_name MapPlayBeachhead
extends RefCounted
## The Beachhead mission on the fleet dossier: eligible hostile coasts, the
## landing note, and the order that marks a site (wiki: ships-and-naval
## § Missions and Movement). Rules stay in NavalTransport; this only drives the
## PlaySession views (REQ-P3-02, REQ-P3-03).


## The court's invasion query: a declared enemy's coast, or a Tribe's, which
## needs no declaration (wiki: factions § Tribe).
static func hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.invadable(play.diplomacy, a, b)


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


## Dossier line for a pending or ready landing site. The line follows the same
## gate the landing uses: a marker whose coast is no longer a hostile shore
## promises nothing (wiki: ships-and-naval § Missions and Movement).
static func note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction or not fleet.has_beachhead():
		return ""
	var place: String = play.model.province_name(fleet.beachhead_province)
	if not NavalTransport.beachhead_target_valid(play.model, fleet, hostile(play)):
		return "The beachhead at %s has lapsed — that shore is no longer hostile." % place
	if NavalTransport.beachhead_ready(fleet, play.turn):
		if fleet.embarked_army < 0:
			return "Beachhead at %s — ready, but no troops are aboard." % place
		return "Beachhead at %s — land the troops this turn." % place
	if fleet.beachhead_turn == play.turn:
		return "Beachhead at %s — the landing opens next turn." % place
	return "The beachhead at %s has lapsed." % place


## The dossier's hint line under the station note: what the site costs, never a
## second copy of the note itself (the mission block already names the site).
static func hint(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction or not fleet.has_beachhead():
		return ""
	if not NavalTransport.beachhead_target_valid(play.model, fleet, hostile(play)):
		return ""
	if NavalTransport.beachhead_ready(fleet, play.turn):
		if fleet.embarked_army < 0:
			return "No troops are aboard — the site lapses at the end of this turn."
		return "Landing spends the site; an unused site lapses at the end of this turn."
	return "Sailing, docking or losing the hulls drops the site before it opens."


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