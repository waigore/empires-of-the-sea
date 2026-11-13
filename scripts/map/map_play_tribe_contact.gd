class_name MapPlayTribeContact
extends RefCounted
## Rival first contact with the Tribes a court's chart reaches, at the close of a
## turn (wiki: diplomacy § GP–Tribe first contact).
##
## The fog pass has just settled every chart, so this reads the same grid the
## courts plan from and no rival negotiates with a Tribe it never saw
## (REQ-P2-03). A new relation is silent: the wiki gives the rival court no
## herald, and the crown's own discovery keeps its app-layer pass.


static func resolve(play: PlaySession) -> Array[Dictionary]:
	if play == null or play.diplomacy == null:
		return []
	# Charts are built with each region's load; a session without them has
	# nothing to discover from (a headless fixture, not a playthrough).
	if play.court_charts == null:
		return []
	return TribeContact.apply(
		play.court_charts, play.diplomacy, play.human_faction_id(), play.turn,
		play.leaders
	)
