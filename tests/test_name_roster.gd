extends GdToolsTest
## One deterministic christening core for every named thing (wiki: naming,
## DR-20261111-07/18, DR-20261112-03): the hull, regiment and general rosters all
## draw their pick, their repeat numbering and their FNV-1a digest from
## NameRoster, so a saved campaign speaks the same names on every load and the
## three rosters can never drift apart. Pure arithmetic: pools in, titles out.

const POOL: Array[String] = ["Revenge", "Sovereign", "Vanguard"]


func test_a_pick_comes_from_the_pool_and_never_repeats() -> void:
	var taken: Array[String] = []
	for step in POOL.size():
		var name: String = NameRoster.pick(POOL, "%d" % step, taken, "Unnamed")
		assert_true(POOL.has(name), "step %d picked '%s' from its pool" % [step, name])
		assert_false(taken.has(name), "'%s' is worn twice" % name)
		taken.append(name)


func test_the_same_key_always_christens_the_same_name() -> void:
	var first: String = NameRoster.pick(POOL, "0:0:ship_1", [], "Unnamed")
	var second: String = NameRoster.pick(POOL, "0:0:ship_1", [], "Unnamed")

	assert_eq(first, second, "a reload draws the same title")
	assert_false(NameRoster.pick(POOL, "0:0:ship_2", [], "Unnamed").is_empty())


func test_a_spent_pool_numbers_its_repeats() -> void:
	var taken: Array[String] = POOL.duplicate()
	var numbered: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")

	assert_true(numbered.ends_with(" II"), "the fourth hull is numbered, got '%s'" % numbered)
	assert_false(taken.has(numbered), "the numbered pick is still free")


func test_a_pool_past_its_last_ordinal_repeats_its_last_title() -> void:
	var taken: Array[String] = POOL.duplicate()
	for _cycle in NameRoster.ORDINALS.size():
		var name: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")
		if not taken.has(name):
			taken.append(name)
	var last: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")

	assert_true(taken.has(last), "an exhausted numbering falls back to a taken title")
	assert_true(last.ends_with(" VIII"), "the last ordinal is the ceiling, got '%s'" % last)


func test_an_empty_pool_falls_back_to_the_callers_word() -> void:
	var empty: Array[String] = []

	assert_eq(NameRoster.pick(empty, "0:0:ship_1", [], "Unnamed"), "Unnamed")
	assert_eq(NameRoster.pick(empty, "0:general_1", [], "Commander"), "Commander")


func test_a_crown_with_no_pool_reads_the_generic_one() -> void:
	var pools: Dictionary = {0: ["Revenge"]}
	var generic: Array[String] = ["Providence"]

	assert_eq(NameRoster.pool_of(pools, generic, 0), ["Revenge"])
	assert_eq(NameRoster.pool_of(pools, generic, 9), generic, "an unknown crown is generic")


func test_taken_names_reads_the_store_and_skips_the_new_instance() -> void:
	var store: Dictionary = {"ship_1": "Revenge", "ship_2": "", "ship_3": "Vanguard"}

	assert_eq(
		NameRoster.taken_names(["ship_1", "ship_2", "ship_3"], store, "ship_1"),
		["Vanguard"],
		"the hull being christened and the unnamed one are left out"
	)
	assert_eq(NameRoster.taken_names([], {}, ""), [], "an empty roster names nothing")


func test_a_saved_title_map_reads_json_keys_as_strings() -> void:
	assert_eq(
		NameRoster.map_from({"1": "Revenge"}),
		{"1": "Revenge"},
		"a string-keyed map survives"
	)
	assert_eq(
		NameRoster.map_from({1: "Vanguard"}),
		{"1": "Vanguard"},
		"a numeric key is read back as the string a save writes"
	)
	assert_eq(NameRoster.map_from([1, 2]), {}, "a malformed map reads empty")
	assert_eq(NameRoster.map_from(null), {}, "a missing map reads empty")


## A JSON round-trip turns every count into a float; the reader casts it back, so
## a restored regiment's condition and record compare equal to what was saved.
func test_a_saved_number_map_reads_json_values_as_ints() -> void:
	var json: String = JSON.stringify({"unit_1": 3, "unit_2": 0})
	var raw: Variant = JSON.parse_string(json)

	assert_eq(
		NameRoster.numbers_from(raw),
		{"unit_1": 3, "unit_2": 0},
		"counts survive a JSON round-trip as ints"
	)
	assert_eq(NameRoster.numbers_from({1: "2"}), {"1": 2}, "a numeric key and a text value")
	assert_eq(NameRoster.numbers_from("nonsense"), {}, "malformed reads empty")
	assert_eq(NameRoster.numbers_from(null), {}, "a missing map reads empty")


func test_the_digest_is_the_fn_1a_save_contract() -> void:
	assert_eq(NameRoster.stable_hash("0:0:ship_1"), 3815455475)
	assert_eq(NameRoster.stable_hash("0:general_1"), 2632187469)
	assert_eq(NameRoster.stable_hash("0:1:unit_101"), 1682817625)
	assert_false(
		NameRoster.stable_hash("0:0:ship_1") == NameRoster.stable_hash("0:0:ship_2"),
		"a different instance draws a different start"
	)


func test_every_roster_numbers_repeats_the_same_way() -> void:
	var hulls: Array[String] = ShipNames.pool_for(0).duplicate()
	var regiments: Array[String] = RegimentNames.pool_for(0).duplicate()
	var generals: Array[String] = GeneralNames.pool_for(0).duplicate()

	assert_true(ShipNames.mint(0, 0, "ship_1", hulls).ends_with(" II"))
	assert_true(RegimentNames.mint(0, 0, "unit_1", regiments).ends_with(" II"))
	assert_true(GeneralNames.mint(0, "general_1", generals).ends_with(" II"))
