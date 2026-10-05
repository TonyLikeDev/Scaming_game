#!/bin/bash
# Phase 1 round three: the refined director (every turn gets a note; pay odds calibrated by gullibility).
cd "$(dirname "$0")/.." || exit 1
models=(
  "Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf qwen3.5-4b-q4km"
  "gemma-4-E4B-it-Q4_K_M.gguf gemma4-e4b-q4km"
)
for entry in "${models[@]}"; do
  set -- $entry
  scripts/bench.sh "$1" "$2" 1 "v3-director" --calls=4 --closers=2 --rules=res://data/caller_rules_v3.txt --order=action_first --director=1
done
echo MATRIX3_DONE
