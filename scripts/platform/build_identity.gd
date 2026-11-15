class_name BuildIdentity
extends RefCounted
## Export-time bake of the short git SHA and last-commit UTC stamp.
## Empty in the repo and in editor/dev runs. `tools/bake_build_identity.sh`
## fills these before export; CI restores the empty placeholders afterward.

const GIT_SHA: String = ""
const COMMIT_UTC: String = ""


static func is_baked() -> bool:
	return not GIT_SHA.is_empty() and not COMMIT_UTC.is_empty()
