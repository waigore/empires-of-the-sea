class_name BattlePlates
extends RefCounted
## The turn's battle plates: the land Quick Battle plate and the sea's despatch,
## queued in the order the turn resolved them (land first, `MapPlayTurn`) and the
## court's news held while either is up (wiki: quick-battle, ships-and-naval
## § Naval Combat Resolution; REQ-P5-06). Owns no node and decides no rule — the
## views paint what the resolvers reported.

var land_plate: QuickBattleOverlay = null
var sea_plate: NavalPlate = null
var despatches: HudDespatches = null
## Engagements waiting their turn, oldest first.
var land_queue: Array[Dictionary] = []
var sea_queue: Array[Dictionary] = []


## Binds the two plates and the news lane, so a plate closing serves the next
## engagement itself and never needs the HUD to poll.
func attach(land: QuickBattleOverlay, sea: NavalPlate, news: HudDespatches) -> void:
	land_plate = land
	sea_plate = sea
	despatches = news
	if land_plate != null:
		land_plate.finished.connect(finish)
	if sea_plate != null:
		sea_plate.finished.connect(finish)


## Raises a land engagement, or queues it behind the plate already up.
func show_land(battle: Dictionary, province: String, names: Array) -> void:
	if land_plate == null or despatches == null:
		return
	if land_plate.is_shown() or is_sea_shown():
		land_queue.append({"battle": battle, "province": province})
		return
	despatches.set_covered(true)
	land_plate.show_battle(battle, province, names)


## Raises a sea engagement, or queues it behind either plate.
func show_sea(battle: Dictionary, zone: String, names: Array) -> void:
	if sea_plate == null or despatches == null:
		return
	if sea_plate.is_shown() or (land_plate != null and land_plate.is_shown()):
		sea_queue.append({"battle": battle, "zone": zone})
		return
	despatches.set_covered(true)
	sea_plate.show_engagement(battle, zone, names)


func is_sea_shown() -> bool:
	return sea_plate != null and sea_plate.is_shown()


## A plate closed: the next engagement of the turn takes the court, land first,
## or the news the turn raised while the fighting played finally reaches it.
func finish() -> void:
	if not land_queue.is_empty() and land_plate != null:
		var next: Dictionary = land_queue.pop_front()
		land_plate.show_battle(
			next["battle"], String(next["province"]), FactionCatalog.names()
		)
		return
	if not sea_queue.is_empty() and sea_plate != null:
		var sea: Dictionary = sea_queue.pop_front()
		sea_plate.show_engagement(sea["battle"], String(sea["zone"]), FactionCatalog.names())
		return
	if despatches != null:
		despatches.set_covered(false)
