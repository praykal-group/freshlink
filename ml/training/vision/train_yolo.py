"""Train YOLOv8s for one category, export ONNX, measure mAP@0.5 and grade accuracy (ML-01).

    python ml/training/vision/train_yolo.py --category fish [--epochs 100] [--batch 16] [--device 0]

Writes runs/<category>/metrics.json with MEASURED values on the held-out test split.
Grade accuracy applies the exact service grade rule (ml/service/app/core/vision.py) to the
ONNX model's detections and compares with grades.csv (inspector labels).
"""

import argparse
import csv
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "ml" / "service"))

from app.core.vision import combine, grade_image, VisionModel  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--category", choices=["fish", "produce"], required=True)
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--device", default=None, help="'0' for the first GPU, 'cpu' to force CPU")
    args = ap.parse_args()

    from ultralytics import YOLO  # training-only dependency

    data_yaml = HERE / f"data_{args.category}.yaml"
    data_dir = (HERE / "../data/vision" / args.category).resolve()
    if not (data_dir / "images" / "train").is_dir():
        sys.exit(f"Dataset not found at {data_dir}. See ml/training/README.md for the layout.")

    project = HERE / "runs" / args.category
    model = YOLO("yolov8s.pt")
    model.train(
        data=str(data_yaml),
        epochs=args.epochs,
        batch=args.batch,
        imgsz=args.imgsz,
        optimizer="SGD",
        lr0=0.01,
        fliplr=0.5,
        hsv_h=0.015,
        hsv_s=0.7,
        hsv_v=0.4,
        project=str(project),
        name="train",
        exist_ok=True,
        device=args.device,
        seed=42,
    )

    best = project / "train" / "weights" / "best.pt"
    trained = YOLO(str(best))
    test_metrics = trained.val(data=str(data_yaml), split="test", imgsz=args.imgsz, conf=0.001, iou=0.6)
    map50 = float(test_metrics.box.map50)

    onnx_path = Path(trained.export(format="onnx", imgsz=args.imgsz, opset=12, simplify=True))
    names = [trained.names[i] for i in sorted(trained.names)]

    grade_acc, n_graded, latency_ms = grade_accuracy(onnx_path, names, data_dir, args.imgsz)

    metrics = {
        "category": args.category,
        "mAP50_test": round(map50, 4),
        "gradeAccuracy_test": None if grade_acc is None else round(grade_acc, 4),
        "gradedImages": n_graded,
        "meanInferenceMsPerImage_cpu": latency_ms,
        "epochs": args.epochs,
        "imgsz": args.imgsz,
        "classes": names,
        "onnx": onnx_path.name,
        "trainedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    (project / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, indent=2))


def grade_accuracy(onnx_path: Path, classes, data_dir: Path, imgsz: int):
    """Per-image grade accuracy against grades.csv using the service's ONNX path end to end."""
    from PIL import Image

    labels = data_dir / "grades.csv"
    if not labels.exists():
        print("grades.csv missing: grade accuracy not measured")
        return None, 0, None
    model = VisionModel(str(onnx_path), classes, "eval", imgsz)
    correct = total = 0
    elapsed = 0.0
    with labels.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            img_path = data_dir / "images" / "test" / row["image"]
            if not img_path.exists():
                continue
            img = Image.open(img_path)
            t0 = time.perf_counter()
            g = grade_image(model.detect(img), img.size)
            elapsed += time.perf_counter() - t0
            grade, _ = combine([g])
            correct += int(grade == row["grade"].strip().upper())
            total += 1
    if not total:
        return None, 0, None
    return correct / total, total, round(1000 * elapsed / total, 1)


if __name__ == "__main__":
    main()
