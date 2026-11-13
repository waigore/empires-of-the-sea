class_name GazetteCopyMuster
extends RefCounted
## The crown's own Build/work: the worker the workshops finished training, the
## civilian engaged at the capital, the regiment the drill yard mustered and the
## hull the slips delivered. Each figure and name arrives in the record already
## decided by the rules; the desk only sets it in the sheet's voice
## (wiki: the-gazette § Item catalog; REQ-P2-03).


static func worker_recruited(rec: Dictionary) -> String:
	var label: String = String(rec.get("label", "worker")).to_lower()
	return (
		"The workshops have finished their training: a new %s joins the crown's labour."
		% label
	)


static func civilian_mustered(rec: Dictionary) -> String:
	var label: String = String(rec.get("label", "civilian"))
	var place: String = String(rec.get("place", "the capital"))
	return "A %s is engaged at %s, and stands ready for the crown's orders." % [label, place]


## A christened regiment prints the title it was mustered under
## (DR-20261111-18); a crown with no naming table gets the plain line.
static func regiment_mustered(rec: Dictionary) -> String:
	var label: String = String(rec.get("label", "regiment"))
	var title: String = String(rec.get("title", ""))
	if title.is_empty():
		return (
			"The drill yard has done its work: a new regiment of %s musters at the capital."
			% label
		)
	return "The drill yard has done its work: %s — %s musters at the capital." % [title, label]


static func ship_launched(rec: Dictionary) -> String:
	var label: String = String(rec.get("label", "hull"))
	var place: String = String(rec.get("place", "the capital"))
	return "A %s slides from the slips at %s and joins the home fleet." % [label, place]
