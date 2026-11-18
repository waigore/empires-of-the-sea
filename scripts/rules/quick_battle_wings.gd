class_name QuickBattleWings
extends RefCounted
## The three wings a line is fought in when it stands in the open (wiki:
## quick-battle § Wings and collapse; DR-20261117-08).
##
## A line is not one mass. The horse holds the two flanks and the foot and guns
## hold the centre, so an army with cavalry fights on three wings and one
## without fights on a centre alone. Every blow is delivered into one wing:
## fire goes into the fullest part of the enemy line, a charge into its
## thinnest. A wing that loses its last regiment **breaks**; the flank beside a
## broken wing is turned, and the blow that lands there is heavier.
##
## A wall has no wings: a garrison stands on its parapet, and the wall/behind
## split of [SiegeLanes] is what shelters it. So the besieging line has wings
## and the garrison does not.
##
## Pure data and maths: no nodes (REQ-P3-01, REQ-P3-03).

## Left to right, in the order the plate prints them.
const WINGS: Array[String] = ["left", "center", "right"]
## Prose names for the despatch: "into the left", "the centre breaks".
const LABELS: Dictionary = {"left": "left", "center": "centre", "right": "right"}
## A blow that lands on a wing whose neighbour has broken takes the flank.
const TURNED_SCALE: float = 1.2
## Both neighbours down: the line is taken from three sides.
const ENCIRCLED_SCALE: float = 1.35
## How an action picks its wing: the line's fire into the mass, a charge into
## the thinnest part of it. An action that strikes nobody names no wing.
const AIMED: Dictionary = {"volley": "fullest", "assault": "thinnest", "sortie": "thinnest"}


## Deals one side's deployed line into its wings: the horse alternates between
## the flanks, strongest first, and everything else — foot, guns — holds the
## centre. A side with no horse has open flanks, and no wing there to lose.
static func deploy(side: Array[ArmyState], limit: int) -> Dictionary:
	var wings: Dictionary = {
		"left": [] as Array[String],
		"center": [] as Array[String],
		"right": [] as Array[String],
	}
	var horse: Array[String] = []
	for entry: Dictionary in ArmyModifiers.deployed(side, limit):
		var army: ArmyState = entry["army"]
		var regiment_id: String = String(entry["id"])
		if RegimentCatalog.is_cavalry(army.type_of(regiment_id)):
			horse.append(regiment_id)
		else:
			(wings["center"] as Array[String]).append(regiment_id)
	for index in horse.size():
		var wing: String = "left" if index % 2 == 0 else "right"
		(wings[wing] as Array[String]).append(horse[index])
	return wings


## Regiments standing on each wing, in wing order.
static func counts(wings: Dictionary) -> Dictionary:
	var held: Dictionary = {}
	for wing: String in WINGS:
		held[wing] = (wings.get(wing, []) as Array).size()
	return held


## Which wing a blow is delivered into. Fire falls on the fullest wing; a
## charge falls on the thinnest. "" when the action strikes no wing at all, or
## when the enemy line holds nobody.
static func target(held: Dictionary, action: String) -> String:
	var mode: String = String(AIMED.get(action, ""))
	if mode.is_empty():
		return ""
	var chosen: String = ""
	var best: int = -1
	for wing: String in WINGS:
		var count: int = int(held.get(wing, 0))
		if count <= 0:
			continue
		if chosen.is_empty():
			chosen = wing
			best = count
			continue
		if mode == "fullest" and count > best:
			chosen = wing
			best = count
		elif mode == "thinnest" and count < best:
			chosen = wing
			best = count
	return chosen


static func neighbours(wing: String) -> Array[String]:
	var beside: Array[String] = []
	match wing:
		"left", "right":
			beside.append("center")
		_:
			beside.append_array(["left", "right"])
	return beside


