extends GdToolsTest
## Ledger copy: the market clearing line and its quiet empty case.


func test_a_quiet_market_prints_nothing() -> void:
	assert_eq(LedgerText.market_summary({}, 0), "")


func test_fills_carry_and_lapse_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"bought": 2, "spent": 60, "sold": 1}},
		"carry": [{"commodity": "timber"}],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 0,
			"commodity": "grain",
		}],
	}
	var line: String = LedgerText.market_summary(report, 0)
	assert_true(line.contains("bought 2 for 60 ducats"))
	assert_true(line.contains("sold 1"))
	assert_true(line.contains("1 order carried"))
	assert_true(line.contains("1 order lapsed"))


func test_another_courts_lapse_is_not_ours() -> void:
	var report: Dictionary = {
		"fills": {},
		"carry": [],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 1,
			"commodity": "grain",
		}],
	}
	assert_eq(LedgerText.market_summary(report, 0), "")
