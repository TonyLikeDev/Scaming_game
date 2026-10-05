#!/bin/bash
# Run the Phase 1 model test: scripts/bench.sh <model file in models/> <label> <gpu 0|1> <run number> [extra model_test args]
# Raw per-turn data goes to docs/runs/, then the table in docs/measurements.md is rebuilt.
cd "$(dirname "$0")/.." || exit 1
model="$1"; label="$2"; gpu="$3"; run="$4"; shift 4
machine="${BENCH_MACHINE:-win-pc}"
out="docs/runs/$(date +%Y-%m-%d)_${machine}_${label}_$([ "$gpu" = 1 ] && echo gpu || echo cpu)_run${run}.jsonl"
python scripts/godot_run.py --timeout 900 --log "bench_${label}_${gpu}_${run}" -- --headless scenes/model_test.tscn -- \
  --model="models/${model}" --label="${label}" --gpu="${gpu}" --out="${out}" "$@" | grep -E "^MODEL_TEST|^ERROR|SCRIPT ERROR"
python scripts/bench_table.py
