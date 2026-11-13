import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { Observable, tap } from 'rxjs';
import { PrismaService } from '../../infra/prisma/prisma.service';
import type { AppRequest } from '../auth/auth-user';

const WRITE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const REDACT = /pass(word)?|secret|token|otp|code$|key$/i;

function redact(value: unknown, depth = 0): unknown {
  if (depth > 5 || value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((v) => redact(v, depth + 1));
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).map(([k, v]) => [k, REDACT.test(k) ? '[REDACTED]' : redact(v, depth + 1)]),
  );
}

/**
 * Section 14: audit log for every successful manager/admin write.
 * Records route + target id + redacted request body; services add before/after where they need it.
 */
@Injectable()
export class AuditInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditInterceptor.name);

  constructor(private readonly prisma: PrismaService) {}

  intercept(ctx: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = ctx.switchToHttp().getRequest<AppRequest>();
    const user = req.user;
    if (!WRITE_METHODS.has(req.method) || !user || (user.role !== 'MANAGER' && user.role !== 'ADMIN')) {
      return next.handle();
    }
    const route = (req.route as { path?: string } | undefined)?.path ?? req.path;
    const entity = route.replace(/^\/?api\/v1\//, '').split('/').filter((p) => p && !p.startsWith(':'))[0] ?? 'unknown';

    return next.handle().pipe(
      tap((result) => {
        const params = req.params ?? {};
        const resultId = (result as { id?: unknown } | undefined)?.id;
        const entityId = String(params.id ?? params.key ?? resultId ?? '-');
        this.prisma.auditLog
          .create({
            data: {
              actorId: user.id,
              action: `${req.method} ${route}`,
              entity,
              entityId,
              after: redact(req.body) as Prisma.InputJsonValue,
              ip: req.ip,
              requestId: req.id === undefined ? null : String(req.id),
            },
          })
          .catch((e: Error) => this.logger.error(`audit log write failed: ${e.message}`));
      }),
    );
  }
}
