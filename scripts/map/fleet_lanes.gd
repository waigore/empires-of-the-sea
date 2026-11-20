class_name FleetLanes
extends RefCounted
## Where a station's markers stand when several squadrons share one sea zone or
## one port: the crown's squadrons fan out in a short row so each can be picked,
## while the rest of hers and every rival's ride one stack that a tap cycles
## (wiki: ships-and-naval § Fleets in one station; DR-20261119-08). Pure
## bookkeeping, so the layer, the markers and the tests read one plan
## (REQ-P3-01, REQ-P3-03).

## The crown's squadrons in one station that still stand in the row; any others
## of hers, and every rival's, ride the stack behind them.
const FAN_LIMIT: int = 3
## Distance between two markers of one station, in the marker's own drawing
## units: the row keeps its proportions at every chart zoom, because a marker's
## ink scales with the same chart (REQ-P1-07).
const LANE_SPAN: float = 46.0


## The station a squadron keeps: the port she is moored in, else her water.
static func station_of(fleet: FleetState) -> String:
	if fleet == null:
		return ""
	if fleet.is_in_port():
		return "port:%d" % fleet.province
	return "sea:%d" % fleet.sea_zone


## The plan for a region's roster.
##
## `lanes` maps a fleet id to the offset her marker draws at, so a squadron the
## chart draws always has one; `stacks` maps a fleet id to the order a tap
## cycles in her station (a squadron standing alone keeps an empty one);
## `stations` maps every squadron of a shared station to the station's whole
## reading order — the crown's row first, then the stack — so the court can hear
## her place among all of them (`2 of 4 squadrons here`, the row's included);
## and `fronts` names the squadron of a stack whose hull is drawn. A squadron in
## a stack that is not her front is covered: her hull is hidden, her pennant is
## not lost, and the cycle brings her forward when the crown picks her.
##
## `hidden` is the squadrons the chart does not draw at all (a rival under the
## fog): the stack never hands the hull to one of them while another of hers can
## be seen, the station's count never names them, and their colour never rides a
## pennant pip (wiki: ships-and-naval § Sighted strength, § Fleets in one
## station).
static func plan(
	fleets: Array, player: int, selected: int = -1, hidden: Array[int] = []
) -> Dictionary:
	var lanes: Dictionary = {}
	var stacks: Dictionary = {}
	var stations: Dictionary = {}
	var fronts: Dictionary = {}
	var groups: Dictionary = {}
	for raw: Variant in fleets:
		var fleet: FleetState = raw as FleetState
		if fleet == null:
			continue
		var key: String = station_of(fleet)
		var group: Array = []
		group.assign(groups.get(key, []))
		group.append(fleet)
		groups[key] = group
	for key: String in groups.keys():
		_plan_station(
			groups[key] as Array, player, selected, hidden, lanes, stacks, stations, fronts
		)
	return {
		"lanes": lanes, "stacks": stacks, "stations": stations, "fronts": fronts,
	}


static func _plan_station(
	group: Array,
	player: int,
	selected: int,
	hidden: Array[int],
	lanes: Dictionary,
	stacks: Dictionary,
	stations: Dictionary,
	fronts: Dictionary
) -> void:
	var mine: Array = []
	var theirs: Array = []
	for raw: Variant in group:
		var fleet: FleetState = raw as FleetState
		if fleet.owner == player:
			mine.append(fleet)
		else:
			theirs.append(fleet)
	_by_id(mine)
	_by_id(theirs)
	var row: Array = mine.slice(0, FAN_LIMIT)
	# The crown's row is her first squadrons in id order; her remainder and every
	# rival's ride the one stack, so a rival is never a nation row of her own.
	var stack: Array = mine.slice(FAN_LIMIT, mine.size())
	stack.append_array(theirs)
	var head: int = _head(stack, selected, hidden)
	var slots: int = row.size() + (1 if head >= 0 else 0)
	for index in row.size():
		lanes[(row[index] as FleetState).id] = _lane(index, slots)
	# The station's reading order: the row as it stands, then the stack — and
	# never a squadron the fog withholds, so a water the crown half-sees is
	# counted by what she can see (REQ-P5-05).
	var here: Array[int] = []
	for raw: Variant in row:
		here.append((raw as FleetState).id)
	for raw: Variant in stack:
		if not hidden.has((raw as FleetState).id):
			here.append((raw as FleetState).id)
	for raw: Variant in group:
		stations[(raw as FleetState).id] = here
	if head < 0:
		return
	lanes[(stack[head] as FleetState).id] = _lane(row.size(), slots)
	fronts[station_of(stack[head])] = (stack[head] as FleetState).id
	# The cycle keeps the station's own order — the crown's remainder, then the
	# rivals, each by id — so "2 of 4 here" never moves under the player's
	# finger; only the head the hull is drawn on follows the selection.
	var order: Array[int] = []
	for raw: Variant in stack:
		order.append((raw as FleetState).id)
	for raw: Variant in stack:
		stacks[(raw as FleetState).id] = order


## The squadron of a stack whose hull is drawn: the crown's selection when she
## rides that stack, else the first squadron the chart draws, else none.
static func _head(stack: Array, selected: int, hidden: Array[int]) -> int:
	if stack.is_empty():
		return -1
	for index in stack.size():
		var fleet: FleetState = stack[index] as FleetState
		if fleet.id == selected and not hidden.has(fleet.id):
			return index
	for index in stack.size():
		if not hidden.has((stack[index] as FleetState).id):
			return index
	return -1


static func _by_id(fleets: Array) -> void:
	fleets.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)


## One slot of the row, centred on the station so a lone squadron still stands
## on her own water rather than off to one side.
static func _lane(index: int, slots: int) -> Vector2:
	return Vector2((float(index) - float(slots - 1) * 0.5) * LANE_SPAN, 0.0)