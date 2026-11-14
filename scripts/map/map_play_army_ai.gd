class_name MapPlayArmyAi
extends RefCounted
## Rival land turn: every region's stored roster is planned and applied through
## ArmyMovement, so a march this turn fights this turn (docs/ai.md). Splits run
## first so a court that has just declared war can field an army at once.

## Turn-trace kind for a rival court's own muster (DR-20261111-04).
const KIND_REINFORCE: String = "reinforce"
## Turn-trace kind for a rival army's field hospital train (DR-20261112-08).
const KIND_HOSPITAL: String = "hospital_train"
## The Home Army marching back to a seat that moved (issue #474).
const KIND_RECALL: String = "recall"


static func run(play: PlaySession) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	if play.army_layer == null or play.diplomacy == null or play.world == null:
		return trace
	for region: int in play.army_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[ArmyState] = MapPlayCourt.region_armies(play, region)
		if roster.is_empty():
			continue
		if not _run_region(play, model, roster, trace):
			continue
		play.army_layer.regions.set_region(region, roster)
		if play.army_layer.model != null and play.army_layer.model.region_id == region:
			_adopt_visible(play)
	return trace


## Re-reads the on-screen roster after the rules moved it; the player's selected
## standard survives the refresh when it is still in the region.
static func _adopt_visible(play: PlaySession) -> void:
	var selected: ArmyState = play.army_layer.selected_army
	play.army_layer.spawn(play.army_layer.model)
	if selected != null and play.army_layer.armies.has(selected):
		play.army_layer.select(selected)


static func _run_region(
	play: PlaySession, model: MapModel, roster: Array[ArmyState], trace: Array[Dictionary]
) -> bool:
	var changed: bool = false
	for faction: int in MapPlayCourt.planning_factions(play):
		var kind: String = AiControl.court_kind(play, faction)
		if kind == AiControl.KIND_RANDOM:
			continue
		var config: Variant = AiBind.config(kind, faction, play.map_seed)
		# The court raises its men before it plans this turn's march, so a fresh
		# regiment can hold the seat or join the field army it detaches
		# (wiki: ai-architecture § Land reinforcement; DR-20261111-04). A court
		# striking for food raises none: its own men would go hungry instead
		# (issue #489).
		changed = _reinforce(play, model, roster, faction, config, kind, trace) or changed
		# The court brings its surgeons along before it gives the march: a worn
		# field army on its own ground pitches a train (DR-20261112-07,
		# DR-20261112-08).
		changed = _pitch_train(play, model, roster, faction, kind, trace) or changed
		for action: Dictionary in AiBind.military_split(
			kind, config, play.diplomacy, model, roster
		):
			changed = _apply_split(play, model, roster, faction, action, trace) or changed
		var plan: Dictionary = AiBind.military_march(
			kind, config, play.diplomacy, model, roster
		)
		changed = _apply_marches(
			play, model, roster, faction, plan, AiMilitaryPlanner.KIND_MARCH, trace
		) or changed
	# Minor Nations and Tribes take no offensive orders: they only send a relief
	# column onto home soil an invader already holds (docs/ai.md).
	var defenders: Array[int] = FactionCatalog.minor_ids()
	defenders.append_array(FactionCatalog.tribe_ids())
	for faction: int in defenders:
		if faction == play.player_faction and not play.observer_mode:
			continue
		for action: Dictionary in AiDefensePlanner.split_orders(
			play.diplomacy, model, roster, faction
		):
			changed = _apply_split(play, model, roster, faction, action, trace) or changed
		var plan: Dictionary = AiDefensePlanner.march_orders(
			play.diplomacy, model, roster, faction
		)
		changed = _apply_marches(
			play, model, roster, faction, plan, AiDefensePlanner.KIND_RELIEVE, trace
		) or changed
	return changed


## Applies one detach through ArmyRoster.split, minting the next field army id.
static func _apply_split(
	play: PlaySession,
	model: MapModel,
	roster: Array[ArmyState],
	faction: int,
	action: Dictionary,
	trace: Array[Dictionary]
) -> bool:
	var home: ArmyState = MapPlayCourt.army_by_id(
		roster, int(action["army_id"]), faction
	)
	if home == null:
		return false
	var ids: Array[String] = []
	ids.assign(action["regiments"])
	var split: Dictionary = ArmyRoster.split(
		roster, home, ids, play.army_layer.next_army
	)
	if not bool(split.get("ok", false)):
		return false
	var field: ArmyState = split["army"] as ArmyState
	play.army_layer.next_army += 1
	trace.append({
		"faction": faction,
		"kind": AiMilitaryPlanner.KIND_SPLIT,
		"army": field.id,
		"province": field.province,
		"province_name": model.province_name(field.province),
		"region": model.region_id,
	})
	return true


## Applies each planned march through ArmyMovement so the rules own legality.
static func _apply_marches(
	play: PlaySession,
	model: MapModel,
	roster: Array[ArmyState],
	faction: int,
	plan: Dictionary,
	kind: String,
	trace: Array[Dictionary]
) -> bool:
	var changed: bool = false
	for order: Dictionary in plan["orders"]:
		var army: ArmyState = MapPlayCourt.army_by_id(
			roster, int(order["army_id"]), faction
		)
		if army == null:
			continue
		var province: int = int(order["province"])
		var march: Dictionary = ArmyMovement.apply_move(model, army, province, true)
		if not bool(march.get("ok", false)):
			continue
		changed = true
		trace.append({
			"faction": faction,
			"kind": kind,
			"army": army.id,
			"province": province,
			"province_name": model.province_name(province),
			"region": model.region_id,
			"attacked": bool(march.get("attacked", false)),
		})
		_report_march(play, model, faction, province)
	return changed


