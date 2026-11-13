class_name QuickBattleOverlay
extends BattlePlateFrame
## The Quick Battle plate: a bright animated field, round-by-round despatches and
## a decisive outcome stamp. Presentation only — it replays the report the rules
## resolver produced and never changes it (REQ-P2-03). Despatch copy lives in
## [QuickBattleCopy], the shared plate furniture in [BattlePlateFrame].
## Skippable with one tap so the juice stays non-modal (REQ-P5-06, REQ-P3-01).

const ROUND_SECONDS: float = 1.15

var province_name: String = ""

var field: QuickBattleField = null
var _round_label: Label = null
var _plan_label: Label = null
var _wall_label: Label = null
var _pips: Array[Label] = []


func show_battle(p_battle: Dictionary, p_province: String, p_names: Array) -> void:
	province_name = p_province
	_reveal(p_battle, p_names)


# --- frame hooks -------------------------------------------------------------


func _look() -> Dictionary:
	return {
		"title": "QUICK BATTLE",
		"title_pixels": 24,
		"headline_pixels": 16,
		"wrap_headline": false,
		"skip_tip": "Skip the animation",
		"panel_fill": Color(0.09, 0.07, 0.05, 0.97),
		"name_width": 120.0,
		"wrap_names": false,
		"outcome_pixels": 22,
	}


## The round counter joins the header beside the place and the Skip.
func _build_header_tail(header: HBoxContainer) -> void:
	_round_label = _label("", 13, Palette.GOLD)
	header.add_child(_round_label)


func _build_body(column: VBoxContainer) -> void:
	field = QuickBattleField.new()
	field.custom_minimum_size = Vector2(0, 140)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.size_flags_stretch_ratio = 3.0
	column.add_child(field)


## The round pips sit under the bars; the wall a siege is fought over is kept
## apart from the three-line round log.
func _build_after_bars(column: VBoxContainer) -> void:
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	column.add_child(pips)
	pips.add_child(_label("ROUNDS", 11, Palette.TEXT_DIM))
	for index in 3:
		var pip := _label(QuickBattleCopy.roman(index + 1), 13, Palette.TEXT_DIM)
		_pips.append(pip)
		pips.add_child(pip)
	_plan_label = _label("", 11, Palette.TEXT_DIM)
	_plan_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pips.add_child(_plan_label)
	_wall_label = _label("", 12, Palette.TEXT)
	_wall_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wall_label.visible = false
	column.add_child(_wall_label)


func _reset_body() -> void:
	for pip: Label in _pips:
		pip.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_wall_label.text = ""
	_wall_label.visible = false
	field.set_battle(battle)


func _populate() -> void:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_headline.text = province_name
	_tint_side(_atk_name, _atk_bar, int(battle.get("attacker", 0)))
	_tint_side(_def_name, _def_bar, int(battle.get("defender", 1)))
	_plan_label.text = QuickBattleCopy.plan_text(battle)
	# A siege plate names the wall before the first round — the fort, its
	# protection, its lanes and its gates — not only in the aftermath
	# (wiki: siege-mechanics § Quick Battle lanes, § Gates and Sortie). The round
	# log holds three lines, so it cannot carry it.
	var wall: String = QuickBattleCopy.siege_opening(battle)
	_wall_label.text = wall
	_wall_label.visible = not wall.is_empty()
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1))
	)
	_round_label.text = ""


func _play() -> void:
	var rounds: Array = (battle.get("quick", {}) as Dictionary).get("rounds", []) as Array
	if rounds.is_empty():
		_finish()
		return
	_tween = create_tween()
	for index in rounds.size():
		_tween.tween_callback(_enter_round.bind(index))
		_tween.tween_interval(ROUND_SECONDS)
	_tween.tween_callback(_finish)


## Skip still names the round it stopped in, so the aftermath is read with the
## last round's line on the plate.
func _skip_to_end() -> void:
	var rounds: Array = (battle.get("quick", {}) as Dictionary).get("rounds", []) as Array
	if not rounds.is_empty():
		_enter_round(rounds.size() - 1)


