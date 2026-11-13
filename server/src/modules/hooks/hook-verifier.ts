import { Webhook, WebhookVerificationError } from 'standardwebhooks';

export interface SendSmsHookPayload {
  user: { id?: string; phone: string };
  sms: { otp: string };
}

export class HookSignatureError extends Error {}

/**
 * Standard Webhooks check for the Supabase Send SMS Hook (AUTH-08):
 * HMAC-SHA256 over `${webhook-id}.${webhook-timestamp}.${body}`, 5-minute timestamp tolerance.
 * The secret is stored as `v1,whsec_<base64>`; both prefixes are stripped here.
 */
export class SupabaseHookVerifier {
  private readonly webhook: Webhook;

  constructor(secret: string) {
    this.webhook = new Webhook(secret.replace(/^v1,/, '').replace(/^whsec_/, ''));
  }

  verify(rawBody: string | Buffer, headers: Record<string, string | string[] | undefined>): SendSmsHookPayload {
    const pick = (k: string) => {
      const v = headers[k];
      return Array.isArray(v) ? v[0] : (v ?? '');
    };
    try {
      const payload = this.webhook.verify(rawBody, {
        'webhook-id': pick('webhook-id'),
        'webhook-timestamp': pick('webhook-timestamp'),
        'webhook-signature': pick('webhook-signature'),
      }) as SendSmsHookPayload;
      if (!payload?.user?.phone || !payload?.sms?.otp) throw new HookSignatureError('payload missing user.phone or sms.otp');
      return payload;
    } catch (e) {
      if (e instanceof HookSignatureError) throw e;
      throw new HookSignatureError(e instanceof WebhookVerificationError ? e.message : 'invalid webhook');
    }
  }
}

/** Supabase sends phones without '+'; httpSMS wants E.164. */
export function toE164(phone: string): string {
  const digits = phone.replace(/[^\d]/g, '');
  return `+${digits}`;
}

export const otpMessage = (code: string) =>
  `I-CCMS: your login code is ${code}. Valid for 5 minutes. Do not share it.`;
