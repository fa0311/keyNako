#!/usr/bin/env bash
# Overnight tier-finalization chain (2026-08-16):
#   1. deep-min (6L x 192) full cascade run — the missing min-tier data
#   2. deep-mid (6L x 384) resume at 10x5 — the std-tier challenger
# Both train on the max-v8 cascade logits. Each stage retries; a stage that
# exhausts retries is skipped so the rest of the night still produces data.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
ART="$TOOLS/artifacts"
cd "$TOOLS"

MIX=(
  --train "$ART/materialized/v1/train.jsonl"
  --train "$ART/materialized/v1/train.jsonl"
  --train "$ART/materialized/lexical-v1/train.jsonl"
  --train "$ART/materialized/note-v1/train-200k.jsonl"
  --train "$ART/materialized/bunsetsu-v7/train.jsonl"
  --train "$ART/materialized/noctx-v7/train.jsonl"
  --train "$ART/materialized/noctx-v7/train.jsonl"
  --train "$ART/materialized/compose-v2/train.jsonl"
  --train "$ART/materialized/compose-v2/train.jsonl"
  --train "$ART/materialized/compose-suffix-v3/train.jsonl"
  --train "$ART/materialized/compose-suffix-v3/train.jsonl"
  --dev "$ART/materialized/v1/dev.jsonl"
  --dev "$ART/materialized/bunsetsu-v7/dev.jsonl"
  --teacher-logits-dir "$ART/cascade-logits-v8"
)

retry() { # retry <label> <cmd...>
  local label="$1"; shift
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "[$label] attempt $attempt failed; retrying" >&2; sleep 30
  done
  echo "[$label] FAILED" >&2; return 1
}

echo "== stage 1: deep-min init + train =="
uv run ime-init-cascade --teacher "$ART/students/ime-reranker-max-v8" \
  --student deep-min --output-dir "$ART/students/deep-min-init" \
&& retry train-min uv run ime-distill --student deep-min \
  --init-from "$ART/students/deep-min-init" \
  --tokenizer-dir "$ART/students/ime-reranker-max-v8" \
  "${MIX[@]}" \
  --output-dir "$ART/students/ime-reranker-deep-min-v8" \
  && echo DEEP_MIN_DONE

echo "== stage 2: deep-mid resume (10x5) =="
retry train-mid uv run ime-distill --student deep-mid \
  --init-from "$ART/students/deep-mid-ep1" \
  --tokenizer-dir "$ART/students/ime-reranker-max-v8" \
  "${MIX[@]}" \
  --output-dir "$ART/students/ime-reranker-deep-mid-v8" \
  --epochs 3 --learning-rate 2e-4 \
  --query-batch-size 10 --gradient-accumulation 5 \
  && echo DEEP_MID_DONE

echo "NIGHT_TIER_CHAIN_DONE"
