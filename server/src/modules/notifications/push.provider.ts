import { Injectable, Logger } from '@nestjs/common';
import type { App } from 'firebase-admin/app';
import { AppConfig } from '../../config/config.service';

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
  critical: boolean;
}

export interface SendResult {
  ok: boolean;
  providerRef?: string;
  error?: string;
  /** Tokens FCM reported as no longer valid (the caller clears them). */
  deadTokens?: string[];
}

const DEAD_TOKEN_CODES = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);

/**
 * FCM push (D-10). Data messages with high priority so the driver app can play the alarm even in
 * the background (Section 6.4). FIREBASE_CREDENTIALS_JSON = service-account JSON, raw or base64.
 */
@Injectable()
export class PushProvider {
  private readonly logger = new Logger(PushProvider.name);
  private app?: App | null;

  constructor(private readonly config: AppConfig) {}

  private async firebase(): Promise<App | null> {
    if (this.app !== undefined) return this.app;
    const raw = this.config.get('FIREBASE_CREDENTIALS_JSON');
    if (!raw) {
      this.app = null;
      return null;
    }
    const json = raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
    const { cert, initializeApp, getApps } = await import('firebase-admin/app');
    this.app = getApps().find((a) => a.name === 'iccms') ?? initializeApp({ credential: cert(JSON.parse(json)) }, 'iccms');
    return this.app;
  }

  async send(tokens: string[], msg: PushMessage): Promise<SendResult> {
    if (!tokens.length) return { ok: false, error: 'NO_DEVICE_TOKEN' };
    const app = await this.firebase();
    if (!app) return { ok: false, error: 'PUSH_NOT_CONFIGURED' };
    const { getMessaging } = await import('firebase-admin/messaging');
    try {
      const res = await getMessaging(app).sendEachForMulticast({
        tokens,
        data: { ...msg.data, title: msg.title, body: msg.body, critical: String(msg.critical) },
        android: { priority: 'high', ttl: 10 * 60_000 },
      });
      const deadTokens = res.responses.flatMap((r, i) => (!r.success && r.error && DEAD_TOKEN_CODES.has(r.error.code) ? [tokens[i]] : []));
      const firstOk = res.responses.find((r) => r.success);
      return res.successCount > 0
        ? { ok: true, providerRef: firstOk?.messageId, deadTokens }
        : { ok: false, error: res.responses[0]?.error?.code ?? 'PUSH_FAILED', deadTokens };
    } catch (e) {
      this.logger.error({ msg: 'fcm send failed', error: (e as Error).message });
      return { ok: false, error: (e as Error).message };
    }
  }
}
