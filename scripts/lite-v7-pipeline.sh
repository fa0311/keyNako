#!/usr/bin/env bash
# lite-v7 cascade pipeline: rescore the v7 mix with the certified max-v7
# student as teacher, PCA-init the narrow tier from its weights, distill.
# Requires a completed v7-pipeline.sh run (materialized caches in place).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
ART="$TOOLS/artifacts"
MAX="$ART/students/ime-reranker-max-v7"
LOGITS="$ART/cascade-logits-v7"

cd "$TOOLS"

retry() { # retry <label> <cmd...>
  local label="$1"; shift
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "[$label] attempt $attempt failed; retrying" >&2; sleep 30
  done
  echo "[$label] FAILED" >&2; return 1
}

echo "== stage 1: cascade scoring (GPU) =="
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

echo "== stage 2: PCA cascade init =="
uv run ime-init-cascade --teacher "$MAX" --student lite \
  --output-dir "$ART/students/lite-v7-init"

echo "== stage 3: train lite-v7 =="
retry train uv run ime-distill --student lite \
  --init-from "$ART/students/lite-v7-init" \
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
  --teacher-logits-dir "$LOGITS" \
  --output-dir "$ART/students/ime-reranker-lite-v7"

echo "LITE_V7_PIPELINE_DONE"
