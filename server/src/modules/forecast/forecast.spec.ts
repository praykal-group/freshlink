import { AppError } from '../../common/errors/app-error';
import { MlCallError } from '../../infra/ml/ml-client.service';
import { msUntilNextIst } from '../../workers/jobs/forecast.job';
import { ForecastService, istTomorrow, latestPerDay } from './forecast.service';

describe('forecast helpers', () => {
  it('istTomorrow uses the India calendar day', () => {
    expect(istTomorrow(new Date('2026-11-13T10:00:00Z'))).toBe('2026-11-14'); // 15:30 IST
    expect(istTomorrow(new Date('2026-11-13T20:00:00Z'))).toBe('2026-11-15'); // 01:30 IST on the 14th
  });

  it('latestPerDay keeps the newest run per site/product/day', () => {
    const d = (s: string) => new Date(`${s}T00:00:00Z`);
    const rows = [
      { siteId: 's', productId: 'p', forecastDate: d('2026-11-14'), runId: 'new' },
      { siteId: 's', productId: 'p', forecastDate: d('2026-11-15'), runId: 'new' },
      { siteId: 's', productId: 'p', forecastDate: d('2026-11-14'), runId: 'old' },
    ];
    expect(latestPerDay(rows).map((r) => r.runId)).toEqual(['new', 'new']);
  });

  it('msUntilNextIst: next 02:00 India time', () => {
    // 2026-11-13 19:00 UTC = 00:30 IST on the 14th → 1.5 h to 02:00
    expect(msUntilNextIst(new Date('2026-11-13T19:00:00Z'))).toBe(90 * 60_000);
    // 21:00 UTC = 02:30 IST → 23.5 h
    expect(msUntilNextIst(new Date('2026-11-13T21:00:00Z'))).toBe(23.5 * 3_600_000);
  });
});

function setup(ml: jest.Mock) {
  const prisma = {
    site: { findMany: jest.fn().mockResolvedValue([{ id: 'dc1', lat: 19.8, lng: 75.3 }]) },
    product: { findMany: jest.fn().mockResolvedValue([{ id: 'p1' }, { id: 'p2' }]) },
    demandForecast: { createMany: jest.fn(async ({ data }) => ({ count: data.length })) },
  };
  return { service: new ForecastService(prisma as never, { post: ml } as never), prisma };
}

describe('ForecastService.run', () => {
  it('forecasts distribution centres × active products and stores the rows under one run id', async () => {
    const rows = ['p1', 'p2'].flatMap((p) =>
      Array.from({ length: 7 }, (_, i) => ({ siteId: 'dc1', productId: p, date: `2026-11-${14 + i}`, predictedKg: 100, lowerKg: 85, upperKg: 115, historySource: 'SIMULATED' })),
    );
    const ml = jest.fn().mockResolvedValue({ runId: 'run-1', rows, modelVersion: 'forecast:v1', method: 'ENSEMBLE', latencyMs: 40 });
    const { service, prisma } = setup(ml);
    const r = await service.run({ startDate: '2026-11-14' });

    expect(prisma.site.findMany.mock.calls[0][0].where).toMatchObject({ active: true, type: 'DISTRIBUTION_CENTRE' });
    expect(ml).toHaveBeenCalledWith(
      '/v1/forecast/run',
      expect.objectContaining({ siteIds: ['dc1'], productIds: ['p1', 'p2'], startDate: '2026-11-14', horizonDays: 7, siteCoords: { dc1: { lat: 19.8, lng: 75.3 } } }),
      60_000,
    );
    const data = prisma.demandForecast.createMany.mock.calls[0][0].data;
    expect(data).toHaveLength(14);
    expect(data[0]).toMatchObject({ siteId: 'dc1', productId: 'p1', runId: 'run-1', modelVersion: 'forecast:v1', forecastDate: new Date('2026-11-14T00:00:00Z') });
    expect(r).toMatchObject({ runId: 'run-1', rows: 14, sites: 1, products: 2, method: 'ENSEMBLE' });
  });

  it('ML failure → 503 FORECAST_UNAVAILABLE, nothing stored', async () => {
    const { service, prisma } = setup(jest.fn().mockRejectedValue(new MlCallError(0, 'ML_UNREACHABLE', 'x')));
    const err = await service.run().catch((e) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).code).toBe('FORECAST_UNAVAILABLE');
    expect(prisma.demandForecast.createMany).not.toHaveBeenCalled();
  });

  it('background job: one at a time, status becomes DONE', async () => {
    let release!: () => void;
    const ml = jest.fn(() => new Promise((res) => (release = () => res({ runId: 'r', rows: [], modelVersion: 'm', method: 'SEASONAL_NAIVE', latencyMs: 1 }))));
    const { service } = setup(ml as never);
    const job = service.start({});
    expect(job.status).toBe('RUNNING');
    expect(() => service.start({})).toThrow(AppError);
    await new Promise((r) => setImmediate(r));
    release();
    await new Promise((r) => setImmediate(r));
    await new Promise((r) => setImmediate(r));
    expect(service.job(job.id).status).toBe('DONE');
  });
});
