import { HttpStatus } from '@nestjs/common';
import { AppError } from '../../common/errors/app-error';
import { OffersService, tokenHash } from '../diversions/offers.service';
import type { DecisionEntry } from './incident-rules';
import { IncidentsService } from './incidents.service';

/**
 * Incident engine scenarios (M9 tests) against an in-memory Prisma: the engine's own queries run for
 * real; offers, rerouting, alerts and telemetry are mocks whose calls are asserted.
 */

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

function matches(row: Row, where: Row = {}): boolean {
  return Object.entries(where).every(([k, cond]) => {
    const v = row[k];
    if (cond === undefined) return true;
    if (cond !== null && typeof cond === 'object' && !(cond instanceof Date) && !Array.isArray(cond)) {
      if ('in' in cond) return cond.in.includes(v);
      if ('notIn' in cond) return !cond.notIn.includes(v);
      if ('not' in cond) return cond.not === null ? v !== null && v !== undefined : v !== cond.not;
      if ('lte' in cond || 'gte' in cond || 'gt' in cond || 'lt' in cond) {
        const t = v instanceof Date ? v.getTime() : v;
        const n = (x: unknown) => (x instanceof Date ? x.getTime() : (x as number));
        return (cond.lte === undefined || t <= n(cond.lte)) && (cond.gte === undefined || t >= n(cond.gte)) && (cond.gt === undefined || t > n(cond.gt)) && (cond.lt === undefined || t < n(cond.lt));
      }
      return v !== null && v !== undefined && typeof v === 'object' ? matches(v, cond) : false;
    }
    return v === cond;
  });
}

function table(rows: Row[] = [], defaults: Row = {}) {
  let seq = 0;
  const t = {
    rows,
    findMany: jest.fn(async (a: Row = {}) => rows.filter((r) => matches(r, a.where))),
    findFirst: jest.fn(async (a: Row = {}) => {
      const hits = rows.filter((r) => matches(r, a.where));
      return (a.orderBy?.createdAt === 'desc' ? hits.reverse() : hits)[0] ?? null;
    }),
    findUnique: jest.fn(async (a: Row) => rows.find((r) => matches(r, a.where)) ?? null),
    findUniqueOrThrow: jest.fn(async (a: Row) => {
      const r = rows.find((x) => matches(x, a.where));
      if (!r) throw new Error(`not found ${JSON.stringify(a.where)}`);
      return r;
    }),
    count: jest.fn(async (a: Row = {}) => rows.filter((r) => matches(r, a.where)).length),
    create: jest.fn(async (a: Row) => {
      const r = { id: a.data.id ?? `gen-${++seq}`, createdAt: new Date(Date.now() + seq), ...defaults, ...a.data };
      rows.push(r);
      return r;
    }),
    update: jest.fn(async (a: Row) => {
      const r = rows.find((x) => matches(x, a.where));
      if (!r) throw new Error('update: not found');
      Object.assign(r, a.data);
      return r;
    }),
    updateMany: jest.fn(async (a: Row) => {
      const hits = rows.filter((r) => matches(r, a.where));
      for (const r of hits) Object.assign(r, a.data);
      return { count: hits.length };
    }),
  };
  return t;
}

