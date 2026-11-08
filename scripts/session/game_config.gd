class_name GameConfig
extends RefCounted
## New-game choices from the setup screen (wiki: game-setup). The map is
## generated from seed + region sizes, so these four values are all a save
## needs to rebuild the world.

const DEFAULT_SEED: int = 1500
const DEFAULT_SIZE_INDEX: int = 1

## Playable map presets; Standard matches the desktop default.
const SIZES: Array[Dictionary] = [
	{"label": "Small", "width": 96, "height": 64},
	{"label": "Standard", "width": 128, "height": 84},
	{"label": "Large", "width": 160, "height": 104},
]

var map_seed: int = DEFAULT_SEED
var map_width: int = 128
var map_height: int = 84
## The human Great Power slot; the rest are AI.
var player_faction: int = FactionCatalog.PLAYER_FACTION


static func make(
	seed_value: int, size_index: int, player: int = FactionCatalog.PLAYER_FACTION
) -> GameConfig:
	var config := GameConfig.new()
	config.map_seed = seed_value
	config.apply_size(size_index)
	config.player_faction = player
	return config


func apply_size(index: int) -> void:
	var clamped: int = clampi(index, 0, SIZES.size() - 1)
	map_width = int(SIZES[clamped]["width"])
	map_height = int(SIZES[clamped]["height"])


## A non-zero seed keeps the wiki's "same seed, same world" guarantee.
static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 999_999)


func to_dict() -> Dictionary:
	return {
		"map_seed": map_seed,
		"map_width": map_width,
		"map_height": map_height,
		"player_faction": player_faction,
	}


static func from_dict(data: Dictionary) -> GameConfig:
	var config := GameConfig.new()
	config.map_seed = int(data.get("map_seed", DEFAULT_SEED))
	config.map_width = int(data.get("map_width", 128))
	config.map_height = int(data.get("map_height", 84))
	config.player_faction = int(data.get("player_faction", FactionCatalog.PLAYER_FACTION))
	return config
