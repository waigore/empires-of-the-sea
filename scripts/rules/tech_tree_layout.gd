class_name TechTreeLayout
extends RefCounted
## Where every catalog advance stands on the college's chart: a pure
## left-to-right layout over the prerequisite DAG (wiki: tech-tree
## § Prerequisites; DR-20261115-15). A tech's column is the longest chain of
## prerequisites above it, so every edge runs strictly left to right and a
## reader can follow a road without crossing back.
##
## Nothing here reads research state, draws or orders: the modal renders this
## and the tests read it (REQ-P2-03, REQ-P3-03).

const NODE_WIDTH: float = 168.0
## 40 px matches the phone sheet's own close door: a chart node is a tap target
## first and a label second (REQ-P5-07).
const NODE_HEIGHT: float = 40.0
const COLUMN_GAP: float = 66.0
const ROW_GAP: float = 10.0
const PAD: float = 20.0


## Longest prerequisite chain above the tech: a root sits at 0, its dependents
## at 1, and so on. An unknown id sits at 0.
static func depth(tech_id: String) -> int:
	return int(_depths().get(tech_id, 0))


## The chart's columns, left to right: column `n` holds every advance whose
## deepest prerequisite chain is `n` long. Within a column the advances are
## ordered by the average row of their prerequisites (a barycentre pass), so a
## chain stays near its parents and the edges stay short; ties keep catalog
## order, so the chart is the same on every boot.
static func columns() -> Array:
	var depths: Dictionary = _depths()
	var count: int = 0
	for tech_id: Variant in depths.keys():
		count = maxi(count, int(depths[tech_id]) + 1)
	var out: Array = []
	for index in count:
		var empty: Array[String] = []
		out.append(empty)
	for tech_id: String in TechCatalog.ids():
		var column: Array[String] = out[int(depths[tech_id])]
		column.append(tech_id)
	for index in out.size():
		_order_column(out, index)
	return out


## Tech id -> the node's top-left corner on the chart.
static func positions() -> Dictionary:
	var out: Dictionary = {}
	var chart: Array = columns()
	for column in chart.size():
		var techs: Array[String] = chart[column]
		for row in techs.size():
			out[techs[row]] = Vector2(
				PAD + float(column) * (NODE_WIDTH + COLUMN_GAP),
				PAD + float(row) * (NODE_HEIGHT + ROW_GAP)
			)
	return out


## The chart's whole size, so the scroll view can pan to its last node.
static func bounds() -> Vector2:
	var chart: Array = columns()
	var rows: int = 0
	for column: Variant in chart:
		rows = maxi(rows, (column as Array).size())
	return Vector2(
		PAD * 2.0 + float(chart.size()) * NODE_WIDTH
			+ float(maxi(chart.size() - 1, 0)) * COLUMN_GAP,
		PAD * 2.0 + float(rows) * NODE_HEIGHT + float(maxi(rows - 1, 0)) * ROW_GAP
	)


## Every prerequisite edge, as `{from: prerequisite, to: dependent}`.
static func edges() -> Array:
	var out: Array = []
	for tech_id: String in TechCatalog.ids():
		for prereq: String in TechCatalog.prerequisites(tech_id):
			out.append({"from": prereq, "to": tech_id})
	return out


## The tech and every prerequisite above it, however deep — the cone a reader
## highlights when they aim at an advance. Empty for an unknown id.
static func ancestors(tech_id: String) -> Dictionary:
	var out: Dictionary = {}
	if not TechCatalog.known(tech_id):
		return out
	var frontier: Array[String] = [tech_id]
	while not frontier.is_empty():
		var next: Array[String] = []
		for node: String in frontier:
			if out.has(node):
				continue
			out[node] = true
			for prereq: String in TechCatalog.prerequisites(node):
				next.append(prereq)
		frontier = next
	return out


## The edges that lie wholly inside the advance's ancestor cone: the road the
## highlight draws, and nothing else.
static func path_edges(tech_id: String) -> Array:
	var cone: Dictionary = ancestors(tech_id)
	var out: Array = []
	if cone.is_empty():
		return out
	for edge: Dictionary in edges():
		if cone.has(String(edge["from"])) and cone.has(String(edge["to"])):
			out.append(edge)
	return out


# --- helpers -----------------------------------------------------------------


## Longest chain above every catalog tech, memoised in one pass.
static func _depths() -> Dictionary:
	var memo: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		_depth_of(tech_id, memo)
	return memo


static func _depth_of(tech_id: String, memo: Dictionary) -> int:
	if memo.has(tech_id):
		return int(memo[tech_id])
	var deepest: int = -1
	for prereq: String in TechCatalog.prerequisites(tech_id):
		deepest = maxi(deepest, _depth_of(prereq, memo))
	memo[tech_id] = deepest + 1
	return deepest + 1


## Sorts one column in place: the barycentre of the prerequisites already
## placed, then catalog order. Column 0 has no parents, so it keeps catalog
## order and anchors the pass.
static func _order_column(chart: Array, index: int) -> void:
	var techs: Array[String] = chart[index]
	if index == 0:
		techs.sort_custom(TechOrder.before)
		return
	var rows: Dictionary = {}
	for column in index:
		var placed: Array[String] = chart[column]
		for row in placed.size():
			rows[placed[row]] = float(row)
	var centre: Dictionary = {}
	for tech_id: String in techs:
		var total: float = 0.0
		var count: int = 0
		for prereq: String in TechCatalog.prerequisites(tech_id):
			if not rows.has(prereq):
				continue
			total += float(rows[prereq])
			count += 1
		centre[tech_id] = total / float(count) if count > 0 else 1e9
	techs.sort_custom(func(a: String, b: String) -> bool:
		if not is_equal_approx(float(centre[a]), float(centre[b])):
			return float(centre[a]) < float(centre[b])
		return TechOrder.before(a, b)
	)
