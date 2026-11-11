class_name VictoryRules
extends RefCounted
## Campaign victory (wiki: victory § Current scope: military victory only).
## Pure rules over the world map — no nodes, so the check runs headless and the
## HUD only renders the record it returns (REQ-P2-03, REQ-P3-03).

## The published bar: 31 Old World provinces. Every rival clears this number at
## every level, and so does the human crown on `normal`; the difficulty layer
## moves the crown's own bar (crown_threshold, DR-20261111-28).
const MILITARY_THRESHOLD: int = 31


## The bar the human crown must clear on this campaign's level: the published
## bar scaled by the level's published percentage, rounded onto whole provinces
## (wiki: ruleset-config § Difficulty). `normal` returns the published bar, so a
## campaign with no level reads byte-identically to the previous game.
static func crown_threshold(difficulty: String) -> int:
	return Difficulty.scaled(MILITARY_THRESHOLD, Difficulty.level_percent(difficulty))


## The bar a court must clear: the published one for every rival, and the
## level's own bar for the human crown. `human` is NO_ID for the full-AI
## observer, which stays on the published rows (wiki: ruleset-config
## § Difficulty — the layer never changes a rival-versus-rival ratio).
static func threshold_for(faction_id: int, human: int, difficulty: String) -> int:
	if human == MapModel.NO_ID or faction_id != human:
		return MILITARY_THRESHOLD
	return crown_threshold(difficulty)


## Victory state at the end of `turn`. An already-set victory stays as it is,
## because the wiki makes end-of-turn evaluation idempotent.
static func resolve(
	current: VictoryState,
	world: WorldMap,
	turn: int,
	human: int = MapModel.NO_ID,
	difficulty: String = Difficulty.DEFAULT
) -> VictoryState:
	if current != null:
		return current
	return evaluate(world, turn, human, difficulty)


## Military victory for the end of `turn`, or null while no Great Power holds
## enough of the Old World.
static func evaluate(
	world: WorldMap,
	turn: int,
	human: int = MapModel.NO_ID,
	difficulty: String = Difficulty.DEFAULT
) -> VictoryState:
	var winner: int = _winner(world, human, difficulty)
	if winner == MapModel.NO_ID:
		return null
	return VictoryState.military(winner, turn)


## Old World provinces a faction owns (the only region that counts).
static func old_world_holdings(world: WorldMap, faction_id: int) -> int:
	if world == null:
		return 0
	return world.owned_provinces(WorldMap.OLD_WORLD, faction_id)


## Eligible crowns that meet their own threshold, already ordered by the
## determinism rule: the lexicographically smallest player id wins a shared turn.
static func qualified(
	world: WorldMap,
	human: int = MapModel.NO_ID,
	difficulty: String = Difficulty.DEFAULT
) -> Array[int]:
	var ids: Array[int] = []
	if world == null:
		return ids
	for faction_id: int in world.great_powers_in(WorldMap.OLD_WORLD):
		if not FactionCatalog.can_win(faction_id):
			continue
		if old_world_holdings(world, faction_id) >= threshold_for(faction_id, human, difficulty):
			ids.append(faction_id)
	ids.sort_custom(func(a: int, b: int) -> bool: return str(a) < str(b))
	return ids


static func _winner(world: WorldMap, human: int, difficulty: String) -> int:
	var ids: Array[int] = qualified(world, human, difficulty)
	if ids.is_empty():
		return MapModel.NO_ID
	return ids[0]


## Calendar cap: the campaign closes after the last turn that starts in the stop
## year unless infinite mode was chosen at setup (wiki: turn-time-mapping
## § Campaign calendar cap). A mapping with no stop turn never halts.
static func calendar_halt(turn: int, infinite_mode: bool) -> bool:
	return not infinite_mode and TurnTime.is_cap_turn(turn)


## Strongest crown when the calendar closes the age without a military victory.
## The declared leader has the strictly highest Great Power power score; a tie
## at the top (or no eligible scorer) declares no-one (wiki: victory
## § Calendar campaign end, diplomacy § Great Power power score).
## `strength` and `ships` map faction id → the crown's order-of-battle strength
## (FPN + FPM, no medals) and hull count; a court with no field forces scores on
## provinces alone, which is what it reads anyway.
static func declared_leader(
	world: WorldMap, strength: Dictionary = {}, ships: Dictionary = {}
) -> int:
	if world == null:
		return MapModel.NO_ID
	var leader: int = MapModel.NO_ID
	var best: int = -1
	var tied: bool = false
	for faction_id: int in FactionCatalog.great_power_ids():
		var score: int = AiPower.score(
			world,
			faction_id,
			int(roundf(float(strength.get(faction_id, 0.0)))),
			int(ships.get(faction_id, 0))
		)
		if score > best:
			leader = faction_id
			best = score
			tied = false
		elif score == best:
			tied = true
	return MapModel.NO_ID if tied else leader
