class_name HospitalRules
extends RefCounted
## Hospitals: the province building that sets an army's recovery tempo and
## blunts the wear a defeat leaves behind (wiki: combat § Regiment condition;
## DR-20261111-12). A province stores only `hospital_level`; the rest share,
## the triage scale and the build gates are derived here, so the turn tick,
## combat and the dossier read one table (REQ-P3-03).

const MAX_LEVEL: int = 2

## Food a hospital's staff eats each turn, per level (wiki: combat § Regiment
## condition; DR-20261112-04). The last ration in the larder goes to the sick,
## after the living, so a famine empties the wards before it empties the fields.
const RATION_PER_LEVEL: int = 2

## A field hospital **train** marches with one army (DR-20261112-07): tents and
## a surgeon's chest, level 1 only, never a province record. Its nurses ride in
## the army's own ration line, so the train eats with the men rather than in the
## wards' separate pass.
const TRAIN_REST_SHARE: float = 0.40
const TRAIN_FOOD: int = 2
const TRAIN_TECH: String = "organised_regiments"
const TRAIN_COST: Dictionary = {"lumber": 2, "fabric": 1}

## Level 0 is a bare field. `rest_bonus` adds to RegimentCondition.REST_SHARE;
## `triage` is the share of battle wear the province's owner still takes.
const LEVELS: Array[Dictionary] = [
	{},
	{
		"name": "Field hospital",
		"rest_bonus": 0.15,
		"triage": 0.20,
		"turns": 1,
		"tech": "organised_regiments",
		"cost": {"lumber": 3, "fabric": 2},
	},
	{
		"name": "General hospital",
		"rest_bonus": 0.30,
		"triage": 0.35,
		"turns": 2,
		"tech": "modern_military_funding",
		"cost": {"lumber": 4, "fabric": 3, "steel": 2},
	},
]


static func clamp_level(level: int) -> int:
	return clampi(level, 0, MAX_LEVEL)


static func level_name(level: int) -> String:
	return String(_entry(level).get("name", "None"))


## Share of a regiment's pool restored at turn start in this province.
static func rest_share(level: int) -> float:
	return RegimentCondition.REST_SHARE + float(_entry(level).get("rest_bonus", 0.0))


## Multiplier on the battle wear the province's owner takes (1.0 = no relief).
static func triage_scale(level: int) -> float:
	return 1.0 - float(_entry(level).get("triage", 0.0))


static func turns(level: int) -> int:
	return int(_entry(level).get("turns", 1))


static func cost(level: int) -> Dictionary:
	return (_entry(level).get("cost", {}) as Dictionary).duplicate()


## Owned tech id required to raise the province to `level`, or "" when free.
static func tech_gate(level: int) -> String:
	return String(_entry(level).get("tech", ""))


static func next_level(current: int) -> int:
	return mini(clamp_level(current) + 1, MAX_LEVEL)


static func level_at(model: MapModel, province: int) -> int:
	if model == null:
		return 0
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return 0
	return clamp_level(data.hospital_level)


## The level that heals: a hospital whose staff went unfed this turn reads as a
## bare field for the rest tick, while its walls still shelter the wounded in
## battle (wiki: combat § Regiment condition; DR-20261112-04).
static func effective_level(model: MapModel, province: int) -> int:
	if model == null:
		return 0
	var data: ProvinceState = model.province_data(province)
	if data == null or not data.hospital_staffed:
		return 0
	return clamp_level(data.hospital_level)


## Food this hospital's staff eats in a turn: nothing for a bare field.
static func food_demand(level: int) -> int:
	return clamp_level(level) * RATION_PER_LEVEL


## The tile a hospital is raised on: the province's town, like a fort
## (wiki: siege-mechanics § Fort Levels). -1 on legacy maps with no seat.
static func site_tile(model: MapModel, province: int) -> Vector2i:
	return FortRules.site_tile(model, province)


static func rest_share_at(model: MapModel, province: int) -> float:
	return rest_share(effective_level(model, province))


static func triage_scale_at(model: MapModel, province: int) -> float:
	return triage_scale(level_at(model, province))


## The better of the province's ward and the army's own train, never both
## (DR-20261112-07). A bare field with no train reads the field's quarter.
static func army_rest_share(model: MapModel, province: int, train: bool) -> float:
	var share: float = RegimentCondition.REST_SHARE
	if model != null and province != MapModel.NO_ID:
		share = maxf(share, rest_share_at(model, province))
	if train:
		share = maxf(share, TRAIN_REST_SHARE)
	return share


# --- field hospital train (DR-20261112-07) ------------------------------------


static func train_cost() -> Dictionary:
	return TRAIN_COST.duplicate()


static func train_food() -> int:
	return TRAIN_FOOD


static func train_tech() -> String:
	return TRAIN_TECH


