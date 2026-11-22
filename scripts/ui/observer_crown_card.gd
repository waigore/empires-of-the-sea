class_name ObserverCrownCard
extends PanelContainer
## One Great Power's card on the AI observatory: its rank, name, standing toward
## the bar, profile line, the ledger it holds and the order it filed last turn
## (REQ-P3-01). The observatory owns the snapshot and the turn loop; this owns
## the dress, so a board of twelve crowns costs one node family and a `fill`
## per row instead of a dozen labels built in the panel's build pass
## (DR-20261114-04; wiki: ai-observer).

## Room the cards keep on a short screen; the observatory's plate scrolls around
## them (REQ-P1-07).
const MIN_HEIGHT: float = 180.0

## The card's lines, read by the observatory's witnesses and suites. They are
## filled together from one snapshot row and never edited from outside.
var rank: Label = null
var name_label: Label = null
var progress: Label = null
var meta: Label = null
var stats: Label = null
var last: Label = null


func _init() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Palette.INK_SOFT, Palette.GOLD_DIM, 1, 3, Vector4(8, 4, 8, 4))
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	rank = UiRowBuilder.label("#–", 11, Palette.GOLD_DIM)
	rank.custom_minimum_size = Vector2(30.0, 0.0)
	head.add_child(rank)
	name_label = UiRowBuilder.serif_line("", 16, Palette.GOLD_PALE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	progress = UiRowBuilder.label("", 11, Palette.TEXT)
	head.add_child(progress)
	meta = UiRowBuilder.serif_line("", 10, Palette.TEXT_DIM)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meta)
	stats = UiRowBuilder.serif_line("", 11, Palette.TEXT)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(stats)
	last = UiRowBuilder.serif_line("", 11, Palette.GOLD)
	last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(last)


## Paint one snapshot row onto this crown's card.
func fill(row: Dictionary) -> void:
	rank.text = "#%d" % int(row["rank"])
	name_label.text = "%s%s" % [
		String(row["name"]), "" if bool(row["alive"]) else " (fallen)",
	]
	# A court that can see the bar presses for it (DR-20261114-04): the reading
	# sits beside its standing so the observer sees the endgame coming.
	progress.text = "%d/%d%s" % [
		int(row["provinces_old"]), VictoryRules.MILITARY_THRESHOLD,
		"  ·  pressing" if AiVictoryPressure.presses(
			String(row.get("pressure_stage", ""))
		) else "",
	]
	meta.text = "%s  ·  %s  ·  %s  ·  %s  ·  %s" % [
		String(row["leader"]), String(row["agenda"]), String(row["profile"]),
		String(row["posture"]), String(row["intent"]),
	]
	var wars: Array = row["wars"]
	stats.text = (
		"%d OW · %d NW  ·  power %d  ·  army %d  ·  fleet %d  ·  civilians %d\n"
		+ "treasury %s  ·  stock %d  ·  workers %d  ·  wars: %s"
	) % [
		int(row["provinces_old"]), int(row["provinces_new"]), int(row["power"]),
		int(row["regiments"]), int(row["ships"]), int(row["civilians"]),
		TextFormat.thousands(int(row["treasury"])), int(row["stock"]), int(row["workers"]),
		", ".join(PackedStringArray(wars)) if not wars.is_empty() else "none",
	]
	last.text = "Last turn: %s" % String(row["headline"])
