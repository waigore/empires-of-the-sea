class_name TileOwnership
extends RefCounted
## Per-tile ownership overrides for one region (wiki: world-model-identity,
## civilian-units § Merchant). A tile without an override belongs to its
## province owner; a purchased tile keeps its deed even when the province is
## still held by a Minor Nation or Tribe. Pure data so saves and rules can share
## it (REQ-P3-03).

const NO_OWNER: int = -1

## Tile index -> faction id. Sparse, so ordinary provinces cost nothing.
var owners: Dictionary = {}
## Tile index -> buying faction id. A tile is bought at most once.
var purchased: Dictionary = {}


func clear() -> void:
	owners.clear()
	purchased.clear()


func has_deed(index: int) -> bool:
	return owners.has(index)


func owner_of(index: int, fallback: int) -> int:
	return int(owners.get(index, fallback))


func is_purchased(index: int) -> bool:
	return purchased.has(index)


func purchaser(index: int) -> int:
	return int(purchased.get(index, NO_OWNER))


## Records a first purchase. Returns false when the tile already has a deed.
func purchase(index: int, buyer: int) -> bool:
	if index < 0 or buyer < 0 or purchased.has(index):
		return false
	owners[index] = buyer
	purchased[index] = buyer
	return true


## Plain data for local saves; int keys survive Godot's text variant writer.
func to_dict() -> Dictionary:
	return {
		"owners": owners.duplicate(),
		"purchased": purchased.duplicate(),
	}


func apply_dict(data: Dictionary) -> void:
	owners = _int_keys(data.get("owners", {}))
	purchased = _int_keys(data.get("purchased", {}))


## Index -> true for every land tile this faction owns, including purchased
## enclaves and excluding tiles carved out of its own provinces.
func owned_indices(model, faction: int) -> Dictionary:
	var result: Dictionary = {}
	for province_record: ProvinceState in model.provinces:
		if province_record.owner != faction:
			continue
		for tile: Vector2i in province_record.tiles:
			var index: int = model.index_of(tile.x, tile.y)
			if has_deed(index) and owner_of(index, faction) != faction:
				continue
			result[index] = true
	for raw: Variant in owners.keys():
		var index: int = int(raw)
		if owner_of(index, NO_OWNER) == faction:
			result[index] = true
	return result


## Owned land tiles in row-major order, for extraction and the estates ledger.
func owned_tiles(model, faction: int) -> Array[Vector2i]:
	var indices: Dictionary = owned_indices(model, faction)
	var ordered: Array[int] = []
	for raw: Variant in indices.keys():
		ordered.append(int(raw))
	ordered.sort()
	var result: Array[Vector2i] = []
	for index: int in ordered:
		var y: int = int(index / model.width)
		result.append(Vector2i(index - y * model.width, y))
	return result


static func _int_keys(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	var source: Dictionary = raw
	for key: Variant in source.keys():
		result[int(key)] = int(source[key])
	return result
