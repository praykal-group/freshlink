import { randomUUID } from 'node:crypto';

export const FILE_PURPOSES = ['BATCH_IMAGE', 'POD_SIGNATURE', 'POD_PHOTO', 'INCIDENT_PHOTO', 'VOICE_NOTE'] as const;
export type FilePurpose = (typeof FILE_PURPOSES)[number];

const IMAGE_TYPES: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const AUDIO_TYPES: Record<string, string> = { 'audio/mp4': 'm4a', 'audio/x-m4a': 'm4a', 'audio/m4a': 'm4a', 'audio/aac': 'aac' };

const MB = 1024 * 1024;
export const MAX_IMAGE_BYTES = 2 * MB;
export const MAX_AUDIO_BYTES = 5 * MB;

export type UploadCheck =
  | { ok: true; ext: string; maxBytes: number }
  | { ok: false; code: 'UNSUPPORTED_TYPE' | 'FILE_TOO_LARGE' | 'EMPTY_FILE'; message: string };

/** Section 6.4 Files: jpeg/png/webp (≤ 2 MB) for images, m4a/aac (≤ 5 MB) for voice notes. */
export function checkUpload(purpose: FilePurpose, contentType: string, sizeBytes: number): UploadCheck {
  const audio = purpose === 'VOICE_NOTE';
  const table = audio ? AUDIO_TYPES : IMAGE_TYPES;
  const ext = table[contentType.toLowerCase()];
  if (!ext) {
    return { ok: false, code: 'UNSUPPORTED_TYPE', message: `${contentType} is not allowed for ${purpose}; use ${Object.keys(table).join(', ')}` };
  }
  if (sizeBytes <= 0) return { ok: false, code: 'EMPTY_FILE', message: 'sizeBytes must be > 0' };
  const maxBytes = audio ? MAX_AUDIO_BYTES : MAX_IMAGE_BYTES;
  if (sizeBytes > maxBytes) {
    return { ok: false, code: 'FILE_TOO_LARGE', message: `max ${maxBytes / MB} MB for ${purpose}` };
  }
  return { ok: true, ext, maxBytes };
}

/** Key pattern `<purpose>/<yyyy>/<mm>/<uuid>.<ext>`. */
export function buildKey(purpose: FilePurpose, ext: string, now = new Date(), id = randomUUID()): string {
  const yyyy = now.getUTCFullYear();
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  return `${purpose}/${yyyy}/${mm}/${id}.${ext}`;
}

const KEY_RE = /^(BATCH_IMAGE|POD_SIGNATURE|POD_PHOTO|INCIDENT_PHOTO|VOICE_NOTE)\/\d{4}\/\d{2}\/[0-9a-f-]{36}\.(jpg|png|webp|m4a|aac)$/;

export function parseKey(key: string): { purpose: FilePurpose } | null {
  const m = KEY_RE.exec(key);
  return m ? { purpose: m[1] as FilePurpose } : null;
}
