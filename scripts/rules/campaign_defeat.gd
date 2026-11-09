class_name CampaignDefeat
extends RefCounted
## Great Power defeat on terminal fall (wiki: victory § Great Power defeat;
## DR-20261109-05). Pure rules over the capital-loss report: no nodes, so the
## verdict resolves headless and the HUD only renders the record.
##
## Only a Great Power can be defeated, and only the human crown's fall seals the
## session. An AI fall removes that crown and the campaign continues; a Minor
## Nation or Tribe fall is map cleanup (wiki: capital-and-connectivity
## § Great Power fall).


## The human crown's defeat from a CapitalLoss fall report, or null when the
## fallen crowns do not include the human Great Power.
static func resolve(fallen: Array, player_faction: int, turn: int) -> DefeatState:
	if not FactionCatalog.can_win(player_faction):
		return null
	for entry: Variant in fallen:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		if int(row.get("faction", MapModel.NO_ID)) != player_faction:
			continue
		return DefeatState.terminal_fall(
			player_faction, int(row.get("conqueror", MapModel.NO_ID)), turn
		)
	return null
