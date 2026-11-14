class_name AiTribeColony
extends RefCounted
## The Tribe a rival court is drawing into its empire (wiki: diplomacy § GP–Tribe
## Rules; docs/ai.md; DR-20261114-02).
##
## A Tribe's land is no war prize: its provinces never count toward victory, and
## a war on it clears the envoy chain that would have made it a colony. A colony
## instead pays its suzerain every turn — the favoured trading partner, its
## output and the boycotts that follow. So a court that has charted a Tribe's
## shore wants the envoy chain opened and the Join Empire bought, and it does not
## declare on that Tribe while the chain stands.
##
## Pure: state, chart, treasury and tech reads in; a target and a utility bonus
## out (REQ-P2-03, REQ-P3-03). Every legality check stays in `DiplomacyRules`;
## this module only says how much the court wants the step.

## What the next envoy step is worth while the colony stands in reach, on the
## same 0–100 scale as every peaceful offer (AiUtility). The Join Empire itself
## is worth more than the steps before it: it is the step that founds the colony.
const BONUS: int = 20
const JOIN_BONUS: int = 15


## The Tribe this court most wants, or {} when no charted Tribe is in reach:
## `target`, `stage`, `cost`, `bonus`. The furthest overture stage wins, then
## the warmer relation, then the lower faction id, so a replay always chooses
## the same Tribe (REQ-P2-03).
static func best(
	state: DiplomacyState,
	world: WorldMap,
	charts: CourtCharts,
	faction: int,
	treasury: int,
	tech: Dictionary
) -> Dictionary:
	var chosen: Dictionary = {}
	for tribe: int in FactionCatalog.tribe_ids():
		var read: Dictionary = ambition(state, world, charts, faction, tribe, treasury, tech)
		if not bool(read.get("wanted", false)):
			continue
		if chosen.is_empty() or _before(read, chosen):
			chosen = read
	return chosen


## How much this court wants the next envoy step toward one Tribe:
## {"target", "wanted", "stage", "cost", "bonus", "held", "reason"}. `wanted` is
## false with a reason when the Tribe is not in reach — no envoy, at war, another
## crown's colony, an uncharted shore, or a step the treasury cannot cover.
## `held` says a chain already stands with a charted Tribe: the court has spent
## on it, so it does not declare war and clear it while the purse catches up.
static func ambition(
	state: DiplomacyState,
	world: WorldMap,
	charts: CourtCharts,
	faction: int,
	target: int,
	treasury: int,
	tech: Dictionary
) -> Dictionary:
	var read: Dictionary = {
		"target": target, "wanted": false, "held": false, "stage": "", "cost": 0,
		"bonus": 0, "relation": 0.0, "reason": "",
	}
	if state == null or target < 0:
		return _deny(read, "no tribal court")
	if FactionCatalog.type_of(target) != FactionCatalog.Type.TRIBE:
		return _deny(read, "not a tribe")
	var relation: DiplomacyRelation = state.relation(faction, target)
	if relation == null:
		return _deny(read, "no envoy has reached that court")
	read["relation"] = relation.score
	if relation.at_war:
		return _deny(read, "at war with the tribal court")
	var colony_of: int = state.colony_of(target)
	if colony_of == faction:
		return _deny(read, "already a colony of this crown")
	if colony_of >= 0:
		return _deny(read, "another crown's colony")
	var stage: String = DiplomacyCatalog.next_stage(state.overture(faction, target))
	if stage.is_empty():
		return _deny(read, "the envoy chain is complete")
	if not charted(world, charts, faction, target):
		return _deny(read, "the court has not charted that shore")
	# An open chain is a stake: the court has paid for it and means to keep it.
	read["held"] = state.overture(faction, target) != DiplomacyCatalog.STAGE_NONE
	var provinces: int = DiplomacyRules.provinces_owned(world, target)
	var cost: int = DiplomacyCatalog.stage_cost(stage, provinces)
	if treasury < cost:
		return _deny(read, "the treasury cannot cover the %s" % (
			DiplomacyCatalog.stage_label(stage)
		))
	read["wanted"] = true
	read["stage"] = stage
	read["cost"] = cost
	read["bonus"] = BONUS + (JOIN_BONUS if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE else 0)
	return read


## The technology that stands between this court and the next link of the colony
## it is buying, or "" when nothing does. A chain with a charted Tribe that the
## court means to finish is only as open as its next stage: an Embassy needs
## Diplomatic Expertise, and a court that never studies it leaves the chain dead
## at the Consulate (wiki: diplomacy § GP–Minor Rules, § GP–Tribe Rules;
## tech-tree-diplomacy-civilian; DR-20261114-05).
static func door(
	state: DiplomacyState,
	world: WorldMap,
	charts: CourtCharts,
	faction: int,
	tech: Dictionary
) -> String:
	if state == null:
		return ""
	for tribe: int in FactionCatalog.tribe_ids():
		var relation: DiplomacyRelation = state.relation(faction, tribe)
		if relation == null or relation.at_war:
			continue
		if state.colony_of(tribe) >= 0:
			continue
		var stage: String = DiplomacyCatalog.next_stage(state.overture(faction, tribe))
		if stage.is_empty():
			continue
		if not charted(world, charts, faction, tribe):
			continue
		var needed: String = DiplomacyCatalog.tech_needed(
			stage, FactionCatalog.Type.TRIBE
		)
		if not needed.is_empty() and not tech.has(needed):
			return needed
	return ""


## True when this court's chart holds one tile of the Tribe's land at `fogged`
## or better. A session with no chart reads the published map, as the other
## chart-backed reads do (DR-20261113-03).
static func charted(
	world: WorldMap, charts: CourtCharts, faction: int, target: int
) -> bool:
	if world == null:
		return false
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var view: VisibilityModel = charts.model_for(faction, index) if charts != null else null
		for province: ProvinceState in model.provinces:
			if province.owner != target:
				continue
			if view == null or view.is_province_known(province.id):
				return true
	return false


## The order the rank of wanted targets reads: furthest stage, then the warmer
## relation, then the lower id.
static func _before(left: Dictionary, right: Dictionary) -> bool:
	var left_stage: int = DiplomacyCatalog.STAGES.find(String(left.get("stage", "")))
	var right_stage: int = DiplomacyCatalog.STAGES.find(String(right.get("stage", "")))
	if left_stage != right_stage:
		return left_stage > right_stage
	var left_relation: float = float(left.get("relation", 0.0))
	var right_relation: float = float(right.get("relation", 0.0))
	if not is_equal_approx(left_relation, right_relation):
		return left_relation > right_relation
	return int(left.get("target", 0)) < int(right.get("target", 0))


static func _deny(read: Dictionary, reason: String) -> Dictionary:
	read["wanted"] = false
	read["reason"] = reason
	return read
