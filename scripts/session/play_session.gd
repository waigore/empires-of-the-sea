class_name PlaySession
extends RefCounted
## Narrow play context for MapPlay* helpers (REQ-P3-02).
## Holds session state and injected presentation refs — not a Node/autoload.
## MapScreen owns the Node tree and signals; helpers talk through this bag.

const TILE_SIZE: float = 22.0
## Legacy default (Spain); a game setup may choose another Great Power.
const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION

## Human slot chosen in game setup; the rules read this everywhere the player
## is special-cased (view, upkeep, diplomacy).
var player_faction: int = PLAYER_FACTION
## Full-AI observer (wiki: game-setup § Human/AI slot assignment): every Great
## Power runs the AI planners and no court holds consent decisions. Debug tool,
## not a player-facing campaign mode.
var observer_mode: bool = false
## One merged record per resolved turn (MapPlayObserver); the observatory panel
## and the headless exporter read it (wiki: turn-trace-interpretation).
var ai_turns: Array[Dictionary] = []
## Endless campaign chosen at setup: the calendar cap never closes the age
## (wiki: turn-time-mapping § Campaign calendar cap).
var infinite_mode: bool = false
## Advanced-start preset (wiki: advanced-starts; DR-20261111-01). Empty/"none"
## is the ordinary turn-0 campaign.
var advanced_start: String = AdvancedStart.NONE
## Set once the calendar cap closes an undecided campaign; turns stay shut even
## though no victory was declared (wiki: victory § Calendar campaign end).
var campaign_halted: bool = false
## Generation recipe, kept so a save can rebuild the identical world.
var map_seed: int = 1500
var map_width: int = 128
var map_height: int = 84

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
## Set once the rules decide the campaign (wiki: victory); turns then stay shut.
var victory: VictoryState = null
## Set when the human Great Power suffers terminal fall: the session is defeated
## and sealed, distinct from a military victory (wiki: victory § Great Power
## defeat; DR-20261109-05).
var defeat: DefeatState = null
## A consent decision (call to arms) holds turn resolution until answered
## (wiki: diplomacy § Alliances).
var turn_suspended: bool = false
## Rival-court AI bookkeeping (fixed agendas, per-pair cooldowns) and the last
## turn's decision trace (wiki: ai-architecture).
var ai: AiState = null
var ai_trace: Array[Dictionary] = []
## Despatch of the last resolved turn for every court a Spy shadows — `turn`,
## `shadowed` (rival Great Powers covered) and `facts` (wiki: civilian-units
## § Spy — court reports). Derived, so a save carries no copy.
var court_reports: Dictionary = {}
## Event count when the player's turn started resolving, so the despatch reads
## only this turn's diplomatic acts (the ledger's own turn stamp may lag).
var court_report_mark: int = 0

var turn: int = 1
## Quick Battle stance for the human's land battles: aggressive, balanced or
## defensive (wiki: quick-battle § Turn structure and actions).
var battle_plan: String = "balanced"
var income: int = 120
var selected_province: int = -1
var capital_province: int = -1
var capital_tile: Vector2i = CapitalChoice.NO_TILE
var hover_province: int = -1
var charted_provinces: Dictionary = {}
## Last resolved army feeding coverage per faction (fed / demanded rations).
var feeding: Dictionary = {}
## Faction -> leaderKey, fixed at game start and serialized with the save
## (wiki: leader-bonuses § Leader Selection).
var leaders: Dictionary = {}

var ship_layer: ShipLayer = null
var civilian_layer: CivilianLayer = null
var army_layer: ArmyLayer = null
var canvas: MapCanvas = null
var overlay: MapOverlay = null
## Resource survey lens: a view, never a rules source (REQ-P3-03).
var lens: ResourceLens = null
## Diplomatic lens: political standing wash, also presentation only.
var diplomacy_lens: DiplomacyLens = null
var camera: MapCamera = null
var hud: GameHud = null
var improvements: ImprovementPanel = null

## MapScreen (or test double) that owns signals and the viewport.
var host: Node = null


func bind_host(p_host: Node) -> void:
	host = p_host


