import { Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { ForecastService } from '../../modules/forecast/forecast.service';

/** 02:00 IST daily (Section 5.1 "forecast nightly"). */
export const RUN_AT_IST = { hour: 2, minute: 0 };

/** Milliseconds from `now` until the next HH:MM in India time (UTC+05:30, no DST). */
export function msUntilNextIst(now: Date, hour = RUN_AT_IST.hour, minute = RUN_AT_IST.minute): number {
  const offset = 5.5 * 3_600_000;
  const ist = new Date(now.getTime() + offset);
  const target = new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate(), hour, minute, 0, 0));
  if (target.getTime() <= ist.getTime()) target.setUTCDate(target.getUTCDate() + 1);
  return target.getTime() - ist.getTime();
}

/**
 * Nightly forecast in the worker process. A plain timer until BullMQ repeatable jobs arrive with
 * Redis in M8 (D-71): if the worker is down at 02:00 that night's run is skipped, and the next
 * start runs it once if today's forecast is missing.
 */
@Injectable()
export class ForecastJob implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger(ForecastJob.name);
  private timer?: NodeJS.Timeout;

  constructor(private readonly forecasts: ForecastService) {}

  onApplicationBootstrap() {
    this.schedule();
  }

  onApplicationShutdown() {
    if (this.timer) clearTimeout(this.timer);
  }

  private schedule() {
    const wait = msUntilNextIst(new Date());
    this.logger.log({ msg: 'next nightly forecast', inMinutes: Math.round(wait / 60_000) });
    this.timer = setTimeout(() => void this.tick(), wait);
    this.timer.unref?.();
  }

  async tick() {
    try {
      const r = await this.forecasts.run();
      this.logger.log({ msg: 'nightly forecast done', ...r });
    } catch (e) {
      this.logger.error({ msg: 'nightly forecast failed', error: (e as Error).message });
    } finally {
      this.schedule();
    }
  }
}
