import numpy as np
import pytest
from PIL import Image

from app.core.vision import (
    PRODUCE_CLASSES,
    FISH_CLASSES,
    Detection,
    combine,
    decode,
    grade_image,
    letterbox,
)

from .helpers import yolo_output

SIZE = (1000, 1000)


def det(cls, conf, box):
    return Detection(cls, conf, box)


# ───────────── grade rule (Section 8) ─────────────

def test_no_defect_is_grade_a():
    g = grade_image([det("fresh", 0.9, (100, 100, 900, 900))], SIZE)
    assert (g.grade, g.confidence, g.defects, g.item_detected) == ("A", 0.9, [], True)


def test_small_defect_is_grade_b():
    item = det("fresh", 0.9, (0, 0, 1000, 1000))  # 1,000,000 px²
    bruise = det("bruise", 0.7, (0, 0, 200, 200))  # 4 % of the item
    g = grade_image([item, bruise], SIZE)
    assert g.grade == "B"
    assert g.defects[0]["areaPct"] == pytest.approx(4.0)
    assert g.confidence == 0.7


def test_defects_summing_to_10_percent_is_grade_c():
    item = det("fresh", 0.9, (0, 0, 1000, 1000))
    a = det("bruise", 0.6, (0, 0, 250, 200))  # 5 %
    b = det("cut_crack", 0.8, (500, 500, 750, 700))  # 5 %
    assert grade_image([item, a, b], SIZE).grade == "C"


def test_rot_or_mould_is_always_grade_c():
    item = det("fresh", 0.9, (0, 0, 1000, 1000))
    rot = det("rot_mould", 0.55, (10, 10, 30, 30))  # tiny
    g = grade_image([item, rot], SIZE)
    assert g.grade == "C"
    assert g.confidence == 0.55


def test_area_is_relative_to_the_item_not_the_image():
    item = det("fresh", 0.9, (0, 0, 300, 300))  # small item in a big photo
    spot = det("discoloured_skin", 0.7, (0, 0, 100, 100))  # 11 % of the item, 1 % of the image
    assert grade_image([item, spot], SIZE).grade == "C"


def test_without_a_fresh_box_the_whole_image_is_the_item():
    spot = det("bruise", 0.7, (0, 0, 100, 100))  # 1 % of the image
    g = grade_image([spot], SIZE)
    assert g.grade == "B"
    assert g.item_detected is True


def test_nothing_detected_is_a_with_zero_confidence():
    g = grade_image([], SIZE)
    assert (g.grade, g.confidence, g.item_detected) == ("A", 0.0, False)


def test_batch_grade_is_the_worst_image():
    a = grade_image([det("fresh", 0.9, (0, 0, 1000, 1000))], SIZE)
    b = grade_image([det("fresh", 0.9, (0, 0, 1000, 1000)), det("bruise", 0.6, (0, 0, 100, 100))], SIZE)
    assert combine([a, b, a]) == ("B", 0.6)


# ───────────── preprocessing / decoding ─────────────

def test_letterbox_keeps_aspect_and_pads():
    tensor, r, pad = letterbox(Image.new("RGB", (1280, 720), (255, 0, 0)))
    assert tensor.shape == (1, 3, 640, 640) and tensor.dtype == np.float32
    assert r == pytest.approx(0.5)
    assert pad == (0.0, 140.0)
    assert tensor[0, :, 0, 320] == pytest.approx([114 / 255] * 3)  # grey padding row
    assert tensor[0, 0, 320, 320] == pytest.approx(1.0)  # red image content


def test_decode_maps_boxes_back_to_the_original_image():
    out = yolo_output([((320, 320, 100, 50), 0, 0.9)], nc=len(PRODUCE_CLASSES))
    d = decode(out, PRODUCE_CLASSES, ratio=0.5, pad=(0.0, 140.0), orig_size=(1280, 720))
    assert len(d) == 1 and d[0].cls == "fresh"
    assert d[0].box == pytest.approx((540, 310, 740, 410))


def test_decode_drops_low_confidence():
    out = yolo_output([((320, 320, 100, 100), 1, 0.34), ((100, 100, 50, 50), 1, 0.35)], nc=5)
    assert [x.conf for x in decode(out, PRODUCE_CLASSES, 1.0, (0, 0), (640, 640))] == [pytest.approx(0.35)]


def test_nms_suppresses_overlaps_within_a_class_only():
    out = yolo_output(
        [
            ((320, 320, 100, 100), 1, 0.9),  # bruise
            ((325, 320, 100, 100), 1, 0.8),  # bruise, IoU ≈ 0.9 → suppressed
            ((320, 320, 100, 100), 2, 0.7),  # rot_mould on the same spot → kept (class-wise NMS)
            ((100, 100, 50, 50), 1, 0.6),  # separate bruise → kept
        ],
        nc=5,
    )
    got = sorted((x.cls, round(x.conf, 2)) for x in decode(out, PRODUCE_CLASSES, 1.0, (0, 0), (640, 640)))
    assert got == [("bruise", 0.6), ("bruise", 0.9), ("rot_mould", 0.7)]


def test_decode_rejects_a_class_count_mismatch():
    with pytest.raises(ValueError, match="classes"):
        decode(yolo_output([], nc=5), FISH_CLASSES, 1.0, (0, 0), (640, 640))