const POS = { lat: 19.87, lng: 75.34 }; // the failing truck, Chh. Sambhajinagar
const allDay = Object.fromEntries(['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => [d, [['00:00', '23:59']]]));

function world(o: { coldStorage?: boolean; rescue?: 'near' | 'far' | 'none'; buyers?: number; reeferOn?: boolean | null; tempC?: number } = {}) {
  const product = { id: 'p-rohu', code: 'ROHU', name: 'Rohu', safeTempMin: 0, safeTempMax: 4, baseShelfLifeH: 72 };
  const batch = (id: string, kg: number) => ({ id, code: `FSH-${id}`, productId: product.id, product, currentGrade: 'B', weightKg: kg, remainingShelfLifeH: 20, caughtOrHarvestedAt: new Date(Date.now() - 6 * 3_600_000) });
  const depotSite = { id: 'site-dock', lat: 19.48, lng: 75.38 };
  const trips = [
    { id: 'trip-1', code: 'TRP-1', status: 'IN_PROGRESS', vehicleId: 'veh-1', driverId: 'drv-1', currentRouteVersion: 1, depotSite, vehicle: { reeferMinTemp: -2, reeferMaxTemp: 12, capacityKg: 2000 }, batches: [] as Row[] },
  ];
  const positions: Record<string, typeof POS | null> = { 'veh-1': POS };
  if (o.rescue && o.rescue !== 'none') {
    trips.push({
      id: 'trip-2', code: 'TRP-2', status: 'IN_PROGRESS', vehicleId: 'veh-2', driverId: 'drv-2', currentRouteVersion: 1, depotSite,
      vehicle: { reeferMinTemp: -2, reeferMaxTemp: 10, capacityKg: 3000 }, batches: [{ batch: { ...batch('b-9', 400), product } }],
    });
    positions['veh-2'] = o.rescue === 'near' ? { lat: 19.9, lng: 75.36 } : { lat: 20.6, lng: 75.36 }; // ~5 km vs ~105 km
  }
  const buyers: Row[] = [];
  if (o.coldStorage) buyers.push({ id: 'cs-1', name: 'Waluj Cold Storage', type: 'COLD_STORAGE', phone: '+919999900101', lat: 19.8434, lng: 75.2355, acceptedProductIds: [product.id], minGrade: 'C', discountPct: 5, openingHours: allDay, capacityKg: 8000, active: true });
  for (let i = 1; i <= (o.buyers ?? 2); i++) {
    buyers.push({ id: `buyer-${i}`, name: `Buyer ${i}`, type: 'PROCESSING', phone: `+91999990020${i}`, lat: 19.86 + i * 0.01, lng: 75.46, acceptedProductIds: [product.id], minGrade: 'C', discountPct: 20 + i, openingHours: allDay, capacityKg: null, active: true });
  }
  // Excluded buyers the spec names: closed, wrong product, grade too low.
  buyers.push({ id: 'closed', name: 'Closed Mart', type: 'LOCAL_MARKET', phone: '+919999900301', lat: 19.88, lng: 75.33, acceptedProductIds: [product.id], minGrade: 'C', discountPct: 1, openingHours: {}, capacityKg: null, active: true });
  buyers.push({ id: 'tomato', name: 'Tomato Cannery', type: 'CANNING', phone: '+919999900302', lat: 19.88, lng: 75.33, acceptedProductIds: ['p-tomato'], minGrade: 'C', discountPct: 1, openingHours: allDay, capacityKg: null, active: true });
  buyers.push({ id: 'premium', name: 'Premium Retail', type: 'DISCOUNT_RETAIL', phone: '+919999900303', lat: 19.88, lng: 75.33, acceptedProductIds: [product.id], minGrade: 'A', discountPct: 1, openingHours: allDay, capacityKg: null, active: true });

  const db: Row = {
    trip: table(trips),
    tripBatch: table([{ tripId: 'trip-1', batchId: 'b-1', unloadedAt: null, batch: batch('b-1', 120) }, { tripId: 'trip-1', batchId: 'b-2', unloadedAt: null, batch: batch('b-2', 80) }]),
    incident: table([], { status: 'OPEN', decidedAction: null, rescueTripId: null, decisionLog: [] }),
    backupBuyer: table(buyers),
    diversionOffer: table(),
    batch: table([batch('b-1', 120), batch('b-2', 80)]),
    tripEvent: table(),
    tripStop: table(),
    alert: table(),
    $transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn(db)),
    $queryRaw: jest.fn(async () => []),
    // UPDATE incidents SET decision_log = decision_log || <json>::jsonb ... WHERE id = <id>
    $executeRaw: jest.fn(async (_s: TemplateStringsArray, json: string, id: string) => {
      const inc = db.incident.rows.find((r: Row) => r.id === id)!;
      inc.decisionLog = [...(inc.decisionLog ?? []), ...JSON.parse(json)];
      return 1;
    }),
  };
  // trip.findMany for rescue candidates returns trips with their on-board batches (include is ignored by the fake).

  let offerSeq = 0;
  const offers = {
    send: jest.fn(async (i: Row) => {
      const offer = await db.diversionOffer.create({ data: { id: `offer-${++offerSeq}`, incidentId: i.incidentId, buyerId: i.buyerId, batchIds: i.batchIds, quantityKg: i.quantityKg, status: 'SENT', expiresAt: new Date(Date.now() + 600_000) } });
      return { offer, url: `http://x/offer/tok-${offerSeq}` };
    }),
    claim: jest.fn(),
    expire: jest.fn(async (id: string) => {
      const r = db.diversionOffer.rows.find((x: Row) => x.id === id && x.status === 'SENT');
      if (!r) return null;
      r.status = 'EXPIRED';
      return r;
    }),
    cancelOpen: jest.fn(async () => 0),
    recordAccepted: jest.fn(),
  };
  const rerouting = {
    pendingStops: jest.fn(async () => []),
    propose: jest.fn(async (i: Row) => ({ tripId: i.tripId, version: 2, reason: i.reason, provider: 'ML', distanceKm: 12, stops: [...i.first, ...i.others].map((s: Row, n: number) => ({ stopId: `s-${n}`, seq: n + 1, type: s.type })) })),
    cancelResponseJob: jest.fn(),
  };
  let alertSeq = 0;
  const alerts = { raise: jest.fn(async (a: Row) => db.alert.create({ data: { id: `alert-${++alertSeq}`, status: 'OPEN', ...a } })), resolveBySystem: jest.fn(async () => true) };
  const reading = { tempC: o.tempC ?? 8, reeferOn: o.reeferOn === undefined ? false : o.reeferOn, ts: new Date().toISOString(), receivedAt: new Date().toISOString() };
  const telemetry = {
    lastReading: jest.fn(async (vehicleId: string) => (positions[vehicleId] ? { ...reading, ...positions[vehicleId] } : null)),
    vehicleTemps: jest.fn(async () => [0, 5, 10, 15, 20].map((m) => ({ at: Date.now() - (20 - m) * 60_000, tempC: 5 + m * 0.01, doorOpen: false }))), // 0.1 °C / 10 min
  };
  const context = { tripCargo: jest.fn(async () => ({ limits: { tempMin: 0, tempMax: 4 } })) };
  const config = { get: jest.fn(async (k: string) => ({ driftSlopeMax: 0.5, safetyMarginH: 2, rescueRadiusKm: 30, offerMinutes: 10 })[k]) };
  const queue = { add: jest.fn(async () => ({})), remove: jest.fn(async () => 1) };
  const svc = new IncidentsService(
    db as never, alerts as never, { toManagers: jest.fn(), toTrip: jest.fn(), toUser: jest.fn() } as never, config as never, { publish: jest.fn() } as never,
    telemetry as never, context as never, { onEstimate: jest.fn() } as never, offers as never, rerouting as never, { append: jest.fn() } as never, queue as never,
  );
  const steps = () => (db.incident.rows[0]?.decisionLog as DecisionEntry[]).map((e) => e.step);
  return { svc, db, offers, rerouting, alerts, telemetry, queue, steps };
}

describe('incident engine: reefer_failure (W-2)', () => {
  it('cold storage reachable → offer to the nearest cold storage first', async () => {
    const w = world({ coldStorage: true, rescue: 'near' });
    const inc = await w.svc.handleTrigger({ tripId: 'trip-1', source: 'TEMP_ALERT', alertId: 'a-1' });
    expect(inc).toMatchObject({ kind: 'REEFER_FAILURE', decidedAction: 'DIVERT_COLD_STORAGE', status: 'ACTION_IN_PROGRESS' });
    expect(w.offers.send).toHaveBeenCalledWith(expect.objectContaining({ buyerId: 'cs-1', batchIds: ['b-1', 'b-2'], quantityKg: 200 }));
    expect(w.steps()).toEqual(['CLASSIFIED', 'COLD_STORAGE_SEARCH', 'OFFER_SENT']);
    expect(w.rerouting.propose).not.toHaveBeenCalled(); // route changes only after the buyer accepts (W-1)
  });

  it('no cold storage → rescue by the nearest compatible truck (two-trip replan)', async () => {
    const w = world({ coldStorage: false, rescue: 'near' });
    const inc = await w.svc.handleTrigger({ tripId: 'trip-1', source: 'DRIVER_REPORT', eventType: 'INCIDENT_REEFER_FAULT' });
    expect(inc).toMatchObject({ kind: 'REEFER_FAILURE', decidedAction: 'RESCUE_PICKUP', rescueTripId: 'trip-2' });
    const [failing, rescue] = w.rerouting.propose.mock.calls.map((c) => c[0]);
    expect(failing).toMatchObject({ tripId: 'trip-1', reason: 'RESCUE', first: [expect.objectContaining({ type: 'RESCUE_DROP', lat: POS.lat, lng: POS.lng })] });
    expect(rescue).toMatchObject({ tripId: 'trip-2', reason: 'RESCUE', first: [expect.objectContaining({ type: 'RESCUE_PICKUP', lat: POS.lat, lng: POS.lng })] });
    expect(w.steps()).toEqual(['CLASSIFIED', 'COLD_STORAGE_SEARCH', 'RESCUE_SEARCH', 'RESCUE_PLANNED']);
    expect(w.offers.send).not.toHaveBeenCalled();
  });

  it('no cold storage, rescue truck out of range → buyer offer; closed / wrong product / low grade buyers excluded', async () => {
    const w = world({ coldStorage: false, rescue: 'far' });
    const inc = await w.svc.handleTrigger({ tripId: 'trip-1', source: 'TEMP_ALERT' });
    expect(inc).toMatchObject({ decidedAction: 'DIVERT_BUYER' });
    expect(w.offers.send).toHaveBeenCalledWith(expect.objectContaining({ buyerId: 'buyer-1' })); // 21 % < 22 %
    const log = w.db.incident.rows[0].decisionLog as DecisionEntry[];
    const rescue = log.find((e) => e.step === 'RESCUE_SEARCH')!.candidates as { excluded: { tripId: string; reason: string }[] };
    expect(rescue.excluded).toEqual([expect.objectContaining({ tripId: 'trip-2', reason: 'TOO_FAR' })]);
    const buyers = log.find((e) => e.step === 'BUYER_SEARCH')!.candidates as { excluded: { buyerId: string; reason: string }[] };
    expect(Object.fromEntries(buyers.excluded.map((x) => [x.buyerId, x.reason]))).toEqual({ closed: 'CLOSED_AT_ETA', tomato: 'PRODUCT_NOT_ACCEPTED', premium: 'GRADE_TOO_LOW' });
  });
});

describe('incident engine: offers (W-1)', () => {
  it('offer expiry → next buyer; the expired buyer is not offered again', async () => {
    const w = world({ buyers: 2 });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'SPOILAGE_GATE' });
    expect(w.offers.send).toHaveBeenLastCalledWith(expect.objectContaining({ buyerId: 'buyer-1' }));
    expect(await w.svc.expireOffer('offer-1')).toBe(true);
    expect(w.offers.send).toHaveBeenLastCalledWith(expect.objectContaining({ buyerId: 'buyer-2' }));
    const second = (w.db.incident.rows[0].decisionLog as DecisionEntry[]).filter((e) => e.step === 'BUYER_SEARCH')[1].candidates as { excluded: { buyerId: string; reason: string }[] };
    expect(second.excluded).toContainEqual(expect.objectContaining({ buyerId: 'buyer-1', reason: 'ALREADY_OFFERED' }));
    expect(await w.svc.expireOffer('offer-1')).toBe(false); // the job firing twice changes nothing
  });

  it('all buyers reject → MANUAL + CRITICAL alert to managers (with SMS)', async () => {
    const w = world({ buyers: 1 });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'SPOILAGE_GATE' });
    w.offers.claim.mockImplementation(async () => Object.assign(w.db.diversionOffer.rows[0], { status: 'REJECTED' }));
    await w.svc.respondOffer('tok-1', false);
    const inc = w.db.incident.rows[0];
    expect(inc).toMatchObject({ decidedAction: 'MANUAL', status: 'OPEN' });
    expect(w.alerts.raise).toHaveBeenCalledWith(expect.objectContaining({ type: 'SPOILAGE_RISK', severity: 'CRITICAL', smsManagers: true, data: { incidentId: inc.id } }));
    expect(w.steps()).toEqual(['CLASSIFIED', 'BUYER_SEARCH', 'OFFER_SENT', 'OFFER_REJECTED', 'BUYER_SEARCH', 'MANUAL']);
  });

  it('accepted offer → batches DIVERTED (trace) and a DIVERSION route with the buyer stop first', async () => {
    const w = world({ buyers: 1 });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'SPOILAGE_GATE' });
    w.offers.claim.mockImplementation(async () => Object.assign(w.db.diversionOffer.rows[0], { status: 'ACCEPTED' }));
    await w.svc.respondOffer('tok-1', true);
    expect(w.db.batch.rows.map((b: Row) => b.status)).toEqual(['DIVERTED', 'DIVERTED']);
    expect(w.rerouting.propose).toHaveBeenCalledWith(expect.objectContaining({ reason: 'DIVERSION', first: [expect.objectContaining({ type: 'DIVERSION_DROP', buyerId: 'buyer-1', demandKg: 200 })] }));
    expect(w.db.incident.rows[0]).toMatchObject({ decidedAction: 'DIVERT_BUYER', status: 'ACTION_IN_PROGRESS' });
    await w.svc.onDropCompleted('trip-1', 'DIVERSION_DROP');
    expect(w.db.incident.rows[0].status).toBe('RESOLVED');
  });
});

