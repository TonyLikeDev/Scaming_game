#!/usr/bin/env python3
"""Run Godot for a test or a scene, on Windows or macOS, and print its log.

Usage:  python scripts/godot_run.py [--timeout SECONDS] [--log NAME] [--import] [--] <godot arguments>
Example: python scripts/godot_run.py --import --timeout 120 -- --headless --script tests/test_persona.gd

Why this exists: on the Windows PC, Godot hangs at exit when its output is redirected to a file or pipe by the
shell. This wrapper starts the GUI binary with `--log-file` instead and prints that file afterwards.
`--import` first runs a headless import so new `class_name` scripts are known (needed after adding scripts).
Binary lookup: $GODOT_BIN, then .tools/godot/ (python scripts/setup_godot.py puts it there), then /Applications/Godot.app.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT / ".tools" / "logs"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
NOISE = re.compile(r"^(TextServer|Using \"default\" pen|CORE API HASH|EDITOR API HASH|Loading resource|Completed load|"
                   r"SceneTreeFTI|Loaded system CA|Godot Engine v|Vulkan|OpenGL)")


def find_godot() -> Path:
    env = os.environ.get("GODOT_BIN")
    if env and Path(env).exists():
        return Path(env)
    local = ROOT / ".tools" / "godot"  # put there by scripts/setup_godot.py
    for pattern in ("Godot_v4.7*_win64.exe", "Godot.app/Contents/MacOS/Godot", "Godot_v4.7*_linux.x86_64"):
        hits = sorted(local.glob(pattern))
        if hits:
            return hits[-1]
    mac = Path("/Applications/Godot.app/Contents/MacOS/Godot")
    if mac.exists():
        return mac
    sys.exit("Godot not found: set GODOT_BIN or put the editor in .tools/godot/")


def run(args: list[str], timeout: int, log_name: str) -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log = LOG_DIR / f"{log_name}.log"
    log.unlink(missing_ok=True)
    cmd = [str(find_godot()), "--log-file", str(log), "--path", str(ROOT), *args]
    proc = subprocess.Popen(cmd, cwd=ROOT)
    started = time.time()
    while True:
        try:
            code = proc.wait(timeout=2)
            break
        except subprocess.TimeoutExpired:
            pass
        if time.time() - started > timeout:
            print(f"[godot_run] timed out after {timeout}s", file=sys.stderr)
            proc.kill()
            code = 124
            break
        # Godot does not exit when a script fails to parse: it idles until the timeout. Stop at once instead.
        if log.exists() and "Failed to load script" in log.read_text(encoding="utf-8", errors="replace"):
            print("[godot_run] a script failed to load (parse error), stopping", file=sys.stderr)
            proc.kill()
            code = 3
            break
    proc.wait()
    if log.exists():
        text = ANSI.sub("", log.read_text(encoding="utf-8", errors="replace"))
        print("\n".join(line for line in text.splitlines() if not NOISE.match(line)))
    return code


def main() -> int:
    # Model replies contain curly quotes and the like; a cp1252 console would crash while printing the log.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--log", default="godot_run", help="log file name under .tools/logs/")
    ap.add_argument("--import", dest="do_import", action="store_true", help="run a headless import first")
    ap.add_argument("godot_args", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    godot_args = args.godot_args[1:] if args.godot_args[:1] == ["--"] else args.godot_args  # only the wrapper's own `--`
    if args.do_import:
        run(["--headless", "--import"], 180, args.log + "_import")
    return run(godot_args, args.timeout, args.log)


if __name__ == "__main__":
    raise SystemExit(main())
