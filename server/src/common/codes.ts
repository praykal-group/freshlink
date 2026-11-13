import type { Prisma } from '@prisma/client';

/**
 * Next human code `<prefix><0001>` inside the caller's transaction. A transaction-scoped advisory
 * lock on the prefix serialises concurrent allocations (same pattern as batch codes, D-49).
 * `last` returns the highest existing code with this prefix.
 */
export async function nextCode(
  tx: Prisma.TransactionClient,
  prefix: string,
  last: (prefix: string) => Promise<string | null>,
  width = 4,
): Promise<string> {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${prefix}))`;
  const prev = await last(prefix);
  const seq = prev ? Number(prev.slice(prefix.length)) + 1 : 1;
  if (!Number.isFinite(seq) || String(seq).length > width) throw new RangeError(`code sequence exhausted for ${prefix}`);
  return `${prefix}${String(seq).padStart(width, '0')}`;
}
