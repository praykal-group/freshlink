import type { ImageView } from '@prisma/client';

export const GRADING_VIEWS: ImageView[] = ['TOP', 'SIDE', 'CLOSEUP'];

/**
 * FO-FR-06: grading uses the latest TOP, SIDE and CLOSEUP photo (a retake replaces the earlier one).
 * Returns the keys in that order, or the views that are still missing.
 */
export function pickGradingImages(images: { view: ImageView; s3Key: string; capturedAt: Date }[]):
  | { ok: true; keys: string[] }
  | { ok: false; missing: ImageView[] } {
  const latest = new Map<ImageView, { key: string; at: number }>();
  for (const img of images) {
    const prev = latest.get(img.view);
    if (!prev || img.capturedAt.getTime() > prev.at) latest.set(img.view, { key: img.s3Key, at: img.capturedAt.getTime() });
  }
  const missing = GRADING_VIEWS.filter((v) => !latest.has(v));
  if (missing.length) return { ok: false, missing };
  return { ok: true, keys: GRADING_VIEWS.map((v) => (latest.get(v) as { key: string }).key) };
}
