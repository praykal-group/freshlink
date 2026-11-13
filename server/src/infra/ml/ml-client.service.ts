import { Injectable, Logger } from '@nestjs/common';
import { AppConfig } from '../../config/config.service';

/** status 0 = no HTTP response (network error / timeout). */
export class MlCallError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

/** Internal HTTP client for the FastAPI ML service (D-02). Never exposed publicly. */
@Injectable()
export class MlClient {
  private readonly logger = new Logger(MlClient.name);

  constructor(private readonly config: AppConfig) {}

  async post<T>(path: string, body: unknown, timeoutMs: number): Promise<T> {
    const url = `${this.config.get('ML_SERVICE_URL').replace(/\/+$/, '')}${path}`;
    const started = Date.now();
    let res: Response;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-internal-token': this.config.get('ML_INTERNAL_TOKEN') },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (e) {
      const name = (e as Error).name;
      throw new MlCallError(0, name === 'TimeoutError' ? 'ML_TIMEOUT' : 'ML_UNREACHABLE', (e as Error).message);
    }
    const json = (await res.json().catch(() => ({}))) as { error?: { code?: string; message?: string; details?: Record<string, unknown> } };
    this.logger.debug({ msg: 'ml call', path, status: res.status, latencyMs: Date.now() - started });
    if (!res.ok) {
      throw new MlCallError(res.status, json.error?.code ?? `ML_HTTP_${res.status}`, json.error?.message ?? 'ML service error', json.error?.details ?? {});
    }
    return json as T;
  }
}