## Critical state changes are never silent: a rival entering the human's land
## gets a toast; battles and captures already report through the battle line.
static func _report_march(
	play: PlaySession, model: MapModel, faction: int, province: int
) -> void:
	if play.hud == null or model.province_owner(province) != play.player_faction:
		return
	play.hud.toast(
		"%s's army marches into %s"
		% [FactionCatalog.name_of(faction), model.province_name(province)]
	)


## The extra regiments this court arms up for while it can see the victory bar
## (wiki: ai-architecture § Notable strategic policies; DR-20261114-04). A
## session with no world reads none, so the published target stands.
static func _extra_regiments(play: PlaySession, faction: int, config: Variant) -> int:
	return int(AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)["extra_regiments"])


## A rival court raises one line regiment a turn from its own ledger while it
## stands under its target strength and its economy can carry the muster — the
## growth-stage throttle (wiki: ai-architecture § Land reinforcement;
## DR-20261111-04). The regiment joins the Home Army at the capital through
## `ArmyTraining`, so the AI pays the same treasury, materials and peasant the
## human drill yard does (REQ-P2-03).
static func _reinforce(
	play: PlaySession,
	model: MapModel,
	roster: Array[ArmyState],
	faction: int,
	config: Variant,
	kind: String,
	trace: Array[Dictionary]
) -> bool:
	if play.ai == null or play.army_layer == null or play.diplomacy == null:
		return false
	var capital: int = _capital_province(model, faction)
	if capital < 0:
		return false
	var home: ArmyState = ArmyTraining.home_army(roster, faction)
	if home == null:
		return false
	if home.province != capital:
		# A court whose seat moved musters nowhere: the garrison re-forms at the
		# new capital, then the muster below prices its regiment (issue #474).
		_recall(play, model, home, faction, capital, trace)
	var economy: PlayerEconomy = play.ai.economies.get(faction, null) as PlayerEconomy
	if economy == null:
		return false
	var plan: Dictionary = AiBind.reinforce_plan(
		kind,
		config,
		economy,
		play.army_layer.regiment_count_all(faction),
		MapPlayCourt.at_war(play, faction),
		_extra_regiments(play, faction, config),
		AiBind.fed_slack(
			kind, economy, play.army_layer.food_upkeep_all(faction),
			MapPlayCourt.ships(play, faction)
		),
		# The hull the court is saving for outranks the next regiment: the
		# muster spends only what stands above that chest (issue #484).
		MapPlayCourt.navy_chest(play, faction)
	)
	var type_id: String = String(plan["muster"])
	if type_id.is_empty():
		return false
	var unit_id: String = "unit_%d" % play.army_layer.next_regiment
	if not bool(ArmyTraining.recruit(economy, home, type_id, unit_id).get("ok", false)):
		return false
	play.army_layer.next_regiment += 1
	trace.append({
		"faction": faction,
		"kind": KIND_REINFORCE,
		"army": home.id,
		"type": type_id,
		"regiment": unit_id,
		"province": home.province,
		"province_name": model.province_name(home.province),
		"region": model.region_id,
	})
	return true


## Re-forms a stranded Home Army at the new seat. The Home Army is the seat's
## garrison, not a field column — the rules never let it march (`can_move`
## refuses it) — so when the capital moves the garrison re-forms there instead
## of standing at the old seat for the rest of the campaign, which is what
## blocked every muster after a capital fell (issue #474).
static func _recall(
	play: PlaySession,
	model: MapModel,
	home: ArmyState,
	faction: int,
	capital: int,
	trace: Array[Dictionary]
) -> bool:
	if AiArmyReinforce.recall_target(home.province, capital) < 0:
		return false
	var from: int = home.province
	home.province = capital
	home.moved = false
	trace.append({
		"faction": faction,
		"kind": KIND_RECALL,
		"army": home.id,
		"province": capital,
		"province_name": model.province_name(capital),
		"from": from,
		"region": model.region_id,
	})
	return true


## A court at war pitches its surgeons: the wornest field army on the court's own
## ground takes a train, paid from the same table the crown's dossier prints
## (DR-20261112-07, DR-20261112-08). One train a turn per court, and nothing is
## invented when a court lacks the tech, the material or a wound to tend.
static func _pitch_train(
	play: PlaySession,
	model: MapModel,
	roster: Array[ArmyState],
	faction: int,
	kind: String,
	trace: Array[Dictionary]
) -> bool:
	if play.ai == null or play.army_layer == null or _trained_this_turn(trace, faction):
		return false
	var economy: PlayerEconomy = play.ai.economies.get(faction, null) as PlayerEconomy
	if economy == null:
		return false
	var army: ArmyState = AiBind.hospital_best_army(
		kind, model, roster, faction, economy, MapPlayCourt.at_war(play, faction)
	) as ArmyState
	if army == null:
		return false
	var cost: Dictionary = HospitalTrain.cost()
	for commodity: String in cost.keys():
		economy.take(commodity, int(cost[commodity]))
	HospitalTrain.apply(army)
	trace.append({
		"faction": faction,
		"kind": KIND_HOSPITAL,
		"army": army.id,
		"province": army.province,
		"province_name": model.province_name(army.province),
		"region": model.region_id,
	})
	return true


## A court brings one train a turn, however many regions its armies stand in.
static func _trained_this_turn(trace: Array[Dictionary], faction: int) -> bool:
	for record: Dictionary in trace:
		if String(record.get("kind", "")) != KIND_HOSPITAL:
			continue
		if int(record.get("faction", MapModel.NO_ID)) == faction:
			return true
	return false


static func _capital_province(model: MapModel, faction: int) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			return province.id
	return MapModel.NO_ID
