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
## Regions whose setup post-pass (ports, roads, grain farms) already ran.
var bootstrapped_regions: Dictionary = {}
var land_works: LandWorks = null
var economy: EconomyController = null
var diplomacy: DiplomacyState = null
## Rival-court AI bookkeeping (fixed agendas, per-pair cooldowns) and the last
## turn's decision trace (wiki: ai-architecture).
var ai: AiState = null
var ai_seed: int = 0
var ai_trace: Array[Dictionary] = []

var turn: int = 1
var prestige: int = 38
var income: int = 120
var selected_province: int = -1
var capital_province: int = -1
var capital_tile: Vector2i = CapitalChoice.NO_TILE
var hover_province: int = -1
var charted_provinces: Dictionary = {}
## Last resolved army feeding coverage per faction (fed / demanded rations).
var feeding: Dictionary = {}
## Faction -> leaderKey; empty until leader selection ships (wiki: leader-bonuses).
var leaders: Dictionary = {}

var ship_layer: ShipLayer = null
var civilian_layer: CivilianLayer = null
var army_layer: ArmyLayer = null
var canvas: MapCanvas = null
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
	p_armies: ArmyLayer,
	p_canvas: MapCanvas,
	p_overlay: MapOverlay,
	p_camera: MapCamera,
	p_hud: GameHud,
	p_improvements: ImprovementPanel
) -> void:
	ship_layer = p_ships
	civilian_layer = p_civilians
	army_layer = p_armies
	canvas = p_canvas
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


## Extraction caps this crown's researched techs allow, per commodity
## (wiki: tech-and-extraction-cap). Empty before the economy exists.
func tech_caps() -> Dictionary:
	if economy == null or economy.economy == null:
		return {}
	return TechCatalog.extraction_caps(economy.economy.tech_unlocked)


## Researched tech ids, for work-order gates that are not extraction caps.
func tech_unlocked() -> Dictionary:
	if economy == null or economy.economy == null:
		return {}
	return economy.economy.tech_unlocked


## Recomputes which resources the crown has seen, so discovery techs unlock
## once an explorer reveals (and prospects) them (wiki: tech-tree § Discovery).
func refresh_research() -> void:
	if economy == null or economy.economy == null:
		return
	economy.economy.research.set_revealed(
		TechDiscovery.revealed(world, visibility_by_region, land_works, PLAYER_FACTION)
	)


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


## Political ownership changed (Join Empire): ask the screen to redraw the map.
func refresh_map_views() -> void:
	if host != null and host.has_method("refresh_political_map"):
		host.call("refresh_political_map")


## Swaps the whole view onto another region (fleet crossing a passage).
func switch_region(index: int) -> void:
	if host != null and host.has_method("load_region"):
		host.call("load_region", index)
