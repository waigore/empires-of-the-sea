class_name NavalDeck
extends RefCounted
## What a squadron's deck can hold, and what the sea takes when a hull goes
## down: one hull carries one regiment or one colonist (wiki: ships-and-naval
## § Naval transport, § Losses; DR-20261109-08). Pure rules: callers apply the
## result, this module never touches nodes (REQ-P3-03).
##
## Split from [NavalTransport] so the orders that fill a deck and the capacity
## they must obey answer from one place (REQ-P3-01). The roster repair, the
## yard's break-up gate and the bar's loss lines all read the same count here,
## so a deck can never be asked to hold more than its hulls.


## Regiments the squadron can carry: one per hull.
static func capacity(fleet: FleetState) -> int:
	if fleet == null:
		return 0
	return fleet.ship_count()


## Passengers the squadron actually carries: the army's regiments plus any
## colonists (wiki: ships-and-naval § Naval transport, § Civilian passengers).
static func aboard(fleet: FleetState, army: ArmyState) -> int:
	if fleet == null:
		return 0
	var men: int = 0 if army == null else army.count()
	return fleet.civilian_count() + men


## A squadron that loses hulls keeps only the passengers the deck still holds:
## one hull carries one regiment or one colonist, so a hull that goes down takes
## her passenger with her (wiki: ships-and-naval § Naval transport — "each hull
## carries one regiment"; § Losses — "a squadron sunk in naval combat takes its
## embarked army with it"). The repair is read at the turn's close, because a
## victor still loses hulls to the beaten side's strength and a raid sinks a
## prize: either can leave a deck shorter than the men it carried, which the
## published capacity forbids. Regiments drown weakest-first, as a battle's
## casualties are drawn ([method ArmyForce.apply_losses]); colonists drown last
## boarded first, so the answer is deterministic and the roster order stays the
## record. A squadron the sea empties loses her seat with the men.
## Returns {"regiments": [ids], "civilians": [ids]} — what the deck could not hold.
static func trim_aboard(fleet: FleetState, army: ArmyState) -> Dictionary:
	var drowned: Dictionary = {
		"regiments": [] as Array[String],
		"civilians": [] as Array[int],
	}
	if fleet == null:
		return drowned
	var deck: int = fleet.ship_count()
	var colonists: Array[int] = drowned["civilians"]
	while fleet.civilian_count() > deck:
		colonists.append(int(fleet.embarked_civilians.pop_back()))
	if army == null or fleet.embarked_army < 0:
		return drowned
	var room: int = maxi(deck - fleet.civilian_count(), 0)
	var over: int = army.count() - room
	if over <= 0:
		return drowned
	var only: Array[ArmyState] = [army]
	drowned["regiments"] = ArmyForce.apply_losses(only, only, over, 0)
	if army.is_empty():
		fleet.embarked_army = -1
		army.embarked_fleet = -1
	return drowned


## The bar's lines for a squadron that drowned her surplus, one per kind, and
## none when nobody went down (REQ-P5-05, wiki: hud-toasts). Read from a row of
## [method ArmyTransport.reconcile_aboard], so the news names the same loss the
## roster lost.
static func drown_news(row: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var men: Array = row.get("regiments", [])
	if not men.is_empty():
		lines.append(
			"%d regiment%s went down with the sunk hulls — the deck could not hold them"
			% [men.size(), "" if men.size() == 1 else "s"]
		)
	if not (row.get("civilians", []) as Array).is_empty():
		lines.append("A colonist went down with a sunk hull")
	return lines


## Breaking up a hull must not leave more regiments or colonists aboard than
## hulls afloat.
static func can_scrap(fleet: FleetState, army: ArmyState) -> Dictionary:
	if fleet == null:
		return OrderVerdict.allow()
	var aboard: int = fleet.civilian_count()
	if fleet.embarked_army >= 0 and army != null:
		aboard += army.count()
	if fleet.ship_count() - 1 < aboard:
		return OrderVerdict.deny(
			"The squadron cannot break up a hull while it carries %d passengers."
			% aboard
		)
	if fleet.embarked_army < 0:
		return OrderVerdict.allow()
	if army == null:
		return OrderVerdict.deny("The troops aboard cannot be accounted for.")
	return OrderVerdict.allow()
