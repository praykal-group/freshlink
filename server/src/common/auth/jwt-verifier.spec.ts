import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWK } from 'jose';
import { JwtVerifier, TokenVerificationError } from './jwt-verifier';

// M3 unit: JWKS verification — valid / expired / wrong issuer / wrong audience / tampered (AUTH-05).
const SUPABASE_URL = 'https://abc.supabase.co';
const ISS = `${SUPABASE_URL}/auth/v1`;

type Key = Awaited<ReturnType<typeof generateKeyPair>>['privateKey'];
let privateKey: Key;
let otherKey: Key;
let verifier: JwtVerifier;

beforeAll(async () => {
  const pair = await generateKeyPair('ES256');
  privateKey = pair.privateKey;
  otherKey = (await generateKeyPair('ES256')).privateKey;
  const jwk: JWK = { ...(await exportJWK(pair.publicKey)), kid: 'k1', alg: 'ES256', use: 'sig' };
  verifier = new JwtVerifier(createLocalJWKSet({ keys: [jwk] }), `${SUPABASE_URL}/`);
});

function token(opts: { iss?: string; aud?: string; exp?: number | string; key?: Key; sub?: string } = {}) {
  return new SignJWT({ role: 'authenticated', phone: '919999900011' })
    .setProtectedHeader({ alg: 'ES256', kid: 'k1' })
    .setSubject(opts.sub ?? '6f1c2b8e-1111-4a5b-9c0d-222233334444')
    .setIssuer(opts.iss ?? ISS)
    .setAudience(opts.aud ?? 'authenticated')
    .setIssuedAt()
    .setExpirationTime(opts.exp ?? '1h')
    .sign(opts.key ?? privateKey);
}

async function reason(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return 'OK';
  } catch (e) {
    return e instanceof TokenVerificationError ? e.reason : 'OTHER';
  }
}

describe('JwtVerifier', () => {
  it('accepts a valid token and returns its claims', async () => {
    const claims = await verifier.verify(await token());
    expect(claims.sub).toBe('6f1c2b8e-1111-4a5b-9c0d-222233334444');
    expect(claims.aud).toBe('authenticated');
  });

  it('normalises the issuer (trailing slash in SUPABASE_URL)', () => {
    expect(verifier.issuer).toBe(ISS);
  });

  it('rejects an expired token as EXPIRED', async () => {
    const exp = Math.floor(Date.now() / 1000) - 60;
    expect(await reason(verifier.verify(await token({ exp })))).toBe('EXPIRED');
  });

  it('rejects a wrong issuer', async () => {
    expect(await reason(verifier.verify(await token({ iss: 'https://evil.supabase.co/auth/v1' })))).toBe('INVALID');
  });

  it('rejects a wrong audience', async () => {
    expect(await reason(verifier.verify(await token({ aud: 'anon' })))).toBe('INVALID');
  });

  it('rejects a tampered payload', async () => {
    const [h, p, s] = (await token()).split('.');
    const claims = JSON.parse(Buffer.from(p, 'base64url').toString());
    claims.sub = '00000000-0000-4000-8000-000000000000';
    const forged = `${h}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.${s}`;
    expect(await reason(verifier.verify(forged))).toBe('INVALID');
  });

  it('rejects a token signed by a key that is not in the JWKS', async () => {
    expect(await reason(verifier.verify(await token({ key: otherKey })))).toBe('INVALID');
  });

  it('rejects garbage', async () => {
    expect(await reason(verifier.verify('not.a.jwt'))).toBe('INVALID');
  });
});
