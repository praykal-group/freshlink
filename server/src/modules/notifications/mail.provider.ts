import { Injectable } from '@nestjs/common';
import nodemailer, { type Transporter } from 'nodemailer';
import { AppConfig } from '../../config/config.service';
import type { SendResult } from './push.provider';

/** Alert email via custom SMTP (D-11; the same SMTP Supabase uses). */
@Injectable()
export class MailProvider {
  private transport?: Transporter | null;

  constructor(private readonly config: AppConfig) {}

  private get mailer(): Transporter | null {
    if (this.transport !== undefined) return this.transport;
    const host = this.config.get('SMTP_HOST');
    if (!host || !this.config.get('SMTP_FROM')) {
      this.transport = null;
      return null;
    }
    const port = this.config.get('SMTP_PORT') ?? 587;
    const user = this.config.get('SMTP_USER');
    this.transport = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: user ? { user, pass: this.config.get('SMTP_PASS') } : undefined,
    });
    return this.transport;
  }

  async send(to: string, subject: string, text: string): Promise<SendResult> {
    const m = this.mailer;
    if (!m) return { ok: false, error: 'EMAIL_NOT_CONFIGURED' };
    try {
      const info = await m.sendMail({ from: this.config.get('SMTP_FROM'), to, subject, text });
      return { ok: true, providerRef: info.messageId };
    } catch (e) {
      return { ok: false, error: (e as Error).message };
    }
  }
}