describe('incident engine: temp_drift_recoverable', () => {
  it('reefer ON + slow drift → DRIVER_FIX; recovered at the re-check → RESOLVED without diversion', async () => {
    const w = world({ reeferOn: true, tempC: 5.2 });
    const inc = await w.svc.handleTrigger({ tripId: 'trip-1', source: 'TEMP_ALERT', alertId: 'a-1' });
    expect(inc).toMatchObject({ kind: 'TEMP_DRIFT', decidedAction: 'DRIVER_FIX', status: 'ACTION_IN_PROGRESS' });
    expect(w.alerts.raise).toHaveBeenCalledWith(expect.objectContaining({ type: 'DRIVER_FIX', notifyDriver: true }));
    expect(w.queue.add).toHaveBeenCalledWith('driver-fix-recheck', { incidentId: inc!.id }, expect.objectContaining({ jobId: `dfr-${inc!.id}`, delay: 15 * 60_000 }));
    w.telemetry.lastReading.mockResolvedValue({ tempC: 3.1, reeferOn: true, lat: POS.lat, lng: POS.lng, ts: new Date().toISOString(), receivedAt: new Date().toISOString() } as never);
    expect(await w.svc.recheckDriverFix(inc!.id)).toBe('RECOVERED');
    expect(w.db.incident.rows[0].status).toBe('RESOLVED');
    expect(w.offers.send).not.toHaveBeenCalled();
    expect(w.rerouting.propose).not.toHaveBeenCalled();
    expect(w.steps()).toEqual(['CLASSIFIED', 'DRIVER_FIX', 'DRIVER_FIX_RECOVERED']);
  });

  it('not recovered at the re-check → SPOILAGE_RISK → buyer offer', async () => {
    const w = world({ reeferOn: true, tempC: 6 });
    const inc = await w.svc.handleTrigger({ tripId: 'trip-1', source: 'TEMP_ALERT' });
    expect(await w.svc.recheckDriverFix(inc!.id)).toBe('ESCALATED');
    expect(w.db.incident.rows[0]).toMatchObject({ kind: 'SPOILAGE_RISK', decidedAction: 'DIVERT_BUYER' });
    expect(w.steps()).toEqual(['CLASSIFIED', 'DRIVER_FIX', 'DRIVER_FIX_FAILED', 'BUYER_SEARCH', 'OFFER_SENT']);
  });

  it('reefer failure during a driver fix escalates the same incident (no second incident)', async () => {
    const w = world({ reeferOn: true, tempC: 5.2 });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'TEMP_ALERT' });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'DRIVER_REPORT', eventType: 'INCIDENT_REEFER_FAULT' });
    expect(w.db.incident.rows).toHaveLength(1);
    expect(w.db.incident.rows[0].kind).toBe('REEFER_FAILURE');
    expect(w.queue.remove).toHaveBeenCalledWith(`dfr-${w.db.incident.rows[0].id}`);
    expect(w.steps()).toContain('ESCALATED');
  });
});

