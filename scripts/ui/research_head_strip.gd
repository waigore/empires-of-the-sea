class_name ResearchHeadStrip
extends VBoxContainer
## The college's head: the standing line (how many slots, how many at study,
## what the purse holds, how many techs are known) and, when a study starves,
## the rule that stops it (REQ-P3-01).
##
## The panel keeps the state and the walk; this strip only prints what they
## said (REQ-P3-03). The rule behind an unpaid study is always visible: a phone
## hides the standing line, and a hover-only rule is unreachable on touch
## (REQ-P1-05, REQ-P5-05).

## The rule that stops an unpaid study, or "" when every slot is paid.
var _notice: Label = null
var _summary: Label = null
var _compact: bool = false


func _init() -> void:
	add_theme_constant_override("separation", 2)
	_summary = UiRowBuilder.label("", 14, Palette.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_notice = UiRowBuilder.label("", 12, Palette.CRIMSON)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	add_child(_notice)


## The standing line for `state` and the crown's `treasury`. A sheet that has
## not been bound to a study yet keeps the line it printed last.
func set_slots(state: ResearchState, treasury: int) -> void:
	if state == null:
		return
	var slots: int = state.slots.size()
	var known: int = state.unlocked_ids().size()
	_summary.text = "%d slot%s · %d at study · %s · %d tech%s known" % [
		slots,
		"" if slots == 1 else "s",
		state.researching().size(),
		MoneyText.ducats(treasury),
		known,
		"" if known == 1 else "s",
	]
	_summary.add_theme_font_size_override("font_size", 13 if _compact else 14)


## The rule behind a starving study (`ResearchQueueDesk.notice_line`); "" when
## the purse pays every slot.
func set_unpaid(line: String) -> void:
	_notice.text = line
	_notice.visible = not line.is_empty()


## Whether the rule is on the sheet — the standing hint stands down when it is.
func notice_shown() -> bool:
	return _notice.visible


## A phone trades the standing line for list room; the rule stays, because a
## hungry purse is what the crown must act on (REQ-P5-05).
func set_compact(compact: bool) -> void:
	_compact = compact
	_summary.visible = not compact
	_summary.add_theme_font_size_override("font_size", 13 if compact else 14)


## The standing line, for a test that reads the sheet's summary (REQ-P3-02).
func summary_text() -> String:
	return _summary.text


## Whether the standing line is on the sheet: a phone trades it for list room
## and keeps the rule (REQ-P5-05).
func summary_hidden() -> bool:
	return not _summary.visible


## The rule line, or "" — the reading a test checks without walking labels.
func notice_text() -> String:
	return _notice.text