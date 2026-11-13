import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * ERP request signing (SYN-02, Section 6.4):
 *   X-Api-Key:   the raw key (server stores only sha256(key) in integration_clients.key_hash)
 *   X-Signature: hex HMAC-SHA256(raw request body, key), optionally prefixed "sha256="
 */
export const hashKey = (key: string) => createHash('sha256').update(key).digest('hex');

export const newApiKey = () => `iccms_${randomBytes(32).toString('base64url')}`;

export function sign(body: string | Buffer, key: string): string {
  return createHmac('sha256', key).update(body).digest('hex');
}

export function verifySignature(body: string | Buffer, key: string, header: unknown): boolean {
  if (typeof header !== 'string') return false;
  const given = header.replace(/^sha256=/i, '').trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(given)) return false;
  return timingSafeEqual(Buffer.from(given, 'hex'), Buffer.from(sign(body, key), 'hex'));
}
