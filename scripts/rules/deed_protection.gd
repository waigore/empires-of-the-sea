class_name DeedProtection
extends RefCounted
## Ground a crown has bought and will defend (wiki: diplomacy § GP–Minor Rules
## § Intervention — the trigger is "an Embassy with that Minor/Tribe **or**
## purchased land recorded in its provinces", the investment-protection half of
## that rule; DR-20261110-20). Pure reads over WorldMap: the intervention trial,
## the rival war planner and the court copy all count the same deeds
## (REQ-P2-03, REQ-P3-03).
##
## A deed is counted only while the victim still owns the province: a province
## the victim has lost takes the deed with it (Intervention docs, same rule).

## Deeds a crown must hold before it treats the victim as worth protecting. One
## deed is already a paid-for stake; the second makes the court a serious
## protector, so the intervention bands step up as the holding grows.
const PROTECT_MIN_DEEDS: int = 1
const SERIOUS_DEEDS: int = 2


## Every tile `court` has bought inside a province `target` owns right now.
## Row-major order so callers print the same holding every turn.
static func deeds(world: WorldMap, court: int, target: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if world == null or court < 0 or target < 0 or court == target:
		return tiles
	for model: MapModel in world.regions:
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != target:
				continue
			for tile: Vector2i in province.tiles:
				if model.ownership.purchaser(model.index_of(tile.x, tile.y)) == court:
					tiles.append(tile)
	tiles.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
	)
	return tiles


static func deed_count(world: WorldMap, court: int, target: int) -> int:
	return deeds(world, court, target).size()


static func holds_deed(world: WorldMap, court: int, target: int) -> bool:
	return deed_count(world, court, target) > 0


## What the deeds would cost to buy again today: the merchant's 15 × base price
## per tile. The purse a crown has sunk into the victim's land is the honest
## measure of how much it stands to lose (wiki: civilian-units § Merchant).
static func stake_value(world: WorldMap, court: int, target: int) -> int:
	var total: int = 0
	if world == null:
		return total
	for model: MapModel in world.regions:
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != target:
				continue
			for tile: Vector2i in province.tiles:
				if model.ownership.purchaser(model.index_of(tile.x, tile.y)) == court:
					total += LandPurchase.cost(model, tile)
	return total


## True when the holding is worth a diplomatic stand (one deed is enough; the
## constant is the tunable threshold the DR names).
static func worth_protecting(world: WorldMap, court: int, target: int) -> bool:
	return deed_count(world, court, target) >= PROTECT_MIN_DEEDS


## True when the holding is big enough to make the court a serious protector.
static func serious_stake(world: WorldMap, court: int, target: int) -> bool:
	return deed_count(world, court, target) >= SERIOUS_DEEDS


## Every Great Power holding a deed in the victim's provinces, ascending id.
static func holders(world: WorldMap, target: int) -> Array[int]:
	var found: Array[int] = []
	if world == null or target < 0:
		return found
	for court: int in FactionCatalog.great_power_ids():
		if court != target and holds_deed(world, court, target):
			found.append(court)
	return found


## Player-facing phrase for a holding: "2 deeds" / "a deed".
static func holding_text(world: WorldMap, court: int, target: int) -> String:
	var count: int = deed_count(world, court, target)
	if count <= 0:
		return ""
	if count == 1:
		return "a deed"
	return "%d deeds" % count
