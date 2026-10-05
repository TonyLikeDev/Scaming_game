# Scam Desk (working title)

A comedy co-op sim in Godot 4.7. You work a scam call center: you talk to AI-voiced callers over your microphone (or type), try
to talk them out of their savings with absurd, obviously fictional scams, and survive your boss's review at the end of every shift.
The AI runs **locally on your computer**: no server, no API key, no running costs. See `THEGAME.md` for the idea this is inspired
by and `docs/PLAN.md` for the plan.

**Where it stands:** a playable flat-UI desk. Clock in, take calls from a queue of callers, hit the day's quota, get roasted by the
boss, three missed quotas and you are fired. Phases 1 to 4 of 9 are built (see `ROADMAP.md`); threats, modding, co-op and the 3D
office are still to do.

## Set it up

You need Python 3.9 or newer, git, and a GPU with about 4 GB of free VRAM (the main model took 3.6 GB; it was tested on a Windows PC
with an NVIDIA RTX 3070). An Apple silicon Mac should work (NobodyWho uses Metal there) but **has not been tried yet**. Without a
usable GPU use the smaller model (see below). Everything downloads from its official source and is checked against a pinned checksum.

```bash
python scripts/setup_godot.py      # Godot 4.7.1 into .tools/godot/ (skip on the Mac if /Applications/Godot.app is 4.7)
python scripts/setup_addons.py     # NobodyWho (the language model engine) and godot-whisper (speech to text)
python scripts/setup_models.py     # the language model (Gemma 4 E4B, 5 GB) and the speech model (148 MB); optional, see below
```

You can skip the last step: if the game finds no model on its first launch it explains what it needs, suggests the model that
suits your computer (the main one for a graphics card with 6 GB or more, the small one otherwise), and downloads it for you with a
progress bar.

For a PC without a usable GPU: `python scripts/setup_models.py e2b` (3 GB), and run the desk with
`-- --model=models/gemma-4-E2B-it-Q4_K_M.gguf` (see "Play"). On a CPU alone it answers in about 2 s.
Voices: the Windows or macOS voices work with no download; **Kokoro** (nicer, many voices) downloads 326 MB the first time you pick
it in the game's drop-down.

## Play

```bash
python scripts/godot_run.py -- scenes/desk.tscn
```

`scripts/godot_run.py` finds Godot for you (it also works around a Windows quirk where Godot hangs at exit when its output is
redirected). Options for the game go after a second `--`:

```bash
python scripts/godot_run.py -- scenes/desk.tscn -- --model=models/gemma-4-E2B-it-Q4_K_M.gguf --voice=kokoro --mute
```

`--model` picks another model, `--voice=kokoro|os|off` the voices, `--mute` plays everything silently.

1. Press **Clock in**. The clock runs for 8 minutes; the bar shows how close you are to the day's quota.
2. Press **Answer the phone**. Type what you say and press Enter, or **hold V** (with the text box not selected) or the
   **Hold to talk** button, speak, and release.
3. Persuade the caller. They pay when the game decides they are convinced, so being specific, charming and patient helps, and
   pushing too hard makes them suspicious (the meter) and hang up. Name a price: they pay what you asked, up to their means.
4. When the clock runs out the boss reads your numbers. Miss the quota three times and you are fired.

Your day and strikes are saved after every review (`user://save.json`, which is `%APPDATA%/Godot/app_userdata/Scam Desk/` on
Windows).

## Check it works

One command runs the tests. Each prints a line with PASS or FAIL; a test passes when it ends with `ALL PASSED`.

```bash
python scripts/run_tests.py            # the 9 tests that need no model: under 10 seconds
python scripts/run_tests.py --full     # plus the 5 that use the real model (about 4 minutes): every button on the desk through
                                       # three days to a firing and a new game, compressed shifts with a bot scammer, a mod caller,
                                       # a model download, and the first launch
python scripts/run_tests.py --list     # what there is
```

The full group needs the model in `models/` and downloads a small 484 MB test model once. Run one test by hand with, for example,
`python scripts/godot_run.py --import -- --headless --script tests/test_persona.gd` (`--import` once after adding a script with a
`class_name`). Speed and quality of a model: `scripts/bench.sh gemma-4-E4B-it-Q4_K_M.gguf gemma4-e4b-q4km 1 myrun --director=1`.

## Where things are

| Path | What |
| :--- | :--- |
| `docs/PLAN.md`, `ROADMAP.md` | the plan and the live status board (read the roadmap first) |
| `docs/measurements.md`, `docs/runs/`, `docs/playtests/` | every measured number, its raw data, and the call transcripts |
| `src/` | the game: `call_session.gd` (rules of a call), `call_director.gd` (when callers pay), `caller_brain.gd`, `shift.gd`, `boss.gd`, `desk.gd` (the screen), voice and speech code |
| `callers/`, `data/` | the caller personas (JSON, one file each) and the prompt text |
| `scenes/`, `tests/`, `scripts/` | scenes (the desk and the test and demo scenes), tests, and setup and benchmark scripts |

To add a caller of your own, see `MODDING.md`: drop a JSON file into the game's `callers` folder, no code needed. The built-in
callers in `callers/` make good templates.