describe('incident engine: one incident per trip, DELAY, decision log', () => {
  it('a second trigger while active is noted in the log, not a new incident', async () => {
    const w = world({ buyers: 1 });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'SPOILAGE_GATE' });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'DRIVER_REPORT', eventType: 'INCIDENT_DELAY' });
    expect(w.db.incident.rows).toHaveLength(1);
    expect(w.steps().at(-1)).toBe('TRIGGER_NOTED');
  });

  it('DELAY still feasible → REPLAN of the same stops; resolved when the driver accepts', async () => {
    const w = world();
    w.rerouting.pendingStops.mockResolvedValue([{ id: 'stop-1', type: 'DROP', lat: 19.9, lng: 75.4, order: { quantityKg: 200, batches: [{ batchId: 'b-1' }, { batchId: 'b-2' }] } }] as never);
    const inc = await w.svc.handleTrigger({ tripId: 'trip-1', source: 'DRIVER_REPORT', eventType: 'INCIDENT_DELAY' });
    expect(inc).toMatchObject({ kind: 'DELAY', decidedAction: 'REPLAN' });
    expect(w.rerouting.propose).toHaveBeenCalledWith(expect.objectContaining({ reason: 'DELAY', first: [] }));
    await w.svc.onRouteAccepted('trip-1', 2, 'DELAY');
    expect(w.db.incident.rows[0].status).toBe('RESOLVED');
    expect(w.steps()).toEqual(['CLASSIFIED', 'DELAY_CHECK', 'ROUTE_PROPOSED', 'ROUTE_ACCEPTED', 'RESOLVED']);
  });

  it('every decision-log entry has time, step and reason; searches carry inputs + candidates; choices carry what was chosen', async () => {
    const w = world({ coldStorage: false, rescue: 'far' });
    await w.svc.handleTrigger({ tripId: 'trip-1', source: 'TEMP_ALERT', alertId: 'a-1' });
    const log = w.db.incident.rows[0].decisionLog as DecisionEntry[];
    for (const e of log) {
      expect(Number.isNaN(Date.parse(e.at))).toBe(false);
      expect(e.step).toBeTruthy();
      expect(e.reason.length).toBeGreaterThan(3);
    }
    expect(log[0].inputs).toMatchObject({ source: 'TEMP_ALERT', alertId: 'a-1', reeferOn: false, kind: 'REEFER_FAILURE' });
    for (const s of log.filter((e) => e.step.endsWith('_SEARCH'))) expect(s.candidates).toBeDefined();
    expect(log.find((e) => e.step === 'OFFER_SENT')!.chosen).toMatchObject({ buyerId: 'buyer-1', offerId: 'offer-1' });
  });

  it('trips that are not in progress are ignored', async () => {
    const w = world();
    w.db.trip.rows[0].status = 'COMPLETED';
    expect(await w.svc.handleTrigger({ tripId: 'trip-1', source: 'SPOILAGE_GATE' })).toBeNull();
    expect(w.db.incident.rows).toHaveLength(0);
  });
});