## Validation for pitching a train, so the dossier can name the refusal before
## the crown taps. Pure: it spends nothing.
static func train_check(
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
	if not bool(tech_unlocked.get(TRAIN_TECH, false)):
		return _refuse("A field hospital needs %s." % TechCatalog.display_name(TRAIN_TECH))
	for commodity: String in TRAIN_COST.keys():
		if int(stockpile.get(commodity, 0)) < int(TRAIN_COST[commodity]):
			return _refuse(
				"A field hospital needs %d %s."
				% [int(TRAIN_COST[commodity]), CommodityCatalog.label(commodity)]
			)
	return {"ok": true, "reason": ""}


## Pitching the train: the army carries it from now on. The caller spends the
## materials (REQ-P3-03).
static func apply_train(army: ArmyState) -> void:
	if army != null:
		army.field_hospital = true


## Dossier wording for an army that carries one, e.g.
## "Field hospital train · rest 40% · staff 2 food".
static func train_describe() -> String:
	return "Field hospital train · rest %d%% · staff %d food" % [
		roundi(TRAIN_REST_SHARE * 100.0), TRAIN_FOOD
	]


## Applies a finished build: the province reaches the level that project was
## raised for, and a later completion can never leap a level. A new building
## opens with its staff hired.
static func apply_build(data: ProvinceState, ordered: int) -> void:
	if data == null:
		return
	var target: int = ordered if ordered > 0 else next_level(data.hospital_level)
	data.hospital_level = clampi(maxi(data.hospital_level, target), 0, MAX_LEVEL)
	data.hospital_staffed = true


## Every hospital this crown keeps, seat first and then the chart's own order.
## Each row is `{region, province, level, demand, seat}`.
static func demand_rows(world: WorldMap, faction: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if world == null:
		return rows
	var home: int = FactionCatalog.region_of(faction)
	var seat: int = world.capital_province_of(home, faction) if home >= 0 else MapModel.NO_ID
	var seat_at: int = -1
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		for province in model.province_count():
			var data: ProvinceState = model.province_data(province)
			if data == null or data.owner != faction or data.hospital_level <= 0:
				continue
			var is_seat: bool = index == home and province == seat
			if is_seat:
				seat_at = rows.size()
			rows.append({
				"region": index,
				"province": province,
				"level": clamp_level(data.hospital_level),
				"demand": food_demand(data.hospital_level),
				"seat": is_seat,
			})
	# The seat is served first; the rest keep the chart's order.
	if seat_at > 0:
		rows.insert(0, rows.pop_at(seat_at))
	return rows


## The order the wards are fed in, as one integer per hospital: the seat first,
## then the chart's own order (DR-20261112-04). Its sum is the crown's whole
## hospital ration for the turn.
static func demand_list(world: WorldMap, faction: int) -> Array[int]:
	var demands: Array[int] = []
	for row: Dictionary in demand_rows(world, faction):
		demands.append(maxi(int(row["demand"]), 0))
	return demands


## Food the whole staffs can eat from `available` units, fed in `demands` order:
## a hospital the larder cannot cover is skipped and the rest of the larder is
## offered to the next, so a ration is never stranded on a ward that cannot be
## staffed (DR-20261112-04). [method feed] walks the same rows the same way, so
## the food the larder pays is exactly the food the seated staffs eat.
static func ration(demands: Array[int], available: int) -> int:
	var left: int = maxi(available, 0)
	var spent: int = 0
	for raw: int in demands:
		var need: int = maxi(raw, 0)
		if need <= 0 or need > left:
			continue
		left -= need
		spent += need
	return spent


## Feeds the staffs from `food_available` units, whole hospitals only: a
## hospital the larder cannot cover goes unstaffed and the rest of the larder is
## offered to the next. Marks every hospital for the turn, so a ward that ate
## last turn is not starved by a stale flag. Returns `{spent, demand, hungry}`.
static func feed(world: WorldMap, faction: int, food_available: int) -> Dictionary:
	var rows: Array[Dictionary] = demand_rows(world, faction)
	var left: int = maxi(food_available, 0)
	var spent: int = 0
	var demand: int = 0
	var hungry: Array[int] = []
	for row: Dictionary in rows:
		demand += int(row["demand"])
		var model: MapModel = world.region(int(row["region"]))
		var data: ProvinceState = model.province_data(int(row["province"])) if model != null else null
		if data == null:
			continue
		var cost: int = int(row["demand"])
		var fed: bool = cost <= left
		data.hospital_staffed = fed
		if fed:
			left -= cost
			spent += cost
		else:
			hungry.append(int(row["province"]))
	return {"spent": spent, "demand": demand, "hungry": hungry}


## Dossier wording, e.g. "Field hospital · rest 40% · wear 80% · staff 2 food".
static func describe(level: int, staffed: bool = true) -> String:
	if level <= 0:
		return "No hospital"
	var rest: float = rest_share(level) if staffed else RegimentCondition.REST_SHARE
	var line: String = "%s · rest %d%% · wear %d%%" % [
		level_name(level),
		roundi(rest * 100.0),
		roundi(triage_scale(level) * 100.0),
	]
	if not staffed:
		return line + " · unstaffed — no rations this turn"
	return line + " · staff %d food" % food_demand(level)


static func _entry(level: int) -> Dictionary:
	return LEVELS[clamp_level(level)]


## Validation for the Engineer's `build_hospital` order. Returns `{"ok": true}`
## (with the level to raise in `details`) or a refusal shaped like
## CivilianWork's `_no`.
static func work_check(
	model: MapModel,
	unit: CivilianState,
	tile: Vector2i,
	province: int,
	tech_unlocked: Dictionary
) -> Dictionary:
	if model.owner_at(tile.x, tile.y) != unit.owner:
		return _refuse("This land is not held by your crown.")
	if level_at(model, province) >= MAX_LEVEL:
		return _refuse("This province already holds a general hospital.")
	var next: int = next_level(level_at(model, province))
	var gate: String = tech_gate(next)
	if not gate.is_empty() and not bool(tech_unlocked.get(gate, false)):
		return _refuse(
			"A %s needs %s." % [level_name(next), TechCatalog.display_name(gate)]
		)
	return {"ok": true, "details": {"hospital_level": next}}


## The work detail a hospital order records, for CivilianWork.assign.
static func work_details(check: Dictionary) -> Dictionary:
	return (check.get("details", {}) as Dictionary).duplicate()


## Applies a finished hospital order and reports the painted tile.
static func work_complete(
	model: MapModel, province: int, unit: CivilianState, tile: Vector2i
) -> Array:
	apply_build(model.province_data(province), unit.work_detail("hospital_level"))
	return [model.index_of(tile.x, tile.y)]


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}