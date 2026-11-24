class_name HudDespatchPlate
extends PanelContainer
## One news plate in the court's despatch lane (REQ-P5-05): the words it prints,
## the medallion it raises, and the fade that ends it. It carries its own state,
## so the lane reads a plate before it cancels one instead of tagging the node
## (REQ-P3-02).
##
## The fade is short-lived and presentation only; a drive that clears the lane
## kills it here, and a cancelled plate never counts down the lane's live slots.

## The line the court reads.
var text: String = ""
## The medallion's kind; empty draws words alone.
var icon_name: String = ""
## The fade that raises this plate and lets it go.
var fade: Tween = null
## The lane took the plate back (a sheet covers it, or a drive cleared it): the
## fade's callback must not count down a plate that has left the lane.
var cancelled: bool = false


## Is this plate still the lane's to count?
func is_live() -> bool:
	return not cancelled and not is_queued_for_deletion()


## Hands the plate the line it prints and the medallion it raises.
func dress(line: String, icon: String = "") -> void:
	text = line
	icon_name = icon


## The lane stepped this plate aside before its fade ended.
func cancel() -> void:
	cancelled = true
	stop_fade()


## Kills the fade where it stands, so nothing outlives a plate freed on the spot
## (docs/testing.md § Speed rules: a driven run leaves no Tween busy).
func stop_fade() -> void:
	if fade != null and fade.is_valid():
		fade.kill()
	fade = null
