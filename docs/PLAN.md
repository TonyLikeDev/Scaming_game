# Plan: *Scam Desk* (working title)

A co-op comedy sim inspired by *Scam With Your Friends* (see `../THEGAME.md`). You work a scam call center, talk to AI-voiced callers over your mic, dodge scambaiters and police raids, and survive your boss's review at the end of every shift.

Use our own name, art and characters. Copying mechanics is fine; copying their branding isn't.

**Tone rule:** the scams are absurd and fictional, like selling "premium air", an extended warranty for the Moon, or a timeshare on a cloud. That keeps it a comedy and not a how-to.

**Cost rule:** everything runs locally on the player's computer. That means no API keys, no server and no running costs.

---

## Tech decisions

| Area | Decision | Why |
|---|---|---|
| Engine | Godot 4.7 (4.7.1 current), GDScript | Same engine as `parkourgame` |
| Platform | Windows 10/11 first, macOS second | Steam players are mostly on Windows, and the reference game is Windows-only. Both machines are benchmarked (Windows PC with an RTX 3070, Mac M4) |
| Look | Flat UI desk until Phase 7 | Prove the fun before building a 3D office |
| Caller AI | [NobodyWho](https://docs.nobodywho.ooo) plugin: runs a local AI model inside Godot | Free, offline, no keys. Metal on Mac, Vulkan on Windows, CPU fallback |
| Model | **Gemma 4 E4B, Q4_K_M, non-thinking** (`gemma-4-E4B-it-Q4_K_M.gguf`, 4.98 GB, Apache 2.0). Fallback: Qwen3.5-4B. Chosen in Phase 1 | On the RTX 3070 it replies in a median 0.72 s (p95 1.2 s), reads as the most fluent and funniest of the three tested (Qwen3.5-4B, Gemma 4 E4B, Ministral-3 8B) in the transcripts (the user's fun check is still to come), and needs +3.6 GB VRAM. The 8B model was too slow and too big for an 8 GB card. Mac M4 numbers are still to be measured. See `docs/measurements.md` |
| Low-end setting | **Gemma 4 E2B, Q4_K_M** (3.1 GB, Apache 2.0): on a GPU +2.0 GB VRAM and a median 0.48 s reply; CPU only a median 2.1 s (E4B takes 3.8 s there) | For PCs with little VRAM or no GPU. Same director and grammar, so the game behaves the same; the lines are blander. Measured on the Windows PC only |
| Caller reply | A **GBNF grammar** (not a JSON schema) enforces the reply: fixed key order, no whitespace outside the spoken text, `say` capped at 300 characters. The game also cuts a turn off at 220 tokens | The JSON-schema route let the model pick any key order and loop on whitespace for thousands of tokens. The grammar gave 100% valid replies on every model tested |
| Game director | The code decides *when* a caller pays or hangs up, and sends the model a private `[DIRECTOR: ...]` note each turn (`src/call_director.gd`) | The models are unreliable about paying (Gemma paid in 0 of 12 calls unaided; Qwen paid at random). With notes they obey every order, and the pay rate becomes a number we balance: Gladys 93%, Barry 37%, a scambaiter 10% of calls |
| Caller voice | Two engines, switchable in the desk: the OS voices (`DisplayServer.tts_speak()`, the default) or NobodyWho's Kokoro-82M. The caller starts speaking as soon as the spoken line is complete, sentence by sentence | OS voices cost nothing and start in about 60 ms, but Windows only has 3 US voices and they talk slowly. Kokoro has 54 voices (British and American, men and women), is 7× faster than real time, starts in 0.4–0.5 s, and needs a 326 MB download. Which one is the default is the user's call after listening |
| Your voice | [godot-whisper](https://github.com/appsinacup/godot-whisper) addon (whisper.cpp), `ggml-base.en` (148 MB), push-to-talk. NobodyWho's own Whisper is the one-addon alternative | About 150 ms per line, word-perfect on a real human recording in the test; NobodyWho's takes 530 ms. Microphone and speech-to-text were checked, a person speaking was not |
| Saves | JSON in `user://` | No extra code needed |

**Plan B if the local AI isn't funny enough:** swap the caller brain to the Claude API. It's paid and needs a key, but the reply format stays the same, so only one script changes.

### Caller persona (`callers/*.json`)
```json
{
  "id": "gladys",
  "name": "Gladys Pemberton",
  "age": 82,
  "savings": 14000,
  "gullibility": 0.8,
  "quirks": ["thinks you are her nephew Kevin", "keeps mentioning her cat Mr. Biscuits"],
  "voice": "en-GB",
  "is_scambaiter": false
}
```

### What the AI sends back on every turn
```json
{"say":"Kevin? Is that you? Mr. Biscuits says hello.","action":"talk","amount":0,"suspicion":35}
```
- The keys always come in this order, `say` first so speech can start early and `action` straight after the line it belongs to. The grammar guarantees it.
- `suspicion` is the full 0–100 value each turn, not a change from last turn, so the game never has to add up numbers the AI got wrong.
- `action` is one of `talk`, `pay`, `hang_up` or `counter_attack` (scambaiters only). The director tells the model which one to use whenever money comes up.
- If the reply is broken or empty, the caller hangs up. A bad reply never crashes the call.

---

## Phases

Each phase ends with a **Done when** test. Don't start the next phase until it passes.

This is the plan: it holds the schedule and the decisions. Progress is recorded in `ROADMAP.md`, never here.

### Phase 1: Setup and model test (1 day)
- New Godot 4.7 project in this folder, plus `git init` and a `.gitignore` (ignore `*.gguf`, since model files are gigabytes)
- Install NobodyWho and godot-whisper from their GitHub releases with `scripts/setup_addons.py`, which pins the versions and checks SHA-256. The binaries are fetched, not committed, because some are over GitHub's 100 MB file limit. **Check both load in 4.7**
- Download 2–3 candidate models (one 4B, one 8B)
- Test scene: Gladys's persona + one scam line. Print the reply, words per second and RAM use for each model

**Done when:** one model replies in character, as valid JSON, in under 2 seconds.

### Phase 2: One call (the core loop, typed)
- 3 starter personas in `callers/`
- Caller brain: system prompt = shared rules + persona. Keeps the call history and returns the reply format above
- Desk UI: incoming-call button, transcript, text box, suspicion meter, cash counter
- Caller speaks each `say` through TTS, with a different OS voice per persona
- Call ends on `pay`, `hang_up` or suspicion 100

**Done when:** you type a scam at Gladys, she stays in character and sometimes pays. **Fun check:** if typing isn't funny, fix the prompts or try a bigger model before adding voice. If nothing works, switch to Plan B.

### Phase 3: Voice
- Push-to-talk (hold `V`) streams the mic into godot-whisper
- Measure each step: speech-to-text → AI → TTS. **Target: under 3 s** from releasing `V` until the caller starts talking
- If it's too slow: shorter replies, a smaller model, or start speaking as soon as `say` has finished streaming

**Done when:** a whole call works by voice alone.

### Phase 4: The shift
- Shift timer (about 8 real minutes) and a daily cash quota that grows each day: $400 on day 1, +15% a day, to the nearest $50 (`GameState`). A call still running when the clock hits zero may finish (up to 60 s)
- Call queue: random persona each call, never the same twice in a row, with randomized savings (0.5–1.5×) and gullibility (±0.1, and 0.015 lower for every day after the first)
- Boss review: the AI writes a rant from the shift stats (cash, calls, hang-ups, your best and worst lines), spoken by TTS. The game decides pass or fail and the boss's tone (a performance word and a tone line from cash ÷ quota); the model only writes the words. If the model cannot answer, a written fallback with the same numbers is used
- 3 failed reviews = fired (game over); a pass does not remove a strike. Save the current day between sessions (`user://save.json`, written after every review)

**Done when:** a full day works: clock in → calls → review → next day.

### Phase 5: Threats
- **Scambaiters** (`is_scambaiter: true`): they waste your time, fake-pay (the money disappears later) or `counter_attack` with malware. Malware is a short popup-closing minigame, and failing it costs cash
- **Police raids:** a heat meter rises with cash earned. A raid warning gives you a few seconds to hide the evidence. Failing loses the day's cash
- **Mid-call surprises** ("your grandson just walked in"), added as an extra note into the caller's conversation: the director gives about 40% of calls one surprise on reply 2 to 5, from a list of 10, never on a payment or hang-up reply (built and measured, 38% of calls in the test)

**Done when:** most shifts have at least one surprise.

### Phase 6: Modding
- Also load personas from `user://callers/*.json` (a file with a built-in `id` replaces that caller). Skip bad files with a warning, never crash
- `MODDING.md` documenting the persona format
- Voice cloning: **deferred.** Free local voice-cloning models exist but are heavy. Revisit only if playtests say the OS voices feel too cheap

**Done when:** dropping a JSON file into the folder adds a new caller.

### Phase 7: 3D office (optional)
- First-person desk with phone, monitor and shredder. Try reusing `parkourgame`'s player controller
- Raids and malware become physical actions in the office

**Done when:** the 3D version is more fun than the flat UI. Otherwise, keep the flat UI.

### Phase 8: Co-op
- Godot high-level multiplayer (`ENetMultiplayerPeer`), 1 host + up to 3 players
- Each player has their own desk and calls. Quota and raid heat are shared
- Each player's computer runs its own AI for its own calls. The host only syncs game state
- Voice chat between players: skip it and use Discord

**Done when:** 2 players on a local network finish a shift together.

### Phase 9: Release prep
- Decide how players get the model: **downloaded on first launch** (decided and built: players need only one of two models, depending on hardware; NobodyWho downloads it from Hugging Face, with a progress bar and a Try again button). Bundling is the fallback if Hugging Face becomes a worry
- Minimum specs (recommended: 6 GB of VRAM, 16 GB of RAM; minimum: 8 GB of RAM and no GPU with the small model, measured on one PC only), plus a "low-end" setting that uses a smaller model: the game picks the model that fits the machine (`ModelPicker`)
- Steam: lobbies and invites via the GodotSteam addon instead of typing IPs
- Final name, art and store page

---

## Risks

| Risk | Plan |
|---|---|
| **A small model isn't funny or loses character** | Test in Phases 1–2. Try a bigger model, then Plan B (Claude API) |
| **Too slow on players' PCs** | Measure on the Windows PC and the M4. Add a low-end setting with a smaller model |
| Plugins break on Godot 4.7 | Checked in Phase 1. If they break, run [Ollama](https://ollama.com) beside the game and call it over localhost |
| Game download gets big | Download the model on first launch (Phase 9) |

## Not in scope (yet)
Voice cloning, voice chat between players, procedurally generated personas (hand-written JSON first), a 3D office before Phase 7, mobile or console versions.
