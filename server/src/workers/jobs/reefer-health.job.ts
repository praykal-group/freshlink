import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { AlertsService } from '../../modules/alerts/alerts.service';
import { BASELINE_WEEKS, healthVerdict, median, pulldownRate, pulldownStarts } from '../../modules/maintenance/reefer-health';
import { TelemetryService } from '../../modules/telemetry/telemetry.service';

const WEEK_MS = 7 * 86_400_000;

export interface ReeferHealthRow {
  vehicleId: string;
  regNo: string;
  windows: number;
  pulldownRate: number | null;
  baselineRate: number | null;
  baselineFinal: boolean;
  degradationPct: number | null;
  flagged: boolean;
  note?: string;
}

/**
 * Weekly reefer health (SYN-17): for each vehicle, the median pull-down rate of the week from the
 * trips it started and its door-close events; stored in `reefer_health`. The baseline is the median
 * of the first 4 weekly rates (then saved on the vehicle); before that nothing is flagged.
 * Re-running a week updates its row instead of adding a second one.
 */
@Injectable()
export class ReeferHealthJob {
  private readonly logger = new Logger(ReeferHealthJob.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly telemetry: TelemetryService,
    private readonly alerts: AlertsService,
  ) {}

  async run(now = new Date()): Promise<{ periodStart: string; periodEnd: string; vehicles: ReeferHealthRow[] }> {
    const periodEnd = now;
    const periodStart = new Date(now.getTime() - WEEK_MS);
    const vehicles = await this.prisma.vehicle.findMany({ where: { status: { not: 'INACTIVE' } } });
    const out: ReeferHealthRow[] = [];
    for (const v of vehicles) {
      try {
        out.push(await this.vehicle(v.id, v.regNo, v.baselinePulldownRate, periodStart, periodEnd));
      } catch (e) {
        this.logger.error({ msg: 'reefer health failed', vehicleId: v.id, error: (e as Error).message });
        out.push({ vehicleId: v.id, regNo: v.regNo, windows: 0, pulldownRate: null, baselineRate: null, baselineFinal: false, degradationPct: null, flagged: false, note: (e as Error).message });
      }
    }
    return { periodStart: periodStart.toISOString(), periodEnd: periodEnd.toISOString(), vehicles: out };
  }

  private async vehicle(vehicleId: string, regNo: string, savedBaseline: number | null, from: Date, to: Date): Promise<ReeferHealthRow> {
    const trips = await this.prisma.trip.findMany({ where: { vehicleId, startedAt: { gte: from, lt: to } }, select: { startedAt: true } });
    const series = await this.telemetry.vehicleTemps(vehicleId, from, to);
    const points = series.map((p) => ({ at: p.at, tempC: p.tempC }));
    const doors = series.filter((p) => p.doorOpen !== null).map((p) => ({ at: p.at, open: p.doorOpen as boolean }));
    const starts = pulldownStarts(doors, trips.map((t) => t.startedAt!.getTime()));
    const rates = starts.map((s) => pulldownRate(points, s)).filter((r): r is number => r !== null);
    const current = median(rates);
    if (current === null) {
      return { vehicleId, regNo, windows: starts.length, pulldownRate: null, baselineRate: savedBaseline, baselineFinal: savedBaseline !== null, degradationPct: null, flagged: false, note: 'no pull-down window with data this week' };
    }

    // Baseline: saved, or the median of the first 4 weekly rates once they exist (this week included).
    const history = await this.prisma.reeferHealth.findMany({ where: { vehicleId, periodStart: { lt: from } }, orderBy: { periodStart: 'asc' }, take: BASELINE_WEEKS, select: { pulldownRate: true } });
    let baseline = savedBaseline;
    let baselineFinal = savedBaseline !== null;
    if (baseline === null) {
      const firstWeeks = [...history.map((h) => h.pulldownRate), current].slice(0, BASELINE_WEEKS);
      baseline = median(firstWeeks)!;
      if (firstWeeks.length >= BASELINE_WEEKS) {
        baselineFinal = true;
        await this.prisma.vehicle.update({ where: { id: vehicleId }, data: { baselinePulldownRate: baseline } });
      }
    }
    const { degradationPct, flagged } = healthVerdict(current, baseline, baselineFinal);
    const data = { pulldownRate: current, baselineRate: baseline, degradationPct, flagged, periodEnd: to };
    const existing = await this.prisma.reeferHealth.findFirst({ where: { vehicleId, periodStart: from } });
    if (existing) await this.prisma.reeferHealth.update({ where: { id: existing.id }, data });
    else await this.prisma.reeferHealth.create({ data: { vehicleId, periodStart: from, ...data } });

    if (flagged) {
      await this.alerts.raise({
        type: 'REEFER_MAINTENANCE',
        severity: 'WARNING',
        vehicleId,
        message: `Reefer of ${regNo} cools ${Math.round(degradationPct * 100)} % slower than its baseline (${current.toFixed(3)} vs ${baseline.toFixed(3)} °C/min): schedule maintenance`,
        data: { pulldownRate: current, baselineRate: baseline, degradationPct, windows: rates.length },
      });
    }
    return { vehicleId, regNo, windows: rates.length, pulldownRate: current, baselineRate: baseline, baselineFinal, degradationPct, flagged };
  }
}
