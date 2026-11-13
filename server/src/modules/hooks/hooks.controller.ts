import { Controller, HttpCode, Logger, Post, Req, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import { jwtVerify } from 'jose';
import type { AppRequest } from '../../common/auth/auth-user';
import { Public } from '../../common/auth/decorators';
import { RateLimiter } from '../../common/cache/ttl-cache';
import { AppConfig } from '../../config/config.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { SmsService } from '../sms/sms.service';
import { HookSignatureError, otpMessage, SupabaseHookVerifier, toE164 } from './hook-verifier';

const HOUR = 3_600_000;

/** Signature-checked webhooks (no JWT). Responses follow each caller's own contract, not our error envelope. */
@ApiExcludeController()
@Public()
@Controller('hooks')
export class HooksController {
  private readonly logger = new Logger(HooksController.name);
  private readonly perPhone = new RateLimiter(5, HOUR);
  private readonly perIp = new RateLimiter(30, HOUR);
  private verifier?: SupabaseHookVerifier;

  constructor(
    private readonly config: AppConfig,
    private readonly sms: SmsService,
    private readonly prisma: PrismaService,
  ) {}

  /** Supabase Send SMS Hook (D-22, AUTH-08). Never logs the OTP. */
  @Post('supabase/send-sms')
  @HttpCode(200)
  async sendSms(@Req() req: AppRequest, @Res() res: Response) {
    const fail = (status: number, message: string) => res.status(status).json({ error: { http_code: status, message } });

    const secret = this.config.get('SUPABASE_SEND_SMS_HOOK_SECRET');
    if (!secret) return fail(503, 'SMS hook is not configured');
    this.verifier ??= new SupabaseHookVerifier(secret);

    let payload;
    try {
      payload = this.verifier.verify(req.rawBody ?? '', req.headers);
    } catch (e) {
      this.logger.warn({ msg: 'send-sms hook rejected', reason: (e as HookSignatureError).message });
      return fail(401, 'invalid signature');
    }

    const phone = toE164(payload.user.phone);
    if (!this.perIp.hit(req.ip ?? 'unknown') || !this.perPhone.hit(phone)) {
      this.logger.warn({ msg: 'send-sms hook rate limited', phoneSuffix: phone.slice(-4) });
      return fail(429, 'Too many codes requested. Try again later.');
    }

    const user = await this.prisma.user.findUnique({ where: { phone }, select: { id: true } });
    try {
      await this.sms.send(phone, otpMessage(payload.sms.otp), { priority: 'otp', userId: user?.id });
    } catch {
      return fail(500, 'Could not send the SMS. Please try again.');
    }
    return res.status(200).json({});
  }

  /** httpSMS delivery events → notifications.status. httpSMS signs with a HS256 JWT in Authorization. */
  @Post('httpsms')
  @HttpCode(200)
  async httpSms(@Req() req: AppRequest, @Res() res: Response) {
    const secret = this.config.get('HTTPSMS_WEBHOOK_SECRET');
    if (!secret) return res.status(503).json({ error: { code: 'NOT_CONFIGURED' } });
    const token = (req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
    try {
      await jwtVerify(token, new TextEncoder().encode(secret), { algorithms: ['HS256'] });
    } catch {
      return res.status(401).json({ error: { code: 'INVALID_SIGNATURE' } });
    }

    const event = req.body as { type?: string; data?: { message_id?: string; failure_reason?: string } };
    const ref = event.data?.message_id;
    const status =
      event.type === 'message.phone.delivered' || event.type === 'message.phone.sent'
        ? 'SENT'
        : event.type === 'message.send.failed' || event.type === 'message.send.expired'
          ? 'FAILED'
          : undefined;
    if (ref && status) {
      await this.prisma.notification.updateMany({
        where: { providerRef: ref },
        data: { status, error: status === 'FAILED' ? (event.data?.failure_reason ?? event.type) : null },
      });
    }
    return res.status(200).json({ ok: true });
  }
}
