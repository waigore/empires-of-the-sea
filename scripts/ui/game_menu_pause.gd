class_name GameMenuPause
extends RefCounted
## The pause page's desk — crown, seed, action rows, mix desk and status
## (REQ-P3-01). GameMenu owns open/close and the overlay shell; this helper
## builds the rows so the menu layer stays an orchestrator (REQ-P3-02).

var pause_page: VBoxContainer = null
var crown_label: Label = null
var seed_label: Label = null
var copy_seed_button: Button = null
var resume_button: Button = null
var save_button: Button = null
var load_button: Button = null
var keys_button: Button = null
var main_menu_button: Button = null
var sound_desk: SoundDesk = null
var status: Label = null


## Fills `frame` with the pause rows. Callers wire the pressed signals; `short`
## is the page's compact answer (`MenuFrame.is_short`).
func build(frame: Control, short: bool) -> void:
	var row: float = MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	pause_page = VBoxContainer.new()
	pause_page.add_theme_constant_override("separation", 8 if short else 10)
	frame.add_child(pause_page)

	var heading := MenuFrame.title("PAUSED", 26 if short else 30)
	pause_page.add_child(heading)
	if not short:
		pause_page.add_child(MenuFrame.subtitle("The sea waits while the ledger is open."))

	# Who am I: the crown's own leader and the effect the bonus table publishes
	# for it, in the words the new-game chooser used (REQ-P5-01, REQ-P5-05).
	# A phone drops the caption, not the reading, so the row costs the compact
	# page what the dropped subtitle gave back.
	if not short:
		pause_page.add_child(MenuFrame.caption("Your leader"))
	crown_label = MenuFrame.subtitle("—")
	crown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_page.add_child(crown_label)

	pause_page.add_child(MenuFrame.caption("Map seed"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	pause_page.add_child(seed_row)
	seed_label = MenuFrame.subtitle("—")
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_label)
	copy_seed_button = MenuFrame.small_button("COPY", 96.0)
	seed_row.add_child(copy_seed_button)

	resume_button = MenuFrame.action_button("RESUME", row)
	pause_page.add_child(resume_button)

	save_button = MenuFrame.action_button("SAVE GAME", row)
	pause_page.add_child(save_button)

	load_button = MenuFrame.action_button("LOAD GAME", row)
	pause_page.add_child(load_button)

	# The chart's controls, one press from the pause: a keyboard player never
	# guesses a key, and a touch player reads the door that does the same work
	# (`KeyReference`; REQ-P5-03).
	keys_button = MenuFrame.action_button("KEYS", row)
	pause_page.add_child(keys_button)

	main_menu_button = MenuFrame.action_button("MAIN MENU", row)
	pause_page.add_child(main_menu_button)

	# The mix desk lives here now: the map's cartouche carries no sound seal.
	pause_page.add_child(MenuFrame.separator())
	sound_desk = SoundDesk.new()
	sound_desk.name = "SoundDesk"
	pause_page.add_child(sound_desk)

	status = MenuFrame.subtitle("")
	status.add_theme_color_override("font_color", Palette.GOLD_PALE)
	pause_page.add_child(status)
