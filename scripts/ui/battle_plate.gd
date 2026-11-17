class_name BattlePlate
extends RefCounted
## The painted battlefield facade: ground, wall and figure painters each own a
## module; this spine keeps the pre-split API and shared constants callers and
## tests still name (REQ-P3-01). No rule outcome is decided here (REQ-P2-03).

const GROUND: float = BattlePlateAssets.GROUND
const GATES: int = BattlePlateWall.GATES
const PLATES: Dictionary = BattlePlateAssets.PLATES
const WALLS: Array[String] = BattlePlateAssets.WALLS
const SOLDIER: String = BattlePlateAssets.SOLDIER
const CANNON: String = BattlePlateAssets.CANNON
const HORSE: String = BattlePlateAssets.HORSE
const RUBBLE: String = BattlePlateAssets.RUBBLE


static func draw_ground(
	canvas: CanvasItem, width: float, height: float, horizon: float, terrain: String
) -> void:
	BattlePlateGround.draw(canvas, width, height, horizon, terrain)


static func wall_height(height: float, fort: int) -> float:
	return BattlePlateWall.wall_height(height, fort)


static func parapet_y(height: float, fort: int) -> float:
	return BattlePlateWall.parapet_y(height, fort)


static func draw_wall(
	canvas: CanvasItem, width: float, height: float, fort: int, broken: int,
	color: Color, time: float
) -> void:
	BattlePlateWall.draw(canvas, width, height, fort, broken, color, time)


static func draw_wall_crest(
	canvas: CanvasItem, width: float, height: float, fort: int
) -> void:
	BattlePlateWall.draw_crest(canvas, width, height, fort)


static func draw_standard(canvas: CanvasItem, pos: Vector2, color: Color, time: float) -> void:
	BattlePlateWall.draw_standard(canvas, pos, color, time)


static func draw_soldier(
	canvas: CanvasItem, pos: Vector2, soldier_h: float, color: Color, facing: float,
	index: int, health: float, medals: int, type_id: String = ""
) -> void:
	BattlePlateFigures.draw_soldier(
		canvas, pos, soldier_h, color, facing, index, health, medals, type_id
	)


static func draw_cannon(
	canvas: CanvasItem, pos: Vector2, color: Color, facing: float, flash: float,
	gun_h: float = 18.0
) -> void:
	BattlePlateFigures.draw_cannon(canvas, pos, color, facing, flash, gun_h)


static func draw_horse(
	canvas: CanvasItem, pos: Vector2, color: Color, height: float
) -> void:
	BattlePlateFigures.draw_horse(canvas, pos, color, height)


static func soldier_height(height: float) -> float:
	return BattlePlateFigures.soldier_height(height)
