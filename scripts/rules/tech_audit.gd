class_name TechAudit
extends RefCounted
## Static checks the wiki asks the catalog to pass at start-up (wiki: tech-tree
## § Acceptance Criteria, tech-and-extraction-cap § Static catalog validation).
## Pure and side-effect free: tests call it, the game never guesses a tech.

const EXPECTED_COUNT: int = 113


## Empty array means the catalog is valid; otherwise one line per failure.
static func validate() -> Array[String]:
	var errors: Array[String] = []
	if TechCatalog.TECHS.size() != EXPECTED_COUNT:
		errors.append(
			"catalog holds %d techs, expected %d"
			% [TechCatalog.TECHS.size(), EXPECTED_COUNT]
		)
	errors.append_array(_shape_errors())
	errors.append_array(_prerequisite_errors())
	errors.append_array(_graph_errors())
	errors.append_array(_cap_errors())
	errors.append_array(_role_errors())
	return errors


static func is_valid() -> bool:
	return validate().is_empty()


# --- checks ------------------------------------------------------------------


static func _shape_errors() -> Array[String]:
	var errors: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		var entry: Dictionary = TechCatalog.entry(tech_id)
		if String(entry.get("name", "")).is_empty():
			errors.append("%s has no display name" % tech_id)
		var era: int = int(entry.get("era", 0))
		if era < 1 or era > 4:
			errors.append("%s has era %d, expected 1..4" % [tech_id, era])
		var category: String = String(entry.get("category", ""))
		if not TechCatalog.CATEGORIES.has(category):
			errors.append("%s has unknown category '%s'" % [tech_id, category])
	return errors


static func _prerequisite_errors() -> Array[String]:
	var errors: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		for prereq: String in TechCatalog.prerequisites(tech_id):
			if not TechCatalog.known(prereq):
				errors.append("%s requires unknown tech '%s'" % [tech_id, prereq])
	return errors


## Acyclicity plus reachability from the root techs (no prerequisites).
static func _graph_errors() -> Array[String]:
	var errors: Array[String] = []
	var visiting: Dictionary = {}
	var done: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		_visit(tech_id, visiting, done, errors)
	for tech_id: String in TechCatalog.ids():
		if not _reaches_root(tech_id, {}):
			errors.append("%s is unreachable from any starting tech" % tech_id)
	return errors


static func _visit(
	tech_id: String, visiting: Dictionary, done: Dictionary, errors: Array[String]
) -> void:
	if done.has(tech_id):
		return
	if visiting.has(tech_id):
		errors.append("%s sits on a prerequisite cycle" % tech_id)
		return
	visiting[tech_id] = true
	for prereq: String in TechCatalog.prerequisites(tech_id):
		if TechCatalog.known(prereq):
			_visit(prereq, visiting, done, errors)
	visiting.erase(tech_id)
	done[tech_id] = true


static func _reaches_root(tech_id: String, seen: Dictionary) -> bool:
	if TechCatalog.prerequisites(tech_id).is_empty():
		return true
	if seen.has(tech_id):
		return false
	seen[tech_id] = true
	for prereq: String in TechCatalog.prerequisites(tech_id):
		if TechCatalog.known(prereq) and _reaches_root(prereq, seen):
			return true
	return false


## Every upgradeable resource must climb to 4 unless the wiki declares an
## exception, and every exception must stay inside 1..4.
static func _cap_errors() -> Array[String]:
	var errors: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		var caps: Dictionary = TechCatalog.caps_of(tech_id)
		for commodity: Variant in caps.keys():
			var level: int = int(caps[commodity])
			if level < TechCatalog.MIN_LEVEL or level > TechCatalog.MAX_LEVEL:
				errors.append("%s grants %s %d, expected 1..4" % [tech_id, commodity, level])
	var resources: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		for commodity: Variant in TechCatalog.caps_of(tech_id).keys():
			resources[String(commodity)] = true
	for commodity: Variant in TechCatalog.CAP_EXCEPTIONS.keys():
		var cap: int = int(TechCatalog.CAP_EXCEPTIONS[commodity])
		if cap < TechCatalog.MIN_LEVEL or cap > TechCatalog.MAX_LEVEL:
			errors.append(
				"cap exception %s = %d is outside 1..4" % [commodity, cap]
			)
		var highest: int = _highest_cap(String(commodity))
		if highest != cap:
			errors.append(
				"cap exception %s = %d but the catalog tops out at %d"
				% [commodity, cap, highest]
			)
	for commodity: Variant in resources.keys():
		var id: String = String(commodity)
		if TechCatalog.CAP_EXCEPTIONS.has(id):
			continue
		if _highest_cap(id) < TechCatalog.MAX_LEVEL:
			errors.append("%s has no unlocked chain reaching level 4" % id)
	return errors


static func _highest_cap(commodity: String) -> int:
	var highest: int = TechCatalog.MIN_LEVEL
	for tech_id: String in TechCatalog.ids():
		if TechCatalog.caps_of(tech_id).has(commodity):
			highest = maxi(highest, int(TechCatalog.caps_of(tech_id)[commodity]))
	return highest


## Every tech must do something structural: grant a cap, gate discovery,
## unlock a dependent, or name a documented effect (wiki: tech-tree audit).
static func _role_errors() -> Array[String]:
	var errors: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		var has_role: bool = not TechCatalog.caps_of(tech_id).is_empty()
		has_role = has_role or not TechCatalog.discovery_resources(tech_id).is_empty()
		has_role = has_role or not TechCatalog.dependents(tech_id).is_empty()
		has_role = has_role or not String(TechCatalog.entry(tech_id).get("note", "")).is_empty()
		if not has_role:
			errors.append("%s has no effect, unlock or dependent tech" % tech_id)
	return errors