func _finish() -> void:
	if _finished:
		return
	_round_label.text = "AFTERMATH"
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var atk_left: int = int(quick.get("attacker_left", 0))
	var def_left: int = int(quick.get("defender_left", 0))
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		atk_left, def_left,
		_average(battle.get("attacker_health", []) as Array, atk_left),
		_average(battle.get("defender_health", []) as Array, def_left)
	)
	var outcome: int = int(battle.get("outcome", ArmyCombat.Outcome.STALEMATE))
	field.set_outcome(outcome)
	# The final field carries the aftermath, not another round's animation.
	field.attacker_count = atk_left
	field.defender_count = def_left
	field.guns = int(quick.get("guns_left", 0))
	field.attacker_health = battle.get("attacker_health", []) as Array
	field.defender_health = battle.get("defender_health", []) as Array
	field.queue_redraw()
	# Ground, the line, walls and named dead: told, never silently written back
	# (REQ-P5-05).
	var lines: Array[String] = [
		QuickBattleCopy.terrain_line(battle),
		QuickBattleCopy.line_line(battle, faction_names),
		QuickBattleCopy.loss_line(battle, faction_names),
		QuickBattleCopy.health_line(battle, faction_names),
		QuickBattleCopy.chevron_line(battle, faction_names),
		QuickBattleCopy.honour_line(battle, province_name, faction_names),
		QuickBattleCopy.citation_line(battle, province_name, faction_names),
		QuickBattleCopy.siege_line(battle),
	]
	for text: String in lines:
		if not text.is_empty():
			add_line(text)
	stamp_outcome(
		QuickBattleCopy.outcome_text(outcome, battle, province_name, faction_names),
		QuickBattleCopy.player_won(outcome, battle)
	)


func _enter_round(index: int) -> void:
	var rounds: Array = (battle.get("quick", {}) as Dictionary).get("rounds", []) as Array
	if index < 0 or index >= rounds.size():
		return
	var round: Dictionary = rounds[index] as Dictionary
	field.set_round(
		index,
		int(round.get("attacker_count", 0)),
		int(round.get("defender_count", 0)),
		int(round.get("guns", 0)),
		round.get("attacker_health", []) as Array,
		round.get("defender_health", []) as Array,
		int(round.get("gates", 0))
	)
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		int(round.get("attacker_count", 0)), int(round.get("defender_count", 0)),
		float(round.get("attacker_strength", 1.0)),
		float(round.get("defender_strength", 1.0))
	)
	_round_label.text = "ROUND %s" % QuickBattleCopy.roman(index + 1)
	if index < _pips.size():
		_pips[index].add_theme_color_override("font_color", Palette.GOLD_PALE)
	for action: Dictionary in round.get("actions", []):
		add_line(QuickBattleCopy.action_line(action, battle, faction_names))
		_show_hits(action)


# --- bars and hits -----------------------------------------------------------


func _set_bars(
	atk_start: int, def_start: int, atk: int, def_now: int,
	atk_fraction: float = 1.0, def_fraction: float = 1.0
) -> void:
	_atk_bar.max_value = maxi(atk_start, 1)
	_atk_bar.value = atk
	_def_bar.max_value = maxi(def_start, 1)
	_def_bar.value = def_now
	_atk_name.text = "%s  %d · %d%%" % [
		QuickBattleCopy.faction(int(battle.get("attacker", 0)), faction_names), atk,
		roundi(atk_fraction * 100.0)
	]
	_def_name.text = "%d · %d%%  %s" % [
		def_now, roundi(def_fraction * 100.0),
		QuickBattleCopy.faction(int(battle.get("defender", 1)), faction_names)
	]


## Floats the damage an action dealt (and took) over the side it struck.
func _show_hits(action: Dictionary) -> void:
	var actor: int = int(action.get("side", -1))
	var acting: String = "attacker" if actor == int(battle.get("attacker", 0)) else "defender"
	var hurt: String = "defender" if acting == "attacker" else "attacker"
	var hits: Array = action.get("hits", []) as Array
	if not hits.is_empty():
		field.add_hits(hurt, hits, Palette.faction_color(int(battle.get(hurt, 0))))
	var own: Array = action.get("own_hits", []) as Array
	if not own.is_empty():
		field.add_hits(acting, own, Palette.faction_color(actor))


## Mean health of a side; a side left with no regiments reads zero, one whose
## record predates condition tracking reads full.
func _average(entries: Array, count: int) -> float:
	if entries.is_empty():
		return 1.0 if count > 0 else 0.0
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("fraction", 1.0))
	return total / float(entries.size())
