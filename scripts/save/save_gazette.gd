class_name SaveGazette
extends RefCounted
## Save shape of the crown's news sheet: the watchlist and every filed sheet
## (wiki: the-gazette § Courts of interest, § History screen; DR-20261110-14).
## The archive is unbounded within a campaign and travels with it, so a load
## resumes the same list and the same history (REQ-P3-03).


## Empty for a campaign that has not opened a sheet yet; a legacy save simply
## loads that way and the first turn close founds the list.
static func capture(play: PlaySession) -> Dictionary:
	if play == null or play.gazette == null:
		return {}
	return play.gazette.to_dict()


static func restore(play: PlaySession, data: Dictionary) -> void:
	if play == null:
		return
	play.gazette = GazetteState.from_dict(data.get("gazette", {}))
