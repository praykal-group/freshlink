import { LoggerModule } from 'nestjs-pino';
import { randomUUID } from 'node:crypto';
import { loadEnv } from '../config/env.schema';

/** pino JSON logs with requestId; secrets redacted (Section 6.1). */
export function loggerModule() {
  const env = loadEnv();
  return LoggerModule.forRoot({
    pinoHttp: {
      level: env.LOG_LEVEL,
      genReqId: (req, res) => {
        const id = (req.headers['x-request-id'] as string) || randomUUID();
        res.setHeader('x-request-id', id);
        return id;
      },
      customProps: (req) => ({ route: req.url }),
      redact: {
        paths: [
          'req.headers.authorization',
          'req.headers["x-internal-token"]',
          '*.otp',
          '*.code',
          '*.password',
          '*.token',
          '*.secret',
        ],
        censor: '[REDACTED]',
      },
      transport:
        env.NODE_ENV === 'development'
          ? { target: 'pino-pretty', options: { singleLine: true } }
          : undefined,
    },
  });
}