## The regiments standing on one wing: the ids a blow into it may break, and the
## only ones it may. Empty for a line with no wings (behind a wall, or a record
## made before wings existed).
static func ids(wings: Dictionary, wing: String) -> Array[String]:
	var held: Array[String] = []
	if wing.is_empty() or wings.is_empty():
		return held
	for regiment_id: String in wings.get(wing, []) as Array:
		held.append(regiment_id)
	return held


## How much heavier a blow is for a turned flank: one broken neighbour 1.2, or
## both 1.35. An unturned wing fights at 1.0.
static func turned_scale(wing: String, broken: Array) -> float:
	if wing.is_empty() or broken.is_empty():
		return 1.0
	var taken: int = 0
	for beside: String in neighbours(wing):
		if broken.has(beside):
			taken += 1
	if taken <= 0:
		return 1.0
	return ENCIRCLED_SCALE if taken >= 2 else TURNED_SCALE


## Drops the fallen from every wing of one side and names the wings that broke
## on this pass. A wing breaks once and stays named once, so a collapse is
## reported exactly when it happens.
static func fell(state: Dictionary, key: String) -> Array[String]:
	var broken_now: Array[String] = []
	var side: Dictionary = state.get(key, {}) as Dictionary
	if side.is_empty() or not side.has("wings"):
		return broken_now
	var wings: Dictionary = side["wings"] as Dictionary
	if wings.is_empty():
		return broken_now
	var standing: Dictionary = standing_ids(side)
	var already: Array = side.get("broken", []) as Array
	for wing: String in WINGS:
		var held: Array = wings.get(wing, []) as Array
		var left: Array[String] = []
		for regiment_id: String in held:
			if standing.has(regiment_id):
				left.append(regiment_id)
		wings[wing] = left
		if left.is_empty() and not held.is_empty() and not already.has(wing):
			already.append(wing)
			broken_now.append(wing)
	return broken_now


## The wings one blow broke, each on the line it belonged to: the enemy's under
## `wing_broken`, the actor's own under `own_broken`, since a sallying charge can
## empty a wing of either (wiki: quick-battle § Wings and collapse). A field is
## left out while nothing on that line broke.
static func marks(state: Dictionary, key: String, enemy_key: String) -> Dictionary:
	var marks: Dictionary = {}
	var broke: Array[String] = fell(state, enemy_key)
	if not broke.is_empty():
		marks["wing_broken"] = broke
	var own: Array[String] = fell(state, key)
	if not own.is_empty():
		marks["own_broken"] = own
	return marks


## Every regiment id still standing on one side, for the prune above.
static func standing_ids(side: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	for army: ArmyState in side.get("side", []) as Array:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			ids[regiment_id] = true
	return ids


## Regiments standing on each side's wings, in the order a record prints them.
static func counts_of(state: Dictionary) -> Dictionary:
	var held: Dictionary = {}
	for key: String in ["attacker", "defender"]:
		held[key] = counts((state.get(key, {}) as Dictionary).get("wings", {}) as Dictionary)
	return held


## What a battle (or one round of it) writes about the wings: the counts each
## line holds, and the wings the enemy has broken. `opened` carries the deal the
## battle began with, and is left out of a round's record.
static func record(state: Dictionary, opened: Dictionary = {}) -> Dictionary:
	var held: Dictionary = {
		"wings": counts_of(state),
		"wings_broken": {
			"attacker": (state["attacker"]["broken"] as Array).duplicate(),
			"defender": (state["defender"]["broken"] as Array).duplicate(),
		},
	}
	if not opened.is_empty():
		held["wings_open"] = opened
	return held


## "L 2 · C 5 · R 1" — the counts the plate prints beside a line.
static func describe(held: Dictionary) -> String:
	return "L %d · C %d · R %d" % [
		int(held.get("left", 0)), int(held.get("center", 0)), int(held.get("right", 0))
	]


static func label(wing: String) -> String:
	return String(LABELS.get(wing, wing))