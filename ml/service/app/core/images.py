"""Download the 3 grading photos from presigned S3 URLs (in parallel, size-capped)."""

import asyncio
import io
from typing import List, Sequence

import httpx
from PIL import Image, UnidentifiedImageError

from .errors import MlError

MAX_BYTES = 3 * 1024 * 1024  # uploads are capped at 2 MB by the backend; small margin
TIMEOUT_S = 5.0


async def _fetch(client: httpx.AsyncClient, url: str, index: int) -> Image.Image:
    try:
        async with client.stream("GET", url) as r:
            if r.status_code != 200:
                raise MlError("IMAGE_FETCH_FAILED", f"image {index}: HTTP {r.status_code}", 422)
            buf = bytearray()
            async for chunk in r.aiter_bytes():
                buf.extend(chunk)
                if len(buf) > MAX_BYTES:
                    raise MlError("IMAGE_TOO_LARGE", f"image {index} exceeds {MAX_BYTES} bytes", 422)
    except httpx.HTTPError as e:
        raise MlError("IMAGE_FETCH_FAILED", f"image {index}: {e.__class__.__name__}", 422) from e
    try:
        img = Image.open(io.BytesIO(bytes(buf)))
        img.load()
        return img
    except (UnidentifiedImageError, OSError) as e:
        raise MlError("IMAGE_INVALID", f"image {index} is not a readable image", 422) from e


async def fetch_images(urls: Sequence[str]) -> List[Image.Image]:
    async with httpx.AsyncClient(timeout=TIMEOUT_S, follow_redirects=False) as client:
        return list(await asyncio.gather(*(_fetch(client, u, i) for i, u in enumerate(urls))))
