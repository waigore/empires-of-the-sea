class_name NameRoster
extends RefCounted
## Deterministic christening shared by hulls, regiments and generals (wiki:
## naming; DR-20261111-07/18, DR-20261112-03). Pure arithmetic over a crown's
## period pool and a stable key: the same crown, container and instance id
## always christen the same title, so a reloaded campaign speaks the same names
## and a legacy save is named on read by the same arithmetic (REQ-P2-03,
## REQ-P3-03). The three rosters keep their own pool data and state; only the
## pick, the numbering and the FNV-1a digest live here, once.

## A pool cycled past its last free name numbers the repeats: "Revenge II".
const ORDINALS: Array[String] = ["", " II", " III", " IV", " V", " VI", " VII", " VIII"]
const HASH_OFFSET: int = 2166136261
const HASH_PRIME: int = 16777619


## The pool a crown names from; a crown with no pool of its own reads the
## generic one.
static func pool_of(
	pools: Dictionary, generic: Array[String], owner: int
) -> Array[String]:
	var raw: Variant = pools.get(owner, generic)
	var pool: Array[String] = []
	pool.assign(raw)
	return pool


## The title `key` takes from `pool`: a stable pick advanced past the names the
## unit already bears, numbering a repeat once the whole pool is spent.
## `fallback` names the unit when its crown has no pool at all.
static func pick(
	pool: Array[String], key: String, taken: Array[String], fallback: String
) -> String:
	if pool.is_empty():
		return fallback
	var start: int = stable_hash(key) % pool.size()
	var index: int = start
	for _step in pool.size():
		var candidate: String = pool[index % pool.size()]
		if not taken.has(candidate):
			return candidate
		index += 1
	var base: String = pool[start % pool.size()]
	for cycle in range(1, ORDINALS.size()):
		var numbered: String = base + ORDINALS[cycle]
		if not taken.has(numbered):
			return numbered
	return base + ORDINALS[ORDINALS.size() - 1]


## The names a roster already bears, read from its id → title store and leaving
## out `skip_id` (the instance being christened carries no name yet).
static func taken_names(
	ids: Array[String], store: Dictionary, skip_id: String = ""
) -> Array[String]:
	var names: Array[String] = []
	for id: String in ids:
		if id == skip_id:
			continue
		var name: String = String(store.get(id, ""))
		if not name.is_empty():
			names.append(name)
	return names


## Reads a saved id → title map; JSON keys arrive as strings.
static func map_from(raw: Variant) -> Dictionary:
	var mapped: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			mapped[String(key)] = String((raw as Dictionary)[key])
	return mapped


## FNV-1a over the key, so a name never depends on Godot's own hashing. This
## arithmetic is part of the save contract: change it and every stored title
## would be re-drawn on the next load.
static func stable_hash(text: String) -> int:
	var value: int = HASH_OFFSET
	for byte in text.to_utf8_buffer():
		value = (value ^ int(byte)) * HASH_PRIME
		value = value & 0xFFFFFFFF
	return value
