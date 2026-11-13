import { HttpException, HttpStatus } from '@nestjs/common';

/** Domain error with a SCREAMING_SNAKE code, rendered by AllExceptionsFilter. */
export class AppError extends HttpException {
  constructor(
    public readonly code: string,
    message: string,
    status: HttpStatus = HttpStatus.BAD_REQUEST,
    public readonly details: Record<string, unknown> = {},
  ) {
    super(message, status);
  }
}
