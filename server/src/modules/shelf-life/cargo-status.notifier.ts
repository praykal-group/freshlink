import { Injectable, Logger } from '@nestjs/common';

export interface CargoStatusUpdate {
  batchId: string;
  remainingShelfLifeH: number;
  method: string;
  trigger: string;
}

/**
 * `cargo.status` hook stub (M5). The realtime gateway (M7) replaces the body with a Socket.IO
 * emit to `trip:<id>` rooms; callers already use the final signature.
 */
@Injectable()
export class CargoStatusNotifier {
  private readonly logger = new Logger('CargoStatus');

  async batchUpdated(update: CargoStatusUpdate): Promise<void> {
    this.logger.debug({ msg: 'cargo.status (stub, not emitted)', ...update });
  }
}
