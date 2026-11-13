"""Checks on the hill itself, run by `hills check`."""

from pathlib import Path

import pytest

from hills import run_evaluator

import eval as hill_eval

HILL = Path(__file__).resolve().parents[1]
EXAMPLES = HILL / "examples"


def test_baseline_fixture_scores():
    result = run_evaluator(HILL, EXAMPLES / "baseline")
    assert result["passed"]
    assert result["metrics"][0]["name"] == "score"
    assert result["metrics"][0]["value"] > 0
    assert result["details"]["fixture"] is True
    primary = {c["name"]: c["value"] for c in result["config"] if c.get("primary")}
    assert primary["ai"] == "bench"
    assert primary["seed"] == 1500
    assert primary["turns"] == 200


def test_weak_fixture_scores_lower_than_baseline():
    base = run_evaluator(HILL, EXAMPLES / "baseline")
    weak = run_evaluator(HILL, EXAMPLES / "weak")
    assert weak["passed"]
    assert weak["metrics"][0]["value"] < base["metrics"][0]["value"]


def test_funded_share_reads_the_ledger_trace(tmp_path):
    """The funded-objective metric (issue #491 T6): mean funded/ranked per turn."""
    import json

    turns = tmp_path / "turns.jsonl"
    turns.write_text(
        "\n".join(
            json.dumps(
                {
                    "turn": turn,
                    "rows": [
                        {"faction": 0, "last": {"objectives": {"ranked": 4, "funded": f}}},
                        {"faction": 1, "last": {}},
                    ],
                }
            )
            for turn, f in ((1, 2), (2, 4), (3, 3))
        )
    )
    assert hill_eval._funded_share(turns, 0) == pytest.approx(75.0)


def test_funded_share_skips_a_turn_with_no_ledger(tmp_path):
    import json

    turns = tmp_path / "turns.jsonl"
    turns.write_text(
        json.dumps({"turn": 1, "rows": [{"faction": 0, "last": {"objectives": {"ranked": 0}}}]})
        + "\n"
        + json.dumps({"turn": 2, "rows": [{"faction": 0, "last": {"objectives": {"ranked": 2, "funded": 1}}}]})
    )
    assert hill_eval._funded_share(turns, 0) == pytest.approx(50.0)
    assert hill_eval._funded_share(tmp_path / "absent.jsonl", 0) == 0.0


def test_missing_project_rejected(tmp_path):
    result = run_evaluator(HILL, tmp_path)
    assert not result["passed"]
    assert "project.godot" in result["details"]["error"]


def test_score_summary_weights_provinces_highest():
    summary = {
        "ai_live": 0,
        "campaign_over": False,
        "winner": -1,
        "turn": 10,
        "resolved_turns": 10,
        "rows": [
            {
                "faction": 0,
                "name": "Spain",
                "plans": True,
                "provinces_old": 2,
                "provinces_new": 0,
                "regiments": 100,
                "ships": 100,
                "workers": 100,
            }
        ],
    }
    scored = hill_eval.score_summary(summary)
    # Two OW provinces alone are 200; forces+workers max out lower without rates.
    assert scored["parts"]["provinces_old"] == 2
    assert scored["score"] == (
        100.0 * 2 + 10.0 * 100 + 10.0 * 100 + 5.0 * 100
    )
