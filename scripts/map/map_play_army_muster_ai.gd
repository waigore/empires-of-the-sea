class_name MapPlayArmyMusterAi
extends RefCounted
## Rival muster: the regiment a court raises from its own ledger, the surgeons'
## train it pitches and the Home Army it re-forms at a moved seat (wiki:
## ai-architecture § Land reinforcement; DR-20261111-04, DR-20261112-08,
## issue #474). MapPlayArmyAi calls this before it gives the day's march, so a
## fresh regiment can hold the seat or join the field army it detaches.
##
## The trace kinds are written here, so they are named here; MapPlayArmyAi
## republishes them for the frozen ai-bench mainline planners (P4).

## Turn-trace kind for a rival court's own muster (DR-20261111-04).
const KIND_REINFORCE: String = "reinforce"
## Turn-trace kind for a rival army's field hospital train (DR-20261112-08).
const KIND_HOSPITAL: String = "hospital_train"
## The Home Army marching back to a seat that moved (issue #474).
const KIND_RECALL: String = "recall"


## The court's whole muster for one region: raise the men, then pitch the train.
## Both legs run every turn — a court that raised a regiment still brings its
## surgeons — so neither answer short-circuits the other. The wall reading
## ([method storm_extra]) is noted on the court's config first, so the plan's
## own target carries it.
static func muster(
	play: PlaySession,
	model: MapModel,
	roster: Array[ArmyState],
	faction: int,
	config: Variant,
	kind: String,
	trace: Array[Dictionary]
) -> bool:
	var wall: Dictionary = storm_extra(
		play, model, faction, play.army_layer.regiment_count_all(faction)
		if play != null and play.army_layer != null else 0
	)
	if config is AiConfig:
		(config as AiConfig).storm_read = wall
	var raised: bool = _reinforce(play, model, roster, faction, config, kind, trace)
	var trained: bool = _pitch_train(play, model, roster, faction, kind, trace)
	return raised or trained


## The extra regiments this court arms up for while it can see the victory bar
## (wiki: ai-architecture § Notable strategic policies; DR-20261114-04). A
## session with no world reads none, so the published target stands.
static func extra_regiments(play: PlaySession, faction: int, config: Variant) -> int:
	return int(AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)["extra_regiments"])


## The muster plan the court's own published policy books from its ledger: the
## eleven readings `AiArmyReinforce.plan` takes — its line, footing, food gate,
## the hull's chest and row, the victory pressure and the conquest bank —
## assembled once, so the drill yard's advice and the rival pass's muster cannot
## drift (REQ-P2-03; DR-20261121-03). Pure: the plan reads the state and writes
## none of it.
static func plan(
	play: PlaySession,
	faction: int,
	config: Variant,
	kind: String,
	economy: PlayerEconomy
) -> Dictionary:
	if play == null or economy == null or play.army_layer == null:
		return {}
	var own_warships: int = MapPlayCourt.warships(play, faction)
	var chest: int = MapPlayCourt.navy_chest(play, faction)
	var held: Dictionary = {}
	if chest > 0 and (
		economy.treasury >= chest or own_warships == 0
	):
		held = AiNavy.due_row(
			MapPlayCourt.at_war(play, faction),
			own_warships,
			MapPlayCourt.hostile_warships(play, faction),
			economy, MapPlayCourt.hull_types(play, faction)
		)
	var slack: int = (
		int(play.ai.food_slack[faction])
		if play.ai != null and play.ai.food_slack.has(faction) else -2
	)
	return AiBindEconomy.reinforce_plan(
		kind,
		config,
		economy,
		play.army_layer.regiment_count_all(faction),
		MapPlayCourt.at_war(play, faction),
		extra_regiments(play, faction, config),
		AiBindEconomy.fed_slack(
			kind, economy, play.army_layer.food_upkeep_all(faction),
			MapPlayCourt.ships(play, faction)
		),
		chest,
		held,
		own_warships,
		# The harvest the court's land carries, noted by the economy pass: the
		# desired army is provisioned before it is raised (issue #807). No
		# reading keeps the store gate.
		slack,
		# Bank-then-blitz (issue #995): a submission court short of the win bar
		# keeps the muster chest at peace so the host can close the gap.
		kind != AiControl.KIND_BASELINE
		and AiVictoryPressure.below_bar(
			play.world, faction, play.human_faction_id(), play.difficulty
		)
	)


