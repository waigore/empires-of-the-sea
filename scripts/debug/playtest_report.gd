class_name PlaytestReport
extends RefCounted
## Composes the playtest report (issue #1393): one machine-readable JSON bag and
## one human-readable Markdown page over the captures a session took. Pure —
## the controller owns the files, this owns their shape.

const REPORT_MD: String = "report.md"
const REPORT_JSON: String = "report.json"


## One capture row. `file` is relative to the session folder so a report stays
## portable when the folder is copied out of the game cache.
static func entry(kind: String, file: String, comment: String, meta: Dictionary) -> Dictionary:
	return {
		"kind": kind,
		"file": file,
		"comment": comment,
		"meta": meta.duplicate(true),
	}


static func compose(meta: Dictionary, entries: Array) -> Dictionary:
	return {
		"meta": meta.duplicate(true),
		"entries": entries.duplicate(true),
	}


static func to_json(report: Dictionary) -> String:
	return JSON.stringify(report, "  ")


static func to_markdown(report: Dictionary) -> String:
	var meta: Dictionary = report.get("meta", {})
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Playtest report")
	lines.append("")
	lines.append("- Seed: %s" % meta.get("seed", 0))
	lines.append("- Turn: %s (year %s)" % [meta.get("turn", 0), meta.get("year", 0)])
	lines.append("- Crown: %s" % meta.get("crown", "unknown"))
	lines.append("- Region: %s" % meta.get("region", "unknown"))
	lines.append("- Build: %s (%s)" % [meta.get("build", ""), meta.get("commit", "")])
	lines.append("- Platform: %s" % meta.get("platform", ""))
	lines.append("- Captured: %s" % meta.get("timestamp", ""))
	lines.append("")
	lines.append("## Captures")
	lines.append("")
	var entries: Array = report.get("entries", [])
	if entries.is_empty():
		lines.append("_No captures yet._")
	for i: int in entries.size():
		var item: Dictionary = entries[i]
		var item_meta: Dictionary = item.get("meta", {})
		lines.append("### %d. %s — %s" % [
			i + 1, kind_label(item.get("kind", "")), item.get("file", "")
		])
		lines.append("")
		lines.append("- File: `%s`" % item.get("file", ""))
		lines.append("- Comment: %s" % comment_text(item.get("comment", "")))
		lines.append("- Turn: %s (year %s)" % [
			item_meta.get("turn", 0), item_meta.get("year", 0)
		])
		lines.append("- Region: %s" % item_meta.get("region", "unknown"))
		lines.append("")
	return "\n".join(lines)


## Writes both faces of the report into `dir_path`; false when the folder or a
## file cannot be opened, so the controller can say so in the overlay.
static func write(dir_path: String, report: Dictionary) -> bool:
	if dir_path.is_empty():
		return false
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
		return false
	var md: FileAccess = FileAccess.open(dir_path.path_join(REPORT_MD), FileAccess.WRITE)
	if md == null:
		return false
	md.store_string(to_markdown(report))
	md.close()
	var js: FileAccess = FileAccess.open(dir_path.path_join(REPORT_JSON), FileAccess.WRITE)
	if js == null:
		return false
	js.store_string(to_json(report))
	js.close()
	return true


## A ready-to-file issue draft for one capture: `todo` plus the caller's label
## (`bug` by default, `enhancement` for a wish). The agent still reviews it.
static func issue_draft(
	item: Dictionary, meta: Dictionary, label: String = "bug"
) -> Dictionary:
	var item_meta: Dictionary = item.get("meta", meta)
	var comment: String = str(item.get("comment", "")).strip_edges()
	var title: String = comment.get_slice("\n", 0).strip_edges()
	if title.is_empty():
		title = "%s capture" % kind_label(item.get("kind", ""))
	var body: PackedStringArray = PackedStringArray()
	body.append("## What happened")
	body.append(comment if not comment.is_empty() else "_No comment typed._")
	body.append("")
	body.append("## Capture")
	body.append("- File: `%s`" % item.get("file", ""))
	body.append("- Kind: %s" % kind_label(item.get("kind", "")))
	body.append("")
	body.append("## Session")
	body.append("- Seed: %s" % item_meta.get("seed", 0))
	body.append("- Turn: %s (year %s)" % [
		item_meta.get("turn", 0), item_meta.get("year", 0)
	])
	body.append("- Crown: %s" % item_meta.get("crown", "unknown"))
	body.append("- Region: %s" % item_meta.get("region", "unknown"))
	body.append("- Build: %s (%s)" % [
		item_meta.get("build", ""), item_meta.get("commit", "")
	])
	body.append("- Platform: %s" % item_meta.get("platform", ""))
	return {
		"title": "[Playtest] %s" % title,
		"body": "\n".join(body),
		"labels": ["todo", label],
	}


static func kind_label(kind: String) -> String:
	return "Video" if kind == "video" else "Screenshot"


static func comment_text(comment: String) -> String:
	var text: String = comment.strip_edges()
	return text if not text.is_empty() else "_No comment._"
