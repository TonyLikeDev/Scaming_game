#!/bin/bash
# Phase 1 comparison: every candidate model with three prompt/key-order configurations, grammar-constrained, on the GPU.
# Usage: scripts/bench_matrix.sh   (about 20 minutes; results land in docs/runs/ and docs/measurements.md)
cd "$(dirname "$0")/.." || exit 1
models=(
  "Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf qwen3.5-4b-q4km"
  "gemma-4-E4B-it-Q4_K_M.gguf gemma4-e4b-q4km"
  "Ministral-3-8B-Instruct-2512-Q4_K_M-vendor-sampling.gguf ministral3-8b-q4km"
)
for entry in "${models[@]}"; do
  set -- $entry
  scripts/bench.sh "$1" "$2" 1 "v1-default"      --calls=4 --closers=2
  scripts/bench.sh "$1" "$2" 1 "v2-default"      --calls=4 --closers=2 --rules=res://data/caller_rules_v2.txt
  scripts/bench.sh "$1" "$2" 1 "v2-actionfirst"  --calls=4 --closers=2 --rules=res://data/caller_rules_v2.txt --order=action_first
done
echo MATRIX_DONE
