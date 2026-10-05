#!/usr/bin/env python3
"""Rebuild the voice table in docs/measurements.md from the raw files in docs/runs/voice/*.jsonl (standard library only).

Usage:  python scripts/voice_table.py [--check]

Each file is written by scenes/voice_test.tscn. The table sits between <!-- voice:start --> and <!-- voice:end -->.
Steady-state figures use the second pass over the clips (the first pass includes warm-up and is shown separately).
"""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNS = ROOT / "docs" / "runs" / "voice"
DOC = ROOT / "docs" / "measurements.md"
START, END = "<!-- voice:start -->", "<!-- voice:end -->"
P_START, P_END = "<!-- pipeline:start -->", "<!-- pipeline:end -->"


def rows_of(path: Path) -> list[dict]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out


def med(values: list[float]) -> float:
    return statistics.median(values) if values else float("nan")


def build() -> str:
    lines = [
        "| Date | Machine | Stage | Engine / model | Load s | First pass ms (median) | Steady ms (median) | Steady real-time factor | Accuracy (word error rate) | Raw data |",
        "| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- |",
    ]
    for path in sorted(RUNS.glob("*.jsonl")):
        rows = rows_of(path)
        env = next((r for r in rows if r.get("kind") == "env"), {})
        date = env.get("date", "?")[:16]
        machine = "win-pc" if "i5-13400F" in env.get("machine", "") else env.get("machine", "?")
        link = f"[{path.name}](runs/voice/{path.name})"
        for kind, label, ms_key in (("tts", "text-to-speech", "synth_ms"), ("stt_nw", "speech-to-text", "ms"), ("stt_gw", "speech-to-text", "ms")):
            data = [r for r in rows if r.get("kind") == kind]
            if not data:
                continue
            load = next((r for r in rows if r.get("kind") == f"{kind}_load"), {})
            first = [r[ms_key] for r in data if r["pass"] == 1]
            steady = [r for r in data if r["pass"] == 2]
            rtf = med([r["rtf"] for r in steady])
            if kind == "tts":
                engine = f"NobodyWho Kokoro-82M, voice {load.get('voice', '?')}"
                acc = f"audio {med([r['audio_s'] for r in steady]):.1f} s per line (median); returns the whole clip, no streaming"
            else:
                engine = ("NobodyWho Whisper base (ONNX q4)" if kind == "stt_nw" else "godot-whisper, ggml-base.en")
                wers = {r["clip"]: r["wer"] for r in steady}
                human = wers.get("jfk_human")
                tts_w = [v for k, v in wers.items() if k.startswith("tts_")]
                acc = (f"human recording {human:.2f}; text-to-speech clips median {med(tts_w):.2f} (digits written as numerals count as errors)"
                       if human is not None else f"clips median {med(list(wers.values())):.2f}")
            lines.append(f"| {date} | {machine} | {label} | {engine} | {load.get('load_ms', 0) / 1000:.1f} | {med(first):.0f} | {med([r[ms_key] for r in steady]):.0f} | {rtf:.3f} | {acc} | {link} |")
        os_rows = [r for r in rows if r.get("kind") == "os_tts"]
        if os_rows:
            voices = next((r for r in rows if r.get("kind") == "os_voices"), {})
            names = ", ".join(voices.get("voices", []))
            lines.append(f"| {date} | {machine} | text-to-speech | Godot OS voices ({voices.get('count', 0)}: {names}) | 0 | - | start {med([r['start_ms'] for r in os_rows]):.0f}, whole line {med([r['total_ms'] for r in os_rows]):.0f} | - | spoken at volume 0, so timing only | {link} |")
    return f"{START}\n" + "\n".join(lines) + f"\n{END}"


def build_pipeline() -> str:
    """End-to-end rows: from the key being released until the caller starts talking (needs the pipeline_summary lines)."""
    lines = [
        "| Date | Machine | Variant | Engine, mode | Turns | First turn ms | Later turns ms (median) | Later turns ms (worst) | Speech-to-text ms | AI reply ms | Voice start ms | Raw data |",
        "| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |",
    ]
    for path in sorted(RUNS.glob("*pipeline*.jsonl")):
        rows = rows_of(path)
        env = next((r for r in rows if r.get("kind") == "env"), {})
        machine = "win-pc" if "i5-13400F" in env.get("machine", "") else env.get("machine", "?")
        variant = path.stem.split("pipeline_")[-1]
        for s in (r for r in rows if r.get("kind") == "pipeline_summary"):
            lines.append(f"| {env.get('date', '?')[:16]} | {machine} | {variant} | {s['engine_mode']} | {s['turns']} | {s['first_turn_total_ms']} | {s['warm_total_ms_median']} | {s['warm_total_ms_max']} | {s['stt_ms_median']:.0f} | {s['reply_ms_median']:.0f} | {s['tts_ms_median']:.0f} | [{path.name}](runs/voice/{path.name}) |")
    return f"{P_START}\n" + "\n".join(lines) + f"\n{P_END}"


def main() -> int:
    text = DOC.read_text(encoding="utf-8")
    for marker in (START, END, P_START, P_END):
        if marker not in text:
            sys.exit(f"{DOC}: marker {marker} not found")
    a, b = text.index(START), text.index(END) + len(END)
    new = text[:a] + build() + text[b:]
    a, b = new.index(P_START), new.index(P_END) + len(P_END)
    new = new[:a] + build_pipeline() + new[b:]
    if "--check" in sys.argv:
        print("up to date" if new == text else "out of date; run scripts/voice_table.py")
        return int(new != text)
    if new != text:
        DOC.write_text(new, encoding="utf-8", newline="\n")
    print(f"{DOC.name}: voice table rebuilt from {len(list(RUNS.glob('*.jsonl')))} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
