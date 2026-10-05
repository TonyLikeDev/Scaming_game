#!/usr/bin/env python3
"""Rebuild the run table in docs/measurements.md from the raw files in docs/runs/*.jsonl (standard library only).

Usage:  python scripts/bench_table.py [--check]

Each run file starts with a {"meta": ...} line and ends with a {"summary": ...} line (written by scenes/model_test.tscn).
The table sits between <!-- runs:start --> and <!-- runs:end --> in docs/measurements.md; nothing in it is typed by hand.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNS = ROOT / "docs" / "runs"
DOC = ROOT / "docs" / "measurements.md"
START, END = "<!-- runs:start -->", "<!-- runs:end -->"
MACHINE = {"13th Gen Intel(R) Core(TM) i5-13400F": "win-pc"}


def load_run(path: Path) -> dict | None:
    meta = summary = head = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue  # a run that is still being written ends in a half line; it has no summary yet and is skipped
        if "meta" in row:
            meta, head = row["meta"], row
        elif "summary" in row:
            summary = row["summary"]
    if not (meta and summary and head):
        return None
    return {"file": path.name, "meta": meta, "head": head, "s": summary}


def _obey(s: dict) -> str:
    """Share of the director's pay and stall orders the model followed, e.g. 11/12 pay, 20/22 stall."""
    o = s.get("director_orders")
    if not o or not (o["pay"] or o["stall"]):
        return "-"
    return f"pay {o['pay_obeyed']}/{o['pay']}, stall {o['stall_obeyed']}/{o['stall']}"


def fmt_row(r: dict) -> str:
    m, s = r["meta"], r["s"]
    machine = MACHINE.get(m.get("machine", ""), m.get("machine", "?"))
    # runs from before these options existed used the JSON schema, the default key order and the first rules file
    settings = (f"{'GPU' if m['gpu'] else 'CPU'}, ctx {m['ctx']}, think {'on' if m['thinking'] else 'off'}, {m.get('constraint', 'schema')}, "
                f"keys {m.get('order', 'default')}, {m.get('rules', 'caller_rules.txt').replace('caller_rules', 'rules').replace('.txt', '')}"
                f"{', director' if m.get('director') else ''}")
    vram = f"+{s['vram_delta_mb']:.0f}" if m["gpu"] and s["vram_mb_before"] >= 0 else "-"
    return "| {date} | `{commit}` | {machine} | {label} ({mb:.0f} MB) | {settings} | {turns} | {valid:.0f}% | {load:.1f} | {ram:.0f} | {vram} | {tot_med:.0f} | {tot_p95:.0f} | {say:.0f} | {tps:.0f} | {words:.0f} | {pay} | {mis} | {spread} | {obey} | [{f}](runs/{f}) |".format(
        date=m.get("date", "?")[:16].replace("T", " "), commit=m.get("commit", "?"), machine=machine, label=m["label"],
        mb=m.get("model_mb", 0), settings=settings, turns=s["turns"], valid=s["valid_pct"], load=s["load_ms"] / 1000,
        ram=s["ram_mb_after_run"], vram=vram, tot_med=s["total_ms_median"], tot_p95=s["total_ms_p95"],
        say=s["say_ms_median"], tps=s["tok_per_s_median"], words=s["words_median"], f=r["file"],
        pay=("%d/%d" % (s["calls_with_pay"], s["calls"])) if "calls" in s else "-",
        obey=_obey(s), mis=s.get("pay_mismatches", "-"), spread=("%.0f" % s["suspicion_spread_mean"]) if "suspicion_spread_mean" in s else "-")


def build() -> str:
    runs = [r for p in sorted(RUNS.glob("*.jsonl")) if (r := load_run(p))]
    runs.sort(key=lambda r: r["meta"].get("date", ""))
    head = ("| Date | Commit | Machine | Model | Settings | Turns | Valid JSON | Load s | RAM MB | VRAM MB | Total ms (median) | Total ms (p95) "
            "| Say ms (median) | Tok/s | Words | Calls paid | Pay mismatches | Suspicion spread | Director obeyed | Raw data |\n"
            "| :--- | :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |")
    rows = "\n".join(fmt_row(r) for r in runs) or "_No runs yet._"
    return f"{START}\n{head}\n{rows}\n{END}" if runs else f"{START}\n_No runs yet._\n{END}"


def main() -> int:
    text = DOC.read_text(encoding="utf-8")
    if START not in text or END not in text:
        sys.exit(f"{DOC}: markers {START} / {END} not found")
    a, b = text.index(START), text.index(END) + len(END)
    new = text[:a] + build() + text[b:]
    if "--check" in sys.argv:
        print("up to date" if new == text else "out of date; run scripts/bench_table.py")
        return int(new != text)
    if new != text:
        DOC.write_text(new, encoding="utf-8", newline="\n")
    print(f"{DOC.name}: {len(list(RUNS.glob('*.jsonl')))} run file(s) tabulated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