## The extra regiments the wall in front of this court asks for (issue #1314):
## every Old World province starts behind a wall, and the storm gate prices the
## wall plus its battery, so a court musting only its published target never
## crosses one and its land stays foreign. The reading is the thinnest wall the
## court does not own against its strongest line, from its own target and
## strength; [method AiArmyReinforce.desired_regiments] raises the guard on it.
static func storm_extra(
	play: PlaySession,
	model: MapModel,
	faction: int,
	own_regiments: int
) -> Dictionary:
	if play == null or model == null or play.ai == null:
		return {}
	var economy: PlayerEconomy = play.ai.economies.get(faction, null) as PlayerEconomy
	if economy == null:
		return {}
	var config: Variant = AiControl.court(play, faction).get("config", null)
	if config == null:
		return {}
	var at_war: bool = MapPlayCourt.at_war(play, faction)
	var target: int = AiArmyReinforce.guard_regiments(config, at_war)
	return AiStormGate.extra(
		thinnest_wall(model, faction, economy.tech_unlocked),
		float(RegimentCatalog.strength(
			AiArmyReinforceLine.strongest_line(economy.tech_unlocked)
		)),
		target,
		own_regiments
	)


## The lowest storm threshold among the walled provinces this court does not
## own, 0 when none stands. The battery is the Royal line every court carries
## (wiki: tech-tree-military), so the reading never guesses a quality it has
## not seen.
static func thinnest_wall(
	model: MapModel, faction: int, tech_unlocked: Dictionary
) -> float:
	if model == null:
		return 0.0
	var thinnest: float = 0.0
	for province: int in model.province_count():
		if model.province_owner(province) == faction:
			continue
		var level: int = FortRules.level_at(model, province)
		if not FortRules.is_siege(level):
			continue
		var threshold: float = FortRules.storm_threshold(tech_unlocked, level)
		if thinnest <= 0.0 or threshold < thinnest:
			thinnest = threshold
	return thinnest


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
	var capital: int = WorldBootstrap.capital_province(model, faction)
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
	# The hull the court is saving for outranks the next regiment: the muster
	# spends only what stands above that chest, and — once the chest is full —
	# only the cloth above the hull's own row, so the launch the purse was saved
	# for can actually be laid (issue #484). The plan is `plan`'s, the same one
	# the drill yard's advice reads (DR-20261121-03).
	var muster_plan: Dictionary = plan(play, faction, config, kind, economy)
	var type_id: String = String(muster_plan["muster"])
	if type_id.is_empty():
		return false
	var unit_id: String = "unit_%d" % play.army_layer.next_regiment
	if not bool(ArmyTraining.recruit(economy, home, type_id, unit_id).get("ok", false)):
		return false
	play.army_layer.next_regiment += 1
	var line: Dictionary = MapPlayCourt.army_trace(
		model, faction, KIND_REINFORCE, home.id, home.province
	)
	line["type"] = type_id
	line["regiment"] = unit_id
	trace.append(line)
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
	var line: Dictionary = MapPlayCourt.army_trace(
		model, faction, KIND_RECALL, home.id, capital
	)
	line["from"] = from
	trace.append(line)
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
	var army: ArmyState = AiBindCampaign.hospital_best_army(
		kind, model, roster, faction, economy, MapPlayCourt.at_war(play, faction)
	) as ArmyState
	if army == null:
		return false
	var cost: Dictionary = HospitalTrain.cost()
	for commodity: String in cost.keys():
		economy.take(commodity, int(cost[commodity]))
	HospitalTrain.apply(army)
	trace.append(
		MapPlayCourt.army_trace(model, faction, KIND_HOSPITAL, army.id, army.province)
	)
	return true


## A court brings one train a turn, however many regions its armies stand in.
static func _trained_this_turn(trace: Array[Dictionary], faction: int) -> bool:
	for record: Dictionary in trace:
		if String(record.get("kind", "")) != KIND_HOSPITAL:
			continue
		if int(record.get("faction", MapModel.NO_ID)) == faction:
			return true
	return false
