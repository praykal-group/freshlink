import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { AppConfig } from '../../config/config.service';

type Check = { name: string; ok: boolean; latencyMs?: number; error?: string };

@Injectable()
export class HealthService {
  constructor(private readonly config: AppConfig) {}

  async readiness() {
    const checks: Check[] = [await this.checkMl()];
    const ok = checks.every((c) => c.ok);
    const body = { status: ok ? 'ok' : 'degraded', checks };
    if (!ok) throw new ServiceUnavailableException(body);
    return body;
  }

  private async checkMl(): Promise<Check> {
    const started = Date.now();
    try {
      const res = await fetch(`${this.config.get('ML_SERVICE_URL')}/health`, {
        headers: { 'X-Internal-Token': this.config.get('ML_INTERNAL_TOKEN') },
        signal: AbortSignal.timeout(2000),
      });
      return { name: 'ml', ok: res.ok, latencyMs: Date.now() - started };
    } catch (e) {
      return { name: 'ml', ok: false, error: (e as Error).message };
    }
  }
}
