# Measurements

Every measured number lives here, one row per run, with the date, git commit, model and settings. Numbers in
`ROADMAP.md` are copied from this file. Machine names below are used in the rows.

## Machines

| Name | CPU | RAM | GPU | OS | How to run Godot |
| :--- | :--- | ---: | :--- | :--- | :--- |
| `win-pc` | Intel Core i5-13400F (10 cores, 16 threads) | 32 GB | NVIDIA GeForce RTX 3070, 8 GB VRAM | Windows 11 Pro 10.0.26200 | `.tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . [--headless] <scene>` |
| `mac-m4` | Apple M4 | 16 GB | M4 (Metal) | macOS | `/Applications/Godot.app/Contents/MacOS/Godot --path . [--headless] <scene>` |

`.tools/` is git-ignored; download Godot 4.7.1 there (official release from `godotengine/godot-builds`, check the SHA-512).

## Versions in use

| Component | Version | Source |
| :--- | :--- | :--- |
| Godot | 4.7.1 stable (`a13da4feb`) | `godotengine/godot-builds` release `4.7.1-stable`, SHA-512 checked 2026-10-05 |
| NobodyWho (Godot plugin) | v11.0.0 (2026-09-10) | GitHub release `nobodywho-godot-v11.0.0`, SHA-256 `567e6da8...` (pinned in `scripts/setup_addons.py`) |
| godot-whisper | v2.0.3 (2026-06-21) | GitHub release `v2.0.3`, SHA-256 `1f1d53df...` (pinned in `scripts/setup_addons.py`) |
| Qwen3.5-4B Q4_K_M | `Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf`, 2.74 GB | `NobodyWho/Qwen_Qwen3.5-4B-GGUF`, Apache 2.0, SHA-256 matched the Hugging Face value |
| Gemma 4 E4B Q4_K_M | `gemma-4-E4B-it-Q4_K_M.gguf`, 4.98 GB | `NobodyWho/Google_Gemma4-E4B-GGUF`, Apache 2.0 |
| Ministral-3-8B-Instruct Q4_K_M | `Ministral-3-8B-Instruct-2512-Q4_K_M-vendor-sampling.gguf`, 5.20 GB | `NobodyWho/Mistral_Ministral-3-8B-Instruct-GGUF`, Apache 2.0 |

## Phase 1: model tests

Run table, rebuilt by `python scripts/bench_table.py` from the raw files in `docs/runs/` (do not edit between the markers).
Columns: *Total ms* is the time from sending the player's line until the whole JSON reply is finished; *Say ms* is the time
until the spoken line (`say`) is complete, which is when speech could start. *RAM MB* is the process total after the run (model
included). *VRAM MB* is the rise in total GPU memory after the model loaded (nvidia-smi, all processes).

