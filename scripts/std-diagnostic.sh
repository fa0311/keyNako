#!/usr/bin/env bash
# standard-tier (4L x 512, ~17M) capacity diagnostic: same cascade recipe as
# lite-v7 but the wider student, initialized from the certified v8 max (16k
# vocab). Answers whether lite's homophone-gate miss (32/39 vs >=35) is a
# capacity problem. Reuses cascade-logits-v7 sidecars (scored by max-v7 —
# near-identical scorer to v8).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
ART="$TOOLS/artifacts"
MAX="$ART/students/ime-reranker-max-v8"

cd "$TOOLS"

retry() { # retry <label> <cmd...>
  local label="$1"; shift
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "[$label] attempt $attempt failed; retrying" >&2; sleep 30
  done
  echo "[$label] FAILED" >&2; return 1
}

echo "== stage 1: PCA cascade init (768 -> 512) =="
uv run ime-init-cascade --teacher "$MAX" --student standard \
  --output-dir "$ART/students/std-v8-init"

echo "== stage 2: train std-v8 =="
retry train uv run ime-distill --student standard \
  --init-from "$ART/students/std-v8-init" \
  --tokenizer-dir "$MAX" \
  --train "$ART/materialized/v1/train.jsonl" \
  --train "$ART/materialized/v1/train.jsonl" \
  --train "$ART/materialized/lexical-v1/train.jsonl" \
  --train "$ART/materialized/note-v1/train-200k.jsonl" \
  --train "$ART/materialized/bunsetsu-v7/train.jsonl" \
  --train "$ART/materialized/noctx-v7/train.jsonl" \
  --train "$ART/materialized/noctx-v7/train.jsonl" \
  --train "$ART/materialized/compose-v2/train.jsonl" \
  --train "$ART/materialized/compose-v2/train.jsonl" \
  --train "$ART/materialized/compose-suffix-v3/train.jsonl" \
  --train "$ART/materialized/compose-suffix-v3/train.jsonl" \
  --dev "$ART/materialized/v1/dev.jsonl" \
  --dev "$ART/materialized/bunsetsu-v7/dev.jsonl" \
  --teacher-logits-dir "$ART/cascade-logits-v7" \
  --output-dir "$ART/students/ime-reranker-std-v8"

echo "STD_DIAGNOSTIC_DONE"
