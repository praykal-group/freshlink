"""Test helpers: YOLOv8-shaped tensors and a tiny constant-output ONNX model."""

import hashlib
import json
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np

Box = Tuple[float, float, float, float]  # cx, cy, w, h in 640x640 letterbox space


def yolo_output(dets: Sequence[Tuple[Box, int, float]], nc: int, n: int = 64) -> np.ndarray:
    """[1, 4+nc, n] with the given (box, class, score) rows; the rest score 0."""
    out = np.zeros((1, 4 + nc, n), dtype=np.float32)
    for i, (box, cls, score) in enumerate(dets):
        out[0, :4, i] = box
        out[0, 4 + cls, i] = score
    return out


def constant_onnx(path: Path, output: np.ndarray) -> None:
    import onnx
    from onnx import TensorProto, helper, numpy_helper

    inp = helper.make_tensor_value_info("images", TensorProto.FLOAT, [1, 3, 640, 640])
    out = helper.make_tensor_value_info("output0", TensorProto.FLOAT, list(output.shape))
    const = helper.make_node("Constant", [], ["output0"], value=numpy_helper.from_array(output, "c"))
    graph = helper.make_graph([const], "const_yolo", [inp], [out])
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    model.ir_version = 8
    onnx.save(model, str(path))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_registry(models_dir: Path, entries: Dict[str, Dict]) -> None:
    reg = {"models": {n: {"active": None, "versions": {}} for n in ("vision_fish", "vision_produce", "shelf_life_cox")}}
    for name, e in entries.items():
        reg["models"][name] = {"active": "v1", "versions": {"v1": e}}
    (models_dir / "registry.json").write_text(json.dumps(reg), encoding="utf-8")


# Seed product reference values (server/prisma/seed.ts): code -> (baseShelfLifeH, q10, safeMin, safeMax)
SEED_PRODUCTS: List[Tuple[str, float, float, float, float]] = [
    ("ROHU", 192, 2.5, 0, 4),
    ("POMFRET", 240, 2.5, 0, 4),
    ("PRAWNS", 96, 3, 0, 2),
    ("SURMAI", 240, 2.5, 0, 4),
    ("BANANA", 336, 2, 13, 15),
    ("TOMATO", 240, 2, 10, 13),
    ("MANGO", 336, 2.2, 12, 14),
    ("SPINACH", 168, 3, 0, 2),
    ("ONION", 2000, 1.8, 0, 4),
    ("GRAPES", 1000, 2.5, -1, 2),
]
