#!/usr/bin/env python3
"""Register a trained model in ml/service/models/registry.json (D-20).

    python scripts/register_model.py <name> <version> <file> [--metrics metrics.json]
                                     [--classes c1 c2 ...] [--imgsz 640] [--activate]

Copies <file> to ml/service/models/<name>/<version>/, records sha256 + metrics, and optionally
makes it the active version. Weights stay gitignored; upload them with the same path to
s3://<bucket>/models/<name>/<version>/<file> (or a release asset) for scripts/fetch_models.sh.
"""

import argparse
import hashlib
import json
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "ml" / "service" / "models"
NAMES = ("vision_fish", "vision_produce", "shelf_life_cox", "forecast")
# `forecast` is a directory model: <file> is the training output folder.
FORECAST_FILES = ("lgbm.txt", "meta.json", "lstm.onnx")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("name", choices=NAMES)
    ap.add_argument("version", help="e.g. v1, v2 (immutable once registered)")
    ap.add_argument("file")
    ap.add_argument("--metrics")
    ap.add_argument("--classes", nargs="*")
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--activate", action="store_true")
    args = ap.parse_args()

    src = Path(args.file)
    if args.name == "forecast":
        register_forecast(args, src)
        return
    if not src.is_file():
        sys.exit(f"not a file: {src}")
    if args.name.startswith("vision_") and not args.classes:
        sys.exit("vision models need --classes in the model's class-id order")

    reg_path = MODELS / "registry.json"
    reg = json.loads(reg_path.read_text(encoding="utf-8"))
    spec = reg.setdefault("models", {}).setdefault(args.name, {"active": None, "versions": {}})
    if args.version in spec["versions"]:
        sys.exit(f"{args.name} {args.version} already registered; versions are immutable, use a new one")

    dest_dir = MODELS / args.name / args.version
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / ("model.onnx" if src.suffix == ".onnx" else "model.json")
    shutil.copy2(src, dest)

    entry = {
        "file": dest.name,
        "sha256": sha256(dest),
        "sizeBytes": dest.stat().st_size,
        "metrics": json.loads(Path(args.metrics).read_text(encoding="utf-8")) if args.metrics else {},
        "registeredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    if args.name.startswith("vision_"):
        entry["classes"] = args.classes
        entry["imgsz"] = args.imgsz
    spec["versions"][args.version] = entry
    if args.activate:
        spec["active"] = args.version

    reg_path.write_text(json.dumps(reg, indent=2) + "\n", encoding="utf-8")
    print(f"registered {args.name} {args.version} sha256={entry['sha256']}{' (active)' if args.activate else ''}")
    print(f"upload: {dest.relative_to(ROOT)} -> models/{args.name}/{args.version}/{dest.name}")


def register_forecast(args, src: Path) -> None:
    if not (src.is_dir() and (src / "lgbm.txt").is_file() and (src / "meta.json").is_file()):
        sys.exit("forecast needs the training output folder with lgbm.txt and meta.json (lstm.onnx optional)")
    reg_path = MODELS / "registry.json"
    reg = json.loads(reg_path.read_text(encoding="utf-8"))
    spec = reg.setdefault("models", {}).setdefault("forecast", {"active": None, "versions": {}})
    if args.version in spec["versions"]:
        sys.exit(f"forecast {args.version} already registered; versions are immutable, use a new one")
    dest_dir = MODELS / "forecast" / args.version
    dest_dir.mkdir(parents=True, exist_ok=True)
    files = {}
    for name in FORECAST_FILES:
        if (src / name).is_file():
            shutil.copy2(src / name, dest_dir / name)
            files[name] = sha256(dest_dir / name)
    metrics_path = Path(args.metrics) if args.metrics else src / "metrics.json"
    spec["versions"][args.version] = {
        "files": files,
        "metrics": json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.is_file() else {},
        "registeredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    if args.activate:
        spec["active"] = args.version
    reg_path.write_text(json.dumps(reg, indent=2) + "\n", encoding="utf-8")
    print(f"registered forecast {args.version} files={sorted(files)}{' (active)' if args.activate else ''}")


if __name__ == "__main__":
    main()
