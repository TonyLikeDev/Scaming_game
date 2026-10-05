#!/usr/bin/env python3
"""Print the dialogue of a model-test run (docs/runs/*.jsonl) for reading.

Usage:  python scripts/show_run.py FILE [--persona gladys] [--call 1] [--player]
        python scripts/show_run.py docs/runs/*gemma*v2-actionfirst*.jsonl --persona barry --call 2
"""
from __future__ import annotations

import argparse
import json
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--persona")
    ap.add_argument("--call", type=int)
    ap.add_argument("--player", action="store_true", help="also print the scripted scammer line")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    for path in args.files:
        print(f"=== {path}")
        last = None
        for line in open(path, encoding="utf-8"):
            r = json.loads(line)
            if "persona" not in r:
                continue
            if args.persona and r["persona"] != args.persona:
                continue
            if args.call and r["call"] != args.call:
                continue
            key = (r["persona"], r["call"])
            if key != last:
                print(f"--- {r['persona']} call {r['call']}")
                last = key
            if args.player:
                print(f"  YOU : {r['player']}")
            if r["ok"]:
                pay = f" ${r['amount']}" if r["action"] == "pay" else ""
                flag = "  [MISMATCH]" if r.get("pay_mismatch") else ""
                print(f"  t{r['turn']} {r['action']}{pay} sus={r['suspicion']}: {r['say']}{flag}")
            else:
                print(f"  t{r['turn']} FAILED: {r['reason']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
