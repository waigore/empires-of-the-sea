class_name AiWorkQuery
extends RefCounted
## One reading of the court's work state: the difficulty knobs, the chart, the
## crew being asked, the roster it belongs to, the works and stores it may
## spend, the studies it holds, the published docket and the tiles another crew
## already claimed this turn.
##
## Every civilian work module reads the same ten fields, so they travel as one
## value instead of ten positional arguments a caller can transpose — `units`
## and `works` are both objects, and a swapped pair would still compile
## (REQ-P3-01, REQ-P3-02). A module that needs more (a town's raw rows, the
## capital network, a screen already up) takes it as its own extra argument, so
## the shared reading stays one shape.
##
## Pure data: state in, no rules touched (REQ-P3-03).

var config: AiConfig = null
var model: MapModel = null
var unit: CivilianState = null
var units: Array = []
var works: LandWorks = null
var stockpile: Dictionary = {}
var tech_caps: Dictionary = {}
var tech_unlocked: Dictionary = {}
var context: Dictionary = {}
var reserved: Dictionary = {}


## The one reading the civilian pass hands every work module for one crew.
static func make(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	reserved: Dictionary
) -> AiWorkQuery:
	var query := AiWorkQuery.new()
	query.config = config
	query.model = model
	query.unit = unit
	query.units = units
	query.works = works
	query.stockpile = stockpile
	query.tech_caps = tech_caps
	query.tech_unlocked = tech_unlocked
	query.context = context
	query.reserved = reserved
	return query


## The roster as the rules read it: the same list, typed for CivilianWork.
func roster() -> Array[CivilianState]:
	var typed: Array[CivilianState] = []
	typed.assign(units)
	return typed


## Whether the court is at war this turn, as the docket published it.
func at_war() -> bool:
	return bool(context.get("at_war", false))


## The court's own chart of the region, or null when the caller published none.
func view() -> VisibilityModel:
	return context.get("visibility", null)
