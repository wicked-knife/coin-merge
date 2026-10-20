"""Export a standalone Web build, precompress it, and check Pages asset limits."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "web"
LIMIT = 25 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4"))
    args = parser.parse_args()
    if not args.godot:
        parser.error("Pass --godot PATH or set GODOT_BIN to the Godot executable.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Remove only old generated assets, so renamed exports cannot linger online.
    for previous in OUTPUT.iterdir():
        if previous.is_file():
            previous.unlink()
        else:
            raise RuntimeError(f"Unexpected directory in build output: {previous}")
    result = subprocess.run(
        [args.godot, "--headless", "--path", str(ROOT), "--export-release", "Web", str(OUTPUT / "index.html")],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8", errors="replace",
    )
    (ROOT / "build" / "web-export.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode or "ERROR:" in result.stdout or "SCRIPT ERROR:" in result.stdout:
        print(result.stdout, file=sys.stderr)
        raise RuntimeError("Godot export failed. See build/web-export.log.")
    if "stripping autoload/_mcp_game_helper" not in result.stdout:
        raise RuntimeError("The editor helper was not stripped from the exported game.")
    for forbidden in ("res://addons/", "res://tests/", "res://docs/", "res://art-source/"):
        if f"{forbidden}" in "\n".join(line for line in result.stdout.splitlines() if "savepack |" in line):
            raise RuntimeError(f"Development resources leaked into the export: {forbidden}")

    headers = ["/*", "  X-Content-Type-Options: nosniff", "  Referrer-Policy: strict-origin-when-cross-origin", "  Cache-Control: public, max-age=0, must-revalidate", ""]
    manifest = {"files": [], "single_threaded": True, "gzip": ["index.wasm", "index.pck"]}
    for name in ("index.wasm", "index.pck"):
        path = OUTPUT / name
        raw = path.read_bytes()
        if name.endswith(".wasm") and not raw.startswith(b"\x00asm"):
            raise RuntimeError("Invalid WebAssembly output.")
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        if gzip.decompress(compressed) != raw:
            raise RuntimeError(f"Compression check failed: {name}")
        path.with_suffix(path.suffix + ".gz").write_bytes(compressed)
        path.unlink()
        manifest.setdefault("compression", {})[name] = {"decoded_bytes": len(raw), "transfer_bytes": len(compressed)}
    (OUTPUT / "_headers").write_text("\n".join(headers), encoding="utf-8")
    shutil.copyfile(ROOT / "web" / "worker.js", OUTPUT / "_worker.js")
    (OUTPUT / "_routes.json").write_text(json.dumps({"version": 1, "include": ["/index.wasm", "/index.pck"], "exclude": []}) + "\n", encoding="utf-8")
    # Disable the Pages SPA fallback for missing game files.
    (OUTPUT / "404.html").write_text('<!doctype html><meta charset="utf-8"><title>Not found</title><p>Page not found. <a href="/">Play Coin Merge</a></p>', encoding="utf-8")
    for path in sorted(OUTPUT.iterdir()):
        data = path.read_bytes()
        if len(data) > LIMIT:
            raise RuntimeError(f"Asset exceeds the 25 MiB limit: {path.name}")
        manifest["files"].append({"name": path.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    manifest["transfer_bytes"] = sum(item["bytes"] for item in manifest["files"])
    (ROOT / "build" / "web-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Web export ready: {OUTPUT}")
    print(f"Total assets: {manifest['transfer_bytes'] / 1024 / 1024:.2f} MiB")
    for name, sizes in manifest["compression"].items():
        print(f"{name}: {sizes['decoded_bytes']:,} -> {sizes['transfer_bytes']:,} bytes (gzip)")


if __name__ == "__main__":
    main()
