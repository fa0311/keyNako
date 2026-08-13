#!/usr/bin/env bash
# v7 (bunsetsu generation) data + training pipeline.
# Regenerates every cache from the pinned submodules — candidate lists now
# reflect the lattice kaomoji policy, so the training distribution matches
# the runtime for the first time. Run from the workspace root via git-bash.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
CLI="$ROOT/engine/target/release/ime-cli.exe"
PACK="$ROOT/data/dictionary-core/dictionary.sqlite3"
DATASET="$ROOT/data/context-dataset/data"
NOTE="$ROOT/data/note-articles"
TEACHER="$ROOT/models/reranker-v1"
ART="$TOOLS/artifacts"
LOGITS="$ART/teacher-logits-v7"

cd "$TOOLS"
mkdir -p "$ART"

retry() { # retry <label> <cmd...>
  local label="$1"; shift
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "[$label] attempt $attempt failed; retrying" >&2; sleep 30
  done
  echo "[$label] FAILED" >&2; return 1
}

echo "== stage 1: mining =="
uv run ime-mine-note --dataset-dir "$NOTE" --pack "$PACK" \
  --output "$ART/mined/note-token.jsonl" --max-rows 400000
uv run ime-mine-note --dataset-dir "$NOTE" --pack "$PACK" \
  --output "$ART/mined/note-bunsetsu.jsonl" --max-rows 300000 --bunsetsu

echo "== stage 2: materialize =="
uv run ime-materialize \
  --dataset-file "$DATASET/core.jsonl" \
  --dataset-file "$DATASET/difficult_context.jsonl" \
  --dataset-file "$DATASET/hard_context.jsonl" \
  --dataset-file "$DATASET/person_context.jsonl" \
  --pack "$PACK" --ime-cli "$CLI" --output-dir "$ART/materialized/v1"
uv run ime-materialize --dataset-file "$ART/mined/note-token.jsonl" \
  --pack "$PACK" --ime-cli "$CLI" --output-dir "$ART/materialized/note-v1"
head -n 200000 "$ART/materialized/note-v1/train.jsonl" > "$ART/materialized/note-v1/train-200k.jsonl"
uv run ime-materialize --dataset-file "$ART/mined/note-bunsetsu.jsonl" \
  --pack "$PACK" --ime-cli "$CLI" --output-dir "$ART/materialized/bunsetsu-v7"

echo "== stage 3: augmentation =="
uv run ime-augment-lexical --pack "$PACK" --ime-cli "$CLI" \
  --output-dir "$ART/materialized/lexical-v1" --count 100000
uv run ime-augment-lexical --pack "$PACK" --ime-cli "$CLI" \
  --output-dir "$ART/materialized/compose-v2" --count 40000 \
  --min-entry-candidates 1 --max-entry-cost 5000 \
  --suffixes "を,に,の,は,が,で,と,へ,も,な,から,まで,には,では"
uv run ime-augment-lexical --pack "$PACK" --ime-cli "$CLI" \
  --output-dir "$ART/materialized/compose-suffix-v3" --count 40000 --seed 43 \
  --min-entry-candidates 1 --max-entry-cost 5000 \
  --suffixes "ちゃん,さん,くん,たん,さま,どの,せんぱい,せんせい"
uv run ime-strip-context \
  --input "$ART/materialized/v1/train.jsonl" \
  --input "$ART/materialized/note-v1/train-200k.jsonl" \
  --input "$ART/materialized/bunsetsu-v7/train.jsonl" \
  --output "$ART/materialized/noctx-v7/train.jsonl"

echo "== stage 4: teacher scoring (GPU, hours) =="
retry score uv run ime-score-teacher --teacher "$TEACHER" \
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

echo "== stage 5: train max-v7 =="
retry train uv run ime-distill --student max \
  --init-from "$ROOT/models/reranker-v2-max" \
  --tokenizer-dir "$ROOT/models/reranker-v2-max" \
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
  --output-dir "$ART/students/ime-reranker-max-v7" \
  --epochs 2 --learning-rate 5e-5 \
  --query-batch-size 8 --gradient-accumulation 5

echo "V7_PIPELINE_DONE"
