import { ConsoleSmsProvider, HttpSmsProvider, SmsSendError } from './sms-provider';

// M3 unit: httpSMS request shape + no double send on 5xx (Section 6.2).
const opts = { apiUrl: 'http://httpsms-api:8000/', apiKey: 'test-key', from: '+919000000000' };

function response(status: number, body: unknown = {}) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

describe('HttpSmsProvider', () => {
  it('posts the documented request and returns the message id', async () => {
    const fetchImpl = jest.fn().mockResolvedValue(response(202, { data: { id: 'msg-42' } }));
    const result = await new HttpSmsProvider({ ...opts, fetchImpl }).send('+919999900011', 'hello');

    expect(result.providerRef).toBe('msg-42');
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe('http://httpsms-api:8000/v1/messages/send');
    expect(init.method).toBe('POST');
    expect(init.headers['x-api-key']).toBe('test-key');
    expect(init.headers['content-type']).toBe('application/json');
    expect(JSON.parse(init.body)).toEqual({ from: '+919000000000', to: '+919999900011', content: 'hello' });
  });

  it('does NOT retry on a 5xx (the message may already be queued)', async () => {
    const fetchImpl = jest.fn().mockResolvedValue(response(503, { message: 'down' }));
    await expect(new HttpSmsProvider({ ...opts, fetchImpl }).send('+91', 'x')).rejects.toMatchObject({ status: 503 });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('does NOT retry on a 4xx', async () => {
    const fetchImpl = jest.fn().mockResolvedValue(response(422));
    await expect(new HttpSmsProvider({ ...opts, fetchImpl }).send('+91', 'x')).rejects.toBeInstanceOf(SmsSendError);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('retries twice on network errors, then gives up', async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new TypeError('fetch failed'));
    await expect(new HttpSmsProvider({ ...opts, fetchImpl }).send('+91', 'x')).rejects.toThrow(/unreachable/);
    expect(fetchImpl).toHaveBeenCalledTimes(3);
  });

  it('succeeds when a retry after a network error gets through', async () => {
    const fetchImpl = jest
      .fn()
      .mockRejectedValueOnce(new TypeError('ECONNRESET'))
      .mockResolvedValueOnce(response(202, { data: { id: 'msg-7' } }));
    const result = await new HttpSmsProvider({ ...opts, fetchImpl }).send('+91', 'x');
    expect(result.providerRef).toBe('msg-7');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});

describe('ConsoleSmsProvider', () => {
  it('writes the SMS to the given log sink', async () => {
    const lines: string[] = [];
    await new ConsoleSmsProvider((l) => lines.push(l)).send('+91999', 'code 1');
    expect(lines[0]).toContain('to=+91999');
  });
});
