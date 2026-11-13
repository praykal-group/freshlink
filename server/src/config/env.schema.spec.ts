import { loadEnv } from './env.schema';

const base = {
  DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
  ML_INTERNAL_TOKEN: 'dev-internal-token',
  SUPABASE_URL: 'https://abc.supabase.co',
  TRACE_SIGNING_KEY: 'x'.repeat(32),
};

describe('loadEnv', () => {
  it('treats empty KEY= lines as unset (copied .env.example boots)', () => {
    const env = loadEnv({ ...base, S3_ENDPOINT: '', S3_BUCKET: '', SUPABASE_JWKS_URL: '  ' });
    expect(env.S3_ENDPOINT).toBeUndefined();
    expect(env.S3_BUCKET).toBeUndefined();
    expect(env.SUPABASE_JWKS_URL).toBeUndefined();
  });

  it('fails fast on a short trace key', () => {
    const exit = jest.spyOn(process, 'exit').mockImplementation((() => {
      throw new Error('exit');
    }) as never);
    const err = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    expect(() => loadEnv({ ...base, TRACE_SIGNING_KEY: 'short' })).toThrow('exit');
    expect(err.mock.calls[0][0]).toContain('TRACE_SIGNING_KEY');
    exit.mockRestore();
    err.mockRestore();
  });
});
