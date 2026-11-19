class_name AiVictoryPressure
extends RefCounted
## Victory-aware military pressure (wiki: ai-architecture § Notable strategic
## policies; phase-planner-architecture § Playable slice; DR-20261114-04).
##
## A court that can see the bar presses for it. Once its Old World holdings
## stand within `victory.pressure_start` per-mille of the bar that crown must
## clear, it arms up for the finish — its muster target rises by
## `victory.pressure_regiments` — and its military, naval and expansion aims
## carry `victory.pressure_boost` per-mille more weight in the ledger. The press
## reaches the war aim too: a pressing court's war desire against a court
## holding the Old World land the bar counts carries `victory.pressure_war`
## points, so the crown that can see the bar opens the war that takes the
## provinces it still needs (DR-20261115-04, issue #601).
##
## Pure: the map, the bar and the registry are the only inputs, so the same
## state always reads the same pressure and a replay never drifts
## (REQ-P2-03, REQ-P3-03). Nothing here changes a rule: the muster still spends
## through `ArmyTraining`, and the bar is `VictoryRules`' own.

const STAGE_FAR: String = "far"
const STAGE_NEAR: String = "near"
const STAGE_AT_BAR: String = "at_bar"
## Per-mille "no change", the same neutral the posture vector uses.
const NEUTRAL: int = 1000

const LABELS: Dictionary = {
	STAGE_FAR: "far from the bar",
	STAGE_NEAR: "pressing for the bar",
	STAGE_AT_BAR: "at the bar",
}


## The court's distance to its bar plus the two readings the planners take from
## it: `holdings`, `bar`, `need`, `share_mille`, `stage`, `extra_regiments`,
## `boost_mille`, `start_mille`. A session with no world reads `far` with no
## extra muster, so a thin fixture plays exactly as before.
static func read(
	world: WorldMap,
	faction: int,
	human: int,
	difficulty: String,
	config: Variant
) -> Dictionary:
	var bar: int = VictoryRules.threshold_for(faction, human, difficulty)
	var holdings: int = VictoryRules.old_world_holdings(world, faction)
	var start: int = (
		int(config.parameter("victory.pressure_start")) if config != null else NEUTRAL
	)
	var share: int = share_mille(holdings, bar)
	var stage: String = stage_for(holdings, bar, share, start)
	return {
		"holdings": holdings,
		"bar": bar,
		"need": maxi(bar - holdings, 0),
		"share_mille": share,
		"stage": stage,
		"extra_regiments": extra_regiments(stage, config),
		"boost_mille": boost_mille(stage, config),
		"war_press": war_press(stage, config),
		"start_mille": start,
	}


## The muster extra alone, for an adapter that only needs the target: the
## regiments a pressing court arms up for, else zero.
static func extra_regiments(stage: String, config: Variant) -> int:
	if not presses(stage) or config == null:
		return 0
	return maxi(int(config.parameter("victory.pressure_regiments")), 0)


## Holdings as a per-mille share of the bar, clamped to 0–1000. A bar of zero
## (no world, no crown) reads zero rather than dividing.
static func share_mille(holdings: int, bar: int) -> int:
	if bar <= 0:
		return 0
	return clampi(holdings * NEUTRAL / bar, 0, NEUTRAL)


## `at_bar` once the holdings clear the bar, `near` from `start` per-mille up,
## `far` below it.
static func stage_for(holdings: int, bar: int, share: int, start: int) -> String:
	if bar > 0 and holdings >= bar:
		return STAGE_AT_BAR
	if share >= start:
		return STAGE_NEAR
	return STAGE_FAR


## The weight the ledger's military, naval and expansion aims carry: neutral
## while the court is far from the bar, the registry boost once it presses.
static func boost_mille(stage: String, config: Variant) -> int:
	if stage == STAGE_FAR or config == null:
		return NEUTRAL
	return int(config.parameter("victory.pressure_boost"))


## True while the court presses: it arms up and its war aims lead.
static func presses(stage: String) -> bool:
	return stage == STAGE_NEAR or stage == STAGE_AT_BAR


## The points the war aim carries against a court holding the Old World land the
## bar counts: zero while the crown is far from the bar, else
## `victory.pressure_war` (wiki: ai-architecture § victory pressure; the press
## reaches the war aim — its war aims lead — DR-20261115-04, issue #601).
static func war_press(stage: String, config: Variant) -> int:
	if not presses(stage) or config == null:
		return 0
	return maxi(int(config.parameter("victory.pressure_war")), 0)


## True while the court stands short of the bar it must clear — the conquest
## shortfall the money goal banks on (issue #995): below the bar with an army
## under target, a court banks for the regiment that takes the provinces it
## still needs instead of building behind a purse that never arms. The bar is
## `VictoryRules`' own — the published 31 for every rival, the level's own bar
## for the crown — and a session with no world reads no gap, so a thin fixture
## keeps the published behaviour (REQ-P2-03).
static func below_bar(
	world: WorldMap, faction: int, human: int, difficulty: String = Difficulty.DEFAULT
) -> bool:
	if world == null:
		return false
	var bar: int = VictoryRules.threshold_for(faction, human, difficulty)
	if bar <= 0:
		return false
	return VictoryRules.old_world_holdings(world, faction) < bar


## Reader-facing label for the observer panel and the turn trace.
static func label(stage: String) -> String:
	return String(LABELS.get(stage, LABELS[STAGE_FAR]))
