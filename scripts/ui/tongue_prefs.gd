class_name TonguePrefs
extends RefCounted
## The reader's chosen tongue and its persistence (REQ-P5-07): the court speaks
## the tongue he picked, on phone, tablet and desktop alike, and the pick
## survives a restart. Node-free so the contract is unit-testable on its own,
## like [AudioMix] and [PanelDock].
##
## An empty record means "follow this device": the reader who never opened the
## settings page reads his own tongue, which is how the French court shipped
## (DR-20261113-06).

const SETTINGS_PATH := "user://tongue.cfg"
const SECTION := "dialogue"
const KEY := "tongue"


## The tongue the reader picked, or "" when he never picked one.
static func stored(path: String = SETTINGS_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return ""
	return String(config.get_value(SECTION, KEY, "")).strip_edges()


## Applies the stored choice, or the device's own tongue when nothing is
## stored. Returns the locale the court now reads.
static func apply(path: String = SETTINGS_PATH) -> String:
	var code: String = stored(path)
	if code.is_empty():
		return DialogueLocale.follow_device()
	DialogueLocale.set_locale(code)
	return DialogueLocale.locale()


## Records a choice and applies it at once, so the next line a court speaks
## answers in it. An empty code means "follow this device" and clears the
## record. Returns false only when the choice could not be written — the
## tongue still moves, and the page says so (REQ-P5-05).
static func choose(code: String, path: String = SETTINGS_PATH) -> bool:
	var wanted: String = code.strip_edges().to_lower()
	if wanted.is_empty():
		DialogueLocale.follow_device()
	else:
		DialogueLocale.set_locale(wanted)
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY, wanted)
	return config.save(path) == OK
