#!/usr/bin/env python3
"""Download the pinned addon releases, verify their SHA-256, and unpack them into addons/ (standard library only).

Usage:  python scripts/setup_addons.py [--platforms windows,macos,linux] [--force]

Why a script and not committed files: NobodyWho's Windows library is 141 MB and its macOS/Linux ones are 94-132 MB,
and GitHub rejects files over 100 MB. So the binaries are git-ignored and fetched here, pinned to exact versions.
Zips are cached in .tools/downloads/ (git-ignored). By default only the current OS's libraries are unpacked.
To upgrade an addon, change its URL and SHA-256 below and record the new version in docs/measurements.md.
"""
from __future__ import annotations

import argparse
import hashlib
import platform
import shutil
import sys
import threading
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".tools" / "downloads"

ADDONS = [
    {
        "name": "NobodyWho (Godot plugin) v11.0.0",
        "file": "nobodywho-v11.0.0.zip",
        "url": "https://github.com/nobodywho-ooo/nobodywho/releases/download/nobodywho-godot-v11.0.0/nobodywho-godot-nobodywho-godot-v11.0.0.zip",
        "sha256": "567e6da8fe7d64555733d4d83da828d75ada4438e241bbc9806d1fe48e3d7243",
        "strip": "bin/",
        # platform -> substrings that select this platform's library files (everything not a library is always kept)
        "libs": {"windows": ["x86_64-pc-windows-msvc-release.dll"],
                 "macos": ["apple-darwin-release.dylib"],
                 "linux": ["x86_64-unknown-linux-gnu-release.so"]},
        "lib_suffixes": (".dll", ".dylib", ".so", ".pdb"),
        "only_under": "addons/",
    },
    {
        "name": "godot-whisper v2.0.3",
        "file": "godot-whisper-v2.0.3.zip",
        "url": "https://github.com/appsinacup/godot-whisper/releases/download/v2.0.3/Godot_Whisper.zip",
        "sha256": "1f1d53dfc2ab486ecf1af5babfb989a59bf5fe70777a30fb8f073f53e5e3ee4a",
        "strip": "godot-whisper/",
        "libs": {"windows": ["libgodot_whisper.windows.template_release.x86_64.dll"],
                 "macos": ["libgodot_whisper.macos.template_release.universal.framework/"],
                 "linux": ["libgodot_whisper.linux.template_release.x86_64.so"]},
        "lib_dir": "addons/godot_whisper/bin/",
        "only_under": "addons/",
    },
]


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def download(url: str, dest: Path, workers: int = 6, chunk: int = 12_000_000) -> None:
    """Parallel ranged download (GitHub release downloads are often slow per connection)."""
    with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as r:
        size = int(r.headers["Content-Length"])
    tmp = dest.with_suffix(dest.suffix + ".part")
    with tmp.open("wb") as f:
        f.truncate(size)
    lock = threading.Lock()
    done = [0]

    def fetch(start: int) -> None:
        end = min(start + chunk, size) - 1
        for attempt in range(8):
            try:
                req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
                with urllib.request.urlopen(req, timeout=60) as r:
                    data = r.read()
                if len(data) != end - start + 1:
                    raise OSError("short read")
                with lock:
                    with tmp.open("r+b") as f:
                        f.seek(start)
                        f.write(data)
                    done[0] += len(data)
                    print(f"\r  {done[0] / 1e6:6.1f} / {size / 1e6:.1f} MB", end="", flush=True)
                return
            except OSError:
                continue
        raise SystemExit(f"download failed at byte {start}")

    with ThreadPoolExecutor(workers) as ex:
        list(ex.map(fetch, range(0, size, chunk)))
    print()
    tmp.replace(dest)


def wanted(addon: dict, rel: str, platforms: list[str]) -> bool:
    """Keep non-library files always; keep library files only for the selected platforms."""
    if not rel.startswith(addon["only_under"]) or rel.endswith("/"):
        return False
    if "lib_suffixes" in addon:
        if not rel.endswith(addon["lib_suffixes"]):
            return True
        return any(sub in rel for p in platforms for sub in addon["libs"][p] if not sub.endswith(".pdb"))
    if rel.startswith(addon["lib_dir"]):
        return any(sub in rel for p in platforms for sub in addon["libs"][p])
    return True


def install(addon: dict, platforms: list[str], force: bool) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    zip_path = CACHE / addon["file"]
    if force or not zip_path.exists() or sha256_of(zip_path) != addon["sha256"]:
        print(f"{addon['name']}: downloading")
        download(addon["url"], zip_path)
    if sha256_of(zip_path) != addon["sha256"]:
        zip_path.unlink(missing_ok=True)
        sys.exit(f"{addon['name']}: SHA-256 mismatch, deleted the download")
    count = 0
    with zipfile.ZipFile(zip_path) as z:
        for info in z.infolist():
            rel = info.filename[len(addon["strip"]):] if info.filename.startswith(addon["strip"]) else None
            if rel is None or not wanted(addon, rel, platforms):
                continue
            target = ROOT / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            count += 1
    print(f"{addon['name']}: unpacked {count} files for {', '.join(platforms)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(platform.system(), "windows")
    ap.add_argument("--platforms", default=default, help="comma list of windows,macos,linux (default: this OS)")
    ap.add_argument("--force", action="store_true", help="download again even if the cached zip is fine")
    args = ap.parse_args()
    platforms = [p.strip() for p in args.platforms.split(",")]
    for addon in ADDONS:
        install(addon, platforms, args.force)
    print("Done. Open the project once (or run scripts/godot_run.py --import) so Godot registers the addons.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
