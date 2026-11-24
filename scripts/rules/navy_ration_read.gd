class_name NavyRationRead
extends RefCounted
## The crown's rations at sea, in the battle's own figures (wiki:
## workers-and-population § Consumption — "Naval combat"; ships-and-naval
## § Ship food upkeep; DR-20261124-15).
##
## The squadron line printed every hull's two food as one bill (`upkeep 10
## food`) and never what the larder fed of it, so a crown whose fleet went hungry
## read nowhere why a won water came home drawn: a navy fed in full fights at
## 1.0, one fed at least half its hulls at 0.75, one fed under half at 0.5 —
## exactly the ladder a hungry army reads
## (`ArmyModifiers.feeding_multiplier`, the one the sea resolver already scales a
## side by).
##
## A reading only: `PlayerEconomy.navy_feeding` owns the coverage the last
## Consumption filed and `NavalExchange` owns the multiplier the fight reads.
## Nothing here spends, starves or fights (REQ-P2-03, REQ-P3-03).

## No reading was handed in — another court's larder is not the crown's to read.
## A caller prints no row rather than a band it never asked about. The same
## sentinel the army's band uses, so one caller can hand either sheet the same
## figure.
const NO_READING: float = ArmyRationRead.NO_READING


## The multiplier the next sea battle reads, for the coverage a crown's
## Consumption filed. `NO_READING` answers the full band, because that is the
## figure `NavalExchange` reads for a court its context carries no coverage for.
## One ladder, read through the army's own home so the two halves of one rule
## cannot drift (`ArmyRationRead.multiplier` → `ArmyModifiers`).
static func multiplier(coverage: float) -> float:
	return ArmyRationRead.multiplier(coverage)


## One dossier line in the wiki's ladder: the share of the crown's hulls last
## turn's Consumption fed and the morale every sea battle fights at. Empty when
## the caller holds no reading.
static func line(coverage: float) -> String:
	if coverage < 0.0:
		return ""
	var morale: float = multiplier(coverage)
	if morale >= 1.0:
		return "Rations · the whole fleet fed · sea battles fight at full morale"
	return "Rations · %d%% of the hulls fed · sea battles fight at %s morale" % [
		_share(coverage), "0.75" if morale >= 0.75 else "half",
	]


## The rule behind the line, for the row's own tip: what the ladder does, and
## that a rival's larder stays behind her colours (wiki: workers-and-population
## § Consumption — naval combat; REQ-P5-03 — a phone keeps no hover, so the line
## above stands on its own words).
static func tip(coverage: float) -> String:
	if coverage < 0.0:
		return ""
	if multiplier(coverage) >= 1.0:
		return (
			"Last turn's Consumption fed every hull's ration bill, so every sea"
			+ " battle compares at full morale (wiki: workers-and-population"
			+ " § Consumption — naval combat)."
		)
	return (
		"Last turn's Consumption fed %d%% of the crown's hulls, so every sea"
		+ " battle she fights is scaled by %s morale — the same ladder a hungry"
		+ " army reads. Another court's larder is not hers to read (wiki:"
		+ " workers-and-population § Consumption — naval combat)."
	) % [_share(coverage), "%.2f" % multiplier(coverage)]


## The fleet's own share. A short band never prints 100: the ladder drops to
## 0.75 the moment a hull goes unfed, so `99%` is the closest a hungry row gets
## to a whole bill and the two figures cannot contradict each other.
static func _share(coverage: float) -> int:
	return mini(floori(clampf(coverage, 0.0, 1.0) * 100.0), 99)
