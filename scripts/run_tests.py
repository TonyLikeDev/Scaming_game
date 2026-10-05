#!/usr/bin/env python3
"""Run the project's tests and print one line per test (standard library only).

Usage:  python scripts/run_tests.py [--fast] [--full] [--only NAME ...] [--list]
        --fast  the tests that need no model (about a minute)            --full  also the ones that use the real model (about 15 minutes)
With neither flag it runs --fast. A test passes when it prints ALL PASSED and Godot exits with code 0.
The full group needs the model in models/ and downloads a 484 MB test model once (for the first-launch tests).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SMALL = "hf:NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf"

# name, godot arguments, timeout in seconds
FAST = [
    ("addons load", ["--headless", "--script", "tests/check_addons.gd"], 120),
    ("persona and mods", ["--headless", "--script", "tests/test_persona.gd"], 120),
    ("reply parser", ["--headless", "--script", "tests/test_reply_parser.gd"], 120),
    ("call director", ["--headless", "--script", "tests/test_call_director.gd"], 120),
    ("call session", ["--headless", "--script", "tests/test_call_session.gd"], 120),
    ("shift logic", ["--headless", "--script", "tests/test_shift_logic.gd"], 180),
    ("voice logic", ["--headless", "--script", "tests/test_voice_pure.gd"], 120),
    ("audio utilities", ["--headless", "--script", "tests/test_audio_util.gd"], 120),
    ("model picker", ["--headless", "--script", "tests/test_model_picker.gd"], 120),
]
FULL = [
    ("desk: every button", ["scenes/desk_flow_test.tscn", "--", "--mute", "--no_mic", "--save=user://desk_flow_save.json"], 600),
    ("compressed shifts", ["--headless", "scenes/shift_test.tscn", "--", "--shift_s=60", "--days=2"], 600),
    ("mod caller on the model", ["--headless", "scenes/mod_check.tscn"], 300),
    ("model download", ["--headless", "scenes/download_check.tscn"], 600),
    ("first launch in the desk", ["scenes/desk_first_launch_test.tscn", "--", "--mute", "--no_mic", "--no_models",
                                   "--settings=user://first_launch_test.cfg", "--save=user://first_launch_save.json", f"--download={SMALL}"], 600),
]


def run_one(name: str, godot_args: list[str], timeout: int) -> tuple[bool, float, str]:
    started = time.time()
    log = "test_" + "".join(c if c.isalnum() else "_" for c in name)
    cmd = [sys.executable, str(ROOT / "scripts" / "godot_run.py"), "--timeout", str(timeout), "--log", log, "--", *godot_args]
    # Godot's -- separator before game arguments is already in godot_args where needed
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout + 60)
    out = proc.stdout + proc.stderr
    # The summary is a line that is exactly "ALL PASSED", or "N FAILED". Check labels may contain any words, so look at whole lines.
    lines = [line.strip() for line in out.splitlines()]
    ok = "ALL PASSED" in lines and not any(re.fullmatch(r"\d+ FAILED", line) for line in lines)
    detail = ""
    if not ok:
        bad = [line for line in out.splitlines() if line.startswith("FAIL") or "SCRIPT ERROR" in line or "godot_run]" in line]
        detail = "; ".join(bad[:3]) or "no ALL PASSED line"
    return ok, time.time() - started, detail


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fast", action="store_true")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--only", nargs="+", metavar="NAME", help="run only tests whose name contains one of these words")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    tests = list(FAST)
    if args.full:
        tests += FULL
    if args.only:
        tests = [t for t in FAST + FULL if any(w.lower() in t[0].lower() for w in args.only)]
    if args.list:
        for name, _a, timeout in FAST + FULL:
            print(f"{name:28} {'fast' if (name, _a, timeout) in FAST else 'full'}")
        return 0
    # One import first, so a newly added class_name script is known to every test
    subprocess.run([sys.executable, str(ROOT / "scripts" / "godot_run.py"), "--timeout", "180", "--log", "test_import", "--", "--headless", "--import"],
                   cwd=ROOT, capture_output=True)
    failed = 0
    started = time.time()
    for name, godot_args, timeout in tests:
        ok, seconds, detail = run_one(name, godot_args, timeout)
        print(f"{'PASS' if ok else 'FAIL'}  {name:28} {seconds:6.1f} s  {detail}", flush=True)
        failed += 0 if ok else 1
    print(f"\n{len(tests) - failed} of {len(tests)} passed in {time.time() - started:.0f} s")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
