class_name HudChartCartouche
extends RefCounted
## The chart's cartouche markings GameHud only routes: the turn's date and the
## minimap the chart repaints (REQ-P3-01). TopBar and HudChrome own the widgets;
## this owns their state, so GameHud names one collaborator per concern instead
## of reaching into chrome it did not build.

var turn_label: Label = null
var minimap: Minimap = null


## TopBar hands over the date line; HudChrome hands over the minimap.
func bind(p_turn_label: Label, p_minimap: Minimap) -> void:
	turn_label = p_turn_label
	minimap = p_minimap


func set_turn(turn: int, year: int) -> void:
	if turn_label != null:
		turn_label.text = "Turn %d  ·  %d" % [turn, year]


func set_minimap(model: MapModel, map_size: Vector2, visibility: VisibilityModel) -> void:
	if minimap != null:
		minimap.build(model, map_size, visibility)


## Ownership moved without the chart changing (a conquest, a treaty swap).
func refresh_minimap() -> void:
	if minimap != null:
		minimap.refresh_ownership()


func update_view_rect(rect: Rect2) -> void:
	if minimap != null:
		minimap.set_view_rect(rect)
