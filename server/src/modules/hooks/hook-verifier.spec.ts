import { randomBytes } from 'node:crypto';
import { Webhook } from 'standardwebhooks';
import { HookSignatureError, otpMessage, SupabaseHookVerifier, toE164 } from './hook-verifier';

// M3 unit: Send SMS Hook signature — valid / bad / stale timestamp (AUTH-08).
const base64Secret = randomBytes(32).toString('base64');
const stored = `v1,whsec_${base64Secret}`; // format Supabase shows and SSM keeps
const signer = new Webhook(base64Secret);
const body = JSON.stringify({ user: { id: 'u1', phone: '919999900011' }, sms: { otp: '123456' } });

function headers(at: Date, payload = body, id = 'msg_1') {
  return {
    'webhook-id': id,
    'webhook-timestamp': String(Math.floor(at.getTime() / 1000)),
    'webhook-signature': signer.sign(id, at, payload),
  };
}

describe('SupabaseHookVerifier', () => {
  const verifier = new SupabaseHookVerifier(stored);

  it('accepts a correctly signed request and strips the v1,whsec_ prefix', () => {
    const payload = verifier.verify(Buffer.from(body), headers(new Date()));
    expect(payload.user.phone).toBe('919999900011');
    expect(payload.sms.otp).toBe('123456');
  });

  it('rejects a bad signature', () => {
    const h = headers(new Date());
    h['webhook-signature'] = `v1,${randomBytes(32).toString('base64')}`;
    expect(() => verifier.verify(body, h)).toThrow(HookSignatureError);
  });

  it('rejects a modified body', () => {
    const h = headers(new Date());
    expect(() => verifier.verify(body.replace('123456', '654321'), h)).toThrow(HookSignatureError);
  });

  it('rejects a stale timestamp (> 5 min)', () => {
    const old = new Date(Date.now() - 10 * 60 * 1000);
    expect(() => verifier.verify(body, headers(old))).toThrow(HookSignatureError);
  });

  it('rejects a request signed with another secret', () => {
    const other = new SupabaseHookVerifier(`v1,whsec_${randomBytes(32).toString('base64')}`);
    expect(() => other.verify(body, headers(new Date()))).toThrow(HookSignatureError);
  });

  it('rejects a signed payload without phone/otp', () => {
    const empty = JSON.stringify({ user: {}, sms: {} });
    expect(() => verifier.verify(empty, headers(new Date(), empty))).toThrow(/missing/);
  });

  it('rejects missing headers', () => {
    expect(() => verifier.verify(body, {})).toThrow(HookSignatureError);
  });
});

describe('hook helpers', () => {
  it('normalises Supabase phones to E.164', () => {
    expect(toE164('919999900011')).toBe('+919999900011');
    expect(toE164('+91 99999 00011')).toBe('+919999900011');
  });

  it('uses the spec OTP template', () => {
    expect(otpMessage('123456')).toBe('I-CCMS: your login code is 123456. Valid for 5 minutes. Do not share it.');
  });
});
