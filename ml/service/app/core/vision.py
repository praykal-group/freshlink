"""YOLOv8 ONNX grading (Section 8): 640x640 letterbox, conf 0.35, NMS 0.5, then the grade rule.

Grade rule (per image, batch = worst image):
  - rot_mould detected, or total defect area >= 10 % of the item  -> C
  - any other defect (smaller)                                     -> B
  - no defect                                                      -> A
Item area = largest `fresh` box in the image; if none was detected, the whole image (D-55).
"""

from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
from PIL import Image

CONF_THRESHOLD = 0.35
IOU_THRESHOLD = 0.5
IMG_SIZE = 640
SEVERE_DEFECTS = {"rot_mould"}
MAJOR_AREA_PCT = 10.0

FISH_CLASSES = ["fresh", "discoloured_skin", "damaged_torn", "sunken_eye"]
PRODUCE_CLASSES = ["fresh", "bruise", "rot_mould", "cut_crack", "overripe"]

GRADE_ORDER = {"A": 0, "B": 1, "C": 2}


@dataclass
class Detection:
    cls: str
    conf: float
    box: Tuple[float, float, float, float]  # x1, y1, x2, y2 in original image pixels

    @property
    def area(self) -> float:
        x1, y1, x2, y2 = self.box
        return max(0.0, x2 - x1) * max(0.0, y2 - y1)


@dataclass
class ImageGrade:
    grade: str
    confidence: float
    defects: List[Dict]
    item_detected: bool


# ───────────────────────────── preprocessing ─────────────────────────────

def letterbox(img: Image.Image, size: int = IMG_SIZE) -> Tuple[np.ndarray, float, Tuple[float, float]]:
    """Resize keeping aspect ratio and pad to size x size with grey (114). Returns NCHW float32 in [0,1]."""
    img = img.convert("RGB")
    w, h = img.size
    r = min(size / w, size / h)
    nw, nh = int(round(w * r)), int(round(h * r))
    resized = img.resize((nw, nh), Image.BILINEAR)
    canvas = Image.new("RGB", (size, size), (114, 114, 114))
    pad_x, pad_y = (size - nw) / 2, (size - nh) / 2
    canvas.paste(resized, (int(round(pad_x - 0.1)), int(round(pad_y - 0.1))))
    arr = np.asarray(canvas, dtype=np.float32) / 255.0
    return arr.transpose(2, 0, 1)[None, ...], r, (pad_x, pad_y)


# ───────────────────────────── postprocessing ─────────────────────────────

