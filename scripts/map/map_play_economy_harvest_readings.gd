class_name MapPlayEconomyHarvestReadings
extends RefCounted
## The larder and labour readings one economy court hires against: the harvest
## slack its land carries, the slack the hire paces itself by, and the hands the
## levy and the yard keep back (REQ-P2-03; DR-20261122-01).
##
## `MapPlayEconomyCourt` owns the plan and the application; this module owns the
## read-only figures both halves share, so a court's own hire and the counsel a
## sheet prints cannot disagree about what its fields can bear. Pure: nothing
## here recruits a worker or spends a ducat.


## The harvest slack the court's land carries — the ration food the extraction
## just landed, less every mouth the consumption phase feeds (issue #807), or the
## `-2` sentinel when there is no harvest to read or no AI pass beside it. The
## muster's growth gate and the provision premium both read it, so a court
## desires its larger army and provisions the food income first. Pure: the
## reading the pass notes and the worker hire reads are the same figure
## (REQ-P2-03; DR-20261122-01).
static func harvest_slack(court: MapPlayEconomyCourt) -> int:
	var harvest: Dictionary = court.overseas.get("extraction", {}) as Dictionary
	if harvest.is_empty() or court.play.ai == null or court.economy == null:
		return -2
	# The harvest's ration food, counted the Consumption phase's way, so the
	# growth gate plans with the same total the phase would eat (REQ-P2-03).
	var harvest_food: int = EconomyConsumption.food_available(harvest)
	return harvest_food - MapPlayEconomyLarder.food_demand(
		court.play, court.faction, court.economy
	)


## The harvest slack the hire reads: this turn's own figure where the land has a
## harvest to count, else the pass's own note, else the `-2` sentinel (no
## reading). The one home for the figure `MapPlayEconomyCourt.book_orders`
## hires against.
static func harvest_reading(court: MapPlayEconomyCourt) -> int:
	var slack: int = harvest_slack(court)
	if slack == -2 and court.play.ai != null:
		return int(court.play.ai.food_slack.get(court.faction, -2))
	return slack


## The larder slack the worker hire reads: the harvest's own figure narrowed by
## the pass's note when there is no harvest in hand — the `-1` sentinel (no
## larder to read) is the published default. `AiBindEconomy.fed_slack` is the
## call `apply_turn` has always hired against (issue #489; DR-20261122-01).
static func fed_slack(court: MapPlayEconomyCourt) -> int:
	var fed: int = AiBindEconomy.fed_slack(
		court.kind, court.economy, court.army_food, court.ships
	)
	if court.play.ai != null and (court.play.ai.food_slack as Dictionary).has(court.faction):
		fed = mini(fed, int(court.play.ai.food_slack[court.faction]))
	return fed


## The hand the worker hire keeps in the fields: the muster's own reservation
## (issue #807) plus the peasant the yard keeps for the hull it is banking
## (issue #1126), so a court that musters buys no worker its levy would consume.
static func muster_hands(court: MapPlayEconomyCourt) -> int:
	if court.kind == AiControl.KIND_BASELINE:
		return 0
	var navy_hand: int = AiNavy.hands(
		court.economy, MapPlayCourt.hull_types(court.play, court.faction), court.hull_chest
	)
	return AiArmyReinforce.muster_hands(
		court.config, court.economy, court.regiments, court.at_war
	) + navy_hand
