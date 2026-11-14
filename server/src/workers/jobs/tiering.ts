import { Injectable, Logger } from '@nestjs/common';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { gzipSync } from 'node:zlib';
import { istAt } from '../../common/ist';
import { AppConfig } from '../../config/config.service';
import { InfluxService } from '../../infra/influx/influx.service';
import { S3Service } from '../../infra/s3/s3.service';

const SKIP = new Set(['result', 'table', '_start', '_stop']);

/** RFC 4180 field. */
const csvField = (v: unknown) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

export function rowsToCsv(rows: Record<string, unknown>[]): string {
  const cols = [...new Set(rows.flatMap((r) => Object.keys(r).filter((k) => !SKIP.has(k))))].sort((a, b) =>
    a === '_time' ? -1 : b === '_time' ? 1 : a.localeCompare(b),
  );
  return [cols.join(','), ...rows.map((r) => cols.map((c) => csvField(r[c])).join(','))].join('\n') + '\n';
}

/** Archive key for an IST day: telemetry-archive/yyyy/mm/dd.csv.gz (SYN-12). */
export const archiveKey = (day: string) => `telemetry-archive/${day.slice(0, 4)}/${day.slice(5, 7)}/${day.slice(8, 10)}.csv.gz`;

/** IST day D−29 relative to `now` (exported before the 30-day bucket retention deletes it). */
export function dayToArchive(now: Date): string {
  const ist = new Date(now.getTime() + 5.5 * 3_600_000 - 29 * 86_400_000);
  return ist.toISOString().slice(0, 10);
}

/**
 * Data tiering (SYN-12): export one IST day of `reefer` + `driver_gps` from InfluxDB to gzip CSV in
 * S3 (or TIERING_LOCAL_DIR in dev), before the 30-day retention removes it. Training reads these.
 */
@Injectable()
export class TieringJob {
  private readonly logger = new Logger(TieringJob.name);

  constructor(
    private readonly influx: InfluxService,
    private readonly s3: S3Service,
    private readonly config: AppConfig,
  ) {}

  async run(day = dayToArchive(new Date())): Promise<{ day: string; rows: number; target: string }> {
    const start = istAt(day).toISOString();
    const stop = istAt(day, '24:00').toISOString();
    const flux = `from(bucket: "${this.influx.bucket}")
  |> range(start: ${start}, stop: ${stop})
  |> filter(fn: (r) => r._measurement == "reefer" or r._measurement == "driver_gps")
  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")`;
    const rows = await this.influx.query<Record<string, unknown>>(flux);
    const body = gzipSync(Buffer.from(rowsToCsv(rows), 'utf8'));
    const key = archiveKey(day);
    let target: string;
    if (this.s3.configured) {
      await this.s3.put(key, body, 'application/gzip');
      target = `s3://${this.config.get('S3_BUCKET')}/${key}`;
    } else {
      const dir = this.config.get('TIERING_LOCAL_DIR');
      if (!dir) throw new Error('Neither S3_BUCKET nor TIERING_LOCAL_DIR is set');
      target = join(dir, key);
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, body);
    }
    this.logger.log({ msg: 'telemetry archived', day, rows: rows.length, target, bytes: body.length });
    return { day, rows: rows.length, target };
  }
}
