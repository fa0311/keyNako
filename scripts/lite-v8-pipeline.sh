#!/usr/bin/env bash
# lite-v8: rescore the cascade with the certified v8 max (its scores differ
# from v7 exactly on rows containing newly-visible characters), then
# continuation-train the vocab-extended lite-v7. Requires lite-v8-init
# (ime-extend-vocab, identity-verified) and the v7 materialized caches.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
ART="$TOOLS/artifacts"
MAX="$ART/students/ime-reranker-max-v8"
LOGITS="$ART/cascade-logits-v8"

cd "$TOOLS"

retry() { # retry <label> <cmd...>
  local label="$1"; shift
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "[$label] attempt $attempt failed; retrying" >&2; sleep 30
  done
  echo "[$label] FAILED" >&2; return 1
}

echo "== stage 1: cascade rescoring with max-v8 (GPU) =="
retry score uv run ime-score-teacher --teacher "$MAX" \
  --input "$ART/materialized/v1/train.jsonl" \
  --input "$ART/materialized/v1/dev.jsonl" \
  --input "$ART/materialized/note-v1/train-200k.jsonl" \
  --input "$ART/materialized/note-v1/dev.jsonl" \
  --input "$ART/materialized/bunsetsu-v7/train.jsonl" \
  --input "$ART/materialized/bunsetsu-v7/dev.jsonl" \
  --input "$ART/materialized/lexical-v1/train.jsonl" \
  --input "$ART/materialized/compose-v2/train.jsonl" \
  --input "$ART/materialized/compose-suffix-v3/train.jsonl" \
  --input "$ART/materialized/noctx-v7/train.jsonl" \
  --output-dir "$LOGITS" --rows-per-batch 8 --resume

echo "== stage 2: train lite-v8 (continuation) =="
retry train uv run ime-distill --student lite \
  --init-from "$ART/students/lite-v8-init" \
  --tokenizer-dir "$ART/students/lite-v8-init" \
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
  --teacher-logits-dir "$LOGITS" \
  --output-dir "$ART/students/ime-reranker-lite-v8" \
  --epochs 2 --learning-rate 1e-4

echo "LITE_V8_PIPELINE_DONE"
