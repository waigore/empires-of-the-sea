class_name MapPlayStationNotes
extends RefCounted
## The fleet dossier's two station prices: what a patrol or blockade standing at
## sea would **catch** this turn and what it would **take**, each read from the
## same rules the turn rolls, so the sheet promises no number the pass would not
## make (wiki: ships-and-naval § Naval Interception Probability, § Trade and
## Transport Interception; DR-20261120-01, DR-20261120-02; REQ-P2-03, REQ-P5-03).
##
## Both lines read [NavalStation] for the water, so one never prices a squadron
## the other leaves out.

const PRIZE_PREFIX: String = "Prize: "
const CATCH_PREFIX: String = "Interception: "


## What a standing station takes this turn: the chance its raid rolls, the cargo
## it would skim and the merchant hull it could send down — read before the
## player commits the move (DR-20261111-17, DR-20261120-01). **A patrol raids as
## a blockade does**, at the patrol factor, and the pass rolls the squadron with
## every other station the crown holds in that water: the price is the group's,
## against a coast the crown is at war with.
static func prize(play: PlaySession, fleet: FleetState) -> String:
	if not _prices(play, fleet) or play.economy == null or play.economy.market == null:
		return ""
	var hostile: Callable = MapPlayRaids.hostile(play)
	var group: Array = NavalStation.group_of(play.model, _roster(play), fleet, hostile)
	var mission: int = FleetMissions.station_mission(play.model, group, hostile)
	var best: Dictionary = best_raid(play, fleet, group, mission)
	var coasts: Array[int] = coasts_reached(play, fleet)
	var afloat: bool = false
	for province_id: int in coasts:
		if not play.economy.market.imports_for(
			play.model.province_owner(province_id)
		).is_empty():
			afloat = true
			break
	if not afloat:
		return _no_prize_words(fleet)
	if best.is_empty():
		return _no_prize_words(fleet, true)
	var chance: int = int(round(float(best.get("chance", 0.0)) * 100.0))
	var take: String = PRIZE_PREFIX + "%d%% to take ~%d cargo" % [
		chance, int(best.get("expected", 0))
	]
	# A patrol's station note names no coast, so its price names the one it works;
	# a blockade's note already reads "Blockading Coro".
	if fleet.mission == FleetState.Mission.PATROL:
		take += " off %s" % String(best.get("coast", "the coast"))
	var at_risk: String = String(best.get("hull_at_risk", ""))
	if at_risk.is_empty():
		return take + " — no merchant hull at risk."
	var hull_chance: int = int(round(float(best.get("hull_chance", 0.0)) * 100.0))
	return "%s; a hit sinks %s on %d%%." % [
		take, with_article(ShipStats.display_name(at_risk)), hull_chance
	]


## The richest coast the station's group would raid this turn: the at-war coast
## the odds favour, each read through the rules' own `NavalRaid.preview`, so the
## dossier and a reader of the same pass ask the same question. `{}` when no
## laden home fleet stands on any coast the water reaches.
static func best_raid(
	play: PlaySession, fleet: FleetState, group: Array, mission: int
) -> Dictionary:
	var best: Dictionary = {}
	for province_id: int in coasts_reached(play, fleet):
		var owner: int = play.model.province_owner(province_id)
		var imports: Dictionary = play.economy.market.imports_for(owner)
		if imports.is_empty():
			continue
		var home: FleetState = MapPlayRaids.home_fleet(play, owner)
		if home == null:
			continue
		var odds: Dictionary = NavalRaid.preview(
			group, home, imports, mission, play.has_tech
		)
		if best.is_empty() or float(odds.get("chance", 0.0)) > float(best.get("chance", 0.0)):
			best = odds
			best["coast"] = play.model.province_name(province_id)
	return best


