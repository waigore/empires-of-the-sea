class_name ResearchCatalogPages
extends RefCounted
## The college's Available and Known desks (REQ-P3-01). The panel keeps the
## tabs and the intents; these pages own the list paint, the open-advance sort,
## and the rebuild that keeps the player's scroll place (REQ-P3-02).


## Signatures of what each desk last drew, so a funding change that leaves the
## open list alone never rebuilds the pages.
var _available_key: String = ""
var _known_key: String = ""


## Researchable, not already in a slot, goal path first.
static func open_advances(state: ResearchState, goal: String) -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in state.researchable():
		if not state.is_active(tech_id):
			out.append(tech_id)
	return TechOrder.sorted(out, goal)


## Replaces a page's rows but keeps the player's place in the list: a rebuild
## that jumped back to the top would read as a reload.
static func rebuild(body: Container, paint: Callable) -> void:
	var scroll := body.get_parent() as ScrollContainer
	var keep: int = scroll.scroll_vertical if scroll != null else 0
	UiRowBuilder.clear(body)
	paint.call()
	if scroll != null:
		scroll.set_deferred("scroll_vertical", keep)


## Rebuilt only when the open list, the goal or the free slot changes; a
## funding change repaints none of it.
func paint_available(
	body: VBoxContainer,
	state: ResearchState,
	techs: Array[String],
	goal: String,
	on_assign: Callable,
	on_goal: Callable
) -> void:
	var key: String = "%s|%s|%d" % [";".join(techs), goal, state.free_slot()]
	if key == _available_key:
		return
	_available_key = key
	rebuild(body, func() -> void:
		if techs.is_empty():
			body.add_child(UiRowBuilder.label(
				"No advances are open — finish a prerequisite or chart a resource.",
				12, Palette.TEXT_DIM
			))
			return
		for tech_id: String in techs:
			body.add_child(ResearchRow.available(
				state, tech_id, on_assign, goal, on_goal
			))
	)


func paint_known(body: VBoxContainer, state: ResearchState, goal: String) -> void:
	var known: Array[String] = state.unlocked_ids()
	var key: String = "%s|%s" % [";".join(known), goal]
	if key == _known_key:
		return
	_known_key = key
	rebuild(body, func() -> void:
		if known.is_empty():
			body.add_child(UiRowBuilder.label(
				"Nothing is known beyond the old learning.", 12, Palette.TEXT_DIM
			))
			return
		for tech_id: String in TechOrder.sorted(known, goal):
			body.add_child(ResearchRow.known(tech_id, goal))
	)
