/**
 * Idempotent dev seed (Section 7). Safe to run repeatedly: every row is upserted on a natural key.
 *   npx prisma db seed
 * Dev phone numbers come from env (SEED_*_PHONE) so real test SIMs can be used for OTP login.
 * Product limits are indicative reference values for the prototype; see docs/DATABASE.md.
 */
import { createHash } from 'node:crypto';
import {
  BuyerType,
  Grade,
  Prisma,
  PrismaClient,
  ProductCategory,
  SiteType,
  StorageUnitType,
  UserRole,
} from '@prisma/client';

const prisma = new PrismaClient();
const env = (k: string, d: string) => process.env[k] || d;
const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

// ── Sites (Chh. Sambhajinagar region + one coastal dock) ──
const sites = [
  { code: 'DCK-PTN', name: 'Paithan (Jayakwadi) Fish Landing', type: SiteType.DOCK, lat: 19.4769, lng: 75.3859, address: 'Paithan, Chh. Sambhajinagar' },
  { code: 'DCK-RTN', name: 'Mirkarwada Harbour', type: SiteType.DOCK, lat: 16.9902, lng: 73.2796, address: 'Ratnagiri' },
  { code: 'FRM-GNG', name: 'Gangapur Farm Gate', type: SiteType.FARM_GATE, lat: 19.6966, lng: 75.0103, address: 'Gangapur, Chh. Sambhajinagar' },
  { code: 'CST-WLJ', name: 'Waluj Cold Storage', type: SiteType.COLD_STORAGE, lat: 19.8434, lng: 75.2355, address: 'Waluj MIDC, Chh. Sambhajinagar' },
  { code: 'DC-CSN', name: 'Chh. Sambhajinagar Distribution Centre', type: SiteType.DISTRIBUTION_CENTRE, lat: 19.8762, lng: 75.3433, address: 'Chikalthana, Chh. Sambhajinagar' },
  { code: 'DC-JLN', name: 'Jalna Distribution Centre', type: SiteType.DISTRIBUTION_CENTRE, lat: 19.8347, lng: 75.8816, address: 'Jalna' },
];

// ── Storage units per site ──
const storageUnits: Array<{ site: string; code: string; type: StorageUnitType; min: number; max: number; cap: number }> = [
  { site: 'DCK-PTN', code: 'BC-1', type: StorageUnitType.BLAST_CHILLER, min: -1, max: 2, cap: 2000 },
  { site: 'DCK-RTN', code: 'BC-1', type: StorageUnitType.BLAST_CHILLER, min: -1, max: 2, cap: 5000 },
  { site: 'DCK-RTN', code: 'CR-1', type: StorageUnitType.COLD_ROOM, min: 0, max: 4, cap: 3000 },
  { site: 'FRM-GNG', code: 'RC-1', type: StorageUnitType.RIPENING_CHAMBER, min: 12, max: 18, cap: 4000 },
  { site: 'FRM-GNG', code: 'CR-1', type: StorageUnitType.COLD_ROOM, min: 0, max: 4, cap: 2000 },
  { site: 'CST-WLJ', code: 'BC-1', type: StorageUnitType.BLAST_CHILLER, min: -1, max: 2, cap: 8000 },
  { site: 'CST-WLJ', code: 'RC-1', type: StorageUnitType.RIPENING_CHAMBER, min: 12, max: 18, cap: 8000 },
  { site: 'CST-WLJ', code: 'CR-1', type: StorageUnitType.COLD_ROOM, min: 0, max: 4, cap: 10000 },
  { site: 'DC-CSN', code: 'CR-1', type: StorageUnitType.COLD_ROOM, min: 0, max: 4, cap: 6000 },
  { site: 'DC-CSN', code: 'RC-1', type: StorageUnitType.RIPENING_CHAMBER, min: 12, max: 18, cap: 4000 },
  { site: 'DC-JLN', code: 'CR-1', type: StorageUnitType.COLD_ROOM, min: 0, max: 4, cap: 4000 },
];

