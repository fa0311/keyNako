#!/usr/bin/env bash
# deep-lite (6L x 256, ~8M) depth-vs-width probe: same cascade recipe as
# lite-v7 but the deeper student, initialized from the certified v8 max (16k
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

echo "== stage 1: PCA cascade init (768 -> 256) =="
uv run ime-init-cascade --teacher "$MAX" --student deep-lite \
  --output-dir "$ART/students/deep-lite-v8-init"

echo "== stage 2: train std-v8 =="
retry train uv run ime-distill --student deep-lite \
  --init-from "$ART/students/deep-lite-v8-init" \
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
  --output-dir "$ART/students/ime-reranker-deep-lite-v8"

echo "DEEP_LITE_DIAGNOSTIC_DONE"
