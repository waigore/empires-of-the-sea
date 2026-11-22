class_name ProvinceHandover
extends RefCounted
## A province changing hands (wiki: diplomacy § Intervention — "purchased land
## remains recorded until normal province conquest rules apply"; world-market
## § Minor and tribe town development — a conquered province's purchased tiles
## leave the index). One write for every handover, so a won battle, a Join
## Empire and a fallen crown's land all drop the same ground. Pure rules: no
## nodes (REQ-P3-01, REQ-P3-03).


## Hands `province_id` to `owner` and drops every deed on its ground: a tile
## bought from a Minor or Tribe answers to its province's owner once the province
## changes hands, so the conqueror can work every tile it took and no dead court
## keeps a claim inside another crown's province. A town the deeds raised never
## falls — development is built, not rented (wiki: civilian-units § Merchant).
## Returns false when the model has no such province.
static func hand_over(model: MapModel, province_id: int, owner: int) -> bool:
	var data: ProvinceState = model.get_province(province_id) if model != null else null
	if data == null:
		return false
	data.owner = owner
	for tile: Vector2i in data.tiles:
		model.ownership.drop_deed(model.index_of(tile.x, tile.y))
	return true
