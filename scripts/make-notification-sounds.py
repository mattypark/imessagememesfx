#!/usr/bin/env python3
"""Copies every board sound into App/NotificationSounds/ as .caf, the format iOS plays when a
push names it (aps.sound). These live in the MAIN app bundle — the app that receives the push —
not the extension. iOS caps a notification sound at 30s; our clips are all shorter.

    python3 scripts/make-notification-sounds.py
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "App" / "NotificationSounds"
SOURCES = [ROOT / "Shared" / "Sounds", ROOT / "Shared" / "Instants"]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    made = []
    for folder in SOURCES:
        for m4a in sorted(folder.glob("*.m4a")):
            caf = OUT / f"{m4a.stem}.caf"
            # IMA4 in a CAF: small, and on Apple's notification-sound list.
            subprocess.run(["afconvert", str(m4a), str(caf), "-d", "ima4", "-f", "caff"], check=True)
            made.append(caf.name)
    (OUT / "sounds.json").write_text(json.dumps(sorted(made), indent=2) + "\n")
    print(f"{len(made)} notification sounds -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
