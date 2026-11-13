"""Model registry (D-20): models/registry.json + versioned files in models/<name>/<version>/.

registry.json (committed) holds, per model name, the active version and per-version metadata:
{
  "models": {
    "vision_fish": {
      "active": "v1",
      "versions": {
        "v1": {"file": "model.onnx", "sha256": "...", "classes": [...], "imgsz": 640,
               "metrics": {...}, "registeredAt": "..."}
      }
    }
  }
}
Weights are gitignored and fetched with scripts/fetch_models.sh. A file whose sha256 does not
match the registry is never loaded.
"""

import hashlib
import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Optional

log = logging.getLogger("registry")

MODEL_NAMES = ("vision_fish", "vision_produce", "shelf_life_cox")


@dataclass
class ModelEntry:
    name: str
    version: str
    path: Path
    meta: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ModelStatus:
    name: str
    active: Optional[str]
    loaded: bool
    reason: Optional[str] = None
    metrics: Dict[str, Any] = field(default_factory=dict)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Registry:
    def __init__(self, models_dir: Path):
        self.models_dir = models_dir
        self.data: Dict[str, Any] = {"models": {}}
        reg = models_dir / "registry.json"
        if reg.exists():
            self.data = json.loads(reg.read_text(encoding="utf-8"))
        self.status: Dict[str, ModelStatus] = {}

    def resolve(self, name: str) -> Optional[ModelEntry]:
        """Active, present and hash-verified entry, or None (with the reason recorded in status)."""
        spec = self.data.get("models", {}).get(name) or {}
        active = spec.get("active")
        if not active:
            self.status[name] = ModelStatus(name, None, False, "no active version registered")
            return None
        meta = (spec.get("versions") or {}).get(active)
        if not meta:
            self.status[name] = ModelStatus(name, active, False, "active version missing from registry")
            return None
        path = self.models_dir / name / active / meta.get("file", "")
        if not path.is_file():
            self.status[name] = ModelStatus(name, active, False, f"file not found: {path.name} (run scripts/fetch_models.sh)")
            return None
        expected = meta.get("sha256")
        if not expected or sha256_file(path) != expected:
            self.status[name] = ModelStatus(name, active, False, "sha256 mismatch; refusing to load")
            log.error("model %s/%s failed sha256 check", name, active)
            return None
        self.status[name] = ModelStatus(name, active, True, None, meta.get("metrics") or {})
        return ModelEntry(name, active, path, meta)

    def mark_failed(self, name: str, reason: str) -> None:
        st = self.status.get(name)
        if st:
            st.loaded = False
            st.reason = reason

    def describe(self) -> Dict[str, Any]:
        return {
            name: {
                "active": st.active,
                "loaded": st.loaded,
                "reason": st.reason,
                "metrics": st.metrics,
            }
            for name, st in sorted(self.status.items())
        }
