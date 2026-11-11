class_name ShellSoundtrack
extends Node
## App-shell score (REQ-P1-06). The sea bed and its ambience start on the first
## frame of the application, before any campaign year exists, and the mute
## shortcut answers on every page. The shell owns one AudioDirector and hands it
## to the map screen, so opening a campaign never restarts the tune.

var audio: AudioDirector = null


func _ready() -> void:
	audio = get_parent().get_node_or_null("Audio") as AudioDirector
	play_menu_bed()


## Title, setup, load and the crown's charge all sit on the era the campaign
## opens on, so the first turn begins on a bed already in progress.
func play_menu_bed() -> void:
	if audio == null:
		return
	audio.play_music(MusicPlaylist.menu_bed_id())


## Global mute key: one handler for the whole app, ahead of page input so the
## title screen and the map both answer it.
func _shortcut_input(event: InputEvent) -> void:
	if audio == null or not InputMap.has_action(InputActions.MUTE):
		return
	if not event.is_action_pressed(InputActions.MUTE):
		return
	audio.toggle_mute()
	audio.play_event(AudioEvents.UI_CLICK)
	get_viewport().set_input_as_handled()
