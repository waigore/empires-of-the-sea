class_name MapPlayCampaign
extends RefCounted
## Campaign close and published standing: records the decision, mounts the plate
## and computes the calendar's declared leader (wiki: victory § Victory Check;
## turn-time-mapping § Campaign calendar cap).
##
## One home for the power formula so the turn, the setup intro and the observer
## panel never duplicate it (REQ-P3-02). Presentation only: every winner is
## already decided by VictoryRules.


## Campaign decided: record the winner, mount the plate, and stop the calendar
## at the turn that decided it (wiki: victory § Victory Check).
static func close_victory(play: PlaySession, victory: VictoryState) -> void:
	play.victory = victory
	if not play.observer_mode:
		play.hud.show_victory(
			victory,
			play.player_faction,
			VictoryRules.old_world_holdings(play.world, victory.winner_player_id)
		)
	play.hud.toast(victory.summary())
	play.emit_turn_ended(play.turn)
	play.emit_campaign_end(victory)


## The calendar closed the age without a military victory: record it, mount the
## campaign-complete plate, and leave the turn number on the last full turn
## (wiki: turn-time-mapping § Campaign calendar cap, victory § Calendar end).
static func close_calendar(play: PlaySession) -> void:
	play.campaign_halted = true
	var leader: int = declared_leader(play)
	if not play.observer_mode:
		play.hud.show_campaign_complete(leader, play.turn, play.player_faction)
	play.hud.toast(
		"Campaign complete — %d" % TurnTime.year_for_turn(play.turn)
	)
	play.emit_turn_ended(play.turn)


## Strongest crown by power score, or NO_ID when the top score is shared. The
## strength term is the public order of battle — FPN + FPM over every regiment
## the crown holds, in both regions, without the general medal multiplier — and
## the hull term counts every ship it floats, again in both regions
## (wiki: victory § Calendar campaign end, diplomacy § Great Power power score).
static func declared_leader(play: PlaySession) -> int:
	var strength: Dictionary = {}
	var ships: Dictionary = {}
	if play.army_layer != null:
		for raw: Variant in play.army_layer.regions.values():
			var stored: Array = []
			stored.assign(raw)
			for army: ArmyState in stored:
				if army != null:
					strength[army.owner] = (
						float(strength.get(army.owner, 0.0)) + army.strength()
					)
	if play.ship_layer != null:
		for faction: int in FactionCatalog.great_power_ids():
			ships[faction] = play.ship_layer.hull_count_all(faction)
	return VictoryRules.declared_leader(play.world, strength, ships)


## Great Power research state for a rules pass over every crown. Rivals keep
## their tech in their own ledger; the human court's lives in EconomyController.
static func tech_by_faction(play: PlaySession) -> Dictionary:
	var tech: Dictionary = {}
	if play == null:
		return tech
	if play.economy != null and play.economy.economy != null:
		tech[play.player_faction] = play.economy.economy.tech_unlocked
	if play.ai == null:
		return tech
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		tech[faction] = play.ai.economy_for(faction).tech_unlocked
	return tech


## A closed campaign accepts no further turns; says why.
static func closed_message(play: PlaySession) -> String:
	if play.defeat != null:
		return play.defeat.summary()
	if play.victory != null:
		return "Campaign ended — %s" % play.victory.winner_name()
	return "Campaign complete — the age has run its course"
