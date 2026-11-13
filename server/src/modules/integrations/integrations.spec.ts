import { AppError } from '../../common/errors/app-error';
import { parseCsv } from '../orders/csv';
import { csvRowToOrder } from '../orders/orders.controller';
import { OrdersService } from '../orders/orders.service';
import { IntegrationsController } from './integrations.controller';
import { hashKey, sign, verifySignature } from './signature';

const KEY = 'iccms_test_key_0123456789abcdefghijklmnop';
const order = {
  externalRef: 'ERP-1001', sourceSiteCode: 'DCK-PTN', destinationSiteCode: 'DC-CSN', productCode: 'ROHU',
  quantityKg: 250, windowStart: '2026-11-14T00:30:00Z', windowEnd: '2026-11-14T12:30:00Z',
};

describe('ERP signature (SYN-02)', () => {
  const body = JSON.stringify({ orders: [order] });

  it('accepts the right HMAC, with or without the sha256= prefix', () => {
    expect(verifySignature(body, KEY, sign(body, KEY))).toBe(true);
    expect(verifySignature(body, KEY, `sha256=${sign(body, KEY)}`)).toBe(true);
  });

  it('rejects a tampered body, another key, garbage and a missing header', () => {
    expect(verifySignature(body.replace('250', '2500'), KEY, sign(body, KEY))).toBe(false);
    expect(verifySignature(body, KEY, sign(body, 'other-key'))).toBe(false);
    expect(verifySignature(body, KEY, 'not-hex')).toBe(false);
    expect(verifySignature(body, KEY, undefined)).toBe(false);
  });
});

describe('IntegrationsController', () => {
  const body = JSON.stringify({ orders: [order] });
  function setup(client: unknown = { name: 'ERP', active: true, scopes: ['orders:write'], keyHash: hashKey(KEY) }) {
    const prisma = { integrationClient: { findUnique: jest.fn().mockResolvedValue(client) } };
    const orders = { importMany: jest.fn().mockResolvedValue([{ index: 0, status: 'CREATED' }]) };
    return { ctl: new IntegrationsController(prisma as never, orders as never), prisma, orders };
  }
  const req = (headers: Record<string, string>, raw = body, parsed: unknown = JSON.parse(body)) =>
    ({ headers, rawBody: Buffer.from(raw), body: parsed }) as never;

  async function code(p: Promise<unknown>) {
    try {
      await p;
      return 'OK';
    } catch (e) {
      return e instanceof AppError ? `${e.getStatus()} ${e.code}` : String(e);
    }
  }

  it('bad HMAC → 401 and nothing imported', async () => {
    const s = setup();
    expect(await code(s.ctl.receiveOrders(req({ 'x-api-key': KEY, 'x-signature': sign(body, 'wrong') })))).toBe('401 INVALID_SIGNATURE');
    expect(s.orders.importMany).not.toHaveBeenCalled();
  });

  it('unknown or disabled key → 401; looks the key up by its sha256 only', async () => {
    const s = setup(null);
    expect(await code(s.ctl.receiveOrders(req({ 'x-api-key': KEY, 'x-signature': sign(body, KEY) })))).toBe('401 INVALID_API_KEY');
    expect(s.prisma.integrationClient.findUnique).toHaveBeenCalledWith({ where: { keyHash: hashKey(KEY) } });
    expect(await code(setup({ active: false }).ctl.receiveOrders(req({ 'x-api-key': KEY, 'x-signature': sign(body, KEY) })))).toBe('401 INVALID_API_KEY');
  });

  it('authenticates before validating: an invalid unsigned body is 401, not 400', async () => {
    const bad = JSON.stringify({ nope: true });
    expect(await code(setup().ctl.receiveOrders(req({ 'x-api-key': KEY, 'x-signature': 'f'.repeat(64) }, bad, { nope: true })))).toBe('401 INVALID_SIGNATURE');
  });

  it('valid signature + scope → orders imported as ERP', async () => {
    const s = setup();
    await s.ctl.receiveOrders(req({ 'x-api-key': KEY, 'x-signature': sign(body, KEY) }));
    expect(s.orders.importMany).toHaveBeenCalledWith([expect.objectContaining({ externalRef: 'ERP-1001' })], 'ERP');
  });

  it('missing scope → 403', async () => {
    const s = setup({ name: 'x', active: true, scopes: [] });
    expect(await code(s.ctl.receiveOrders(req({ 'x-api-key': KEY, 'x-signature': sign(body, KEY) })))).toBe('403 FORBIDDEN_SCOPE');
  });
});

describe('OrdersService import idempotency', () => {
  it('a duplicate externalRef returns the existing order without creating one', async () => {
    const prisma = {
      dispatchOrder: { findUnique: jest.fn().mockResolvedValue({ id: 'o1', code: 'ORD-20261114-0001' }), create: jest.fn() },
      $transaction: jest.fn(),
    };
    const svc = new OrdersService(prisma as never, {} as never, { publish: jest.fn() } as never);
    const [r] = await svc.importMany([order], 'ERP');
    expect(r).toMatchObject({ status: 'DUPLICATE', orderId: 'o1', code: 'ORD-20261114-0001' });
    expect(prisma.dispatchOrder.findUnique).toHaveBeenCalledWith({ where: { origin_externalRef: { origin: 'ERP', externalRef: 'ERP-1001' } } });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('invalid rows are rejected individually with reasons', async () => {
    const svc = new OrdersService({ dispatchOrder: { findUnique: jest.fn() } } as never, {} as never, {} as never);
    const [r] = await svc.importMany([{ ...order, quantityKg: -5 }], 'CSV');
    expect(r).toMatchObject({ status: 'REJECTED', error: { code: 'VALIDATION_FAILED' } });
  });
});

describe('CSV import parsing', () => {
  it('handles a BOM, CRLF, quoted commas and escaped quotes; maps columns', () => {
    const csv =
      '﻿external_ref,source_site_code,destination_site_code,product_code,quantity_kg,window_start,window_end\r\n' +
      '"CSV-1, part A",dck-ptn,DC-CSN,rohu,120.5,2026-11-14T00:30:00Z,2026-11-14T12:30:00Z\r\n' +
      '"CSV-""2""",DCK-PTN,DC-JLN,TOMATO,80,2026-11-14T00:30:00Z,2026-11-14T12:30:00Z\n\n';
    const rows = parseCsv(csv);
    expect(rows).toHaveLength(2);
    expect(csvRowToOrder(rows[0])).toEqual({
      externalRef: 'CSV-1, part A', sourceSiteCode: 'DCK-PTN', destinationSiteCode: 'DC-CSN', productCode: 'ROHU',
      quantityKg: 120.5, windowStart: '2026-11-14T00:30:00Z', windowEnd: '2026-11-14T12:30:00Z',
    });
    expect(rows[1].external_ref).toBe('CSV-"2"');
  });
});
