extends GdToolsTest
## The consent ladder: which blocking decision the court answers first, and the
## words a new order is refused with while one waits (wiki: diplomacy
## § Alliances § Mutual defence, § Intervention, § Court proposals).
##
## Pure state: the ladder reads the pending queues the three rules own, so a
## case needs no world, no screen and no turn.


## A court with nothing waiting on it.
func _free_court() -> DiplomacyState:
	var state: DiplomacyState = DiplomacyState.new()
	state.human_faction = 0
	return state


func _offer(state: DiplomacyState, from_id: int = 2) -> void:
	state.pending_offers.append(
		{"from": from_id, "kind": DiplomacyProposals.KIND_PEACE, "stage": ""}
	)


func _intervention(state: DiplomacyState, court: int = 0) -> void:
	state.pending_interventions.append(
		{"aggressor": 3, "target": 6, "court": court}
	)


func _call(state: DiplomacyState, ally: int = 0) -> void:
	state.pending_calls.append({"aggressor": 3, "defender": 2, "ally": ally})


func test_a_free_court_owes_no_answer() -> void:
	assert_eq(ConsentLadder.pending_kind(_free_court(), 0), "")


func test_a_missing_ledger_owes_no_answer() -> void:
	assert_eq(ConsentLadder.pending_kind(null, 0), "")


func test_a_rival_proposal_waits_last() -> void:
	var state: DiplomacyState = _free_court()
	_offer(state)
	assert_eq(ConsentLadder.pending_kind(state, 0), ConsentLadder.OFFER)


func test_an_intervention_outranks_a_proposal() -> void:
	var state: DiplomacyState = _free_court()
	_offer(state)
	_intervention(state)
	assert_eq(ConsentLadder.pending_kind(state, 0), ConsentLadder.INTERVENTION)


func test_a_call_to_arms_comes_first() -> void:
	var state: DiplomacyState = _free_court()
	_offer(state)
	_intervention(state)
	_call(state)
	assert_eq(ConsentLadder.pending_kind(state, 0), ConsentLadder.CALL)


## The ladder answers for the court named, not for whoever holds a decision.
func test_the_ladder_reads_the_named_court() -> void:
	var state: DiplomacyState = _free_court()
	_call(state, 2)
	_offer(state)
	assert_eq(ConsentLadder.pending_kind(state, 0), ConsentLadder.OFFER)
	assert_eq(ConsentLadder.pending_kind(state, 2), ConsentLadder.CALL)


## A new order's refusal names the answer the court owes first, in the ladder's
## own order.
func test_the_refusal_names_the_answer_owed() -> void:
	assert_eq(ConsentCopy.held(ConsentLadder.CALL), "Answer the call to arms first.")
	assert_eq(
		ConsentCopy.held(ConsentLadder.INTERVENTION), "Answer the intervention first."
	)
	assert_eq(ConsentCopy.held(ConsentLadder.OFFER), "Answer the proposal first.")
