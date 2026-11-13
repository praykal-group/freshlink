#!/usr/bin/env python3
"""Download the active model files listed in ml/service/models/registry.json and verify sha256.

Source, in this order:
  1. MODELS_BASE_URL  e.g. https://github.com/<owner>/<repo>/releases/download/models  (public)
                      -> <base>/<name>-<version>-<file>
  2. S3_BUCKET        uses `aws s3 cp s3://$S3_BUCKET/models/<name>/<version>/<file>` (instance role)
Files that already exist with the right hash are skipped. A hash mismatch deletes the file and fails.
"""

import hashlib
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "ml" / "service" / "models"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(name: str, version: str, file: str, dest: Path) -> None:
    base = os.environ.get("MODELS_BASE_URL")
    bucket = os.environ.get("S3_BUCKET")
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    if base:
        url = f"{base.rstrip('/')}/{name}-{version}-{file}"
        print(f"  GET {url}")
        urllib.request.urlretrieve(url, tmp)  # noqa: S310 - URL comes from operator config
    elif bucket:
        key = f"s3://{bucket}/models/{name}/{version}/{file}"
        print(f"  aws s3 cp {key}")
        subprocess.run(["aws", "s3", "cp", key, str(tmp), "--only-show-errors"], check=True)
    else:
        sys.exit("set MODELS_BASE_URL or S3_BUCKET")
    tmp.replace(dest)


def main() -> int:
    reg = json.loads((MODELS / "registry.json").read_text(encoding="utf-8"))
    failed = 0
    for name, spec in reg.get("models", {}).items():
        version = spec.get("active")
        if not version:
            print(f"{name}: no active version, skipped")
            continue
        meta = spec["versions"][version]
        # Single-file models have file/sha256; directory models (forecast) have files {name: sha256}.
        wanted = meta["files"].items() if isinstance(meta.get("files"), dict) else [(meta["file"], meta["sha256"])]
        for fname, expected in wanted:
            dest = MODELS / name / version / fname
            if dest.exists() and sha256(dest) == expected:
                print(f"{name} {version} {fname}: present, sha256 ok")
                continue
            print(f"{name} {version} {fname}: downloading")
            download(name, version, fname, dest)
            if sha256(dest) != expected:
                dest.unlink()
                print(f"{name} {version} {fname}: SHA256 MISMATCH, file removed")
                failed += 1
            else:
                print(f"{name} {version} {fname}: ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
