import { InfluxDB, Point, type QueryApi, type WriteApi } from '@influxdata/influxdb-client';
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { AppConfig } from '../../config/config.service';
import { requireEnv } from '../redis/redis.module';

export { Point };

/**
 * InfluxDB 2.7 (D-05). Measurements (Section 7): reefer, driver_gps, beacon.
 * Writes are batched: flush every 1 s or 500 points (Section 9.3).
 */
@Injectable()
export class InfluxService implements OnModuleDestroy {
  private readonly logger = new Logger(InfluxService.name);
  private client?: InfluxDB;
  private writer?: WriteApi;
  private reader?: QueryApi;

  constructor(private readonly config: AppConfig) {}

  get configured(): boolean {
    return !!(this.config.get('INFLUX_URL') && this.config.get('INFLUX_TOKEN'));
  }

  get bucket(): string {
    return this.config.get('INFLUX_BUCKET');
  }

  private db(): InfluxDB {
    this.client ??= new InfluxDB({
      url: requireEnv(this.config.get('INFLUX_URL'), 'INFLUX_URL'),
      token: requireEnv(this.config.get('INFLUX_TOKEN'), 'INFLUX_TOKEN'),
      timeout: 10_000,
    });
    return this.client;
  }

  writeApi(): WriteApi {
    this.writer ??= this.db().getWriteApi(this.config.get('INFLUX_ORG'), this.bucket, 'ms', {
      batchSize: 500,
      flushInterval: 1000,
      maxRetries: 5,
      writeFailed: (error, lines, attempt) => {
        this.logger.error({ msg: 'influx write failed', lines: lines.length, attempt, error: error.message });
      },
    });
    return this.writer;
  }

  /** Writes and waits for the flush (used by the telemetry writer to ack Kafka only after storage). */
  async writeNow(points: Point[]): Promise<void> {
    const w = this.writeApi();
    w.writePoints(points);
    await w.flush();
  }

  queryApi(): QueryApi {
    this.reader ??= this.db().getQueryApi(this.config.get('INFLUX_ORG'));
    return this.reader;
  }

  async query<T>(flux: string): Promise<T[]> {
    return this.queryApi().collectRows<T>(flux);
  }

  async onModuleDestroy() {
    await this.writer?.close().catch(() => undefined);
  }
}
