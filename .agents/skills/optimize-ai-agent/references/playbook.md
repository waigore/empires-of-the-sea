# Playbook — optimize AI (ai-bench)

## Official score

```bash
mkdir -p reports/ai-bench
hills eval . -H ai-bench -o reports/ai-bench/00N-<tag>.json
hills verify reports/ai-bench/00N-<tag>.json   # local machine key
```

Contract: `.autolab/hills/ai-bench/README.md` (`hills describe ai-bench`).
Params default: turns=200, seed=1500, size=1, ai=bench.

## Report paths

| Path | Role |
|------|------|
| `reports/ai-bench/baseline.json` | CI floor (do not lower casually) |
| `reports/ai-bench/latest.json` | Current claim for AI-surface PRs |
| `reports/ai-bench/*.json` | Attempt archive |
| `journal.html` | Live climb progress page |

## CI gate

```bash
python tools/check_ai_bench_report.py --base origin/main
# or force:
python tools/check_ai_bench_report.py --always
```

Checks: signature field present, primary config, `ai_surface_hash` matches
this tree, score ≥ baseline. `hills verify` is best-effort on CI (HMAC keys
are per-machine unless a shared key is configured).

## Raw harness (debug only — not an official score)

```bash
OUT=/tmp/eots-ai-vs-ai-$$
tools/run.sh --headless --script res://tools/ai_vs_ai.gd -- \
  --turns=200 --seed=1500 --size=1 --runs=1 --ai=bench --out="$OUT"
```

| Flag | Use |
|------|-----|
| `--ai=bench` | Live crown vs no-op rivals (hill metric) |
| `--ai=full` | All crowns plan (observation) |
| `--ai=noop` | All inert (sanity) |

## Cleanup

```bash
rm -rf /tmp/eots-ai-vs-ai-* /tmp/ai-bench-* /tmp/eots-ai-bench-*
```
