class_name ForceLedgerSheet
extends LedgerSheet
## The one sheet the crown reads its two forces on — the army, regiment by
## regiment, and the navy, hull by hull. Both bind the session, re-read both
## charts through their own projection, paint the chart and reading chips, group
## the rows under the standard or squadron that flies them, print the count line
## and hand each Visit to the map hook that frames it (wiki: military-armies
## § The regiments behind an army; ships-and-naval § Ship combat and cargo stats;
## DR-20261115-14, DR-20261116-16).
##
## The dress is written once here so a force is a handful of words — its
## projection, its chip words, the line under its headings and its Visit — and
## not a second copy of the whole sheet (REQ-P3-01, REQ-P3-02). The sheet chrome,
## fade and pause-door park come from SheetFrame; the chips, rows and empty
## notice from LedgerSheet; the heading dress from LedgerList.


## Re-reads both charts' roster for the player's crown and repaints.
func refresh() -> void:
	if play == null or play.world == null or not _layer_ready():
		return
	_snapshot = _read()
	_fit()
	_sync_counsel()
	_apply_filter()


func _can_open() -> bool:
	return super._can_open() and _layer_ready()


# --- what a force names ------------------------------------------------------


## Whether the layer this sheet reads is mounted on the screen: a campaign booted
## without an army still reads no regiments (REQ-P3-02).
func _layer_ready() -> bool:
	return false


## The projection this sheet prints, read fresh for the player's crown.
func _read() -> Dictionary:
	return {}


## The reading chips this sheet offers, in the order they print.
func _filters() -> Array:
	return []


## One-word name of a reading key.
func _reading_word(key: String) -> String:
	return key


## The noun the chip row counts, singular and capitalised: "Regiment", "Hull".
## A sheet that names its rows names both forms in `_row_word`.
func _row_caption() -> String:
	return _row_word(1).capitalize()


## The noun a heading counts, singular or plural: "regiment", "regiments".
func _row_word(_count: int) -> String:
	return "row"


## The rows one chart-and-reading view leaves, grouped under their chart.
func _groups(_region_key: String, _reading_key: String) -> Array[Dictionary]:
	return []


## How many rows that view prints: the count line and a chip's tally read it.
func _count(_region_key: String, _reading_key: String) -> int:
	return 0


## Where one group stands and what it is doing, printed under its heading: the
## standard's place and footing, the squadron's station and holds.
func _standing_text(_group: Dictionary) -> String:
	return ""


## The rule a crown reads before it pays, printed on the sheet rather than in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	return null


## The row widget this sheet mints, dressed for the profile and wired to its own
## Visit — a regiment names its standard, a hull her squadron.
func _make_row(_raw: Variant, _compact: bool) -> Control:
	return null


# --- the shared body ---------------------------------------------------------


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", _row_caption(), _filters(), _reading_word, _under_chips
	)


## What sits under the chips and above the rows: the court's own reading in
## gold, then the rule the sheet prints — a phone hides the footer hint, so the
## rule keeps its place on the body (REQ-P1-07, REQ-P5-03). A sheet with no
## reading wired prints the rule alone, exactly as it always did.
func _under_chips() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 10)
	_counsel_line(block)
	var note: Control = _note()
	if note != null:
		block.add_child(note)
	return block


func _apply_filter() -> void:
	_paint_filtered(_groups(_region, _reading), _count(_region, _reading), _heading, _make_row)


## One standard's or squadron's heading: where it stands and what it is doing,
## then the regiments it flies or the hulls she sails. A regiment's orders are its
## standard's and a hull's are her squadron's, so they read once.
func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.standing_heading(
		"%s  ·  %d %s" % [String(group["heading"]), count, _row_word(count)],
		_standing_text(group)
	)
