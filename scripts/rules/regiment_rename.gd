class_name RegimentRename
extends RefCounted
## The crown names its own colours (wiki: naming § Regiment names;
## DR-20261113-03). A name is identity only — strength, casualties, chevrons,
## rest, upkeep, price and every AI decision keep reading the type and the
## instance id, so a rename never moves an outcome (REQ-P2-03). Pure data: the
## caller holds the army and the order, this module only reads and writes the
## one store the christening already fills (REQ-P3-03).

## Longest name a colours may bear, so a title still fits a phone dossier row.
const MAX_CHARS: int = 28


## Whether `wanted` may be borne by `regiment_id` in `army`. Never mutates:
## `{ok, reason, name}` with the cleaned name, so the caller can print what was
## actually kept. Ownership is the caller's gate — a rival's army is never
## offered the order — and nothing here reads who is at war with whom.
static func check(army: ArmyState, regiment_id: String, wanted: String) -> Dictionary:
	if army == null:
		return _deny("There is no army to name.")
	if not army.regiments.has(regiment_id):
		return _deny("That regiment is not in this army.")
	var name: String = _clean(wanted)
	if name.is_empty():
		return _deny("A regiment needs a name.")
	if name.length() > MAX_CHARS:
		return _deny("Keep the name to %d letters." % MAX_CHARS)
	for other: String in army.regiments:
		if other == regiment_id:
			continue
		if RegimentNames.of(army, other).to_lower() == name.to_lower():
			return _deny("Another colour in this army bears that name.")
	return {"ok": true, "reason": "", "name": name}


## Writes the name onto the colours and returns `check`'s verdict, so a caller
## that only applies the order still reads the refusal. A refused name leaves
## the colours as they were.
static func apply(army: ArmyState, regiment_id: String, wanted: String) -> Dictionary:
	var verdict: Dictionary = check(army, regiment_id, wanted)
	if not bool(verdict["ok"]):
		return verdict
	army.regiment_names[regiment_id] = String(verdict["name"])
	return verdict


## The name the player typed, tidied into what a title may hold: no line breaks
## and single spaces, so a pasted name cannot break the dossier's rows.
static func _clean(wanted: String) -> String:
	var text: String = wanted.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	var words: PackedStringArray = text.split(" ", false)
	return " ".join(words).strip_edges()


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "name": ""}
