class_name MapPlayRealmCounsel
extends RefCounted
## The crown's own provinces the court's staff would act in this turn, named and
## marked on THE CROWN'S REALM before the crown opens a province (wiki:
## world-model § The crown's provinces; DR-20261121-21).
##
## The reading is not a second opinion: it is `MapPlayPeoplePick` — the work the
## civilian pass would put its crews to, the call THE CROWN'S PEOPLE prints —
## merged with `MapPlayArmyOrdersPick` — the orders the land pass would give its
## hosts, the call THE CROWN'S ARMY prints — narrowed to the provinces the crown
## holds, exactly as the province dossier narrows them (MapPlayProvinceCounsel),
## so the realm cannot name a raise or a march either sheet would refuse
## (REQ-P2-03, REQ-P3-03).
##
## Each pass is asked once for the whole realm, never once a province, so a crown
## holding twenty provinces costs two plan reads and not forty (REQ-P4-01).
##
## A reading only: nothing here sets an order, marches a host or spends a
## material, and the crown still presses her own rows (REQ-P5-06).

## The court would act in at least one of the crown's own provinces.
const KIND_ORDERS: String = "orders"
## The passes ran, crews or hosts waited, and nothing lands on the crown's ground.
const KIND_NONE: String = "none"

## The gate a silent pass earns across the realm: crews or hosts stood for an
## order and the passes booked none of it on the crown's own ground.
const NO_ORDER_LINE: String = (
	"the court would order no work or march on its own ground this turn"
)


## The sheet's sentence: the pick's own line, capitalised and closed — the one
## wording every pick surface prints (MapPlayPickProse; REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession) -> String:
	return MapPlayPickProse.sentence_of(pick(play))


## The realm's pick as the sheet prints it: `{kind, provinces, keys, line}`, where
## each province is `{region, province, name, crews, armies}` and `keys` holds
## `"region:province"` for every one of them. Empty when the session runs no
## planner for the crown, an observer session, a decided campaign, a crown with
## no ledger, a session with no civilian layer, or a realm neither pass would act
## in.
static func pick(play: PlaySession) -> Dictionary:
	if not MapPlayPickProse.crown_crew_ready(play):
		return {}
	var crews: Dictionary = MapPlayPeoplePick.pick(play)
	var armies: Dictionary = MapPlayArmyOrdersPick.pick(play)
	var acted: Array[Dictionary] = []
	var held: int = 0
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != play.player_faction:
				continue
			held += 1
			var counsel: Dictionary = MapPlayProvinceCounsel.from_picks(
				play, model, province.id, crews, armies
			)
			# The dossier's gate is about one ground; the realm only marks the
			# provinces the court would actually put to work or send a host to.
			if counsel.is_empty():
				continue
			if String(counsel.get("kind", "")) != MapPlayProvinceCounsel.KIND_ORDERS:
				continue
			acted.append({
				"region": region,
				"province": province.id,
				"name": String(province.name),
				"crews": counsel.get("crews", []),
				"armies": counsel.get("armies", []),
			})
	if acted.is_empty():
		return gate(_waited(crews, armies))
	return of(acted, held)


## The gate a silent pass earns across the realm: one of the passes named the
## rows it left waiting, so the sheet says so rather than printing a clause it
## cannot say. A realm with nothing waiting has nothing to say (REQ-P5-06).
static func gate(waited: bool) -> Dictionary:
	if not waited:
		return {}
	return {"kind": KIND_NONE, "provinces": [], "keys": {}, "line": NO_ORDER_LINE}


## The pick, worded off the provinces the court would act in: one line naming
## the count against the realm it holds, then the first places, so a crown reads
## how much of her ground her own staff would touch. Pure — a sheet and its suite
## drive it without a session.
static func of(provinces: Array[Dictionary], held: int) -> Dictionary:
	if provinces.is_empty():
		return {}
	var keys: Dictionary = {}
	var places: Array[String] = []
	for province: Dictionary in provinces:
		keys[_key(province)] = true
		var name: String = String(province.get("name", ""))
		if not name.is_empty():
			places.append(name)
	if places.is_empty():
		return {}
	return {
		"kind": KIND_ORDERS,
		"provinces": provinces,
		"keys": keys,
		"line": pick_line(places, held),
	}


## "the court would act in 3 of its 14 provinces this turn — Cádiz, Tucapel and
## Jaén". Beyond three the line counts the places it cannot name (`… and 2 more`)
## so a wide realm stays one line of chrome (REQ-P5-07).
static func pick_line(places: Array[String], held: int) -> String:
	if places.is_empty():
		return ""
	var named: String = MapPlayPickProse.capped(places, MapPlayPickProse.NAMED_LIMIT)
	return "%s this turn — %s" % [_head(places.size(), maxi(held, places.size())), named]


## The count the line opens with, in words that read at every size: one province,
## the whole realm, or the part of it the court would touch.
static func _head(count: int, held: int) -> String:
	if held <= 1:
		return "the court would act in the one province it holds"
	if count >= held:
		return "the court would act in every one of its %d provinces" % held
	return "the court would act in %d of its %d provinces" % [count, held]


## The key a row and a province share: the chart it stands on and its own id,
## because province ids are minted per chart (REQ-P2-03).
static func _key(province: Dictionary) -> String:
	return "%d:%d" % [
		int(province.get("region", -1)), int(province.get("province", -1))
	]


## Whether a silent pass left anyone waiting: the two sheets' own gate lines, so
## the realm never guesses at a gate its sources did not name.
static func _waited(crews: Dictionary, armies: Dictionary) -> bool:
	if String(crews.get("line", "")) == MapPlayPeoplePick.NO_WORK_LINE:
		return true
	return String(armies.get("line", "")) == MapPlayArmyOrdersPick.NO_ORDER_LINE