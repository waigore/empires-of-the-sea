class_name MapPlayCommand
extends RefCounted
## The command ledger's one map hook: the crown's own pool, its researched
## studies and its leader, assembled into the reading [CommandLedger] projects
## (wiki: military-generals § Generals; DR-20261115-11). Presentation only — the
## pool is the army layer's own roster, so the ledger reads the commanders the
## next battle will draw from (REQ-P3-02).


## The player crown's command reading. A session with no army layer (a headless
## fixture) reads an empty pool rather than inventing one.
static func snapshot(play: PlaySession) -> Dictionary:
	if play == null:
		return CommandLedger.snapshot(null, MapModel.NO_ID, {}, "")
	var owner: int = play.player_faction
	var roster: GeneralRoster = play.army_layer.generals if play.army_layer != null else null
	return CommandLedger.snapshot(
		roster, owner, play.tech_unlocked(), String(play.leaders.get(owner, ""))
	)
