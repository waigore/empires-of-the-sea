class_name ArmyRationRead
extends RefCounted
## The crown's rations in the field's own figures (wiki: combat § Feeding
## modifiers, § Auto-resolve ratio bands; DR-20261124-02).
##
## Land combat compares the two sides' morale, and that morale is the feeding
## multiplier: a crown that fed the whole bill fights at 1.0, one fed at least
## half of it at 0.75, one fed under half at 0.5. A hungrier attacker's win
## between 1.5 and 4.0 to one is blunted — heavier losses, and a stalemate even
## when the garrison is wiped. The dossier printed the ration bill and never the
## coverage, so a crown read why a winnable storm came home a draw nowhere.
##
## A reading only: `ArmyModifiers.feeding_multiplier` owns the ladder and the
## crown's ledger owns the coverage. Nothing here spends, starves or fights
## (REQ-P2-03, REQ-P3-03).

## No reading was handed in — another court's larder is not the crown's to read.
## A caller prints no row rather than a full band it never asked about.
const NO_READING: float = -1.0


## The multiplier the next exchange reads, for the coverage a crown's Consumption
## filed. `NO_READING` answers the full band, because that is the figure the
## battle itself reads for a court the context carries no coverage for
## (`ArmyModifiers.morale`).
static func multiplier(coverage: float) -> float:
	if coverage < 0.0:
		return 1.0
	return ArmyModifiers.feeding_multiplier(clampf(coverage, 0.0, 1.0))


## One dossier line in the wiki's ladder: the share of the bill last turn's
## Consumption fed and the morale every engagement fights at. Empty when the
## caller holds no reading.
static func line(coverage: float) -> String:
	if coverage < 0.0:
		return ""
	var morale: float = multiplier(coverage)
	if morale >= 1.0:
		return "Rations · the whole bill fed · engagements fight at full morale"
	return "Rations · %d%% of the bill fed · engagements fight at %s morale" % [
		_share(coverage), "0.75" if morale >= 0.75 else "half",
	]


## The rule behind the line, for the row's own tip: what the ladder does, and the
## band a crown fed less than its enemy fights (REQ-P5-03 — a phone keeps no
## hover, so the line stands on its own words above).
static func tip(coverage: float) -> String:
	if coverage < 0.0:
		return ""
	if multiplier(coverage) >= 1.0:
		return (
			"Last turn's Consumption fed the army's whole ration bill, so every "
			+ "engagement compares at full morale (wiki: combat § Feeding modifiers)."
		)
	return (
		"Last turn's Consumption fed %d%% of the army's ration bill, so every "
		+ "engagement compares at %s morale. A crown fed less than the enemy it "
		+ "attacks fights the blunted band between 1.5 and 4.0 to one: heavier "
		+ "losses, and a stalemate even when the garrison is wiped (wiki: combat "
		+ "§ Feeding modifiers, § Auto-resolve ratio bands)."
	) % [_share(coverage), "%.2f" % multiplier(coverage)]


## The bill's own share. A short band never prints 100: the ladder drops to 0.75
## the moment any mouth goes unfed, so `99%` is the closest a hungry row gets to
## a whole bill and the two figures cannot contradict each other.
static func _share(coverage: float) -> int:
	return mini(floori(clampf(coverage, 0.0, 1.0) * 100.0), 99)
