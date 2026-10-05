#!/usr/bin/env python3
"""Download the language models into models/ and check their SHA-256 (standard library only; resumes if interrupted).

Usage:  python scripts/setup_models.py [e4b] [e2b] [qwen4b] [ministral8b] [whisper] [--all] [--list]
        With no names it downloads the recommended language model (e4b) and the speech-to-text model (whisper). Files that are already complete and correct are skipped.

Models (all Apache 2.0, from NobodyWho's tested GGUF repos on Hugging Face; see docs/measurements.md for the numbers):
  e4b          Gemma 4 E4B Q4_K_M, 4.98 GB. The model the game is built around.
  e2b          Gemma 4 E2B Q4_K_M, 3.11 GB. The low-end setting: little VRAM or no GPU.
  qwen4b       Qwen3.5-4B Q4_K_M, 2.74 GB. A fallback; its lines are weaker.
  ministral8b  Ministral-3 8B Instruct Q4_K_M, 5.20 GB. Too slow and too big for an 8 GB card; kept only for comparison.
  whisper      ggml-base.en.bin, 148 MB (MIT licence). The speech-to-text model for push-to-talk, goes to addons/godot_whisper/models/.
               (The Kokoro voices download themselves the first time they are chosen in the game.)
"""
from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "models"

WHISPER_DIR = ROOT / "addons" / "godot_whisper" / "models"
CATALOG = {
    "e4b": ("gemma-4-E4B-it-Q4_K_M.gguf", "NobodyWho/Google_Gemma4-E4B-GGUF", 4977169568,
            "519b9793ed6ce0ff530f1b7c96e848e08e49e7af4d57bb97f76215963a54146d"),
    "e2b": ("gemma-4-E2B-it-Q4_K_M.gguf", "NobodyWho/Google_Gemma4-E2B-GGUF", 3106736256,
            "9378bc471710229ef165709b62e34bfb62231420ddaf6d729e727305b5b8672d"),
    "qwen4b": ("Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf", "NobodyWho/Qwen_Qwen3.5-4B-GGUF", 2740938080,
               "86e5f89f925974c924dbb39d4aa013b505a4c6f2dc3ef8d529cc38910df3391f"),
    "ministral8b": ("Ministral-3-8B-Instruct-2512-Q4_K_M-vendor-sampling.gguf", "NobodyWho/Mistral_Ministral-3-8B-Instruct-GGUF", 5198386752,
                    "bf018c165e108bb7ce392d0b5e4f24276d5f76053c8ea49d56ba51b8a6ca40ef"),
    "whisper": ("ggml-base.en.bin", "ggerganov/whisper.cpp", 147964211,
                "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"),
}


def folder_for(name: str) -> Path:
    return WHISPER_DIR if name == "whisper" else MODELS


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 22), b""):
            h.update(block)
    return h.hexdigest()


def fetch(name: str) -> None:
    file, repo, size, sha = CATALOG[name]
    folder = folder_for(name)
    dest = folder / file
    if dest.exists() and dest.stat().st_size == size and sha256_of(dest) == sha:
        print(f"{name}: {file} is already complete and correct")
        return
    url = f"https://huggingface.co/{repo}/resolve/main/{file}"
    folder.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    have = part.stat().st_size if part.exists() else 0
    print(f"{name}: downloading {file} ({size / 1e9:.2f} GB), resuming from {have / 1e6:.0f} MB")
    while have < size:
        req = urllib.request.Request(url, headers={"Range": f"bytes={have}-"} if have else {})
        try:
            with urllib.request.urlopen(req, timeout=60) as r, part.open("ab" if have else "wb") as out:
                while True:
                    block = r.read(1 << 20)
                    if not block:
                        break
                    out.write(block)
                    have += len(block)
                    print(f"\r  {have / 1e6:8.0f} / {size / 1e6:.0f} MB", end="", flush=True)
        except OSError as exc:
            print(f"\n  connection problem ({exc}); retrying")
            have = part.stat().st_size if part.exists() else 0
    print()
    if sha256_of(part) != sha:
        part.unlink()
        sys.exit(f"{name}: SHA-256 mismatch, the download was deleted; run the script again")
    part.replace(dest)
    print(f"{name}: done, checksum matches")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", metavar="model", help="any of: " + ", ".join(CATALOG))
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    unknown = [n for n in args.names if n not in CATALOG]
    if unknown:
        ap.error("unknown model(s): %s (choose from %s)" % (", ".join(unknown), ", ".join(CATALOG)))
    if args.list:
        for key, (file, _repo, size, _sha) in CATALOG.items():
            state = "present" if (folder_for(key) / file).exists() else "missing"
            print(f"{key:12} {file}  {size / 1e9:.2f} GB  {state}")
        return 0
    wanted = list(CATALOG) if args.all else (args.names or ["e4b", "whisper"])
    for name in wanted:
        fetch(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
