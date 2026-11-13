"""Checks on the hill itself, run by `hills check`."""

import json
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


def _turn(faction: int, top_ranked: int, top_funded: int) -> str:
    return json.dumps(
        {
            "turn": 1,
            "rows": [
                {
                    "faction": faction,
                    "plans": True,
                    "objectives": {
                        "top_ranked": top_ranked,
                        "top_funded": top_funded,
                    },
                }
            ],
        }
    )


def test_funded_share_is_the_mean_of_top_level_shares(tmp_path):
    turns = tmp_path / "turns.jsonl"
    turns.write_text(
        "\n".join(
            [
                _turn(0, 4, 4),  # 1.0
                _turn(0, 4, 2),  # 0.5
                _turn(0, 0, 0),  # no ranked aim: skipped, not counted as 1.0
                _turn(1, 4, 0),  # another court: ignored
            ]
        )
    )
    assert hill_eval._funded_share(turns, 0) == pytest.approx(0.75)


def test_funded_share_without_trace_is_zero(tmp_path):
    assert hill_eval._funded_share(tmp_path / "missing.jsonl", 0) == 0.0


def test_funded_share_metric_is_reported(tmp_path):
    turns = tmp_path / "turns.jsonl"
    turns.write_text(_turn(0, 2, 1))
    summary = {
        "ai_live": 0,
        "campaign_over": False,
        "winner": -1,
        "turn": 1,
        "resolved_turns": 1,
        "rows": [{"faction": 0, "name": "Spain", "plans": True}],
    }
    scored = hill_eval.score_summary(summary, turns)
    assert scored["funded_pct"] == pytest.approx(0.5)
