class_name MapPlayYardPick
extends RefCounted
## What the court's own yard means to lay: the hull the published naval policy
## sends the crown's slip for, and the gate that holds her back (wiki:
## ships-and-naval § Ship build economy, § Ship muster; treasury-planner
## § Priority, ai-architecture § Naval policy; DR-20261121-02).
##
## The plan is not a second opinion: it is `AiNavy`'s own reading — the claim
## `navy.build` is priced on (`AiNavy.due`), the hull the yard would lay down
## today or the gate that refuses her (`AiNavy.laying`), and the hull the court
## means to lay while it waits (`AiNavy.saving_type`, `AiNavy.unlock_tech`).
## `MapPlayCourtHoldings.navy_chest`, the campus's own fleet claim, reads the same three
## calls, so the advice and the chest cannot disagree (REQ-P2-03).
##
## A reading only: nothing here launches a hull, spends a ducat, takes a worker
## or moves a queue, and the crown still presses her own Launch (REQ-P3-03,
## REQ-P5-06).

## The yard can pay for her today: the hull it would lay.
const KIND_LAY: String = "lay"
## The yard refuses, and the purse is why: the hull the claim is saved for.
const KIND_SAVING: String = "saving"
## The yard refuses, and a study is why: the door the saving hull waits on.
const KIND_STUDY: String = "study"
## The yard refuses with the purse already full: the stores or the pool are why,
## and the line names the yard's own gate rather than a purse that is not short
## (wiki: ships-and-naval § Ship build economy; DR-20261121-02).
const KIND_STORES: String = "stores"


## The hull one court's yard means to lay, as the sheet reads it: `{kind, type,
## chest, price, study, line}`. Empty when the court is not rebuilding its navy
## (a fleet that already matches its enemies, no war at all, or warships its techs
## open), when the campaign is decided, when the session runs no planner, or when
## the catalogue opens no warship to save for. A refusing yard names the gate
## that actually holds her: the study, the purse, or the yard's own word for the
## stores and the hand (`KIND_STORES`).
static func pick(play: PlaySession) -> Dictionary:
	if play == null or play.economy == null or play.economy.economy == null:
		return {}
	if play.diplomacy == null or play.ship_layer == null or play.campaign_over():
		return {}
	var faction: int = play.player_faction
	if AiControl.court_kind(play, faction) == AiControl.KIND_NONE:
		return {}
	var economy: PlayerEconomy = play.economy.economy
	return counsel(
		economy,
		MapPlayCourt.at_war(play, faction),
		MapPlayCourtHoldings.warships(play, faction),
		MapPlayCourtHoldings.hostile_warships(play, faction),
		MapPlayCourtHoldings.hull_types(play, faction),
		MapPlayCourtHoldings.navy_chest(play, faction)
	)


## The yard's own answer, given a court's ledger, footing and fleet claim: the
## hull the yard would lay down (its techs and purse allowing), else the hull the
## claim is saved for with the gate that stops it. Pure: the same gates the slip
## and the chest read, and no write anywhere.
static func counsel(
	economy: PlayerEconomy,
	at_war: bool,
	warships: int,
	hostile_warships: int,
	flown: Array[String] = [],
	chest: int = 0
) -> Dictionary:
	if economy == null:
		return {}
	# The claim is the published one: a court at war short of hulls, or one with
	# no fighting hull at all, means to lay one down (issue #484, #500).
	if not AiNavy.due(at_war, warships, hostile_warships):
		return {}
	var laying: Dictionary = AiNavy.laying(economy, flown)
	var type_id: String = String(laying.get("type_id", ""))
	if not type_id.is_empty():
		var line: String = MapPlayYardPickWords.lay_line(type_id)
		if line.is_empty():
			return {}
		return {
			"kind": KIND_LAY,
			"type": type_id,
			"chest": chest,
			"price": ShipEconomy.treasury_cost(type_id),
			"study": "",
			"line": line,
		}
	# The yard refuses: name the hull the claim is saved toward, and the gate it
	# waits on — the study the door asks for, else the purse that is filling,
	# else the yard's own word for the stores or the hand it cannot pay with
	# (wiki: ships-and-naval § Ship build economy; DR-20261121-02).
	var saving: String = AiNavy.saving_type(economy, flown)
	if saving.is_empty():
		return {}
	var door: String = AiNavy.unlock_tech(economy, flown)
	var price: int = AiNavy.price(economy, flown)
	var kind: String = KIND_STUDY
	var say: String = ""
	if not door.is_empty():
		say = MapPlayYardPickWords.study_line(saving, door)
	elif economy.treasury < price:
		kind = KIND_SAVING
		say = MapPlayYardPickWords.saving_line(saving, price, economy.treasury)
	else:
		# The purse already covers her row, so it is not the gate: the yard's
		# own refusal is (`Insufficient materials`, `Insufficient workers`).
		kind = KIND_STORES
		say = MapPlayYardPickWords.gate_line(saving, String(laying.get("reason", "")))
	if say.is_empty():
		return {}
	return {
		"kind": kind,
		"type": saving,
		"chest": chest,
		"price": price,
		"study": door,
		"line": say,
	}


## The sheet's line: the pick's own sentence, or nothing when the court's yard
## means to lay nothing this turn.
static func line(play: PlaySession) -> String:
	return MapPlayPickProse.sentence_of(pick(play))
