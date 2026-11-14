import { Inject, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { type SmsProvider, SmsSendError } from './sms-provider';

export const SMS_PROVIDER = Symbol('SMS_PROVIDER');

export interface SendOptions {
  priority?: 'otp' | 'alert' | 'normal';
  /** When set, a notifications row is written with the provider message id. */
  userId?: string;
  alertId?: string;
}

@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);
  private consecutiveFailures = 0;
  private readonly downListeners: ((streak: number, lastError: string) => void)[] = [];

  /** Section 15: called once when 3 sends in a row have failed (again only after a success). */
  onGatewayDown(listener: (streak: number, lastError: string) => void) {
    this.downListeners.push(listener);
  }

  constructor(
    @Inject(SMS_PROVIDER) private readonly provider: SmsProvider,
    private readonly prisma: PrismaService,
  ) {}

  /** Sends one SMS. Never logs the message text, because it may hold an OTP. */
  async send(to: string, content: string, opts: SendOptions = {}): Promise<{ providerRef?: string }> {
    try {
      const result = await this.provider.send(to, content);
      this.consecutiveFailures = 0;
      await this.record(opts, 'SENT', result.providerRef);
      this.logger.log({ msg: 'sms sent', provider: this.provider.name, priority: opts.priority ?? 'normal', providerRef: result.providerRef });
      return result;
    } catch (e) {
      this.consecutiveFailures += 1;
      const message = e instanceof SmsSendError ? e.message : (e as Error).message;
      await this.record(opts, 'FAILED', undefined, message);
      this.logger.error({ msg: 'sms failed', provider: this.provider.name, priority: opts.priority, error: message });
      if (this.consecutiveFailures === 3) {
        this.logger.error({ msg: 'SMS gateway down', consecutiveFailures: this.consecutiveFailures });
        for (const l of this.downListeners) {
          try {
            l(this.consecutiveFailures, message);
          } catch (err) {
            this.logger.error(`gateway-down listener failed: ${(err as Error).message}`);
          }
        }
      }
      throw e;
    }
  }

  get failureStreak(): number {
    return this.consecutiveFailures;
  }

  private async record(opts: SendOptions, status: 'SENT' | 'FAILED', providerRef?: string, error?: string) {
    if (!opts.userId) return;
    await this.prisma.notification
      .create({ data: { userId: opts.userId, alertId: opts.alertId, channel: 'SMS', status, providerRef, error } })
      .catch((err: Error) => this.logger.warn(`notification row not written: ${err.message}`));
  }
}
