extends SceneTree
## Headless free-playtest drive: plays a real campaign turn by turn and checks
## the wiki's standing invariants after every close (wiki: ships-and-naval
## § Fleet location / § Home Fleet / § Naval transport / § Ship instances;
## diplomacy § Relation Model / § Boycott / § Set Subsidy; world-market
## § Price discovery). A violation is a rules defect, not a display nit.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_invariants.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const MAX_TURNS: int = 24

var _steps: PackedStringArray = PackedStringArray()
var _violations: Array[String] = []
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(
		self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100
	)
	if _screen == null:
		_finish()
		return
	var play: PlaySession = _screen.play
	_say("seed %s · turn %d · player %s" % [
		SEED_TEXT, play.turn, FactionCatalog.name_of(play.player_faction),
	])
	_check(play, "opening")
	_dump(play)
	for _index in MAX_TURNS:
		if play.campaign_over():
			_say("campaign closed at turn %d" % play.turn)
			break
		_end_turn(play)
		_check(play, "turn %d" % play.turn)
	_finish()


# --- the invariants ---------------------------------------------------------


func _check(play: PlaySession, label: String) -> void:
	_check_fleets(play, label)
	_check_armies(play, label)
	_check_relations(play, label)
	_check_prices(play, label)


## military-armies § Definition / § Home Army: every land regiment stands in
## exactly one army, an army occupies exactly one province (an embarked one
## none), and every Great Power keeps exactly one Home Army at its seat.
func _check_armies(play: PlaySession, label: String) -> void:
	if play.army_layer == null:
		return
	var seen_regiments: Dictionary = {}
	var homes: Dictionary = {}
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array = play.army_layer.regions.value(region, [])
		for raw: Variant in roster:
			var army: ArmyState = raw as ArmyState
			if army == null:
				continue
			for regiment_id: String in army.regiments:
				if seen_regiments.has(regiment_id):
					_violation(label, "regiment %s stands in two armies (%d and %d)" % [
						regiment_id, int(seen_regiments[regiment_id]), army.id,
					])
				seen_regiments[regiment_id] = army.id
			if army.is_embarked():
				continue
			if army.province == MapModel.NO_ID or model.province_data(army.province) == null:
				_violation(label, "army %d of %s holds no province" % [
					army.id, FactionCatalog.name_of(army.owner),
				])
			if army.home:
				homes[army.owner] = int(homes.get(army.owner, 0)) + 1
				var capital: int = play.world.capital_province_of(region, army.owner)
				if capital != MapModel.NO_ID and army.province != capital:
					_violation(label, "Home Army %d of %s stands at %s, not its seat %s" % [
						army.id, FactionCatalog.name_of(army.owner),
						model.province_name(army.province), model.province_name(capital),
					])
	for faction: int in FactionCatalog.great_power_ids():
		if int(homes.get(faction, 0)) > 1:
			_violation(label, "%s keeps %d Home Armies" % [
				FactionCatalog.name_of(faction), int(homes[faction]),
			])


## ships-and-naval § Fleet location: a fleet in port is attached to a province
## its owner holds. § Home Fleet: only the home fleet may be in port at the
## capital. § Naval transport: a hull carries one regiment or one civilian.
## § Ship instances: one id, one fleet.
func _check_fleets(play: PlaySession, label: String) -> void:
	var seen_hulls: Dictionary = {}
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var fleets: Array[FleetState] = []
		fleets.assign(play.ship_layer.regions.value(region, []))
		var in_port_at_capital: Dictionary = {}
		for fleet: FleetState in fleets:
			if fleet == null:
				continue
			for hull_id: String in fleet.hulls:
				# One instance id, one fleet, across every chart (wiki:
				# ships-and-naval § Ship instances).
				if seen_hulls.has(hull_id):
					_violation(label, "hull %s sails in two fleets (%d and %d)" % [
						hull_id, int(seen_hulls[hull_id]), fleet.id,
					])
				seen_hulls[hull_id] = fleet.id
			if fleet.is_in_port():
				var data: ProvinceState = model.province_data(fleet.province)
				if data == null:
					_violation(label, "fleet %d in port at unknown province %d" % [
						fleet.id, fleet.province,
					])
				elif data.owner != fleet.owner:
					_violation(label, "fleet %d of %s in port at %s, held by %s" % [
						fleet.id, FactionCatalog.name_of(fleet.owner),
						model.province_name(fleet.province),
						FactionCatalog.name_of(data.owner),
					])
				var capital: int = play.world.capital_province_of(region, fleet.owner)
				if capital != MapModel.NO_ID and fleet.province == capital:
					var key: String = "%d:%d" % [fleet.owner, fleet.province]
					in_port_at_capital[key] = int(in_port_at_capital.get(key, 0)) + 1
			var aboard: int = fleet.civilian_count()
			if fleet.embarked_army >= 0:
				var army: ArmyState = _army(play, fleet.embarked_army)
				if army != null:
					aboard += army.count()
			if aboard > fleet.ship_count():
				_violation(label, "fleet %d carries %d aboard on %d hulls" % [
					fleet.id, aboard, fleet.ship_count(),
				])
		for key: String in in_port_at_capital.keys():
			if int(in_port_at_capital[key]) > 1:
				_violation(label, "%d squadrons in port at the capital of %s" % [
					int(in_port_at_capital[key]), key,
				])


