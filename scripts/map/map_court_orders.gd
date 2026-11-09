class_name MapCourtOrders
extends RefCounted
## Routes court intents from the ledger: answers to a waiting call to arms or
## intervention belong to the turn resolver; every other intent is a diplomatic
## order. Keeps MapScreen's wiring thin (REQ-P3-01) and keeps the rules layer
## free of node deps (REQ-P3-03).


static func apply(play: PlaySession, kind: String, target: int, arg: String) -> void:
	if kind == CallToArms.KIND_JOIN or kind == CallToArms.KIND_REFUSE:
		MapPlayTurn.answer_call(play, kind == CallToArms.KIND_JOIN)
		return
	if kind in [
		Intervention.KIND_INTERVENE,
		Intervention.KIND_NOTHING,
		Intervention.KIND_PROTEST,
	]:
		MapPlayTurn.answer_intervention(play, kind)
		return
	MapPlayDiplomacy.on_order(play, kind, target, arg)
