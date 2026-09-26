#!/usr/bin/env python3
"""Build a Chrome Load-unpacked ZIP with manifest.json at the archive root."""
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXTENSION = ROOT / "chrome_extension"
FILES = [
    Path("manifest.json"),
    Path("INSTALL.md"),
    Path("background.js"),
    Path("firebase-config.js"),
    Path("firebase-sync.js"),
    Path("keepit-schema.js"),
    Path("icons/icon16.png"),
    Path("icons/icon48.png"),
    Path("icons/icon128.png"),
    Path("popup/popup.html"),
    Path("popup/popup.js"),
]


def main() -> int:
    output_dir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "desktop" / "release"
    manifest_path = EXTENSION / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    version = manifest["version"]
    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / f"KeepIt-Chrome-Extension-{version}.zip"

    missing = [str(relative) for relative in FILES if not (EXTENSION / relative).is_file()]
    if missing:
        raise SystemExit(f"Chrome extension package is missing files: {', '.join(missing)}")

    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative in FILES:
            archive.write(EXTENSION / relative, arcname=relative.as_posix())

    with zipfile.ZipFile(archive_path) as archive:
        names = set(archive.namelist())
        if "manifest.json" not in names or "popup/popup.html" not in names:
            raise SystemExit("The Chrome extension ZIP does not have a loadable root manifest.")
    print(f"Packaged Chrome extension {version}: {archive_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
