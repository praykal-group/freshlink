"""Request/response contracts (Section 8). camelCase on the wire to match the NestJS backend."""

from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

Category = Literal["FISH", "PRODUCE"]
GradeLetter = Literal["A", "B", "C"]


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid", protected_namespaces=())


class GradeRequest(_Model):
    batchId: str = Field(min_length=1, max_length=64)
    category: Category
    # Presigned GET URLs for TOP, SIDE, CLOSEUP (in that order).
    imageUrls: List[HttpUrl] = Field(min_length=3, max_length=3)


class DefectOut(_Model):
    cls: str = Field(alias="class")
    conf: float
    box: List[float]
    areaPct: float
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class PerImageOut(_Model):
    index: int
    grade: GradeLetter
    confidence: float
    itemDetected: bool
    defects: List[DefectOut]


class GradeResponse(_Model):
    batchId: str
    grade: GradeLetter
    confidence: float
    defects: List[DefectOut]
    perImage: List[PerImageOut]
    modelVersion: str
    latencyMs: int


class ShelfLifeItem(_Model):
    batchId: str = Field(min_length=1, max_length=64)
    productCode: str = Field(min_length=1, max_length=32)
    category: Category
    grade: Optional[GradeLetter] = None
    hoursSinceHarvest: float = Field(ge=0, le=24 * 365)
    meanTempC: float = Field(ge=-40, le=60)
    degreeMinutesAbove: float = Field(default=0, ge=0)
    humidityPct: Optional[float] = Field(default=None, ge=0, le=100)
    ethylenePpm: Optional[float] = Field(default=None, ge=0)
    shockEvents: int = Field(default=0, ge=0)
    # Product reference values sent by the backend (D-53): the ML service keeps no product table.
    baseShelfLifeH: float = Field(gt=0, le=24 * 365)
    q10: float = Field(ge=1, le=10)
    refTempC: float = Field(ge=-40, le=60)


class ShelfLifeRequest(_Model):
    items: List[ShelfLifeItem] = Field(min_length=1, max_length=200)


class CurvePoint(_Model):
    h: float
    p: float


class ShelfLifeResult(_Model):
    batchId: str
    remainingH: float
    survivalCurve: List[CurvePoint]
    method: Literal["COX", "Q10_FALLBACK"]
    modelVersion: str
    censored: bool = False


class ShelfLifeResponse(_Model):
    results: List[ShelfLifeResult]
    latencyMs: int
