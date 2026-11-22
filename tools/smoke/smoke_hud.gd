extends RefCounted
## Fourth step of the e2e smoke: the bar's doors and the courts — the court
## ledger's war and peace orders with its envoy's reading and the mark on the
## court it is bound for (DR-20261122-11), the sound desk's mute, and one tap on
## an inland province that must stick (REQ-P5-01, REQ-P5-07). The director and
## its cue count stay on the run for the end-of-turn read. The counsel readings
## on the bar's ledgers are their own step (tools/smoke/smoke_counsel.gd).
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeFind = preload("res://tools/smoke/smoke_find.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	await _court(run, screen)
	_audio(run, screen)
	await _province(run, screen)


## The court ledger: seeded relations, a declaration, a peace, and the court's
## own voice and intelligence reading (wiki: diplomacy).
static func _court(run, screen: MapScreen) -> void:
	MapPlayDiplomacy.open(screen.play)
	await run.tree.process_frame
	run.check(screen.play.diplomacy != null, "diplomacy state seeded")
	run.check(
		screen.play.diplomacy.relations.size() >= 81,
		"same-region relations seeded"
	)
	run.check(screen.hud.panels.is_diplomacy_open(), "court ledger opens")
	MapPlayDiplomacy.on_order(screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	run.check(screen.play.diplomacy.relation(0, 1).at_war, "war order applies")
	screen.hud.panels.diplomacy_panel.select_faction(1)
	# The court's own envoy: the one order her staff's planner would spend this
	# turn, printed above the presses it answers (DR-20261121-05).
	var counsel: String = screen.hud.panels.diplomacy_panel.counsel_text()
	run.check(not counsel.is_empty(), "the court names the order its envoy would spend")
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, counsel),
		"the envoy's counsel is on the court's sheet"
	)
	# The crown list marks the court the envoy's one order is bound for, read off
	# the same pick the gold line words (DR-20261122-11).
	var panel: DiplomacyPanel = screen.hud.panels.diplomacy_panel
	var plan: Dictionary = MapPlayDiplomacyPick.plan(screen.play)
	var bound: int = int(
		(plan.get("action", {}) as Dictionary).get("target", MapModel.NO_ID)
	)
	var marked: Array[int] = []
	for faction_id: int in panel._known_ids():
		if panel._is_marked(faction_id):
			marked.append(faction_id)
	run.check(
		marked == ([bound] if bound != MapModel.NO_ID else []),
		"the crown list marks the court the envoy would treat"
	)
	# The order list marks the press the gold line names, and the legend under the
	# line stands with it (DR-20261123-01): one press when the line names one, none
	# when it names none — and no legend without a mark.
	var pressed: bool = run.has_text(
		panel._detail, "%s " % CourtDetailBlock.COURT_MARK
	)
	var press: Dictionary = panel._detail.counsel_press()
	run.check(
		pressed == not press.is_empty(),
		"the order list marks the press the envoy would take"
	)
	run.check(
		run.has_text(
			panel._detail, CourtDetailBlock.MARK_LEGEND % CourtDetailBlock.COURT_MARK
		) == pressed,
		"the legend under the envoy's line stands with the mark"
	)
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, "THEIR ENVOY"),
		"the court answers a declaration in its own voice"
	)
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, "DOSSIER"),
		"the court carries its intelligence reading"
	)
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, "Holds "),
		"the dossier counts the court's public behaviour"
	)
	MapPlayDiplomacy.on_order(screen.play, DiplomacyOrders.KIND_PEACE, 1, "")
	run.check(not screen.play.diplomacy.relation(0, 1).at_war, "peace order applies")
	DiplomacyHud.hide(screen.hud.panels)
	run.check(not screen.hud.panels.is_diplomacy_open(), "court ledger closes")


## The sound desk: one opening bed, sea ambience, a counted cue, and a mute that
## silences the music (REQ-P1-06).
static func _audio(run, screen: MapScreen) -> void:
	run.audio = run.main.get_node_or_null("Audio") as AudioDirector
	var controls: SoundDesk = screen.game_menu.sound_desk
	run.check(run.audio != null, "audio director present")
	run.check(controls != null, "sound desk in the pause menu")
	if run.audio == null:
		return
	# The drive is a wall-clock gate, so every fade it asks for lands at once:
	# a bed nobody waits out buys frames, not quieter rules (docs/testing.md
	# § Speed rules). The knobs the asserts read below are the live ones.
	run.audio.fade_scale = 0.0
	run.check(
		run.audio.current_track_id() == MusicPlaylist.AGE_OF_DISCOVERY, "opening bed playing"
	)
	run.check(run.audio._ambience.playing, "sea ambience playing")
	run.cues_before = run.audio.sfx_played
	run.check(run.audio.play_event(AudioEvents.UI_CLICK), "ui cue fires")
	run.check(run.audio.sfx_played == run.cues_before + 1, "ui cue counted")
	run.audio.set_muted(true)
	run.check(
		run.audio._active_player().volume_db == AudioDirector.SILENT_DB, "mute silences music"
	)
	run.audio.set_muted(false)
	# A driven run ends its fades on the frame it asks for them (fade_scale 0),
	# so nothing keeps resolving after the asserts above — a killed frame would
	# leave the next step's boot or the exit waiting on it (docs/testing.md
	# § Speed rules).
	run.audio.land_fades()


## One tap on an inland province: the selection sticks and its dossier opens.
static func _province(run, screen: MapScreen) -> void:
	var province_id: int = SmokeFind.inland_province(screen)
	run.check(province_id >= 0, "inland province available")
	if province_id < 0:
		return
	var world: Vector2 = screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	MapPlayInput.on_tapped(screen.play, world)
	await run.tree.process_frame
	run.check(screen.selected_province == province_id, "province selection sticks")
	run.check(screen.hud.panels.is_panel_open(), "province panel opens")
	# The capital's rail carries the court's own hire pick: the crew the published
	# hire order takes next, or the gate that holds it (wiki: civilian-units
	# § Training; DR-20261121-06). Any other province hires nobody and says so.
	MapPlayInput.select_province(
		screen.play, screen.capital_province,
		screen.model.province_center(screen.capital_province) * MapScreen.TILE_SIZE
	)
	await run.tree.process_frame
	run.check(
		not screen.hud.panels.panel.hire_line_text().is_empty(),
		"the capital rail names the hire the court takes"
	)
	run.check(
		screen.play.economy.economy.recruits.is_empty(),
		"the hire reading queues nothing"
	)
	# The dossier also names the orders the court would give on this province's
	# ground: the work its civilian pass would put crews to here and the hosts
	# its land pass would send here, or nothing (wiki: world-model § The crown's
	# provinces; DR-20261121-19).
	run.check(
		screen.hud.panels.panel.counsel_source.is_valid(),
		"the province sheet binds the court's reading"
	)
	var counsel: String = screen.hud.panels.panel.counsel_text()
	run.check(
		counsel.is_empty()
		or counsel.begins_with("The court would order ")
		or counsel == MapPlayPickProse.sentence(MapPlayProvinceCounsel.NO_WORK_LINE),
		"the province sheet names the orders the court would give here"
	)
	run.check(
		screen.play.economy.economy.recruits.is_empty(),
		"the province reading queues nothing"
	)
