class_name PlaySession
extends RefCounted
## Narrow play context for MapPlay* helpers (REQ-P3-02).
## Holds session state and injected presentation refs — not a Node/autoload.
## MapScreen owns the Node tree and signals; helpers talk through this bag.

const TILE_SIZE: float = 22.0
const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION

var world: WorldMap = null
## Region currently on screen (Old World first).
var region_index: int = 0
var model: MapModel = null
var visibility: VisibilityModel = null
## One fog model per region, kept across map switches.
var visibility_by_region: Dictionary = {}
var land_works: LandWorks = null
var economy: EconomyController = null

var turn: int = 1
var prestige: int = 38
var income: int = 120
var selected_province: int = -1
var capital_province: int = -1
var capital_tile: Vector2i = CapitalChoice.NO_TILE
var hover_province: int = -1
var charted_provinces: Dictionary = {}

var ship_layer: ShipLayer = null
var civilian_layer: CivilianLayer = null
var overlay: MapOverlay = null
var camera: MapCamera = null
var hud: GameHud = null
var improvements: ImprovementPanel = null

## MapScreen (or test double) that owns signals and the viewport.
var host: Node = null


func bind_host(p_host: Node) -> void:
	host = p_host


func bind_views(
	p_ships: ShipLayer,
	p_civilians: CivilianLayer,
	p_overlay: MapOverlay,
	p_camera: MapCamera,
	p_hud: GameHud,
	p_improvements: ImprovementPanel
) -> void:
	ship_layer = p_ships
	civilian_layer = p_civilians
	overlay = p_overlay
	camera = p_camera
	hud = p_hud
	improvements = p_improvements


## Player ledger — single source of truth (no mirrored MapScreen.treasury).
func treasury() -> int:
	if economy == null or economy.economy == null:
		return 0
	return economy.economy.treasury


## Provinces the player currently holds in the region on screen.
func owned_provinces() -> int:
	return world.owned_provinces(region_index, PLAYER_FACTION)


## Squadrons, civilians and training exist only where the player holds land.
func player_present() -> bool:
	return owned_provinces() > 0


func stockpile() -> Dictionary:
	if economy == null or economy.economy == null:
		return {}
	return economy.economy.stockpile


func viewport() -> Viewport:
	if host == null:
		return null
	return host.get_viewport()


func emit_province_selected(province_id: int) -> void:
	if host != null:
		host.emit_signal("province_selected", province_id)


func emit_selection_cleared() -> void:
	if host != null:
		host.emit_signal("selection_cleared")


func emit_coast_charted(province_id: int) -> void:
	if host != null:
		host.emit_signal("coast_charted", province_id)


func emit_battle_resolved(battles: Array[Dictionary]) -> void:
	if host != null:
		host.emit_signal("battle_resolved", battles)


func emit_turn_ended(p_turn: int) -> void:
	if host != null:
		host.emit_signal("turn_ended", p_turn)