<!-- runs:start -->
| Date | Commit | Machine | Model | Settings | Turns | Valid JSON | Load s | RAM MB | VRAM MB | Total ms (median) | Total ms (p95) | Say ms (median) | Tok/s | Words | Calls paid | Pay mismatches | Suspicion spread | Director obeyed | Raw data |
| :--- | :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| 2026-10-05 01:53 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, schema, keys default, rules | 24 | 100% | 2.0 | 3372 | +3282 | 904 | 1235 | 766 | 88 | 15 | - | - | - | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_run1.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_run1.jsonl) |
| 2026-10-05 01:53 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, schema, keys default, rules | 24 | 100% | 1.9 | 3373 | +3282 | 910 | 1207 | 772 | 89 | 15 | - | - | - | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_run2.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_run2.jsonl) |
| 2026-10-05 01:54 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | CPU, ctx 4096, think off, schema, keys default, rules | 24 | 100% | 0.8 | 3134 | - | 5237 | 5830 | 4375 | 14 | 15 | - | - | - | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_cpu_run1.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_cpu_run1.jsonl) |
| 2026-10-05 01:56 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, schema, keys default, rules | 21 | 95% | 65.7 | 3648 | +3628 | 786 | 13593 | 669 | 77 | 20 | - | - | - | - | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_run1.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_run1.jsonl) |
| 2026-10-05 01:59 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, schema, keys default, rules | 21 | 95% | 2.5 | 3621 | +3637 | 779 | 1360 | 656 | 77 | 20 | - | - | - | - | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_run2.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_run2.jsonl) |
| 2026-10-05 02:01 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, grammar, keys default, rules | 24 | 100% | 53.1 | 3377 | +3279 | 773 | 1186 | 593 | 80 | 16 | - | - | - | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_run3.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_run3.jsonl) |
| 2026-10-05 02:13 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, grammar, keys default, rules | 66 | 100% | 1.9 | 3410 | +3289 | 828 | 1180 | 648 | 80 | 16 | 3/12 | 15 | 22 | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv1-default.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv1-default.jsonl) |
| 2026-10-05 02:14 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, grammar, keys default, rules_v2 | 63 | 100% | 1.8 | 3381 | +3289 | 848 | 1131 | 669 | 80 | 16 | 3/12 | 3 | 25 | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv2-default.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv2-default.jsonl) |
| 2026-10-05 02:16 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v2 | 67 | 100% | 1.8 | 3378 | +3288 | 870 | 1125 | 690 | 80 | 16 | 5/12 | 0 | 34 | - | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv2-actionfirst.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv2-actionfirst.jsonl) |
| 2026-10-05 02:17 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, grammar, keys default, rules | 71 | 100% | 86.8 | 3578 | +3650 | 731 | 1242 | 510 | 70 | 20 | 1/12 | 4 | 31 | - | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv1-default.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv1-default.jsonl) |
| 2026-10-05 02:19 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, grammar, keys default, rules_v2 | 72 | 100% | 2.2 | 3587 | +3636 | 717 | 1276 | 524 | 70 | 21 | 0/12 | 0 | 31 | - | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv2-default.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv2-default.jsonl) |
| 2026-10-05 02:20 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v2 | 72 | 100% | 2.2 | 3578 | +3636 | 724 | 1263 | 531 | 70 | 21 | 0/12 | 0 | 28 | - | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv2-actionfirst.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv2-actionfirst.jsonl) |
| 2026-10-05 02:22 | `9b6a2e2+wip` | win-pc | ministral3-8b-q4km (4958 MB) | GPU, ctx 4096, think off, grammar, keys default, rules_v2 | 71 | 100% | 2.8 | 5329 | +5472 | 1759 | 2138 | 1491 | 61 | 43 | 4/12 | 10 | 45 | - | [2026-10-05_win-pc_ministral3-8b-q4km_gpu_runv2-default.jsonl](runs/2026-10-05_win-pc_ministral3-8b-q4km_gpu_runv2-default.jsonl) |
| 2026-10-05 02:30 | `9b6a2e2+wip` | win-pc | ministral3-8b-q4km (4958 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v2 | 65 | 100% | 2.7 | 5324 | +5478 | 1552 | 1960 | 1304 | 61 | 40 | 7/12 | 6 | 36 | - | [2026-10-05_win-pc_ministral3-8b-q4km_gpu_runv2-actionfirst.jsonl](runs/2026-10-05_win-pc_ministral3-8b-q4km_gpu_runv2-actionfirst.jsonl) |
| 2026-10-05 02:39 | `9b6a2e2+wip` | win-pc | qwen3.5-4b-q4km (2614 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v3, director | 58 | 100% | 1.8 | 3413 | +3288 | 890 | 1138 | 718 | 83 | 16 | 7/12 | 0 | 18 | pay 7/7, stall 42/42 | [2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv3-director.jsonl](runs/2026-10-05_win-pc_qwen3.5-4b-q4km_gpu_runv3-director.jsonl) |
| 2026-10-05 02:40 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v3, director | 57 | 100% | 2.2 | 3583 | +3637 | 717 | 1221 | 518 | 72 | 20 | 8/12 | 0 | 13 | pay 8/8, stall 41/41 | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv3-director.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runv3-director.jsonl) |
| 2026-10-05 03:07 | `9b6a2e2+wip` | win-pc | gemma4-e2b-q4km (2963 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v3, director | 57 | 100% | 1.6 | 1956 | +2005 | 475 | 973 | 359 | 107 | 22 | 8/12 | 0 | 4 | pay 8/8, stall 41/41 | [2026-10-05_win-pc_gemma4-e2b-q4km_gpu_runv3-director.jsonl](runs/2026-10-05_win-pc_gemma4-e2b-q4km_gpu_runv3-director.jsonl) |
| 2026-10-05 03:07 | `9b6a2e2+wip` | win-pc | gemma4-e2b-q4km (2963 MB) | CPU, ctx 4096, think off, grammar, keys action_first, rules_v3, director | 15 | 100% | 0.9 | 1767 | - | 2132 | 2932 | 1635 | 28 | 23 | 2/3 | 0 | 3 | pay 2/2, stall 12/12 | [2026-10-05_win-pc_gemma4-e2b-q4km_cpu_runv3-director.jsonl](runs/2026-10-05_win-pc_gemma4-e2b-q4km_cpu_runv3-director.jsonl) |
| 2026-10-05 03:08 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | CPU, ctx 4096, think off, grammar, keys action_first, rules_v3, director | 15 | 100% | 1.1 | 3231 | - | 3815 | 4388 | 2919 | 17 | 23 | 2/3 | 0 | 14 | pay 2/2, stall 12/12 | [2026-10-05_win-pc_gemma4-e4b-q4km_cpu_runv3-director.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_cpu_runv3-director.jsonl) |
| 2026-10-05 04:16 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km (4747 MB) | GPU, ctx 4096, think off, grammar, keys action_first, rules_v3, director | 57 | 100% | 2.3 | 3581 | +3637 | 745 | 1228 | 566 | 72 | 20 | 8/12 | 0 | 12 | pay 8/8, stall 41/41 | [2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runfinal-v3-director.jsonl](runs/2026-10-05_win-pc_gemma4-e4b-q4km_gpu_runfinal-v3-director.jsonl) |
<!-- runs:end -->

## Phase 2: typed playtest

Ten open-ended calls with `scenes/playtest.tscn`: a second chat on the same model plays the scammer (a bot, so these are not
human-typed calls), the victim side runs through the real `CallSession` with the director. Transcripts are in `docs/playtests/`.
"Stayed in character" is my reading of the transcripts (I read calls 1 to 3 in full and checked the caller lines of all ten
for mentions of AI, the game or its rules, repeated lines and markdown), not the user's fun check.

| Date | Commit | Machine | Model | Config | Calls | Paid | Ended by turn limit | Broken replies | Caller lines | Slips out of character | Repeated lines | Lines with `*asterisks*` | Total cash | Transcript |
| :--- | :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| 2026-10-05 02:47 | `9b6a2e2+wip` | win-pc | gemma4-e4b-q4km | GPU, rules v3, keys action_first, grammar, director | 10 | 4 (Gladys 3 of 3, Barry 1 of 4, Priya 0 of 3) | 6 (cap of 10 turns) | 0 | 87 | 0 | 0 | 3 (now stripped by `ReplyParser.clean_say`) | $399 | [2026-10-05_gemma4-e4b_v3-director.md](playtests/2026-10-05_gemma4-e4b_v3-director.md) |

The amounts paid follow the scammer bot's prices ($40 for a $39.99 sticker, $299 for a certificate): the caller pays "the price
the caller named", so the player's own pricing sets the take, up to the persona's cap.

## Phase 3: voice stack (text-to-speech and speech-to-text)

Rebuilt by `python scripts/voice_table.py` from `docs/runs/voice/*.jsonl` (do not edit between the markers), written by
`scenes/voice_test.tscn`. Eight typical caller lines (about 13 words) are synthesized, then the audio is transcribed again, plus one
real human recording (`jfk.wav`, 11 s, shipped inside the godot-whisper release). The text-to-speech audio is clean, so its
accuracy flatters speech-to-text; the human clip is the honest one. Nothing was played out loud, and I cannot judge how a voice
sounds, only how fast and how intelligible it is: **a person has to listen** (the clips are in `.tools/voice/tts_*.wav`).

<!-- voice:start -->
| Date | Machine | Stage | Engine / model | Load s | First pass ms (median) | Steady ms (median) | Steady real-time factor | Accuracy (word error rate) | Raw data |
| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- |
| 2026-10-05 02:55 | win-pc | text-to-speech | Godot OS voices (3: Microsoft David (en_US), Microsoft Mark (en_US), Microsoft Zira (en_US)) | 0 | - | start 62, whole line 6395 | - | spoken at volume 0, so timing only | [2026-10-05_win-pc_os_tts.jsonl](runs/voice/2026-10-05_win-pc_os_tts.jsonl) |
| 2026-10-05 02:54 | win-pc | speech-to-text | godot-whisper, ggml-base.en | 0.4 | 147 | 146 | 0.028 | human recording 0.00; text-to-speech clips median 0.00 (digits written as numerals count as errors) | [2026-10-05_win-pc_stt_godotwhisper.jsonl](runs/voice/2026-10-05_win-pc_stt_godotwhisper.jsonl) |
| 2026-10-05 02:54 | win-pc | speech-to-text | NobodyWho Whisper base (ONNX q4) | 9.5 | 577 | 531 | 0.106 | human recording 0.00; text-to-speech clips median 0.00 (digits written as numerals count as errors) | [2026-10-05_win-pc_stt_nobodywho.jsonl](runs/voice/2026-10-05_win-pc_stt_nobodywho.jsonl) |
| 2026-10-05 02:51 | win-pc | text-to-speech | NobodyWho Kokoro-82M, voice bf_emma | 106.9 | 1268 | 728 | 0.141 | audio 5.1 s per line (median); returns the whole clip, no streaming | [2026-10-05_win-pc_tts_kokoro.jsonl](runs/voice/2026-10-05_win-pc_tts_kokoro.jsonl) |
<!-- voice:end -->

### End to end: key released until the caller starts talking

Rebuilt by `python scripts/voice_table.py` from the `*pipeline*.jsonl` files (do not edit between the markers). A recorded clip stands in
for the microphone; the steps are godot-whisper, then the real model with the director, then the voice. "late" speaks when the
whole reply is in, "early" speaks as soon as the spoken line is complete. The target is under 3 s. Variants: `whole-line` is the first
Kokoro version (one synthesis per line), `sentences` plays the first sentence while the next is synthesized, `sentences-commas` also
splits long sentences at a comma.

<!-- pipeline:start -->
| Date | Machine | Variant | Engine, mode | Turns | First turn ms | Later turns ms (median) | Later turns ms (worst) | Speech-to-text ms | AI reply ms | Voice start ms | Raw data |
| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| 2026-10-05 03:03 | win-pc | gemma4_sentences-commas | kokoro/late | 4 | 2290 | 1790 | 2040 | 262 | 940 | 940 | [2026-10-05_win-pc_pipeline_gemma4_sentences-commas.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_sentences-commas.jsonl) |
| 2026-10-05 03:03 | win-pc | gemma4_sentences-commas | kokoro/early | 4 | 1727 | 1140 | 1450 | 237 | 981 | 490 | [2026-10-05_win-pc_pipeline_gemma4_sentences-commas.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_sentences-commas.jsonl) |
| 2026-10-05 03:02 | win-pc | gemma4_sentences | kokoro/late | 4 | 2214 | 1770 | 2130 | 273 | 987 | 891 | [2026-10-05_win-pc_pipeline_gemma4_sentences.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_sentences.jsonl) |
| 2026-10-05 03:02 | win-pc | gemma4_sentences | kokoro/early | 5 | 1806 | 1700 | 2310 | 232 | 751 | 490 | [2026-10-05_win-pc_pipeline_gemma4_sentences.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_sentences.jsonl) |
| 2026-10-05 03:00 | win-pc | gemma4_whole-line | os/late | 4 | 1432 | 995 | 1125 | 226 | 930 | 68 | [2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl) |
| 2026-10-05 03:00 | win-pc | gemma4_whole-line | os/early | 5 | 1172 | 791 | 823 | 216 | 707 | 64 | [2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl) |
| 2026-10-05 03:00 | win-pc | gemma4_whole-line | kokoro/late | 5 | 2796 | 2772 | 3061 | 252 | 841 | 1501 | [2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl) |
| 2026-10-05 03:00 | win-pc | gemma4_whole-line | kokoro/early | 4 | 2143 | 1588 | 3100 | 230 | 928 | 909 | [2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl](runs/voice/2026-10-05_win-pc_pipeline_gemma4_whole-line.jsonl) |
<!-- pipeline:end -->


## Phase 4: compressed shifts

Whole working days on the real model (Gemma 4 E4B, GPU), each shortened to 90 s (a real day is 480 s), with the scammer bot standing in for
the player, so they are far faster than a human's calls. The shift, call queue, director, boss review and saving are the real ones.
The verdict is arithmetic done by the game; the boss's rant comes from the model. Transcripts and reviews are in
[2026-10-05_compressed-shift_gemma4-e4b.md](playtests/2026-10-05_compressed-shift_gemma4-e4b.md) and, for all six performance tiers,
[2026-10-05_boss-reviews.md](playtests/2026-10-05_boss-reviews.md).

| Date | Machine | Day | Length s | Quota | Cash | Calls | Paid | Verdict | Strikes after | Boss review ready after the clock ran out (ms) | Source |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 2026-10-05 03:15 | win-pc | 1 | 90 | $400 | $1138 | 9 | 4 | pass | 0 | 1463 | model |
| 2026-10-05 03:15 | win-pc | 2 (loaded from the day-1 save) | 90 | $450 | $1008 | 10 | 5 | pass | 0 | 1328 | model |
| 2026-10-05 03:26 | win-pc | 1 (through the desk UI, scripted lines) | 45 | $400 | $1650 | 10 | 5 | pass | 0 | 1247 | model |

Boss review check on six made-up days (`scenes/boss_check.tscn`): 1.2 to 1.6 s each once warm (3.7 s for the first one in a process).
Without amounts in words the model misread "$450" as "forty dollars"; with them it said "four hundred fifty dollars".
