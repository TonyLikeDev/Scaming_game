#!/usr/bin/env python3
"""Download the pinned Godot editor into .tools/godot/ and check its SHA-512 (standard library only).

Usage:  python scripts/setup_godot.py [--force]

Godot 4.7.1 (stable), the official build from godotengine/godot-builds, for this operating system. The Mac already has
Godot in /Applications; this is for a machine that does not, such as the Windows PC. The checksum comes from the release's own
SHA512-SUMS.txt. scripts/godot_run.py looks in .tools/godot/ for the binary.
"""
from __future__ import annotations

import argparse
import hashlib
import platform
import stat
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / ".tools" / "godot"
BASE = "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/"
ASSETS = {
    "windows": "Godot_v4.7.1-stable_win64.exe.zip",
    "macos": "Godot_v4.7.1-stable_macos.universal.zip",
    "linux": "Godot_v4.7.1-stable_linux.x86_64.zip",
}


def download(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url, timeout=60) as r, tmp.open("wb") as out:
        total = int(r.headers.get("Content-Length", 0))
        done = 0
        while True:
            block = r.read(1 << 20)
            if not block:
                break
            out.write(block)
            done += len(block)
            print(f"\r  {done / 1e6:6.1f} / {total / 1e6:.1f} MB", end="", flush=True)
    print()
    tmp.replace(dest)


def sha512_of(path: Path) -> str:
    h = hashlib.sha512()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 22), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="download again even if a verified zip is already here")
    args = ap.parse_args()
    system = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(platform.system())
    if system is None:
        sys.exit(f"Unsupported system: {platform.system()}")
    asset = ASSETS[system]
    DEST.mkdir(parents=True, exist_ok=True)
    sums = DEST / "SHA512-SUMS.txt"
    if args.force or not sums.exists():
        download(BASE + "SHA512-SUMS.txt", sums)
    expected = next((line.split()[0] for line in sums.read_text().splitlines() if line.strip().endswith(asset)), None)
    if expected is None:
        sys.exit(f"{asset} is not listed in {sums}")
    zip_path = DEST / asset
    if args.force or not zip_path.exists() or sha512_of(zip_path) != expected:
        print(f"Downloading {asset}")
        download(BASE + asset, zip_path)
    if sha512_of(zip_path) != expected:
        zip_path.unlink()
        sys.exit("SHA-512 mismatch: the download was deleted; run the script again")
    print("SHA-512 matches the official checksum")
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(DEST)
    if system != "windows":
        binary = DEST / ("Godot.app/Contents/MacOS/Godot" if system == "macos" else "Godot_v4.7.1-stable_linux.x86_64")
        if binary.exists():
            binary.chmod(binary.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"Godot 4.7.1 is in {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
