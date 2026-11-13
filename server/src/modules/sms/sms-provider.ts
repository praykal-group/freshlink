export interface SmsResult {
  /** Provider message id, stored in notifications.provider_ref. */
  providerRef?: string;
}

export interface SmsProvider {
  readonly name: string;
  send(to: string, content: string): Promise<SmsResult>;
}

export class SmsSendError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
  ) {
    super(message);
  }
}

/** Dev only: prints the SMS to the log. The env schema refuses it in production. */
export class ConsoleSmsProvider implements SmsProvider {
  readonly name = 'console';

  constructor(private readonly log: (line: string) => void = console.log) {}

  async send(to: string, content: string): Promise<SmsResult> {
    this.log(`[sms:console] to=${to} text=${JSON.stringify(content)}`);
    return { providerRef: `console-${Date.now()}` };
  }
}

export interface HttpSmsOptions {
  apiUrl: string;
  apiKey: string;
  from: string;
  timeoutMs?: number;
  /** Extra attempts after a *network* failure. HTTP error responses are never retried. */
  networkRetries?: number;
  fetchImpl?: typeof fetch;
}

/**
 * httpSMS (self-hosted, D-11): POST {apiUrl}/v1/messages/send, header x-api-key.
 * Retries only when the request never got an HTTP response; a 5xx may already have queued
 * the message, and an OTP must not go out twice (Section 6.2).
 */
export class HttpSmsProvider implements SmsProvider {
  readonly name = 'httpsms';
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly opts: HttpSmsOptions) {
    this.fetchImpl = opts.fetchImpl ?? fetch;
  }

  async send(to: string, content: string): Promise<SmsResult> {
    const url = `${this.opts.apiUrl.replace(/\/+$/, '')}/v1/messages/send`;
    const body = JSON.stringify({ from: this.opts.from, to, content });
    const attempts = 1 + (this.opts.networkRetries ?? 2);

    let lastError: unknown;
    for (let attempt = 1; attempt <= attempts; attempt++) {
      let res: Response;
      try {
        res = await this.fetchImpl(url, {
          method: 'POST',
          headers: { 'x-api-key': this.opts.apiKey, 'content-type': 'application/json', accept: 'application/json' },
          body,
          signal: AbortSignal.timeout(this.opts.timeoutMs ?? 10_000),
        });
      } catch (e) {
        lastError = e; // no response at all: safe to retry
        continue;
      }
      if (res.status >= 200 && res.status < 300) {
        const json = (await res.json().catch(() => ({}))) as { data?: { id?: string } };
        return { providerRef: json.data?.id };
      }
      const text = await res.text().catch(() => '');
      throw new SmsSendError(`httpSMS responded ${res.status}: ${text.slice(0, 200)}`, res.status);
    }
    throw new SmsSendError(`httpSMS unreachable: ${(lastError as Error)?.message ?? 'unknown error'}`);
  }
}