// ── Products: limits are indicative prototype values (°C, %RH, ppm, g, hours) ──
type P = Omit<Prisma.ProductCreateInput, 'id' | 'batches' | 'forecasts' | 'orders'>;
const F = ProductCategory.FISH;
const V = ProductCategory.PRODUCE;
const products: P[] = [
  { code: 'ROHU', name: 'Rohu', nameHi: 'रोहू', nameMr: 'रोहू', category: F, isClimacteric: false, isEthyleneSensitive: false, safeTempMin: 0, safeTempMax: 4, humidityMin: 85, humidityMax: 98, ethyleneMaxPpm: null, shockMaxG: 3, baseShelfLifeH: 192, q10: 2.5, unitPrice: 180 },
  { code: 'POMFRET', name: 'Pomfret', nameHi: 'पापलेट', nameMr: 'पापलेट', category: F, isClimacteric: false, isEthyleneSensitive: false, safeTempMin: 0, safeTempMax: 4, humidityMin: 85, humidityMax: 98, ethyleneMaxPpm: null, shockMaxG: 3, baseShelfLifeH: 240, q10: 2.5, unitPrice: 650 },
  { code: 'PRAWNS', name: 'Prawns', nameHi: 'झींगा', nameMr: 'कोळंबी', category: F, isClimacteric: false, isEthyleneSensitive: false, safeTempMin: 0, safeTempMax: 2, humidityMin: 85, humidityMax: 98, ethyleneMaxPpm: null, shockMaxG: 2.5, baseShelfLifeH: 96, q10: 3, unitPrice: 450 },
  { code: 'SURMAI', name: 'Surmai (King Mackerel)', nameHi: 'सुरमई', nameMr: 'सुरमई', category: F, isClimacteric: false, isEthyleneSensitive: false, safeTempMin: 0, safeTempMax: 4, humidityMin: 85, humidityMax: 98, ethyleneMaxPpm: null, shockMaxG: 3, baseShelfLifeH: 240, q10: 2.5, unitPrice: 700 },
  { code: 'BANANA', name: 'Banana', nameHi: 'केला', nameMr: 'केळी', category: V, isClimacteric: true, isEthyleneSensitive: true, safeTempMin: 13, safeTempMax: 15, humidityMin: 90, humidityMax: 95, ethyleneMaxPpm: 1, shockMaxG: 2, baseShelfLifeH: 336, q10: 2, unitPrice: 40 },
  { code: 'TOMATO', name: 'Tomato', nameHi: 'टमाटर', nameMr: 'टोमॅटो', category: V, isClimacteric: true, isEthyleneSensitive: true, safeTempMin: 10, safeTempMax: 13, humidityMin: 85, humidityMax: 95, ethyleneMaxPpm: 1, shockMaxG: 2, baseShelfLifeH: 240, q10: 2, unitPrice: 25 },
  { code: 'MANGO', name: 'Mango', nameHi: 'आम', nameMr: 'आंबा', category: V, isClimacteric: true, isEthyleneSensitive: true, safeTempMin: 12, safeTempMax: 14, humidityMin: 85, humidityMax: 90, ethyleneMaxPpm: 1, shockMaxG: 2, baseShelfLifeH: 336, q10: 2.2, unitPrice: 120 },
  { code: 'SPINACH', name: 'Spinach', nameHi: 'पालक', nameMr: 'पालक', category: V, isClimacteric: false, isEthyleneSensitive: true, safeTempMin: 0, safeTempMax: 2, humidityMin: 95, humidityMax: 100, ethyleneMaxPpm: 0.1, shockMaxG: 3, baseShelfLifeH: 168, q10: 3, unitPrice: 30 },
  { code: 'ONION', name: 'Onion', nameHi: 'प्याज', nameMr: 'कांदा', category: V, isClimacteric: false, isEthyleneSensitive: false, safeTempMin: 0, safeTempMax: 4, humidityMin: 65, humidityMax: 75, ethyleneMaxPpm: null, shockMaxG: 5, baseShelfLifeH: 2000, q10: 1.8, unitPrice: 20 },
  { code: 'GRAPES', name: 'Grapes', nameHi: 'अंगूर', nameMr: 'द्राक्षे', category: V, isClimacteric: false, isEthyleneSensitive: true, safeTempMin: -1, safeTempMax: 2, humidityMin: 90, humidityMax: 95, ethyleneMaxPpm: 0.5, shockMaxG: 2, baseShelfLifeH: 1000, q10: 2.5, unitPrice: 80 },
];

