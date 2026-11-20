class_name OrderVerdict
extends RefCounted
## One home for the verdict an order check returns: `{"ok": bool, "reason":
## String}` plus any field the calling rule adds (a unit, a cost, a target).
## Army, navy, market and court orders all answer here, so the shape cannot
## drift between them (REQ-P3-01, REQ-P3-03).


## An accepted order. `extra` adds the rule's own fields to the base verdict.
static func allow(extra: Dictionary = {}) -> Dictionary:
	var verdict: Dictionary = {"ok": true, "reason": ""}
	verdict.merge(extra, true)
	return verdict


## A refused order, with the plain reason the court is told. `extra` carries the
## rule's own fields at their denied values (a null army, an empty name).
static func deny(reason: String, extra: Dictionary = {}) -> Dictionary:
	var verdict: Dictionary = {"ok": false, "reason": reason}
	verdict.merge(extra, true)
	return verdict
