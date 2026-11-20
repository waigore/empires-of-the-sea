class_name KeyReference
extends RefCounted
## The chart's controls as one page of words (docs/ui-demo.md § Controls;
## REQ-P5-03, REQ-P5-07). Pure data: every row names the `InputActions` action
## that answers it, and the page prints the key the InputMap actually holds, so
## a rebound key moves the sheet and never a second table (REQ-P2-03).
##
## A row also names the **door** a touch player presses instead, because a phone
## has no keyboard and the sheet must still read as an answer on one
## (`REQ-P1-05`): the seal, the plaque or the dossier the same reading is filed
## behind. The words are the controls' own — no price, rule or score is here.

## Four groups, in the order the court meets them: the chart itself, the map's
## readings, the ledgers, then the turn.
const GROUPS: Array[Dictionary] = [
	{
		"title": "The chart",
		"rows":
		[
			{
				"label": "Pan",
				"actions": [
					InputActions.PAN_UP,
					InputActions.PAN_LEFT,
					InputActions.PAN_DOWN,
					InputActions.PAN_RIGHT,
				],
				"spaced": true,
				"door": "drag the chart",
			},
			{
				"label": "Zoom",
				"actions": [InputActions.ZOOM_IN, InputActions.ZOOM_OUT],
				"door": "pinch the chart",
			},
			{
				"label": "Seat",
				"actions": [InputActions.FOCUS_CAPITAL],
				"door": "Capital seal",
			},
			{
				"label": "Back",
				"actions": [InputActions.CANCEL],
				"door": "Close on a sheet",
			},
		],
	},
	{
		"title": "Map readings",
		"rows":
		[
			{
				"label": "Any reading",
				"actions": [InputActions.LENS],
				"door": "Lens seal cycles",
			},
			{
				"label": "Trade & politics",
				"actions": [InputActions.DIPLOMACY_LENS],
				"door": "Lens seal cycles",
			},
			{
				"label": "Crown road",
				"actions": [InputActions.CROWN_LENS],
				"door": "Lens seal cycles",
			},
			{
				"label": "Garrison & wall",
				"actions": [InputActions.DEFENCE_LENS],
				"door": "Lens seal cycles",
			},
			{
				"label": "Squadrons & fights",
				"actions": [InputActions.SEA_LENS],
				"door": "Lens seal cycles",
			},
		],
	},
	{
		"title": "Ledgers",
		"rows":
		[
			{"label": "Muster roll", "actions": [InputActions.MUSTER_ROLL], "door": "Muster seal"},
			{
				"label": "Crew roster",
				"actions": [InputActions.CIVILIAN_ROSTER],
				"door": "Civilians plaque",
			},
			{
				"label": "The realm",
				"actions": [InputActions.PROVINCE_LEDGER],
				"door": "Realm seal · province dossier › Realm",
			},
			{
				"label": "Commanders",
				"actions": [InputActions.COMMAND_LEDGER],
				"door": "Army dossier › Commanders",
			},
			{"label": "The crown's eyes", "actions": [InputActions.SPY_LEDGER], "door": "Court › Eyes"},
			{
				"label": "The crown's navy",
				"actions": [InputActions.NAVY_LEDGER],
				"door": "Muster roll › Navy",
			},
		],
	},
	{
		"title": "The turn",
		"rows":
		[
			{"label": "End turn", "actions": [InputActions.END_TURN], "door": "End turn seal"},
			{"label": "Sound", "actions": [InputActions.MUTE], "door": "Menu › sound desk"},
		],
	},
]

## Nothing to print for an action no keyboard answers.
const NO_KEY: String = "—"


## The page's groups with every key already resolved: `{title, rows}` where a
## row is `{label, keys, door}`. The sheet prints this and decides nothing.
static func groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in GROUPS:
		var group: Dictionary = raw
		var rows: Array[Dictionary] = []
		for raw_row: Variant in group.get("rows", []):
			var row: Dictionary = raw_row
			rows.append({
				"label": String(row.get("label", "")),
				"keys": keys_for(
					row.get("actions", []), bool(row.get("spaced", false))
				),
				"door": String(row.get("door", "")),
			})
		out.append({"title": String(group.get("title", "")), "rows": rows})
	return out


## The keys one row prints, in the order the action list names them: the primary
## binding of each action, deduped, joined with " / " (or spaces for a movement
## cluster, so four pan keys read `W A S D` rather than a slash run).
static func keys_for(actions: Array, spaced: bool = false) -> String:
	var out: Array[String] = []
	for raw: Variant in actions:
		var key: String = primary(String(raw))
		if key.is_empty() or out.has(key):
			continue
		out.append(key)
	if out.is_empty():
		return NO_KEY
	return (" " if spaced else " / ").join(out)


## The first key the InputMap binds to an action, as a player reads it off the
## cap; "" when the action is unbound or this build never registered it.
static func primary(action: String) -> String:
	if action.is_empty() or not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		return OS.get_keycode_string(key.physical_keycode)
	return ""


## Every action the page names, once each — the drift guard a test reads against
## `InputActions`'s own constants, so a new control cannot ship unread.
static func actions() -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in GROUPS:
		for raw_row: Variant in (raw as Dictionary).get("rows", []):
			for raw_action: Variant in (raw_row as Dictionary).get("actions", []):
				var action: String = String(raw_action)
				if not out.has(action):
					out.append(action)
	return out
