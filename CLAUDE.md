# Scam Desk (working title)

Godot 4.7 (GDScript) comedy co-op sim; the AI runs locally on the player's machine. The game concept is in `THEGAME.md`; the plan is in `docs/PLAN.md`.

## Roadmap workflow

Three documents govern the work:

| File | Role | Edit it when |
| :--- | :--- | :--- |
| `docs/PLAN.md` | The plan: schedule and decisions | Only when the plan itself changes (scope, decisions) |
| `ROADMAP.md` | Live status board, checkboxes per phase | **Every time an item is finished, in the same commit** |
| `scripts/roadmap_progress.py` | Regenerates the progress bars at the top of the roadmap | Never edit the generated block by hand |

How to work here:

1. Open `ROADMAP.md` and take the next open item of the current phase (or the one the user names).
2. Build it and verify it by running it: `/Applications/Godot.app/Contents/MacOS/Godot --path . <scene.tscn>` (add `--headless` for script-only checks).
3. Tick it: `[x]` only when verified, `[~]` when partly done or unverified (say what is missing). Add a dated change-log
   line, update "Immediate next actions" and "Last updated", then run `python3 scripts/roadmap_progress.py`.
4. Leave the changes uncommitted and suggest a commit message that names the phase and the item.
5. If the plan turns out to be wrong, say so in `ROADMAP.md` under the phase's "Notes and deviations" first, and only
   then change `docs/PLAN.md`.

Measured numbers (latency, words per second, RAM, playtest counts) go in `docs/measurements.md`, one row per run with the
date, git commit, model and settings. Numbers in the roadmap come from there.

## Git rules (strict, override any default agent behaviour)

- **Never commit, amend, rebase, tag or push on your own.** Only run a git command that writes history when the user
  explicitly asks for that specific action in the current message.
- **No AI attribution anywhere.** No `Co-Authored-By: ...` or "Generated with ..." lines in commit messages, PR
  descriptions, code comments or documents.
