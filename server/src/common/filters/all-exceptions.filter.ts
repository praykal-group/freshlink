import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { AppError } from '../errors/app-error';

const STATUS_CODES: Record<number, string> = {
  400: 'BAD_REQUEST',
  401: 'UNAUTHORIZED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  409: 'CONFLICT',
  410: 'GONE',
  413: 'PAYLOAD_TOO_LARGE',
  426: 'UPGRADE_REQUIRED',
  429: 'RATE_LIMITED',
  503: 'SERVICE_UNAVAILABLE',
};

/** Global error envelope: {"error":{code,message,details,requestId}} (Section 6.1). */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<Request>();
    const res = ctx.getResponse<Response>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = 'INTERNAL_ERROR';
    let message = 'Internal server error';
    let details: Record<string, unknown> = {};

    const prismaCode = (exception as { code?: unknown })?.code;
    if (exception instanceof AppError) {
      status = exception.getStatus();
      code = exception.code;
      message = exception.message;
      details = exception.details;
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      code = STATUS_CODES[status] ?? 'HTTP_ERROR';
      const body = exception.getResponse();
      if (typeof body === 'string') {
        message = body;
      } else {
        const m = (body as { message?: unknown }).message;
        if (Array.isArray(m)) {
          code = 'VALIDATION_FAILED';
          message = 'Request validation failed';
          details = { errors: m };
        } else if (typeof m === 'string') {
          message = m;
        } else {
          message = exception.message;
          details = body as Record<string, unknown>;
        }
      }
    } else if (prismaCode === 'P2002') {
      status = HttpStatus.CONFLICT;
      code = 'DUPLICATE';
      message = 'Record already exists';
    } else if (prismaCode === 'P2025') {
      status = HttpStatus.NOT_FOUND;
      code = 'NOT_FOUND';
      message = 'Record not found';
    }

    if (status >= 500) this.logger.error(exception);
    res.status(status).json({ error: { code, message, details, requestId: req.id === undefined ? undefined : String(req.id) } });
  }
}
