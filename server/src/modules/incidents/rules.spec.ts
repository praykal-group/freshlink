import { gradeAccepted, isOpenAt, openingHoursSchema, rankBuyers, type BuyerIn, type CargoIn } from '../buyers/buyer-rules';
import { rankRescue, type RescueCandidateIn } from '../diversions/rescue-rules';
import { healthVerdict, median, pulldownRate, pulldownStarts } from '../maintenance/reefer-health';
import { cteOf, excursions, parseRange, tempStats } from '../reports/report-rules';
import { csvCell, toCsv } from '../../common/csv-write';
import { toTrigger } from '../../workers/consumers/incident-engine';
import { atSpoilageRisk, classify, cumulativeEtaH, delayInfeasible, roadEtaH, tempSlopePer10Min } from './incident-rules';

const T0 = Date.UTC(2026, 10, 14, 6, 0); // 11:30 IST, Saturday
const min = (m: number) => T0 + m * 60_000;

describe('incident classifier (W-2 step 1)', () => {
  const base = { driftSlopeMax: 0.5 };
  it('temperature alert: reefer OFF → REEFER_FAILURE', () => {
    expect(classify({ ...base, source: 'TEMP_ALERT', reeferOn: false, slopePer10Min: 0.1 })?.kind).toBe('REEFER_FAILURE');
  });
  it('temperature alert: reefer ON but warming faster than driftSlopeMax → REEFER_FAILURE', () => {
    expect(classify({ ...base, source: 'TEMP_ALERT', reeferOn: true, slopePer10Min: 0.9 })?.kind).toBe('REEFER_FAILURE');
  });
  it('temperature alert: reefer ON and slow drift → TEMP_DRIFT (boundary: slope = max is still drift)', () => {
    expect(classify({ ...base, source: 'TEMP_ALERT', reeferOn: true, slopePer10Min: 0.5 })?.kind).toBe('TEMP_DRIFT');
    expect(classify({ ...base, source: 'TEMP_ALERT', reeferOn: true, slopePer10Min: null })?.kind).toBe('TEMP_DRIFT');
  });
  it('driver reports map by type; SOS / unknown types are not engine incidents', () => {
    expect(classify({ ...base, source: 'DRIVER_REPORT', reportedType: 'INCIDENT_REEFER_FAULT' })?.kind).toBe('REEFER_FAILURE');
    expect(classify({ ...base, source: 'DRIVER_REPORT', reportedType: 'INCIDENT_DELAY' })?.kind).toBe('DELAY');
    expect(classify({ ...base, source: 'DRIVER_REPORT', reportedType: 'INCIDENT_ROADBLOCK' })?.kind).toBe('DELAY');
    expect(classify({ ...base, source: 'DRIVER_REPORT', reportedType: 'INCIDENT_BREAKDOWN' })?.kind).toBe('BREAKDOWN');
    expect(classify({ ...base, source: 'DRIVER_REPORT', reportedType: 'INCIDENT_ACCIDENT' })?.kind).toBe('BREAKDOWN');
    expect(classify({ ...base, source: 'DRIVER_REPORT', reportedType: 'SOS' })).toBeNull();
  });
  it('spoilage gate and failed driver fix → SPOILAGE_RISK', () => {
    expect(classify({ ...base, source: 'SPOILAGE_GATE' })?.kind).toBe('SPOILAGE_RISK');
    expect(classify({ ...base, source: 'DRIVER_FIX_FAILED' })?.kind).toBe('SPOILAGE_RISK');
  });
  it('slope is °C per 10 min by least squares', () => {
    const pts = [0, 5, 10, 15, 20].map((m) => ({ at: min(m), tempC: 4 + m * 0.03 })); // 0.3 °C / 10 min
    expect(tempSlopePer10Min(pts)).toBeCloseTo(0.3, 6);
    expect(tempSlopePer10Min([{ at: T0, tempC: 4 }])).toBeNull();
  });
  it('spoilage gate: shelf life < remaining ETA + margin', () => {
    expect(atSpoilageRisk(5, 3.5, 2)).toBe(true);
    expect(atSpoilageRisk(5.5, 3.5, 2)).toBe(false);
  });
  it('delay feasibility: batches whose stop ETA + margin exceeds shelf life', () => {
    const from = { lat: 19.87, lng: 75.34 };
    const etas = cumulativeEtaH(from, [{ id: 's1', lat: 19.88, lng: 75.35 }, { id: 's2', lat: 20.2, lng: 75.6 }], 0.5);
    expect(etas.get('s1')!).toBeLessThan(etas.get('s2')!);
    expect(etas.get('s1')!).toBeGreaterThan(0.5); // delay counted
    const late = delayInfeasible(
      [{ batchId: 'b1', stopId: 's1', remainingShelfLifeH: 10 }, { batchId: 'b2', stopId: 's2', remainingShelfLifeH: etas.get('s2')! + 1 }, { batchId: 'b3', stopId: null, remainingShelfLifeH: 99 }],
      etas,
      2,
    );
    expect(late).toEqual(['b2', 'b3']);
  });
});

