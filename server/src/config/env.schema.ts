import { z } from 'zod';

/**
 * Environment schema (Section 17). Variables needed from M1 are required;
 * the rest stay optional until the milestone that uses them makes them required.
 */
export const envSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(3000),
    APP_BASE_URL: z.string().url().default('http://localhost:3000'),
    CORS_ORIGINS: z.string().default(''),
    LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
    DATABASE_URL: z.string().startsWith('postgresql://'),
    MIGRATION_DATABASE_URL: z.string().optional(),
    ML_SERVICE_URL: z.string().url().default('http://localhost:8000'),
    ML_INTERNAL_TOKEN: z.string().min(8),
    SUPABASE_URL: z.string().url().optional(),
    SUPABASE_JWKS_URL: z.string().url().optional(),
    SUPABASE_SERVICE_ROLE_KEY: z.string().optional(),
    SUPABASE_SEND_SMS_HOOK_SECRET: z.string().optional(),
    TRACE_SIGNING_KEY: z.string().optional(),
    OFFER_TOKEN_SECRET: z.string().optional(),
    AWS_REGION: z.string().default('ap-south-1'),
    S3_BUCKET: z.string().optional(),
    SMS_PROVIDER: z.enum(['console', 'httpsms']).default('console'),
    HTTPSMS_API_URL: z.string().url().optional(),
    HTTPSMS_API_KEY: z.string().optional(),
    HTTPSMS_FROM_NUMBER: z.string().optional(),
    SMTP_HOST: z.string().optional(),
    SMTP_PORT: z.coerce.number().int().optional(),
    SMTP_FROM: z.string().optional(),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV === 'production' && env.SMS_PROVIDER === 'console') {
      ctx.addIssue({
        code: 'custom',
        path: ['SMS_PROVIDER'],
        message: 'console SMS provider is not allowed in production',
      });
    }
  });

export type Env = z.infer<typeof envSchema>;

let cached: Env | undefined;

/** Parses process.env once; exits with a readable list of problems (fail fast). */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  if (cached && source === process.env) return cached;
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`);
    console.error(`Invalid environment configuration:\n${lines.join('\n')}`);
    process.exit(1);
  }
  if (source === process.env) cached = parsed.data;
  return parsed.data;
}
