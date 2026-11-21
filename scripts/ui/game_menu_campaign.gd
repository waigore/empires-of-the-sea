class_name GameMenuCampaign
extends RefCounted
## The pause page's campaign reading: the live map seed and the crown's own
## leader line (REQ-P3-01). GameMenu mounts the labels; this helper owns the
## three-step resolve and the clipboard hand, so the pause layer does not walk
## the screen for those answers on every open (REQ-P3-02).


## Prefer the session seed once play is live; fall back to the screen pin.
static func resolve_seed(screen: MapScreen) -> int:
	if screen == null:
		return 0
	if screen.play != null:
		return screen.play.map_seed
	return screen.map_seed


## The crown's own leader as the run bound it: the session roster first, the
## screen's pin while a campaign is still booting, the catalog default last —
## the same three-step read `LeaderCatalog.roster` builds (wiki: leader-bonuses
## § Leader Selection).
static func resolve_leader(screen: MapScreen) -> String:
	if screen == null:
		return LeaderCatalog.DEFAULT_KEY
	if screen.play != null:
		var key: String = String(
			screen.play.leaders.get(screen.play.player_faction, "")
		)
		if not key.is_empty():
			return key
	if not screen.player_leader.is_empty():
		return screen.player_leader
	return LeaderCatalog.default_key(screen.player_faction)


## Rewrites the seed digits, the copy door and the crown line from the live
## screen. Returns the seed shown so COPY can publish it without a second walk.
static func refresh(
	screen: MapScreen,
	seed_label: Label,
	copy_seed_button: Button,
	crown_label: Label
) -> int:
	var shown: int = resolve_seed(screen)
	if seed_label != null:
		seed_label.text = str(shown) if shown != 0 else "—"
	if copy_seed_button != null:
		copy_seed_button.disabled = shown == 0
	if crown_label != null:
		crown_label.text = LeaderCatalog.crown_line(resolve_leader(screen))
	return shown


## Puts the shown seed on the clipboard and confirms on the status line.
static func copy_seed(shown_seed: int, status: Label) -> void:
	if shown_seed == 0:
		return
	DisplayServer.clipboard_set(str(shown_seed))
	if status != null:
		status.text = "Seed copied."
