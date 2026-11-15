class_name ModalDoor
extends ModalShell
## The cartouche's door onto a panel that draws its own chrome — the ledger's
## masthead, the court's tabs, the Gazette's paper. The panel keeps its body; the
## door gives it the one full-screen treatment every bar door uses: the wash, the
## safe area, the pause-door park and the back gesture (REQ-P1-05, REQ-P1-07,
## REQ-P5-01, REQ-P5-07).
##
## The door rides its own canvas layer above the pause menu, so nothing on the
## bar or in the menu can bleed through the sheet.

## Where a hosted sheet prints itself; the door paints no plate of its own.
func _dress_plate(_compact_now: bool) -> void:
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## Builds a door over `host` and gives it its own layer, so the sheet stands
## above the pause menu like the muster roll and the roster do.
static func mount(host: Node, door_name: String) -> ModalDoor:
	var layer: CanvasLayer = ModalShell.mount_layer(host, "%sLayer" % door_name)
	var door := ModalDoor.new()
	door.name = door_name
	layer.add_child(door)
	return door


## Hosts a sheet (or a slot's wrap) in the door's plate: it takes the plate's
## whole room, which is what makes a docked ledger read as a modal.
func host(wrap: Control) -> void:
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(wrap)
