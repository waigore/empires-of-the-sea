class_name MapPlayArmyPick
extends RefCounted
## What the court's own staff would order an army this turn: the split the Home
## Army would take, the march a field army would make, or the road home to merge
## (wiki: military-armies § Home Army, § Movement and attacks; ai-architecture
## § Land reinforcement; DR-20261120-10).
##
## The plan is not a second opinion: it is `AiBindCampaign.military_split` /
## `military_march`, the calls the rival pass and the Auto seat already make for
## a court, read for this crown on its own chart and its own relations — so the
## line can never name a march the rules would refuse (REQ-P2-03). The pass gives
## the split first and the march after it, and so does the pick: the march is read
## off the seat the split leaves, never the chart it found.
##
## A reading only: nothing here splits a standard, marches a regiment or rolls a
## die, and the crown still presses her own order (REQ-P3-03, REQ-P5-06).

## The split the Home Army takes into the field (the pass's own kind).
const KIND_SPLIT: String = AiMilitaryPlanner.KIND_SPLIT
## The march a field army makes, in the pass's own kind.
const KIND_MARCH: String = AiMilitaryPlanner.KIND_MARCH
## The interior-lines march home to merge with the Home Army's mass.
const KIND_ROTATE: String = AiMilitaryPlanner.KIND_ROTATE
## The first leg of the walk home for a host standing on ground it does not hold
## (DR-20261121-15).
const KIND_WALK_HOME: String = AiMilitaryPlanner.KIND_WALK_HOME

## Why a march goes where it goes, read off the ground the planner chose: a
## hostile province to storm, a hostile host standing on the court's own land, or
## the court's own frontier to stage on.
const WHY_STORM: String = "storm"
const WHY_RELIEF: String = "relief"
const WHY_FRONTIER: String = "frontier"


## The pick for one army, as the sheet reads it: `{kind, why, province, regiments,
## line, short}`. Empty when the court would give this army no order — a rival's
## standard, a standard that has already marched, an embarked army (the invasion
## planner steers it), a Home Army the court would not split, a court at peace, a
## session whose court runs no planner, or a chart with no model to read.
static func pick(play: PlaySession, army: ArmyState) -> Dictionary:
	if play == null or army == null or play.army_layer == null:
		return {}
	if play.diplomacy == null or army.owner != play.player_faction:
		return {}
	# An army that has marched keeps the order it was given, and the pass skips
	# her, so the sheet does too (wiki: military-armies § Movement and attacks).
	if army.moved or army.is_embarked() or play.campaign_over():
		return {}
	var region: int = _region_of(play, army)
	var model: MapModel = _model_of(play, region)
	if model == null:
		return {}
	var kind: String = AiControl.court_kind(play, army.owner)
	if kind == AiControl.KIND_NONE:
		return {}
	var config: Variant = AiBind.config(kind, army.owner, play.map_seed, play.ensure_ai().profiles)
	if config == null:
		return {}
	var roster: Array[ArmyState] = _roster_of(play, region)
	if roster.is_empty():
		return {}
	# The pass's own order: the split before the march (MapPlayArmyAi._run_region).
	var splits: Array = AiBindCampaign.military_split(kind, config, play.diplomacy, model, roster)
	for raw: Variant in splits:
		var split: Dictionary = raw
		if int(split.get("army_id", -1)) != army.id:
			continue
		if String(split.get("kind", "")) != KIND_SPLIT:
			continue
		return _split_words(army, split)
	var plan: Dictionary = AiBindCampaign.military_march(
		kind, config, play.diplomacy, model, _seat_after_split(roster, splits)
	)
	for raw: Variant in plan.get("orders", []):
		var order: Dictionary = raw
		if int(order.get("army_id", -1)) != army.id:
			continue
		var target: int = int(order.get("province", MapModel.NO_ID))
		if target == MapModel.NO_ID:
			continue
		return _march_words(play, model, army, order, target)
	return {}


## The sheet's line: the pick's own sentence, or nothing when the court would
## give this army no order this turn.
static func line(play: PlaySession, army: ArmyState) -> String:
	return MapPlayPickProse.sentence_of(pick(play, army))


