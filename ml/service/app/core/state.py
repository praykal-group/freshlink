"""Models loaded once at startup and shared by the routers."""

import logging
import os
from pathlib import Path
from typing import Dict, Optional

from .registry import Registry
from .shelf_life import CoxModel
from .vision import VisionModel, default_classes

log = logging.getLogger("state")

DEFAULT_MODELS_DIR = Path(__file__).resolve().parents[2] / "models"


class State:
    def __init__(self) -> None:
        self.registry: Optional[Registry] = None
        self.vision: Dict[str, VisionModel] = {}
        self.cox: Optional[CoxModel] = None

    def load(self, models_dir: Optional[Path] = None) -> None:
        models_dir = models_dir or Path(os.environ.get("MODELS_DIR", DEFAULT_MODELS_DIR))
        self.registry = reg = Registry(models_dir)
        self.vision, self.cox = {}, None

        for name, category in (("vision_fish", "FISH"), ("vision_produce", "PRODUCE")):
            entry = reg.resolve(name)
            if not entry:
                continue
            try:
                classes = entry.meta.get("classes") or default_classes(category)
                self.vision[category] = VisionModel(str(entry.path), classes, f"{name}:{entry.version}", entry.meta.get("imgsz", 640))
            except Exception as e:  # noqa: BLE001 - a broken model must not crash the service
                log.exception("could not load %s", name)
                reg.mark_failed(name, f"load error: {e}")

        entry = reg.resolve("shelf_life_cox")
        if entry:
            try:
                self.cox = CoxModel.load(entry.path, f"shelf_life_cox:{entry.version}")
            except Exception as e:  # noqa: BLE001
                log.exception("could not load Cox model")
                reg.mark_failed("shelf_life_cox", f"load error: {e}")


state = State()
