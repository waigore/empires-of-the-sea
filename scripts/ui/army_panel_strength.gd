class_name ArmyPanelStrength
extends RefCounted
## Strength line for the army dossier: count, firepower, food, chevrons and the
## ward or train. The strength is the resolver's own aggregation, so the
## dossier, the muster roll and the battle name one figure for a decorated
## standard (wiki: combat § Strength, military-armies § The muster roll;
## REQ-P2-03, REQ-P3-01).


## The dossier's larder line: the rules' own bill, so the dossier and the crown's
## army sheet never name one standard two ways (wiki: military-armies § The
## regiments behind an army, combat § Feeding; DR-20261112-07).
static func food(army: ArmyState) -> int:
	var one: Array[ArmyState] = [army]
	return ArmyRoster.food_upkeep_of(one, army.owner)


## One standing line under the station: regiments, strength, food, then rest.
static func line(model: MapModel, army: ArmyState) -> String:
	var one: Array[ArmyState] = [army]
	var regiments: int = army.count()
	var text: String = "%d regiment%s · %d strength · %d food" % [
		regiments, MoneyText.plural(regiments), roundi(ArmyForce.side_strength(one)), food(army)
	]
	var chevrons: int = RegimentCondition.chevrons(one)
	if chevrons > 0:
		text += " · %d chevron%s" % [chevrons, MoneyText.plural(chevrons)]
	if army.is_embarked():
		return text
	return text + _rest_note(model, army)


## Ward, field hospital, or unstaffed hospital — nothing when the province is
## bare and the tents are not pitched.
static func _rest_note(model: MapModel, army: ArmyState) -> String:
	var ward: int = HospitalRules.effective_level(model, army.province)
	if army.field_hospital:
		# The tents carry the field's tempo anywhere; a fed ward can still
		# beat them, so both shares are named (DR-20261112-07).
		var note: String = " · field hospital · rest %d%%" % roundi(
			HospitalTrain.REST_SHARE * 100.0
		)
		var ward_share: float = HospitalRules.rest_share(ward)
		if ward > 0 and ward_share > HospitalTrain.REST_SHARE:
			note += " · ward %d%%" % roundi(ward_share * 100.0)
		return note
	if ward > 0:
		return " · rest %d%%" % roundi(HospitalRules.rest_share(ward) * 100.0)
	if HospitalRules.level_at(model, army.province) > 0:
		# The ward is there but its staff went unfed (DR-20261112-04).
		return " · hospital unstaffed"
	return ""