## Starts a fresh run in this session: generation recipe, human crown, the
## leaderKey and whether the campaign may outlive the calendar. Rival crowns
## take their configured leader (wiki: leader-bonuses). An advanced start also
## moves the opening turn onto its preset (wiki: advanced-starts).
func configure(
	faction: int,
	seed_value: int,
	width: int,
	height: int,
	leader: String = "",
	infinite: bool = false,
	advanced: String = ""
) -> void:
	player_faction = faction
	map_seed = seed_value
	map_width = width
	map_height = height
	infinite_mode = infinite
	advanced_start = AdvancedStart.normalize(advanced)
	turn = AdvancedStart.turn(advanced_start)
	leaders = LeaderCatalog.roster(faction, leader)


func bind_views(
	p_ships: ShipLayer,
	p_civilians: CivilianLayer,
	p_armies: ArmyLayer,
	p_canvas: MapCanvas,
	p_overlay: MapOverlay,
	p_camera: MapCamera,
	p_hud: GameHud,
	p_improvements: ImprovementPanel,
	p_lens: ResourceLens = null,
	p_diplomacy_lens: DiplomacyLens = null
) -> void:
	ship_layer = p_ships
	civilian_layer = p_civilians
	army_layer = p_armies
	canvas = p_canvas
	overlay = p_overlay
	camera = p_camera
	hud = p_hud
	improvements = p_improvements
	lens = p_lens
	diplomacy_lens = p_diplomacy_lens


## Player ledger — single source of truth (no mirrored MapScreen.treasury).
func treasury() -> int:
	if economy == null or economy.economy == null:
		return 0
	return economy.economy.treasury


## The court that answers consent decisions, or NO_ID when every crown is AI
## (the full-AI observer). Rules modules read this instead of player_faction.
func human_faction_id() -> int:
	return MapModel.NO_ID if observer_mode else player_faction


## Provinces the player currently holds in the region on screen.
func owned_provinces() -> int:
	return world.owned_provinces(region_index, player_faction)


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


## The ledger that answers for a crown: the human's, or a rival's. In the
## full-AI observer no human ledger resolves, so every crown answers from its
## AI ledger — the same rule the observer scoreboard reads (REQ-P2-03).
func ledger_for(faction: int) -> PlayerEconomy:
	if observer_mode or faction != player_faction:
		if ai == null:
			return null
		return ai.economy_for(faction)
	if economy == null:
		return null
	return economy.economy


## Researched tech for any crown: the human's ledger, or a rival's when the
## rules ask about a rival squadron (wiki: tech-tree; REQ-P2-03). Rules take
## this as a Callable so a presentation layer cannot answer for them.
func has_tech(faction: int, tech_id: String) -> bool:
	if tech_id.is_empty():
		return false
	var ledger: PlayerEconomy = ledger_for(faction)
	if ledger == null:
		return false
	return bool(ledger.tech_unlocked.get(tech_id, false))


## Recomputes which resources the crown has seen, so discovery techs unlock
## once an explorer reveals (and prospects) them (wiki: tech-tree § Discovery).
func refresh_research() -> void:
	if economy == null or economy.economy == null:
		return
	economy.economy.research.set_revealed(
		TechDiscovery.revealed(world, visibility_by_region, land_works, player_faction)
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


## The turn's raids, in either direction: the screen answers with a cue and a
## ring on the waters that were worked (REQ-P5-06).
func emit_raid_resolved(raids: Array[Dictionary]) -> void:
	if host != null and host.has_signal("raid_resolved"):
		host.emit_signal("raid_resolved", raids)


func emit_turn_ended(p_turn: int) -> void:
	if host != null:
		host.emit_signal("turn_ended", p_turn)


## The rules closed the campaign — a military victory or the human crown's
## fall; the screen forwards the moment to audio and motion.
func emit_campaign_end(victory: VictoryState = null, defeat: DefeatState = null) -> void:
	if host == null:
		return
	if defeat != null and host.has_signal("defeat_declared"):
		host.emit_signal("defeat_declared", defeat)
	elif victory != null:
		host.emit_signal("victory_declared", victory)


## Turns, orders and map intents close for good once a victory is declared, the
## human crown falls, or the calendar cap closes the age (wiki: victory,
## turn-time-mapping).
func campaign_over() -> bool:
	return victory != null or defeat != null or campaign_halted


## Political ownership changed (Join Empire): ask the screen to redraw the map.
func refresh_map_views() -> void:
	if host != null and host.has_method("refresh_political_map"):
		host.call("refresh_political_map")


## Swaps the whole view onto another region (fleet crossing a passage).
func switch_region(index: int) -> void:
	if host != null and host.has_method("load_region"):
		host.call("load_region", index)
