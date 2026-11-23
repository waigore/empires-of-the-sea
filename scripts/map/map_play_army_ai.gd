class_name MapPlayArmyAi
extends RefCounted
## Rival land turn: every region's stored roster is planned and applied through
## ArmyMovement, so a march this turn fights this turn (docs/ai.md). Splits run
## first so a court that has just declared war can field an army at once.
##
## The muster that precedes the march — the regiment a court raises, its
## surgeons' train and the Home Army's recall — is MapPlayArmyMusterAi's; this
## pass calls it before it gives the day's orders.

## Turn-trace kind for a rotated field army folding into the Home Army
## (issue #974).
const KIND_COMBINE: String = "combine"
## The muster's trace kinds, republished: the frozen ai-bench mainline planners
## read them from this pass (P4), while MapPlayArmyMusterAi writes them.
const KIND_REINFORCE: String = MapPlayArmyMusterAi.KIND_REINFORCE
const KIND_HOSPITAL: String = MapPlayArmyMusterAi.KIND_HOSPITAL
const KIND_RECALL: String = MapPlayArmyMusterAi.KIND_RECALL


static func run(play: PlaySession) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	if play.army_layer == null or play.diplomacy == null or play.world == null:
		return trace
	for region: int in play.army_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[ArmyState] = MapPlayCourtRoster.region_armies(play, region)
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
		var court: Dictionary = AiControl.court(play, faction)
		if court.is_empty() or String(court["kind"]) == AiControl.KIND_RANDOM:
			continue
		var kind: String = String(court["kind"])
		var config: Variant = court["config"]
		# The court raises its men and brings its surgeons before it plans this
		# turn's march, so a fresh regiment can hold the seat or join the field
		# army it detaches, and a worn field army on its own ground pitches a
		# train (wiki: ai-architecture § Land reinforcement; DR-20261111-04,
		# DR-20261112-07, DR-20261112-08). A court striking for food raises none:
		# its own men would go hungry instead (issue #489).
		changed = MapPlayArmyMusterAi.muster(
			play, model, roster, faction, config, kind, trace
		) or changed
		for action: Dictionary in AiBindCampaign.military_split(
			kind, config, play.diplomacy, model, roster
		):
			changed = _apply_split(play, model, roster, faction, action, trace) or changed
		var plan: Dictionary = AiBindCampaign.military_march(
			kind, config, play.diplomacy, model, roster
		)
		changed = _apply_marches(
			play, model, roster, faction, plan, AiMilitaryPlanner.KIND_MARCH, trace
		) or changed
		# The rotation's merge leg (issue #974): a field army the court just
		# marched home folds into the Home Army, so the next split re-fields a
		# full-strength replacement. Baselines issue no rotation orders.
		if kind != AiControl.KIND_BASELINE:
			changed = _apply_rotation_combine(
				play, model, roster, faction, plan, trace
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
	var home: ArmyState = MapPlayCourtRoster.army_by_id(
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
	trace.append(
		MapPlayCourtRoster.army_trace(
			model, faction, AiMilitaryPlanner.KIND_SPLIT, field.id, field.province
		)
	)
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
		var army: ArmyState = MapPlayCourtRoster.army_by_id(
			roster, int(order["army_id"]), faction
		)
		if army == null:
			continue
		var province: int = int(order["province"])
		# The rival marches through the same gate the crown does: a Tribe needs
		# no declaration, but a Tribe province a crown has bought land in does.
		var owner: int = model.province_owner(province)
		var may_enter: bool = (
			owner == MapModel.NO_ID or owner == faction
			or DiplomacyRules.invadable(play.diplomacy, faction, owner, model, province)
		)
		var march: Dictionary = ArmyMovement.apply_move(model, army, province, may_enter)
		if not bool(march.get("ok", false)):
			continue
		changed = true
		var attacked: bool = bool(march.get("attacked", false))
		# The prosecution note (issue #999): an attack on another court's ground
		# is what makes a war pay, and the diplomacy pass reads it.
		if attacked and play.ai != null and owner != MapModel.NO_ID and owner != faction:
			AiWarMemory.note_attack(play.ai, faction, owner, play.turn)
		var line: Dictionary = MapPlayCourtRoster.army_trace(
			model, faction, kind, army.id, province
		)
		line["attacked"] = attacked
		trace.append(line)
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


## The rotation's merge leg (issue #974): a field army the court just marched
## home folds into the Home Army — always the merge target — so the next split
## re-fields a full-strength replacement. An army the rules did not bring home
## stays in the field.
static func _apply_rotation_combine(
	play: PlaySession,
	model: MapModel,
	roster: Array[ArmyState],
	faction: int,
	plan: Dictionary,
	trace: Array[Dictionary]
) -> bool:
	var home: ArmyState = ArmyTraining.home_army(roster, faction)
	if home == null:
		return false
	var changed: bool = false
	for order: Dictionary in plan["orders"]:
		if String(order.get("kind", "")) != AiMilitaryPlanner.KIND_ROTATE:
			continue
		var army: ArmyState = MapPlayCourtRoster.army_by_id(
			roster, int(order["army_id"]), faction
		)
		if army == null or army == home or army.province != home.province:
			continue
		var merged: Dictionary = ArmyRoster.combine(roster, [home, army])
		if not bool(merged.get("ok", false)):
			continue
		changed = true
		trace.append(
			MapPlayCourtRoster.army_trace(
				model, faction, KIND_COMBINE, home.id, home.province
			)
		)
	return changed