describe('OffersService tokens (W-1)', () => {
  function offersWorld(expiresInMs = 600_000) {
    const db = { diversionOffer: table([], { status: 'SENT', respondedAt: null }), backupBuyer: table([{ id: 'buyer-1', name: 'B1', phone: '+919999900201', discountPct: 20 }]) };
    const sms = { send: jest.fn(async () => ({})) };
    const queue = { add: jest.fn(async () => ({})), remove: jest.fn(async () => 1) };
    const svc = new OffersService(
      { ...db, diversionOffer: { ...db.diversionOffer, findUnique: jest.fn(async (a: Row) => db.diversionOffer.rows.find((r) => matches(r, a.where)) ?? null) } } as never,
      sms as never, { get: jest.fn(async () => 10) } as never, { get: jest.fn(() => 'https://iccms.example') } as never, { toManagers: jest.fn() } as never, queue as never,
    );
    return { svc, db, sms, queue, expiresInMs };
  }

  it('stores only the SHA-256 of the token, texts the link, schedules the timeout', async () => {
    const w = offersWorld();
    const { offer, url } = await w.svc.send({ incidentId: 'inc-1', buyerId: 'buyer-1', batchIds: ['b-1'], quantityKg: 120, cargoText: '120 kg Rohu (grade B)', etaAt: new Date() });
    const token = url.split('/offer/')[1];
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(offer.tokenHash).toBe(tokenHash(token));
    expect(JSON.stringify(w.db.diversionOffer.rows)).not.toContain(token);
    expect(w.sms.send).toHaveBeenCalledWith('+919999900201', expect.stringContaining(`https://iccms.example/offer/${token}`), { priority: 'alert' });
    expect(w.queue.add).toHaveBeenCalledWith('offer-timeout', { offerId: offer.id }, expect.objectContaining({ delay: 600_000 }));
  });

  it('a token answers once: reused → 410; expired → 410; unknown → 404', async () => {
    const w = offersWorld();
    const { url } = await w.svc.send({ incidentId: 'inc-1', buyerId: 'buyer-1', batchIds: ['b-1'], quantityKg: 120, cargoText: 'x', etaAt: new Date() });
    const token = url.split('/offer/')[1];
    expect((await w.svc.claim(token, true)).status).toBe('ACCEPTED');
    const reused = await w.svc.claim(token, false).catch((e) => e);
    expect(reused).toBeInstanceOf(AppError);
    expect([reused.code, reused.getStatus(), reused.details.status]).toEqual(['OFFER_GONE', HttpStatus.GONE, 'ACCEPTED']);

    const second = await w.svc.send({ incidentId: 'inc-1', buyerId: 'buyer-1', batchIds: ['b-1'], quantityKg: 120, cargoText: 'x', etaAt: new Date() });
    w.db.diversionOffer.rows.find((r) => r.id === second.offer.id)!.expiresAt = new Date(Date.now() - 1000);
    const expired = await w.svc.claim(second.url.split('/offer/')[1], true).catch((e) => e);
    expect([expired.code, expired.getStatus(), expired.details.status]).toEqual(['OFFER_GONE', 410, 'EXPIRED']);

    const unknown = await w.svc.claim('A'.repeat(43), true).catch((e) => e);
    expect([unknown.code, unknown.getStatus()]).toEqual(['NOT_FOUND', 404]);
    expect(await w.svc.byToken('not-a-token')).toBeNull();
  });
});
