extends GdToolsTest
## Shared counsel-pick chrome: one sentence, one prose join, one capped line.


func test_sentence_opens_and_closes() -> void:
	assert_eq(MapPlayPickProse.sentence(""), "", "no clause, no sentence")
	assert_eq(
		MapPlayPickProse.sentence("the court would raise the farm"),
		"The court would raise the farm.",
		"one capital and a full stop"
	)


func test_join_reads_as_prose() -> void:
	assert_eq(MapPlayPickProse.join([]), "", "empty list")
	assert_eq(MapPlayPickProse.join(["A"]), "A", "one part")
	assert_eq(MapPlayPickProse.join(["A", "B"]), "A and B", "two parts")
	assert_eq(
		MapPlayPickProse.join(["A", "B", "C"]),
		"A, B and C",
		"three parts take a comma and a final and"
	)


func test_capped_counts_the_rest() -> void:
	assert_eq(MapPlayPickProse.capped([], 3), "", "nothing named")
	assert_eq(
		MapPlayPickProse.capped(["A", "B", "C"], 3),
		"A, B and C",
		"under the limit keeps prose join"
	)
	assert_eq(
		MapPlayPickProse.capped(["A", "B", "C", "D", "E"], 3),
		"A, B, C and 2 more",
		"over the limit commas the heads and counts the rest"
	)
	assert_eq(MapPlayPickProse.capped(["A"], 0), "", "no room, no line")


func test_crown_crew_ready_refuses_a_missing_session() -> void:
	assert_false(
		MapPlayPickProse.crown_crew_ready(null),
		"no session, no counsel pick"
	)