// ── Users (phones overridable by env) ──
const users: Array<{ key: string; name: string; role: UserRole; phone: string; email?: string; site?: string }> = [
  { key: 'ADMIN', name: 'Dev Admin', role: UserRole.ADMIN, phone: '+919999900001', email: env('SEED_ADMIN_EMAIL', 'admin@iccms.test') },
  { key: 'MANAGER', name: 'Dev Manager', role: UserRole.MANAGER, phone: '+919999900002', email: env('SEED_MANAGER_EMAIL', 'manager@iccms.test'), site: 'DC-CSN' },
  { key: 'DRIVER1', name: 'Dev Driver 1', role: UserRole.DRIVER, phone: '+919999900011', site: 'DC-CSN' },
  { key: 'DRIVER2', name: 'Dev Driver 2', role: UserRole.DRIVER, phone: '+919999900012', site: 'DC-JLN' },
  { key: 'OPERATOR1', name: 'Dev Operator 1', role: UserRole.OPERATOR, phone: '+919999900021', site: 'DCK-PTN' },
  { key: 'OPERATOR2', name: 'Dev Operator 2', role: UserRole.OPERATOR, phone: '+919999900022', site: 'FRM-GNG' },
];

const vehicles = [
  { regNo: 'MH20-RF-1001', capacityKg: 3000, min: -5, max: 15, home: 'DC-CSN' },
  { regNo: 'MH20-RF-1002', capacityKg: 5000, min: -5, max: 15, home: 'DC-CSN' },
  { regNo: 'MH21-RF-2001', capacityKg: 3000, min: -5, max: 15, home: 'DC-JLN' },
];

const allDays = (open: string, close: string) =>
  Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((d) => [d, [[open, close]]]));

const buyers: Array<{ name: string; type: BuyerType; phone: string; lat: number; lng: number; products: string[]; minGrade: Grade; discountPct: number; capacityKg?: number; hours: Record<string, string[][]> }> = [
  { name: 'Waluj Cold Storage (buyer desk)', type: BuyerType.COLD_STORAGE, phone: '+919999900101', lat: 19.8434, lng: 75.2355, products: ['ROHU', 'POMFRET', 'PRAWNS', 'SURMAI', 'BANANA', 'TOMATO', 'MANGO', 'SPINACH', 'ONION', 'GRAPES'], minGrade: Grade.C, discountPct: 5, capacityKg: 8000, hours: allDays('00:00', '23:59') },
  { name: 'Jalna Agro Cold Chain', type: BuyerType.COLD_STORAGE, phone: '+919999900102', lat: 19.8410, lng: 75.8700, products: ['BANANA', 'TOMATO', 'MANGO', 'ONION', 'GRAPES', 'ROHU'], minGrade: Grade.C, discountPct: 6, capacityKg: 6000, hours: allDays('06:00', '22:00') },
  { name: 'Shendra Fish Processing', type: BuyerType.PROCESSING, phone: '+919999900103', lat: 19.8640, lng: 75.4600, products: ['ROHU', 'POMFRET', 'PRAWNS', 'SURMAI'], minGrade: Grade.C, discountPct: 30, hours: allDays('07:00', '19:00') },
  { name: 'Paithan Gate Canning Unit', type: BuyerType.CANNING, phone: '+919999900104', lat: 19.8820, lng: 75.3300, products: ['TOMATO', 'MANGO', 'GRAPES'], minGrade: Grade.C, discountPct: 35, hours: allDays('08:00', '18:00') },
  { name: 'Jadhavwadi Mandi Traders', type: BuyerType.LOCAL_MARKET, phone: '+919999900105', lat: 19.9050, lng: 75.3200, products: ['BANANA', 'TOMATO', 'SPINACH', 'ONION', 'GRAPES', 'MANGO'], minGrade: Grade.B, discountPct: 15, hours: allDays('04:00', '14:00') },
  { name: 'CIDCO Discount Mart', type: BuyerType.DISCOUNT_RETAIL, phone: '+919999900106', lat: 19.8780, lng: 75.3650, products: ['BANANA', 'TOMATO', 'SPINACH', 'ONION', 'ROHU'], minGrade: Grade.B, discountPct: 20, hours: allDays('09:00', '21:00') },
];

