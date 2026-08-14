#!/usr/bin/env bash
# v8 (vocabulary generation): continuation-train the vocab-extended max on the
# v7 mix. The extension (ime-extend-vocab) is an exact identity — new chars
# start as [UNK] copies — so this run only ever adds literacy for the 8,192
# added characters (kanji completion, kaomoji marks, emoji, width forms).
# Teacher logit sidecars are tokenizer-independent and are reused from v7.
# Requires: artifacts/students/max-v8-init (built), teacher-logits-v7 (full).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
ART="$TOOLS/artifacts"

cd "$TOOLS"

retry() { # retry <label> <cmd...>
  local label="$1"; shift
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "[$label] attempt $attempt failed; retrying" >&2; sleep 30
  done
  echo "[$label] FAILED" >&2; return 1
}

echo "== stage 1: train max-v8 (continuation) =="
retry train uv run ime-distill --student max \
  --init-from "$ART/students/max-v8-init" \
  --tokenizer-dir "$ART/students/max-v8-init" \
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
  --teacher-logits-dir "$ART/teacher-logits-v7" \
  --output-dir "$ART/students/ime-reranker-max-v8" \
  --epochs 2 --learning-rate 5e-5 \
  --query-batch-size 8 --gradient-accumulation 5

echo "V8_PIPELINE_DONE"
