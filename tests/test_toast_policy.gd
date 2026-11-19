extends GdToolsTest
## What the court's despatch lane may raise (wiki: hud-toasts; issue #1056).
## The two readings the turn-path adapters ask: a clash the crown fights, and a
## loss, work or court move that is the crown's own.

const CROWN: int = 0
const RIVAL: int = 1
const OTHER: int = 2


func test_a_clash_the_crown_attacks_is_its_own() -> void:
	assert_true(
		ToastPolicy.battle_touches_crown(CROWN, {"attacker": CROWN, "defender": RIVAL})
	)


func test_a_clash_the_crown_defends_is_its_own() -> void:
	assert_true(
		ToastPolicy.battle_touches_crown(CROWN, {"attacker": RIVAL, "defender": CROWN})
	)


func test_a_clash_between_rivals_is_not_the_crowns() -> void:
	assert_false(
		ToastPolicy.battle_touches_crown(CROWN, {"attacker": RIVAL, "defender": OTHER}),
		"another court's battle is the Gazette's news, never the lane's"
	)


func test_a_battle_with_no_parties_touches_nobody() -> void:
	assert_false(ToastPolicy.battle_touches_crown(CROWN, {}))


func test_an_unseated_crown_touches_nothing() -> void:
	assert_false(
		ToastPolicy.battle_touches_crown(-1, {"attacker": -1, "defender": RIVAL})
	)
	assert_false(ToastPolicy.of_crown(-1, -1))


func test_a_loss_of_the_crowns_is_its_own() -> void:
	assert_true(ToastPolicy.of_crown(CROWN, CROWN))


func test_a_rivals_loss_is_not_the_crowns() -> void:
	assert_false(
		ToastPolicy.of_crown(CROWN, RIVAL),
		"a rival's drowned, wall or court move is her own affair"
	)