const appConfig: Record<string, Prisma.InputJsonValue> = {
  persistMinutes: 15,
  ackMinutes: 5,
  offerMinutes: 10,
  safetyMarginH: 2,
  driftSlopeMax: 0.5,
  rescueRadiusKm: 30,
  emissionFactorKgPerKm: { value: 0.9, source: 'PLACEHOLDER - replace with sourced factor' },
  gpsIntervalSec: 30,
  editWindowMin: 30,
  featureFlags: {},
};

async function main() {
  const siteId: Record<string, string> = {};
  for (const s of sites) {
    const row = await prisma.site.upsert({ where: { code: s.code }, update: s, create: s });
    siteId[s.code] = row.id;
  }

  for (const u of storageUnits) {
    const data = { type: u.type, tempMin: u.min, tempMax: u.max, capacityKg: u.cap };
    await prisma.storageUnit.upsert({
      where: { siteId_code: { siteId: siteId[u.site], code: u.code } },
      update: data,
      create: { ...data, siteId: siteId[u.site], code: u.code },
    });
  }

  const productId: Record<string, string> = {};
  for (const p of products) {
    const row = await prisma.product.upsert({ where: { code: p.code }, update: p, create: p });
    productId[p.code] = row.id;
  }

  for (const u of users) {
    const phone = env(`SEED_${u.key}_PHONE`, u.phone);
    const data = {
      name: u.name,
      role: u.role,
      email: u.email?.toLowerCase() ?? null,
      authMethod: u.email ? ('EMAIL' as const) : ('PHONE' as const),
      siteId: u.site ? siteId[u.site] : null,
      status: 'ACTIVE' as const,
    };
    await prisma.user.upsert({ where: { phone }, update: data, create: { ...data, phone } });
  }

  const deviceSecret = env('SEED_DEVICE_SECRET', 'dev-device-secret');
  for (const [i, v] of vehicles.entries()) {
    const data = { capacityKg: v.capacityKg, reeferMinTemp: v.min, reeferMaxTemp: v.max, homeSiteId: siteId[v.home] };
    const vehicle = await prisma.vehicle.upsert({ where: { regNo: v.regNo }, update: data, create: { ...data, regNo: v.regNo } });
    const code = `DEV-${String(i + 1).padStart(3, '0')}`;
    const dev = { vehicleId: vehicle.id, mqttUsername: code.toLowerCase(), secretHash: sha256(`${code}:${deviceSecret}`) };
    await prisma.iotDevice.upsert({ where: { deviceCode: code }, update: dev, create: { ...dev, deviceCode: code } });
  }

  for (const b of buyers) {
    const data = {
      name: b.name,
      type: b.type,
      phone: b.phone,
      lat: b.lat,
      lng: b.lng,
      acceptedProductIds: b.products.map((c) => productId[c]),
      minGrade: b.minGrade,
      discountPct: b.discountPct,
      capacityKg: b.capacityKg ?? null,
      openingHours: b.hours,
    };
    const existing = await prisma.backupBuyer.findFirst({ where: { name: b.name }, select: { id: true } });
    if (existing) await prisma.backupBuyer.update({ where: { id: existing.id }, data });
    else await prisma.backupBuyer.create({ data });
  }

  // Config is only inserted when missing, so values an admin changed are never overwritten.
  for (const [key, value] of Object.entries(appConfig)) {
    await prisma.appConfig.upsert({ where: { key }, update: {}, create: { key, value } });
  }

  const counts = await Promise.all([
    prisma.site.count(), prisma.storageUnit.count(), prisma.product.count(), prisma.user.count(),
    prisma.vehicle.count(), prisma.iotDevice.count(), prisma.backupBuyer.count(), prisma.appConfig.count(),
  ]);
  console.log('seed done', Object.fromEntries(
    ['sites', 'storageUnits', 'products', 'users', 'vehicles', 'iotDevices', 'buyers', 'appConfig'].map((k, i) => [k, counts[i]]),
  ));
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