## The roster the pass plans its marches over: the chart's own, or — when the seat
## takes the field this turn — the seat the split leaves. The pass applies the
## split before it plans the march (`MapPlayArmyAi._run_region`), and a Home Army
## cut down to its guard no longer answers the rotation's gate
## (`AiMilitaryPlanner._rotation_army_id` reads a seat of more than one standard),
## so a worn field army the pre-split chart would send home is really sent to
## storm or to relieve. The copy is the seat, never the force the split fields:
## that army answers to no standard the crown has read (DR-20261120-10).
static func _seat_after_split(roster: Array[ArmyState], splits: Array) -> Array[ArmyState]:
	for raw: Variant in splits:
		var split: Dictionary = raw
		if String(split.get("kind", "")) != KIND_SPLIT:
			continue
		var army_id: int = int(split.get("army_id", -1))
		for index: int in roster.size():
			var seat: ArmyState = roster[index]
			if seat == null or seat.id != army_id or not seat.is_home_army():
				continue
			var going: Array[String] = []
			going.assign(split.get("regiments", []))
			var guard: Array[String] = []
			var types: Dictionary = {}
			for regiment: String in seat.regiments:
				if going.has(regiment):
					continue
				guard.append(regiment)
				types[regiment] = seat.type_of(regiment)
			var out: Array[ArmyState] = roster.duplicate()
			out[index] = ArmyState.create(
				seat.id, seat.owner, seat.province, true, guard, types
			)
			return out
	return roster


## The Home Army taking the field: every regiment but the published guard leaves
## the seat, and the pick counts them off the split's own list.
static func _split_words(army: ArmyState, split: Dictionary) -> Dictionary:
	var going: int = int((split.get("regiments", []) as Array).size())
	var line: String = MapPlayArmyPickWords.split_line(going, army.count() - going)
	if line.is_empty():
		return {}
	return {
		"kind": KIND_SPLIT,
		"why": "",
		"province": army.province,
		"regiments": going,
		"short": line,
		"line": line,
	}


## One march, carrying the reason the ground gives it: a hostile province to
## storm, a hostile host on the court's own land to throw out, its own frontier,
## or the road home to merge.
static func _march_words(
	play: PlaySession, model: MapModel, army: ArmyState, order: Dictionary, target: int
) -> Dictionary:
	var kind: String = String(order.get("kind", ""))
	if kind == KIND_WALK_HOME:
		var own: bool = model != null and model.province_owner(target) == army.owner
		var leg: String = MapPlayArmyPickWords.walk_line(model, target, own)
		if leg.is_empty():
			return {}
		return {
			"kind": KIND_WALK_HOME,
			"why": "",
			"province": target,
			"regiments": 0,
			"short": leg,
			"line": leg,
		}
	if kind == KIND_ROTATE:
		var home: String = MapPlayArmyPickWords.rotate_line(model, target)
		if home.is_empty():
			return {}
		return {
			"kind": KIND_ROTATE,
			"why": "",
			"province": target,
			"regiments": 0,
			"short": home,
			"line": home,
		}
	var why: String = _why(play, model, army, target)
	var line: String = MapPlayArmyPickWords.march_line(model, target, why)
	if line.is_empty():
		return {}
	return {
		"kind": KIND_MARCH,
		"why": why,
		"province": target,
		"regiments": 0,
		"short": line,
		"line": line,
	}


## The ground a march lands on, read the way the planner's own destination table
## reads it (AiMilitaryPlanner._best_order): a province the court does not own is
## a storm; its own land holding a hostile host is a relief; its own open frontier
## is a staging advance.
static func _why(play: PlaySession, model: MapModel, army: ArmyState, target: int) -> String:
	var owner: int = model.province_owner(target)
	if owner != army.owner:
		return WHY_STORM
	var hostile: Dictionary = Hostility.owners(play.diplomacy, army.owner)
	for other: ArmyState in _roster_of(play, model.region_id):
		if other == null or other.is_empty() or other.province != target:
			continue
		if other.owner != army.owner and hostile.has(other.owner):
			return WHY_RELIEF
	return WHY_FRONTIER


## The chart this army stands on: the layer's live roster when it is drawn there,
## else the region table that stores it (the muster roll's own read).
static func _region_of(play: PlaySession, army: ArmyState) -> int:
	var layer: ArmyLayer = play.army_layer
	if layer.model != null and layer.armies.has(army):
		return layer.model.region_id
	for index: int in layer.regions.region_ids():
		var roster: Array[ArmyState] = []
		roster.assign(layer.regions.value(index, []))
		if roster.has(army):
			return index
	return -1


## The model of one region: the chart on screen when it is that region, else the
## world's own. Null when neither holds it, so no pick is worded off a wrong map.
static func _model_of(play: PlaySession, region: int) -> MapModel:
	if region < 0:
		return null
	if play.model != null and play.model.region_id == region:
		return play.model
	if play.world == null:
		return null
	return play.world.region(region)


## The roster the pass plans over: the chart's live armies when it is the chart on
## screen, else the region table's own (the same read the rival pass makes).
static func _roster_of(play: PlaySession, region: int) -> Array[ArmyState]:
	return MapPlayCourt.visible_armies(play, region)