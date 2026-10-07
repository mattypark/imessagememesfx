#!/usr/bin/env python3
"""Downloads the trending myinstants.com sounds the board uses and writes their manifest.

These clips are other people's uploads (mostly copyrighted), so they live in
Shared/Instants/, which is gitignored: fine for a personal build, never pushed to the public
repo, and they need replacing with licensed sounds before an App Store release.

    python3 scripts/fetch-instants.py

Each entry: slash command, pad title, emoji, file path on myinstants.com.
"""

import json
import subprocess
import urllib.request
from pathlib import Path

BASE = "https://www.myinstants.com/media/sounds/"
ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Shared" / "Instants"
TMP_DIR = ROOT / "build" / "instants"

# From myinstants.com/en/index/us (trending in the US), 2026-10-07.
INSTANTS = [
    ("fah", "FAHHH", "😩", "fahhhhhhhhhhhhhh.mp3"),
    ("boom", "VINE BOOM", "💥", "vine-boom.mp3"),
    ("faaah", "FAAAH", "😫", "faaah.mp3"),
    ("gotthis", "I'VE GOT THIS", "🫡", "ive-got-this-faaaaaaaaahhhhh.mp3"),
    ("bruh", "BRUH", "😐", "movie_1.mp3"),
    ("rizz", "RIZZ", "🤨", "rizz-sound-effect.mp3"),
    ("wow", "ANIME WOW", "😮", "anime-wow-sound-effect.mp3"),
    ("ahh", "ANIME AHH", "😳", "anime-ahh.mp3"),
    ("amogus", "AMONG US", "🔪", "among-us-role-reveal-sound.mp3"),
    ("sus", "SUSSY", "🤭", "deg-deg-sussy.mp3"),
    ("pipe", "METAL PIPE", "🔩", "metal-pipe-clang.mp3"),
    ("crack", "BONE CRACK", "🦴", "bone-crack.mp3"),
    ("fart", "FART", "💨", "dry-fart.mp3"),
    ("chicken", "CHICKEN", "🐔", "chicken-on-tree-screaming.mp3"),
    ("fail", "SPONGEBOB FAIL", "🧽", "spongebob-fail.mp3"),
    ("applepay", "APPLE PAY", "💸", "applepay.mp3"),
    ("dexter", "DEXTER", "🩸", "dexter-meme.mp3"),
    ("spiderman", "SPIDERMAN", "🕷️", "spiderman-meme-song.mp3"),
    ("error", "ERROR", "⚠️", "error_CDOxCYm.mp3"),
    ("heehee", "HEE HEE", "🕺", "michael-jackson-hee-hee.mp3"),
    ("goodboy", "GOOD BOY", "🐶", "what-a-good-boy.mp3"),
    ("romance", "ROMANCE", "💘", "romanceeeeeeeeeeeeee.mp3"),
    ("violin", "SAD VIOLIN", "🎻", "tf_nemesis.mp3"),
    ("undertaker", "UNDERTAKER", "🔔", "undertakers-bell_2UwFCIe.mp3"),
    ("getout", "GET OUT", "🚪", "tuco-get-out.mp3"),
    ("meow", "MEOW", "🐱", "m-e-o-w.mp3"),
    ("discord", "DISCORD", "🎮", "discord-notification.mp3"),
]

MAX_BYTES = 3_000_000  # a meme clip; anything bigger is not what we asked for


def download(name, dest):
    request = urllib.request.Request(BASE + name, headers={"User-Agent": "Mozilla/5.0 MemeFX fetch-instants"})
    with urllib.request.urlopen(request, timeout=20) as response:
        if not response.headers.get("Content-Type", "").startswith("audio/"):
            raise ValueError(f"{name}: not audio ({response.headers.get('Content-Type')})")
        data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError(f"{name}: larger than {MAX_BYTES} bytes")
    dest.write_bytes(data)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    manifest = []
    for command, title, emoji, remote in INSTANTS:
        mp3 = TMP_DIR / remote
        m4a = OUT_DIR / f"instant-{command}.m4a"
        try:
            if not mp3.exists():
                download(remote, mp3)
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", str(mp3), str(m4a)], check=True)
        except Exception as error:  # one bad clip shouldn't sink the board
            print(f"skip /{command}: {error}")
            continue
        manifest.append({"command": command, "title": title, "emoji": emoji, "file": m4a.name})
        print(f"/{command:12} {title}")
    (OUT_DIR / "instants.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(manifest)} sounds -> {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