## What the station catches: the chance a patrol, or a blockade that still
## stands, intercepts a hostile squadron that is still in this water when the
## turn closes — the published formula read through the rules' own
## `NavalInterception.chance`, over the squadrons that hold the station (the same
## list the combat pass rolls). A rival the crown has not read is left out and
## named, so the sheet never promises a number the fog withholds
## (§ Sighted strength).
static func catch(play: PlaySession, fleet: FleetState) -> String:
	if not _prices(play, fleet):
		return ""
	var hostile: Callable = MapPlayRaids.hostile(play)
	var roster: Array = _roster(play)
	var holders: Array = NavalStation.group_of(play.model, roster, fleet, hostile)
	var mission: int = FleetMissions.station_mission(play.model, holders, hostile)
	var targets: Array = []
	var unread: bool = false
	for other: FleetState in roster:
		if other == null or other.owner == fleet.owner:
			continue
		if not other.is_at_sea() or other.sea_zone != fleet.sea_zone:
			continue
		if not other.is_afloat() or not Hostility.between(hostile, fleet.owner, other.owner):
			continue
		if not MapPlayFleetIntel.strength_read(play, other):
			unread = true
			continue
		targets.append(other)
	var read: Dictionary = NavalInterception.preview(
		holders, targets, mission, play.has_tech, unread
	)
	if read.is_empty():
		return ""
	if bool(read.get("unread", false)):
		return CATCH_PREFIX + "the odds wait on a squadron the fog has not read."
	var hulls: int = int(read.get("hulls", 0))
	if hulls <= 0:
		return ""
	var chance: int = int(round(float(read.get("chance", 0.0)) * 100.0))
	return CATCH_PREFIX + "%d%% to catch %d hull%s if they stay." % [
		chance, hulls, "" if hulls == 1 else "s",
	]


## One hull's name with its indefinite article: `an Indiaman`, `a Galleon`. The
## catalogue's only vowel-initial hull is the Indiaman, but the reading is the
## word's own so a later hull cannot inherit the wrong one.
static func with_article(name: String) -> String:
	var first: String = name.substr(0, 1).to_lower()
	var vowel: bool = (
		first == "a" or first == "e" or first == "i" or first == "o" or first == "u"
	)
	return "%s %s" % ["an" if vowel else "a", name]


## The Privateering Companies bonus, phrased for the dossier (wiki:
## ships-and-naval § Trade and Transport Interception).
static func privateers(play: PlaySession) -> String:
	if not play.has_tech(play.player_faction, NavalInterception.PRIVATEERING_TECH):
		return ""
	var percent: int = int(round((NavalInterception.PRIVATEERING_BONUS - 1.0) * 100.0))
	return "Privateers: interception and raids +%d%%." % percent


## The at-war coasts this station's water reaches: the blockaded coast first, so
## a blockade reads its own shore as it always did, then the rest by province id.
static func coasts_reached(play: PlaySession, fleet: FleetState) -> Array[int]:
	var coasts: Array[int] = []
	if fleet.mission == FleetState.Mission.BLOCKADE and fleet.blockade_province >= 0:
		coasts.append(fleet.blockade_province)
	var found: Array[int] = []
	for province_id: int in NavalMovement.provinces_by_zone(play.model, fleet.sea_zone):
		if coasts.has(province_id):
			continue
		var owner: int = play.model.province_owner(province_id)
		if owner < 0 or owner == fleet.owner:
			continue
		if not Hostility.between(MapPlayRaids.hostile(play), fleet.owner, owner):
			continue
		found.append(province_id)
	found.sort()
	coasts.append_array(found)
	return coasts


## True when the dossier has a station to price: the crown's own squadron, at
## sea, on a chart, with orders that work the station.
static func _prices(play: PlaySession, fleet: FleetState) -> bool:
	if fleet == null or fleet.owner != play.player_faction:
		return false
	if play.model == null or not fleet.is_at_sea():
		return false
	return NavalStation.works(play.model, fleet, MapPlayRaids.hostile(play))


## The empty reading: a coast with no cargo afloat this turn, or a coast whose
## merchant hulls are at sea. A patrol works the whole water, so it says so.
static func _no_prize_words(fleet: FleetState, hulls_away: bool = false) -> String:
	if fleet.mission != FleetState.Mission.PATROL:
		if hulls_away:
			return PRIZE_PREFIX + "the coast's merchant hulls are at sea — nothing to take."
		return PRIZE_PREFIX + "no cargo afloat off this coast this turn."
	if hulls_away:
		return PRIZE_PREFIX + "the merchant hulls off these coasts are at sea — nothing to take."
	return PRIZE_PREFIX + "no cargo afloat off these coasts this turn."


## The chart's roster, which is the group the pass reads: the dossier is open on
## a region and every station the crown holds in the water stands on that chart.
static func _roster(play: PlaySession) -> Array:
	if play.ship_layer == null:
		return []
	return play.ship_layer.fleets
