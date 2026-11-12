class_name FieldHospitalTrain
extends RefCounted
## A field hospital that marches with one army (wiki: combat § Regiment
## condition; DR-20261112-07): tents and a surgeon's chest, level 1 only, one
## per army, never a province record. Its nurses eat with the men, so the train
## carries the Field hospital's rest tempo wherever its standard stands and no
## battle-wear relief at all — the triage stays the province's walls. Pure rules
## over [ArmyState], so the turn tick, the dossier and the tests read one table
## (REQ-P3-03).

## The Field hospital's share (HospitalRules level 1), its ration, its tech gate
## and its materials. A train is equipment, so the price is paid at once.
const REST_SHARE: float = 0.40
const FOOD: int = 2
const TECH: String = "organised_regiments"
const COST: Dictionary = {"lumber": 2, "fabric": 1}


static func food() -> int:
	return FOOD


static func tech() -> String:
	return TECH


static func cost() -> Dictionary:
	return COST.duplicate()


## The better of the province's ward and the army's own train, never both. A
## bare field with no train reads the field's quarter.
static func army_rest_share(model: MapModel, province: int, train: bool) -> float:
	var share: float = RegimentCondition.REST_SHARE
	if model != null and province != MapModel.NO_ID:
		share = maxf(share, HospitalRules.rest_share_at(model, province))
	if train:
		share = maxf(share, REST_SHARE)
	return share


## Validation for pitching a train, so the dossier can name the refusal before
## the crown taps. Pure: it spends nothing.
static func check(
	model: MapModel,
	army: ArmyState,
	tech_unlocked: Dictionary = {},
	stockpile: Dictionary = {}
) -> Dictionary:
	if army == null:
		return _refuse("There is no army to shelter.")
	if army.field_hospital:
		return _refuse("This army already carries a field hospital.")
	if army.is_embarked():
		return _refuse("Land the army before pitching its hospital.")
	if army.is_empty():
		return _refuse("An army with no regiments needs no surgeon.")
	if model == null or army.province == MapModel.NO_ID:
		return _refuse("The army is not on the map.")
	if model.province_owner(army.province) != army.owner:
		return _refuse("Tents are pitched on your crown's own land.")
	if not bool(tech_unlocked.get(TECH, false)):
		return _refuse("A field hospital needs %s." % TechCatalog.display_name(TECH))
	for commodity: String in COST.keys():
		if int(stockpile.get(commodity, 0)) < int(COST[commodity]):
			return _refuse(
				"A field hospital needs %d %s."
				% [int(COST[commodity]), CommodityCatalog.label(commodity)]
			)
	return {"ok": true, "reason": ""}


## Pitching the train: the army carries it from now on. The caller spends the
## materials (REQ-P3-03).
static func apply(army: ArmyState) -> void:
	if army != null:
		army.field_hospital = true


## A split leaves the train with the parent standard; when the emptied standard
## is dropped, it marches with the men who are left instead of vanishing.
static func split_carry(source: ArmyState, detached: ArmyState) -> void:
	if source == null or detached == null:
		return
	detached.field_hospital = source.field_hospital
	source.field_hospital = false


## One train survives a combine, whichever standard carried it.
static func combine_carry(target: ArmyState, from_army: ArmyState) -> void:
	if target != null and from_army != null:
		target.field_hospital = target.field_hospital or from_army.field_hospital


## Dossier wording, e.g. "Field hospital train · rest 40% · staff 2 food".
static func describe() -> String:
	return "Field hospital train · rest %d%% · staff %d food" % [
		roundi(REST_SHARE * 100.0), FOOD
	]


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
