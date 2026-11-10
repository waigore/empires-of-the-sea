class_name BattleReport
extends RefCounted
## Formats a NavalCombat record as the one-line despatch the HUD toasts. Pure
## string work, so the screen stays a controller and the wording is unit-tested
## (REQ-P3-03).


static func describe(battle: Dictionary, zone_name: String, faction_names: Array) -> String:
	var attacker: String = _faction(faction_names, int(battle.get("attacker", 0)))
	var defender: String = _faction(faction_names, int(battle.get("defender", 0)))
	var outcome: int = int(battle.get("outcome", NavalCombat.Outcome.STALEMATE))
	var retreat: Dictionary = battle.get("retreat", {})
	if bool(retreat.get("success", false)):
		var beaten: int = int(retreat.get("beaten", int(battle.get("defender", 0))))
		var haven: String = _faction(faction_names, beaten)
		var holder: String = defender if beaten == int(battle.get("attacker", 0)) else attacker
		return "%s withdraws from the %s — %s holds the zone" % [haven, zone_name, holder]
	match outcome:
		NavalCombat.Outcome.SIDE1_VICTORY:
			var sunk: int = (battle.get("defender_lost", []) as Array).size()
			return "%s holds the %s — %s loses %d ships" % [attacker, zone_name, defender, sunk]
		NavalCombat.Outcome.SIDE2_VICTORY:
			var lost: int = (battle.get("attacker_lost", []) as Array).size()
			return "%s repels %s in the %s — %d ships lost" % [defender, attacker, zone_name, lost]
	return "%s and %s trade broadsides in the %s and withdraw" % [attacker, defender, zone_name]


static func _faction(faction_names: Array, owner: int) -> String:
	if owner < 0 or owner >= faction_names.size():
		return "An unknown flag"
	return String(faction_names[owner])


## Formats a raid for the HUD: the cargo the crown loses, or the prize its own
## station takes off rival trade. Every line ends on the rule that matters — a
## raid takes cargo and never a hull (wiki: ships-and-naval § Trade and Transport
## Interception; DR-20261110-13).
static func describe_raid(
	raid: Dictionary, zone_name: String, faction_names: Array, viewer: int
) -> String:
	var place: String = zone_name if not zone_name.is_empty() else "open water"
	var cargo: String = cargo_of(raid.get("losses", {}) as Dictionary)
	var raider: String = _faction(faction_names, int(raid.get("raider", -1)))
	if int(raid.get("raider", -1)) == viewer:
		return "Your station takes %s off the %s as prize — no hull lost" % [cargo, place]
	return "%s seize %s off the %s — no hull lost" % [raider, cargo, place]


## "3 grain", or "5 cargo (3 grain, 2 timber)" when a raid takes several.
## Public so the Gazette's prize prose and the raid toast phrase cargo alike.
static func cargo_of(losses: Dictionary) -> String:
	var ids: Array[String] = []
	var total: int = 0
	for raw_id: Variant in losses.keys():
		var quantity: int = int(losses[raw_id])
		if quantity <= 0:
			continue
		ids.append(String(raw_id))
		total += quantity
	if ids.is_empty():
		return "no cargo"
	ids.sort()
	if ids.size() == 1:
		return "%d %s" % [total, CommodityCatalog.label(ids[0]).to_lower()]
	var parts: PackedStringArray = PackedStringArray()
	for id: String in ids:
		parts.append(
			"%d %s" % [int(losses[id]), CommodityCatalog.label(id).to_lower()]
		)
	return "%d cargo (%s)" % [total, ", ".join(parts)]


## Land-battle toast tail: chevrons won and regiments mauled, so a battle's
## depth is read without opening the plate (REQ-P5-05). Empty when neither.
static func regiment_note(battle: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var gained: int = int(battle.get("attacker_chevrons", 0)) \
		+ int(battle.get("defender_chevrons", 0))
	if gained > 0:
		parts.append("%d chevron%s won" % [gained, "" if gained == 1 else "s"])
	var mauled: int = int(battle.get("attacker_mauled", 0)) \
		+ int(battle.get("defender_mauled", 0))
	if mauled > 0:
		parts.append("%d regiment%s mauled" % [mauled, "" if mauled == 1 else "s"])
	if parts.is_empty():
		return ""
	return " — " + ", ".join(parts)


## Formats an ArmyCombat record for the land-battle toast, with the condition
## tail (chevrons won, men mauled) and an auto-resolved siege's battery tail.
static func describe_land(
	battle: Dictionary, province_name: String, faction_names: Array
) -> String:
	return _land_core(battle, province_name, faction_names) \
		+ regiment_note(battle) + siege_note(battle)


## An auto-resolved siege's tail: how many emplaced guns the besieging train
## silenced and the fort level they left behind. Empty when the battery was not
## touched, so every other despatch reads as before (REQ-P5-05,
## DR-20261110-22).
static func siege_note(battle: Dictionary) -> String:
	var siege: Dictionary = battle.get("siege", {}) as Dictionary
	var lost: int = int(siege.get("guns_lost", 0))
	if lost <= 0:
		return ""
	var start: int = int(siege.get("guns_start", lost))
	var text: String = " — %d of %d emplaced gun%s silenced" % [
		lost, start, "" if start == 1 else "s"
	]
	if not bool(siege.get("fort_downgraded", false)):
		return text
	var after: int = int(siege.get("fort_after", 0))
	return text + ", and the %s fort falls to %s" % [
		FortRules.level_name(int(siege.get("fort_before", 0))),
		FortRules.level_name(after) if after > 0 else "open field",
	]


## The medallion an auto-resolved siege earns: a silenced battery. Empty for
## every other despatch so a plain toast keeps its plain plate.
static func icon_of(battle: Dictionary) -> String:
	return "silenced_gun" if not siege_note(battle).is_empty() else ""


static func _land_core(
	battle: Dictionary, province_name: String, faction_names: Array
) -> String:
	var attacker: String = _faction(faction_names, int(battle.get("attacker", 0)))
	var defender: String = _faction(faction_names, int(battle.get("defender", 0)))
	var outcome: int = int(battle.get("outcome", ArmyCombat.Outcome.STALEMATE))
	match outcome:
		ArmyCombat.Outcome.ATTACKER_VICTORY:
			var broken: int = (battle.get("defender_lost", []) as Array).size()
			return "%s takes %s — %s loses %d regiments" % [
				attacker, province_name, defender, broken
			]
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			var spent: int = (battle.get("attacker_lost", []) as Array).size()
			return "%s holds %s — %s loses %d regiments" % [
				defender, province_name, attacker, spent
			]
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION:
			var garrison: int = int(battle.get("garrison", 0))
			if garrison > 0:
				return "%s and %s destroy each other at %s — a %s garrison reforms" % [
					attacker,
					defender,
					province_name,
					RegimentCatalog.display_name(String(battle.get("recovered_type", ""))),
				]
			return "%s and %s destroy each other at %s — the province stands empty" % [
				attacker, defender, province_name
			]
		ArmyCombat.Outcome.CAPTURE:
			return "%s occupies %s unopposed" % [attacker, province_name]
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			var spent: int = (battle.get("attacker_lost", []) as Array).size()
			return "%s holds the field at %s — %d regiments lost" % [
				attacker, province_name, spent
			]
	return "%s and %s stand off at %s" % [attacker, defender, province_name]
