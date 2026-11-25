class_name ResourceSlots
extends RefCounted
## Works out how many resource rows of each class a region's provinces receive
## before any is placed (wiki: resource-terrain-region-rules § Placement rate,
## § Open-ground split). The seeder spends the plan; this class only splits it.

## Share of the New World's open-ground slots that price the exclusive
## money-makers instead of the `both`-scope ores (issue #1520).
const MONEY_SHARE: float = 0.60
## The published New World riches floor: the plan aims this many rich rows at the
## hills, peaks and desert rather than leaving them to the moisture field's roll
## (issue #1520).
const RICH_FLOOR: int = 100


## The per-province plan: how many cash-crop rows, rich rows, exclusive-seam
## (tin) rows, and shared ore rows each province spends. The Old World keeps the
## published draw, so its whole slice rides in `ore`.
##
## The New World's classes are split by the ground that hosts them, not by the
## province's open-tile slice: a plains block spends its share on crops while a
## swamp block spends its share on ore, so the region keeps the published 60:40
## exclusive:both split however unevenly the cover falls (issue #1520).
static func plan(
	model: MapModel,
	table: Array[Dictionary],
	open: Array[Array],
	quotas: Array[int],
	places: int
) -> Dictionary:
	var count: int = open.size()
	var cash: Array[int] = _zeros(count)
	var rich: Array[int] = _zeros(count)
	var seam: Array[int] = _zeros(count)
	var ore: Array[int] = _zeros(count)
	if model.region_id != FactionCatalog.NEW_WORLD:
		return {"cash": cash, "rich": rich, "seam": seam, "ore": quotas.duplicate()}
	var cash_ground: Array[int] = []
	var rich_ground: Array[int] = []
	var seam_ground: Array[int] = []
	var shared_ground: Array[int] = []
	var cash_all: int = 0
	var rich_all: int = 0
	for index in count:
		var plains: int = ResourceGround.money_ground_count(model, table, open[index], true)
		var high: int = ResourceGround.money_ground_count(model, table, open[index], false)
		var exclusive: int = ResourceGround.exclusive_seam_count(model, table, open[index])
		var all_seams: int = ResourceGround.class_count(model, table, open[index], false)
		cash_ground.append(plains)
		rich_ground.append(high)
		seam_ground.append(exclusive)
		shared_ground.append(all_seams - exclusive)
		cash_all += plains
		rich_all += high
	var money_total: int = int(round(float(places) * MONEY_SHARE))
	var rich_target: int = int(round(
		float(money_total) * float(rich_all) / float(maxi(cash_all + rich_all, 1))
	))
	# The published riches floor is an aim, not a roll of the moisture field.
	rich_target = mini(money_total, maxi(rich_target, RICH_FLOOR))
	cash = _capped_split(cash_ground, cash_ground, money_total - rich_target)
	rich = _capped_split(rich_ground, rich_ground, rich_target)
	_keep_floor(cash, rich, cash_ground, rich_ground)
	var ore_total: int = maxi(0, places - money_total)
	seam = _capped_split(seam_ground, seam_ground, ore_total)
	ore = _capped_split(shared_ground, shared_ground, ore_total - _sum(seam))
	return {"cash": cash, "rich": rich, "seam": seam, "ore": ore}


## Largest-remainder split of `left` places over the provinces' eligible tiles.
static func quotas(weights: Array[int], total: int, left: int) -> Array[int]:
	var result: Array[int] = []
	var remainders: Array[float] = []
	var spent: int = 0
	for weight: int in weights:
		var exact: float = float(left) * float(weight) / float(maxi(total, 1))
		var whole: int = mini(int(floor(exact)), weight)
		result.append(whole)
		remainders.append(exact - float(whole))
		spent += whole
	var order: Array[int] = rank(remainders)
	var cursor: int = 0
	while spent < left and cursor < order.size():
		var index: int = order[cursor]
		if result[index] < weights[index]:
			result[index] += 1
			spent += 1
		cursor += 1
	return result


## Largest-remainder split of `left` over `weights`, never above a cap. Left-over
## places walk the order again until none fit.
static func _capped_split(
	weights: Array[int], caps: Array[int], left: int
) -> Array[int]:
	var result: Array[int] = _zeros(weights.size())
	if left <= 0:
		return result
	var total: int = _sum(weights)
	var remainders: Array[float] = []
	var spent: int = 0
	for index in weights.size():
		var exact: float = float(left) * float(weights[index]) / float(maxi(total, 1))
		var whole: int = mini(int(floor(exact)), caps[index])
		result[index] = whole
		remainders.append(exact - float(whole))
		spent += whole
	var order: Array[int] = rank(remainders)
	while spent < left:
		var progressed: bool = false
		for index: int in order:
			if spent >= left:
				break
			if result[index] < caps[index]:
				result[index] += 1
				spent += 1
				progressed = true
		if not progressed:
			break
	return result


## Provincial indices ordered by descending remainder, ties to the lower id.
static func rank(remainders: Array[float]) -> Array[int]:
	var order: Array[int] = []
	for index in remainders.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(remainders[a], remainders[b]):
			return a < b
		return remainders[a] > remainders[b]
	)
	return order


## Raises every province's money rows to the published floor, over its slice
## when it must.
static func _keep_floor(
	cash: Array[int], rich: Array[int], cash_ground: Array[int], rich_ground: Array[int]
) -> void:
	for index in cash.size():
		var want: int = mini(
			ResourceGround.PROVINCE_MONEY_MARGIN, cash_ground[index] + rich_ground[index]
		)
		var short: int = want - cash[index] - rich[index]
		if short <= 0:
			continue
		var from_plains: int = mini(short, cash_ground[index] - cash[index])
		cash[index] += from_plains
		rich[index] += mini(short - from_plains, rich_ground[index] - rich[index])


static func _sum(values: Array[int]) -> int:
	var total: int = 0
	for value: int in values:
		total += value
	return total


static func _zeros(count: int) -> Array[int]:
	var values: Array[int] = []
	values.resize(count)
	values.fill(0)
	return values