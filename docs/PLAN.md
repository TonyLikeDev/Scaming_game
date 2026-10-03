# Plan: *Scam Desk* (working title)

A co-op comedy sim inspired by *Scam With Your Friends* (see `../THEGAME.md`). You work a scam call center, talk to AI-voiced callers over your mic, dodge scambaiters and police raids, and survive your boss's review at the end of every shift.

Use our own name, art and characters. Copying mechanics is fine; copying their branding isn't.

**Tone rule:** the scams are absurd and fictional, like selling "premium air", an extended warranty for the Moon, or a timeshare on a cloud. That keeps it a comedy and not a how-to.

**Cost rule:** everything runs locally on the player's computer. That means no API keys, no server and no running costs.

---

## Tech decisions

| Area | Decision | Why |
|---|---|---|
| Engine | Godot 4.7, GDScript | Same engine as `parkourgame` |
| Look | Flat UI desk until Phase 7 | Prove the fun before building a 3D office |
| Caller AI | [NobodyWho](https://docs.nobodywho.ooo) plugin: runs a local AI model inside Godot | Free, offline, no keys. Uses the Mac's GPU (Metal) |
| Model | A 4B–8B instruct model in GGUF format (Qwen, Gemma or Llama family). Pick in Phase 1 | Small enough to be fast on an M4 with 16 GB |
| Caller reply | JSON shape enforced by the plugin's grammar feature | Small models get the format wrong unless it's enforced |
| Caller voice | `DisplayServer.tts_speak()`, built-in OS voices | Free and native. Robotic fits the comedy |
| Your voice | [godot-whisper](https://github.com/appsinacup/godot-whisper) addon (whisper.cpp, Metal) | Free, offline, real-time speech-to-text |
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
{ "say": "Kevin? Is that you? Mr. Biscuits says hello.", "suspicion": 35, "action": "talk", "amount": 0 }
```
- `suspicion` is the full 0–100 value each turn, not a change from last turn, so the game never has to add up numbers the AI got wrong.
- `action` is one of `talk`, `pay`, `hang_up` or `counter_attack` (scambaiters only).
- If the reply is broken or empty, the caller hangs up. A bad reply never crashes the call.

---

## Phases

Each phase ends with a **Done when** test. Don't start the next phase until it passes.

This is the plan: it holds the schedule and the decisions. Progress is recorded in `ROADMAP.md`, never here.

### Phase 1: Setup and model test (1 day)
- New Godot 4.7 project in this folder, plus `git init` and a `.gitignore` (ignore `*.gguf`, since model files are gigabytes)
- Install NobodyWho and godot-whisper from the Asset Library. **Check both load in 4.7**, since they list 4.3 as the minimum
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
- Shift timer (about 8 real minutes) and a daily cash quota that grows each day
- Call queue: random persona each call, with randomized savings
- Boss review: the AI writes a rant from the shift stats (cash, calls, hang-ups, your best and worst lines), spoken by TTS
- 3 failed reviews = fired (game over). Save the current day between sessions

**Done when:** a full day works: clock in → calls → review → next day.

### Phase 5: Threats
- **Scambaiters** (`is_scambaiter: true`): they waste your time, fake-pay (the money disappears later) or `counter_attack` with malware. Malware is a short popup-closing minigame, and failing it costs cash
- **Police raids:** a heat meter rises with cash earned. A raid warning gives you a few seconds to hide the evidence. Failing loses the day's cash
- **Mid-call surprises** ("your grandson just walked in"), added as an extra note into the caller's conversation

**Done when:** most shifts have at least one surprise.

### Phase 6: Modding
- Also load personas from `user://callers/*.json`. Skip bad files with a warning, never crash
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
- Decide how players get the model: bundled with the game (adds about 3–5 GB) or downloaded on first launch
- Minimum specs, plus a "low-end" setting that uses a smaller model
- Steam: lobbies and invites via the GodotSteam addon instead of typing IPs
- Final name, art and store page

---

## Risks

| Risk | Plan |
|---|---|
| **A small model isn't funny or loses character** | Test in Phases 1–2. Try a bigger model, then Plan B (Claude API) |
| **Too slow on players' PCs** | Measure on your M4 first. Add a low-end setting with a smaller model |
| Plugins break on Godot 4.7 | Checked in Phase 1. If they break, run [Ollama](https://ollama.com) beside the game and call it over localhost |
| Game download gets big | Download the model on first launch (Phase 9) |

## Not in scope (yet)
Voice cloning, voice chat between players, procedurally generated personas (hand-written JSON first), a 3D office before Phase 7, mobile or console versions.
