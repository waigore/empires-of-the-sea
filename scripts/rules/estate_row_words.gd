class_name EstateRowWords
extends RefCounted
## What an estate's ledger row says (wiki: extraction-and-improvements): the line
## its status earns, the cap that holds the next level flat and the raise the
## Builder would buy. [EstateRows] reads the figures and the Build gate;
## [ImprovementLedger] groups the rows. The copy lives here so a row's numbers and
## its sentences are two small homes instead of one long walk (REQ-P3-01).
##
## Pure over a finished row (or the facts a row kept): strings out, no nodes and
## no snapshot of its own, so a headless test proves the wording without a scene
## (REQ-P3-03, REQ-P5-06).

## A known mineral nobody has surveyed: the row names the Explorer's work to do.
## The status word lives with the words that print it.
const UNPROSPECTED: String = "unprospected"


## The line under the estate's name: what it gathers today, or why it gathers
## nothing — a Builder at work, a raise still gated, a sealed harbour. Every
## figure is the phase's own, so the row never promises a yield the harvest
## refuses (REQ-P2-03).
##
## `level_yield` is the estate's **per-level** yield, before a Great Power ration
## estate's doubling; `output` prints the doubled figure the phase pays. The cap
## note reads the per-level figure, because the multiplier would otherwise name
## the wrong cap or hide it: a level-3 grain estate on a primitive road pays 2
## while the road holds each level at 1, and a town-capped one would print no cap
## at all (wiki: extraction-and-improvements § Ration estates, § Extraction
## formula and town development cap; DR-20261116-10).
static func status_text(
	status: String, resource: int, level: int, output: int, tech_cap: int,
	terrain_cap: int, transport: int, town_cap: int, working: CivilianState,
	is_connected: bool, blockaded: bool = false, level_yield: int = -1
) -> String:
	match status:
		"building":
			var left: int = working.remaining_turns() if working != null else 0
			return "Builder at work · %d turn%s left" % [left, MoneyText.plural(left)]
		"vacant":
			var vacant: String = (
				"Vacant — a Builder can raise a %s" % ImprovementCatalog.base_name(resource)
			)
			if blockaded:
				vacant += " · harbour blockaded, no sea path to the crown"
			elif not is_connected:
				vacant += " · no road to the crown yet"
			return vacant
		UNPROSPECTED:
			return "Prospect this tile before a %s can rise" % ImprovementCatalog.base_name(resource)
		"disconnected":
			# A sealed harbour is a rule, not a missing road: say which one, so
			# the crown never lays a road it does not need (REQ-P2-03).
			if blockaded:
				return "Harbour blockaded — no sea path to the crown"
			return "No road or port to the crown — no yield yet"
		"maxed":
			return "Fully improved · %s" % ImprovementCatalog.output_text(resource, output)
	var text: String = "Yields %s" % ImprovementCatalog.output_text(resource, output)
	var per_level: int = level_yield if level_yield >= 0 else output
	if level > per_level and per_level > 0:
		if per_level == transport:
			text += " · transport cap %d" % transport
		elif terrain_cap < tech_cap:
			text += " · terrain cap %d" % terrain_cap
		elif per_level == tech_cap:
			text += " · tech cap %d" % tech_cap
		else:
			text += " · town cap %d" % town_cap
	return text


## What one more level buys, in the ledger's own words. The figure is the
## phase's arithmetic at the next level (`gain`, `next_output`), so a crown is
## never told a raise pays when a cap holds the estate flat; the line names the
## cap instead, and names the gate a raise still waits on (REQ-P2-03, REQ-P5-06).
## Empty for a finished estate and while a Builder is on it: there is no raise to
## price.
static func preview_text(row: Dictionary) -> String:
	if bool(row.get("working", false)):
		return ""
	var level: int = int(row.get("level", 0))
	if level >= int(row.get("max_level", ImprovementCatalog.MAX_LEVEL)):
		return ""
	var next_level: int = int(row.get("next_level", level + 1))
	# Ground no road reaches gathers nothing at any level, so the raise is priced
	# by the wait rather than by a figure the harvest cannot pay. A deposit no
	# Explorer has read is the same wait, named after the level it would buy. A
	# sealed harbour is a wait the crown cannot road away, so it is named too.
	if not bool(row.get("connected", false)):
		if bool(row.get("blockaded", false)):
			return "Harbour blockaded — L%d pays nothing until the sea path opens" % (
				next_level
			)
		return "No road yet — L%d pays nothing until one reaches it" % next_level
	if int(row.get("gain", 0)) <= 0:
		return "L%d adds nothing — %s holds this estate" % [
			next_level, binding_cap(row)
		]
	var text: String = "L%d pays %s (+%d)" % [
		next_level,
		ImprovementCatalog.output_text(
			int(row.get("resource", -1)), int(row.get("next_output", 0))
		),
		int(row.get("gain", 0)),
	]
	if bool(row.get("needs_prospecting", false)) and not bool(row.get("prospected", false)):
		return text + " once an Explorer prospects it"
	return text


## The cap that stops the next level from paying more, in the row's own words:
## the tightest of the four the phase's formula reads (road transport, town,
## terrain, study). The estate's own output names the same four.
static func binding_cap(row: Dictionary) -> String:
	var limits: Array[Array] = [
		["the road's transport", int(row.get("transport", 0))],
		["the town", int(row.get("town_cap", 0))],
		["the terrain", int(row.get("terrain_cap", 0))],
		["the crown's study", int(row.get("tech_cap", 0))],
	]
	var cap: String = "the terrain"
	var lowest: int = 1 << 30
	for spec: Array in limits:
		if int(spec[1]) < lowest:
			lowest = int(spec[1])
			cap = String(spec[0])
	return cap