def iou(box: np.ndarray, boxes: np.ndarray) -> np.ndarray:
    x1 = np.maximum(box[0], boxes[:, 0])
    y1 = np.maximum(box[1], boxes[:, 1])
    x2 = np.minimum(box[2], boxes[:, 2])
    y2 = np.minimum(box[3], boxes[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    a = (box[2] - box[0]) * (box[3] - box[1])
    b = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    return inter / np.maximum(a + b - inter, 1e-9)


def nms(boxes: np.ndarray, scores: np.ndarray, iou_thr: float = IOU_THRESHOLD) -> List[int]:
    order = scores.argsort()[::-1]
    keep: List[int] = []
    while order.size:
        i = int(order[0])
        keep.append(i)
        if order.size == 1:
            break
        rest = order[1:]
        order = rest[iou(boxes[i], boxes[rest]) <= iou_thr]
    return keep


def decode(
    output: np.ndarray,
    classes: Sequence[str],
    ratio: float,
    pad: Tuple[float, float],
    orig_size: Tuple[int, int],
    conf_thr: float = CONF_THRESHOLD,
    iou_thr: float = IOU_THRESHOLD,
) -> List[Detection]:
    """YOLOv8 head output [1, 4+nc, N] (cx, cy, w, h, class scores; no objectness) → detections."""
    pred = np.asarray(output)[0].T  # (N, 4+nc)
    if pred.shape[1] != 4 + len(classes):
        raise ValueError(f"model output has {pred.shape[1] - 4} classes, registry lists {len(classes)}")
    scores_all = pred[:, 4:]
    cls_ids = scores_all.argmax(axis=1)
    conf = scores_all[np.arange(len(pred)), cls_ids]
    mask = conf >= conf_thr
    if not mask.any():
        return []
    pred, cls_ids, conf = pred[mask], cls_ids[mask], conf[mask]

    cx, cy, w, h = pred[:, 0], pred[:, 1], pred[:, 2], pred[:, 3]
    boxes = np.stack([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], axis=1)
    # Undo letterbox, clip to the original image.
    boxes[:, [0, 2]] = (boxes[:, [0, 2]] - pad[0]) / ratio
    boxes[:, [1, 3]] = (boxes[:, [1, 3]] - pad[1]) / ratio
    ow, oh = orig_size
    boxes[:, [0, 2]] = boxes[:, [0, 2]].clip(0, ow)
    boxes[:, [1, 3]] = boxes[:, [1, 3]].clip(0, oh)

    out: List[Detection] = []
    for c in np.unique(cls_ids):  # class-wise NMS (Ultralytics default, agnostic=False)
        idx = np.where(cls_ids == c)[0]
        for k in nms(boxes[idx], conf[idx], iou_thr):
            j = idx[k]
            out.append(Detection(classes[int(c)], float(conf[j]), tuple(float(v) for v in boxes[j])))
    return sorted(out, key=lambda d: -d.conf)


# ───────────────────────────── grade rule ─────────────────────────────

def grade_image(dets: List[Detection], image_size: Tuple[int, int]) -> ImageGrade:
    fresh = [d for d in dets if d.cls == "fresh"]
    defects = [d for d in dets if d.cls != "fresh"]
    item_area = max((d.area for d in fresh), default=0.0) or float(image_size[0] * image_size[1])

    defect_rows = [
        {
            "class": d.cls,
            "conf": round(d.conf, 4),
            "box": [round(v, 1) for v in d.box],
            "areaPct": round(min(100.0, 100.0 * d.area / item_area), 2),
        }
        for d in defects
    ]
    total_pct = min(100.0, sum(r["areaPct"] for r in defect_rows))

    if any(d.cls in SEVERE_DEFECTS for d in defects) or total_pct >= MAJOR_AREA_PCT:
        decisive = [d for d in defects if d.cls in SEVERE_DEFECTS] or defects
        grade = "C"
    elif defects:
        decisive, grade = defects, "B"
    else:
        decisive, grade = fresh, "A"
    confidence = max((d.conf for d in decisive), default=0.0)
    return ImageGrade(grade, round(confidence, 4), defect_rows, bool(fresh or defects))


def combine(images: List[ImageGrade]) -> Tuple[str, float]:
    """Batch grade = worst image; confidence = mean confidence of the images with that grade."""
    worst = max(images, key=lambda g: GRADE_ORDER[g.grade]).grade
    confs = [g.confidence for g in images if g.grade == worst]
    return worst, round(float(np.mean(confs)) if confs else 0.0, 4)


# ───────────────────────────── model wrapper ─────────────────────────────

class VisionModel:
    def __init__(self, path: str, classes: Sequence[str], version: str, imgsz: int = IMG_SIZE):
        import onnxruntime as ort  # imported lazily so pure-logic tests do not need it

        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 2
        self.session = ort.InferenceSession(path, sess_options=opts, providers=["CPUExecutionProvider"])
        self.input_name = self.session.get_inputs()[0].name
        self.classes = list(classes)
        self.version = version
        self.imgsz = imgsz

    def detect(self, img: Image.Image) -> List[Detection]:
        tensor, ratio, pad = letterbox(img, self.imgsz)
        out = self.session.run(None, {self.input_name: tensor})[0]
        return decode(out, self.classes, ratio, pad, img.size)


def default_classes(category: str) -> List[str]:
    return FISH_CLASSES if category == "FISH" else PRODUCE_CLASSES


def model_name_for(category: str) -> str:
    return "vision_fish" if category == "FISH" else "vision_produce"


def optional_float(v: Optional[float]) -> Optional[float]:
    return None if v is None else float(v)
