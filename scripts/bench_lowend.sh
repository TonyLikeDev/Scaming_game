#!/bin/bash
# Phase 9 low-end data: the smaller Gemma 4 E2B, and what a PC without a usable GPU gets (CPU only), with the director.
cd "$(dirname "$0")/.." || exit 1
common=(--closers=2 --rules=res://data/caller_rules_v3.txt --order=action_first --director=1)
scripts/bench.sh gemma-4-E2B-it-Q4_K_M.gguf gemma4-e2b-q4km 1 "v3-director" --calls=4 "${common[@]}"
scripts/bench.sh gemma-4-E2B-it-Q4_K_M.gguf gemma4-e2b-q4km 0 "v3-director" --calls=1 "${common[@]}"
scripts/bench.sh gemma-4-E4B-it-Q4_K_M.gguf gemma4-e4b-q4km 0 "v3-director" --calls=1 "${common[@]}"
echo LOWEND_DONE
