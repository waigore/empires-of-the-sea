class_name MapPlayArmyMuster
extends RefCounted
## The crown's register: mustering into the Home Army and splitting or combining
## a field army (wiki: military-armies § Recruitment, § Splitting and
## combining). Presentation only — ArmyTraining, ArmyLayer and the roster rules
## own every outcome; this reports them (REQ-P3-02).
##
## March orders and the dossier door live in MapPlayArmies; this module only
## changes what a standard carries.


## Mints one regiment into the Home Army and keeps the HUD count in step.
static func recruit(play: PlaySession, type_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var result: Dictionary = play.army_layer.recruit(
		play.player_faction, type_id, play.economy.economy
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The regiment cannot muster.")))
		return
	play.hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	play.hud.toast(
		"%s joins the Home Army" % RegimentCatalog.display_name(type_id)
	)
	MapPlayArmies.show_panel(play, play.army_layer.selected_army)


## Detaches a batch of regiments in one order (single detach and Detach all
## share this path, so repeated chores stay batched — REQ-P5-04).
static func detach(play: PlaySession, army: ArmyState, ids: Array[String]) -> void:
	var result: Dictionary = play.army_layer.split(army, ids)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The regiments stay.")))
		return
	var created: ArmyState = result["army"] as ArmyState
	play.army_layer.select(created)
	if created.count() == 1:
		play.hud.toast(
			"%s detaches as a field army in %s"
			% [
				RegimentCatalog.display_name(created.type_of(created.regiments[0])),
				play.model.province_name(created.province),
			]
		)
		return
	play.hud.toast(
		"%d regiments form a field army in %s"
		% [created.count(), play.model.province_name(created.province)]
	)


## Combines the selected standard with the friendly army sharing its province.
static func merge(play: PlaySession, army: ArmyState) -> void:
	var result: Dictionary = play.army_layer.combine(army)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The armies stay apart.")))
		return
	var target: ArmyState = result["army"] as ArmyState
	play.army_layer.select(target)
	play.hud.toast(
		"The armies combine under one standard in %s"
		% play.model.province_name(target.province)
	)