## diplomacy § Relation Model: the score is a decimal in [0, 100] and war never
## stands with a formal alliance. § Boycott: the issuer holds a colony and the
## pair is at peace. § Set Subsidy: Minor/Tribe only, 5–20 in steps of 5, and an
## embassy stands.
func _check_relations(play: PlaySession, label: String) -> void:
	var state: DiplomacyState = play.diplomacy
	if state == null:
		return
	for record: DiplomacyRelation in state.relations.values():
		if record.score < 0.0 or record.score > 100.0:
			_violation(label, "relation %d:%d scores %.1f" % [
				record.a, record.b, record.score,
			])
		if record.at_war and record.formal_alliance:
			_violation(label, "relation %d:%d is at war and allied" % [
				record.a, record.b,
			])
	for key: String in state.boycotts.keys():
		var parts: PackedStringArray = key.split(">")
		var issuer: int = int(parts[0])
		var target: int = int(parts[1])
		if not _holds_colony(state, issuer):
			_violation(label, "boycott %s stands without a colony" % key)
		var record: DiplomacyRelation = state.relation(issuer, target)
		if record != null and record.at_war:
			_violation(label, "boycott %s stands at war" % key)
	for key: String in state.subsidies.keys():
		var parts: PackedStringArray = key.split(">")
		var payer: int = int(parts[0])
		var target: int = int(parts[1])
		var percent: int = int(state.subsidies[key])
		var kind: int = FactionCatalog.type_of(target)
		if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
			_violation(label, "subsidy %s pays a court that is no Minor or Tribe" % key)
		if not DiplomacyCatalog.is_valid_subsidy(percent):
			_violation(label, "subsidy %s pays %d%%" % [key, percent])
		if not DiplomacyRules.has_embassy(state, payer, target):
			_violation(label, "subsidy %s stands without an embassy" % key)


## world-market § Price discovery: the published price never falls below 30% of
## the commodity's default.
func _check_prices(play: PlaySession, label: String) -> void:
	var market: WorldMarket = play.economy.market
	if market == null:
		return
	for commodity: String in market.prices.keys():
		var price: int = int(market.prices[commodity])
		var base: int = CommodityCatalog.base_price(commodity)
		if base <= 0:
			continue
		var floor_price: int = int(floor(float(base) * 0.3))
		if price < floor_price:
			_violation(label, "%s clears at %d, under the %d floor" % [
				commodity, price, floor_price,
			])


# --- helpers ----------------------------------------------------------------


func _dump(play: PlaySession) -> void:
	for region in play.world.region_count():
		var fleets: Array[FleetState] = []
		fleets.assign(play.ship_layer.regions.value(region, []))
		_say("--- region %d: %d fleets ---" % [region, fleets.size()])
		for fleet: FleetState in fleets:
			if fleet == null:
				continue
			_say("  fleet %d %s %s %s hulls=%s" % [
				fleet.id, FactionCatalog.name_of(fleet.owner),
				"port" if fleet.is_in_port() else "sea",
				str(fleet.province if fleet.is_in_port() else fleet.sea_zone),
				",".join(fleet.hulls),
			])


func _holds_colony(state: DiplomacyState, gp: int) -> bool:
	for tribe: int in state.colonies.keys():
		if int(state.colonies[tribe]) == gp:
			return true
	return false


func _army(play: PlaySession, army_id: int) -> ArmyState:
	for region in play.world.region_count():
		var roster: Array = play.army_layer.regions.value(region, [])
		for raw: Variant in roster:
			var army: ArmyState = raw as ArmyState
			if army != null and army.id == army_id:
				return army
	return null


func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	for _attempt in 12:
		MapPlayTurn.end_turn(play)
		if play.turn != start_turn:
			return
		var human: int = play.player_faction
		if CallToArms.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, CallToArms.KIND_REFUSE, human, "")
		elif Intervention.has_pending(play.diplomacy, human):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, human, "")
		else:
			return
		if play.turn != start_turn:
			return
	_say("the turn would not close")


func _violation(label: String, line: String) -> void:
	_violations.append("%s: %s" % [label, line])
	print("VIOLATION ", label, ": ", line)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	_say("")
	_say("--- %d violation(s) ---" % _violations.size())
	for line: String in _violations:
		_say("  " + line)
	quit()
