#!/bin/bash
# Phase 1 round two: the director (the game decides when a caller pays). Rules v3 + action-first key order + --director=1,
# for every candidate model, plus the one round-one run that did not finish.
cd "$(dirname "$0")/.." || exit 1
scripts/bench.sh Ministral-3-8B-Instruct-2512-Q4_K_M-vendor-sampling.gguf ministral3-8b-q4km 1 "v2-actionfirst" --calls=4 --closers=2 --rules=res://data/caller_rules_v2.txt --order=action_first
models=(
  "Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf qwen3.5-4b-q4km"
  "gemma-4-E4B-it-Q4_K_M.gguf gemma4-e4b-q4km"
  "Ministral-3-8B-Instruct-2512-Q4_K_M-vendor-sampling.gguf ministral3-8b-q4km"
)
for entry in "${models[@]}"; do
  set -- $entry
  scripts/bench.sh "$1" "$2" 1 "v3-actionfirst-director" --calls=4 --closers=2 --rules=res://data/caller_rules_v3.txt --order=action_first --director=1
done
echo MATRIX2_DONE
