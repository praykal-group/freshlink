import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';

export interface CargoStatusUpdate {
  batchId: string;
  remainingShelfLifeH: number;
  method: string;
  trigger: string;
}

/** `cargo.status` to the rooms of the trips carrying the batch (DA-FR-05). Temperature joins in M8. */
@Injectable()
export class CargoStatusNotifier {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async batchUpdated(update: CargoStatusUpdate): Promise<void> {
    const onBoard = await this.prisma.tripBatch.findMany({
      where: { batchId: update.batchId, unloadedAt: null, trip: { status: 'IN_PROGRESS' } },
      select: { tripId: true },
    });
    for (const { tripId } of onBoard) this.realtime.toTrip(tripId, 'cargo.status', { tripId, ...update });
  }
}