describe('backup buyer filtering and ranking (W-1)', () => {
  const allDay = Object.fromEntries(['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => [d, [['00:00', '23:59']]])) as BuyerIn['openingHours'];
  const buyer = (o: Partial<BuyerIn>): BuyerIn => ({
    id: 'b', name: 'B', type: 'LOCAL_MARKET', lat: 19.88, lng: 75.33, acceptedProductIds: ['p-rohu'], minGrade: 'C', discountPct: 20, openingHours: allDay, capacityKg: null, active: true, ...o,
  });
  const cargo: CargoIn = { productIds: ['p-rohu'], grade: 'B', quantityKg: 120, remainingShelfLifeH: 10, from: { lat: 19.87, lng: 75.34 }, now: new Date(T0), safetyMarginH: 2 };

  it('opening hours are evaluated in IST, including ranges past midnight and "23:59"', () => {
    const at = (iso: string) => new Date(iso);
    expect(isOpenAt({ sat: [['09:00', '21:00']] }, at('2026-11-14T03:29:00Z'))).toBe(false); // 08:59 IST
    expect(isOpenAt({ sat: [['09:00', '21:00']] }, at('2026-11-14T03:30:00Z'))).toBe(true); // 09:00 IST
    expect(isOpenAt({ fri: [['22:00', '04:00']] }, at('2026-11-13T21:00:00Z'))).toBe(true); // Sat 02:30 IST, Friday's night shift
    expect(isOpenAt({ sat: [['00:00', '23:59']] }, at('2026-11-14T18:29:30Z'))).toBe(true); // 23:59:30 IST
    expect(openingHoursSchema.safeParse({ mon: [['6:00', '20:00']] }).success).toBe(false);
    expect(openingHoursSchema.safeParse({ monday: [['06:00', '20:00']] }).success).toBe(false);
  });

  it('grade: A best; ungraded counts as C', () => {
    expect(gradeAccepted('B', 'A')).toBe(true);
    expect(gradeAccepted('B', 'C')).toBe(false);
    expect(gradeAccepted('C', null)).toBe(true);
    expect(gradeAccepted('B', null)).toBe(false);
  });

  it('closed at ETA / wrong product / grade too low / inactive / no capacity / too far are excluded with the reason', () => {
    const r = rankBuyers(
      [
        buyer({ id: 'closed', openingHours: { sat: [['18:00', '20:00']] } }),
        buyer({ id: 'product', acceptedProductIds: ['p-tomato'] }),
        buyer({ id: 'grade', minGrade: 'A' }),
        buyer({ id: 'inactive', active: false }),
        buyer({ id: 'small', capacityKg: 50 }),
        buyer({ id: 'far', lat: 21.1, lng: 79.0 }), // ~420 km
        buyer({ id: 'ok' }),
      ],
      cargo,
      { sort: 'DISCOUNT' },
    );
    expect(r.eligible.map((e) => e.buyer.id)).toEqual(['ok']);
    expect(Object.fromEntries(r.excluded.map((x) => [x.buyerId, x.reason]))).toEqual({
      closed: 'CLOSED_AT_ETA', product: 'PRODUCT_NOT_ACCEPTED', grade: 'GRADE_TOO_LOW', inactive: 'INACTIVE', small: 'NO_CAPACITY', far: 'NOT_REACHABLE_BEFORE_SPOILAGE',
    });
  });

  it('ranks by (discount asc, ETA asc); NEAREST ranks by ETA; already offered and wrong type excluded', () => {
    const r = rankBuyers(
      [buyer({ id: 'cheap-far', discountPct: 10, lat: 19.95 }), buyer({ id: 'cheap-near', discountPct: 10, lat: 19.875 }), buyer({ id: 'dear', discountPct: 5, lat: 19.99 }), buyer({ id: 'done' })],
      cargo,
      { sort: 'DISCOUNT', excludeIds: new Set(['done']) },
    );
    expect(r.eligible.map((e) => e.buyer.id)).toEqual(['dear', 'cheap-near', 'cheap-far']);
    expect(r.excluded).toEqual([{ buyerId: 'done', name: 'B', reason: 'ALREADY_OFFERED' }]);
    const n = rankBuyers([buyer({ id: 'far', type: 'COLD_STORAGE', lat: 19.99, discountPct: 1 }), buyer({ id: 'near', type: 'COLD_STORAGE', lat: 19.875, discountPct: 9 }), buyer({ id: 'mkt' })], cargo, {
      sort: 'NEAREST',
      types: ['COLD_STORAGE'],
    });
    expect(n.eligible.map((e) => e.buyer.id)).toEqual(['near', 'far']);
    expect(n.excluded[0]).toMatchObject({ buyerId: 'mkt', reason: 'WRONG_TYPE' });
  });
});

describe('rescue matching (W-2 b)', () => {
  const cand = (o: Partial<RescueCandidateIn>): RescueCandidateIn => ({
    tripId: 't', code: 'TRP', vehicleId: 'v', reefer: { min: -2, max: 10 }, capacityKg: 2000, loadKg: 500, cargoRanges: [{ min: 0, max: 4 }], position: { lat: 19.88, lng: 75.35 }, ...o,
  });
  const need = { failingTripId: 'fail', cargoRanges: [{ min: 0, max: 4 }], cargoKg: 400, at: { lat: 19.87, lng: 75.34 }, radiusKm: 30, remainingShelfLifeH: 8, safetyMarginH: 2 };
  it('keeps compatible trucks with room inside the radius, nearest first; explains the rest', () => {
    const r = rankRescue(
      [
        cand({ tripId: 'fail' }),
        cand({ tripId: 'nopos', position: null }),
        cand({ tripId: 'far', position: { lat: 20.3, lng: 75.34 } }),
        cand({ tripId: 'full', loadKg: 1700 }),
        cand({ tripId: 'banana', cargoRanges: [{ min: 13, max: 15 }] }),
        cand({ tripId: 'second', position: { lat: 19.95, lng: 75.34 } }),
        cand({ tripId: 'first' }),
      ],
      need,
    );
    expect(r.eligible.map((e) => e.candidate.tripId)).toEqual(['first', 'second']);
    expect(r.eligible[0].setpoint).toEqual({ min: 0, max: 4 });
    expect(Object.fromEntries(r.excluded.map((x) => [x.tripId, x.reason]))).toEqual({ fail: 'SAME_TRIP', nopos: 'NO_POSITION', far: 'TOO_FAR', full: 'NO_CAPACITY', banana: 'INCOMPATIBLE_TEMPERATURE' });
  });
  it('ETA uses the same road factor as buyers', () => {
    expect(roadEtaH({ lat: 19.87, lng: 75.34 }, { lat: 19.87, lng: 75.34 })).toBe(0);
  });
});

describe('reefer health (SYN-17)', () => {
  it('pull-down rate over the first 20 min after a start; none when the box did not cool', () => {
    const cooling = Array.from({ length: 30 }, (_, i) => ({ at: min(i), tempC: 12 - 0.4 * Math.min(i, 20) }));
    expect(pulldownRate(cooling, T0)).toBeCloseTo(0.4, 6);
    const flat = Array.from({ length: 30 }, (_, i) => ({ at: min(i), tempC: 3 + (i % 2) * 0.1 }));
    expect(pulldownRate(flat, T0)).toBeNull();
    expect(pulldownRate(cooling.slice(0, 3), T0)).toBeNull();
  });
  it('window starts = trip starts + door open→closed', () => {
    expect(pulldownStarts([{ at: min(5), open: false }, { at: min(10), open: true }, { at: min(12), open: false }, { at: min(13), open: false }], [min(0)])).toEqual([min(0), min(12)]);
  });
  it('degradation > 30 % flags only with a final 4-week baseline', () => {
    expect(median([3, 1, 2])).toBe(2);
    expect(median([4, 1, 2, 3])).toBe(2.5);
    expect(healthVerdict(0.2, 0.4, true)).toEqual({ degradationPct: 0.5, flagged: true });
    expect(healthVerdict(0.2, 0.4, false).flagged).toBe(false);
    expect(healthVerdict(0.3, 0.4, true).flagged).toBe(false); // exactly 25 %
  });
});

describe('report helpers (SYN-15)', () => {
  const row = (m: number, t: number) => ({ at: new Date(min(m)).toISOString(), tempC: t });
  it('excursions are contiguous out-of-range runs with peak and minutes', () => {
    const rows = [row(0, 2), row(1, 5), row(2, 6.5), row(3, 5.2), row(4, 3), row(5, -1), row(20, 5)];
    expect(excursions(rows, 0, 4)).toEqual([
      { from: rows[1].at, to: rows[3].at, minutes: 3, peakC: 6.5, direction: 'ABOVE' },
      { from: rows[5].at, to: rows[5].at, minutes: 1, peakC: -1, direction: 'BELOW' },
      { from: rows[6].at, to: rows[6].at, minutes: 1, peakC: 5, direction: 'ABOVE' },
    ]);
    expect(tempStats(rows)).toEqual({ count: 7, minC: -1, maxC: 6.5, meanC: 3.67 });
    expect(tempStats([])).toEqual({ count: 0, minC: null, maxC: null, meanC: null });
  });
  it('CTE mapping and range validation', () => {
    expect(cteOf('REGISTERED', 'FISH')).toBe('FIRST_LAND_BASED_RECEIVING');
    expect(cteOf('REGISTERED', 'PRODUCE')).toBe('HARVESTING');
    expect(cteOf('DELIVERED', 'FISH')).toBe('RECEIVING');
    expect(cteOf('GRADED', 'FISH')).toBeNull();
    expect(parseRange('2026-11-01T00:00:00Z', '2026-11-02T00:00:00Z', 92)).toEqual({ from: new Date('2026-11-01T00:00:00Z'), to: new Date('2026-11-02T00:00:00Z') });
    expect(typeof parseRange('2026-11-02', '2026-11-01', 92)).toBe('string');
    expect(typeof parseRange('2026-01-01', '2026-11-01', 92)).toBe('string');
    expect(typeof parseRange(undefined, '2026-11-01', 92)).toBe('string');
  });
  it('CSV quotes, escapes and neutralises formulas', () => {
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`);
    expect(csvCell(-1.5)).toBe('-1.5');
    expect(toCsv(['a', 'b'], [[1, null]])).toBe('a,b\r\n1,\r\n');
  });
});

describe('incident-engine consumer mapping', () => {
  it('critical temperature alerts and driver incident reports become triggers; the rest is ignored', () => {
    expect(toTrigger({ type: 'ALERT_RAISED', alertType: 'TEMP_EXCURSION', severity: 'CRITICAL', tripId: 't1', alertId: 'a1' })).toEqual({ tripId: 't1', source: 'TEMP_ALERT', alertId: 'a1' });
    expect(toTrigger({ type: 'DRIVER_INCIDENT', tripId: 't1', kind: 'INCIDENT_DELAY', eventId: 'e1' })).toEqual({ tripId: 't1', source: 'DRIVER_REPORT', eventType: 'INCIDENT_DELAY', eventId: 'e1' });
    expect(toTrigger({ type: 'ALERT_RAISED', alertType: 'SHOCK', severity: 'WARNING', tripId: 't1' })).toBeNull();
    expect(toTrigger({ type: 'ALERT_RAISED', alertType: 'TEMP_EXCURSION', severity: 'CRITICAL', tripId: null })).toBeNull();
    expect(toTrigger({ type: 'INCIDENT_OPENED', tripId: 't1' })).toBeNull();
  });
});
