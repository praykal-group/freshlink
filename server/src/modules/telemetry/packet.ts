import { crc32 } from 'node:zlib';

/**
 * IoT reefer packet decoding (SYN-01, Section 9.2). Two wire formats, one normalised Reading.
 *
 * JSON: {"d":"DEV-001","ts":"…Z","t":3.4,"h":88,"ax":0.01,"ay":0.02,"az":0.98,"g":1.1,"e":2.5,
 *        "lat":19.87,"lng":75.34,"r":1,"sp":2.0,"do":0,"b":81,"n":1234}
 * Binary (little-endian, 40 bytes; simulator/binary_format.md):
 *   0 u8 version=1 | 1 u8 flags (bit0 reefer_on, bit1 door_open) | 2 u16 battery×10 | 4 u32 epoch_s
 *   8 i16 temp×100 | 10 u16 hum×100 | 12 i16 ax×1000 | 14 i16 ay×1000 | 16 i16 az×1000
 *   18 u16 shock×100 | 20 u16 ethylene×100 | 22 i16 setpoint×100 | 24 i32 lat×1e6 | 28 i32 lng×1e6
 *   32 u32 seq | 36 u32 crc32(bytes 0..35)
 * The spec lists fields totalling 32 bytes for a "40-byte" packet with a CRC over 36: the 4
 * missing bytes carry a packet sequence number (D-89), used for loss counting and dedupe.
 */
export const BINARY_LENGTH = 40;
export const BINARY_VERSION = 1;

export interface Reading {
  deviceCode: string;
  ts: Date;
  seq: number | null;
  tempC: number;
  humidityPct: number | null;
  ax: number | null;
  ay: number | null;
  az: number | null;
  shockG: number | null;
  ethylenePpm: number | null;
  lat: number | null;
  lng: number | null;
  reeferOn: boolean | null;
  setpointC: number | null;
  doorOpen: boolean | null;
  batteryPct: number | null;
  format: 'json' | 'binary';
}

export type DecodeError = 'BAD_CRC' | 'BAD_LENGTH' | 'BAD_VERSION' | 'BAD_JSON' | 'OUT_OF_RANGE' | 'DEVICE_MISMATCH' | 'BAD_TIMESTAMP';

export class PacketError extends Error {
  constructor(public readonly reason: DecodeError, message: string) {
    super(message);
  }
}

/** Physical limits of the pod (Section 9.4); anything outside is a sensor fault, not a reading. */
const LIMITS = {
  tempC: [-40, 60],
  humidityPct: [0, 100],
  accel: [-16, 16],
  shockG: [0, 50],
  ethylenePpm: [0, 200],
  batteryPct: [0, 100],
  setpointC: [-40, 40],
} as const;

/** Readings more than this far in the future are clock errors; old ones are allowed (network_dropout replays). */
const MAX_FUTURE_MS = 5 * 60_000;

function inRange(v: number | null, [lo, hi]: readonly [number, number]): boolean {
  return v === null || (Number.isFinite(v) && v >= lo && v <= hi);
}

function check(r: Reading, now: Date): Reading {
  const bad =
    !inRange(r.tempC, LIMITS.tempC) ||
    !inRange(r.humidityPct, LIMITS.humidityPct) ||
    ![r.ax, r.ay, r.az].every((v) => inRange(v, LIMITS.accel)) ||
    !inRange(r.shockG, LIMITS.shockG) ||
    !inRange(r.ethylenePpm, LIMITS.ethylenePpm) ||
    !inRange(r.batteryPct, LIMITS.batteryPct) ||
    !inRange(r.setpointC, LIMITS.setpointC) ||
    !inRange(r.lat, [-90, 90]) ||
    !inRange(r.lng, [-180, 180]);
  if (bad) throw new PacketError('OUT_OF_RANGE', 'a value is outside the sensor range');
  if (Number.isNaN(r.ts.getTime()) || r.ts.getTime() - now.getTime() > MAX_FUTURE_MS) {
    throw new PacketError('BAD_TIMESTAMP', 'timestamp is invalid or in the future');
  }
  return r;
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const flag = (v: unknown): boolean | null => (v === 1 || v === true ? true : v === 0 || v === false ? false : null);

export function decodeJson(raw: Buffer | string, deviceCode: string, now = new Date()): Reading {
  let o: Record<string, unknown>;
  try {
    o = JSON.parse(typeof raw === 'string' ? raw : raw.toString('utf8'));
  } catch {
    throw new PacketError('BAD_JSON', 'not valid JSON');
  }
  if (!o || typeof o !== 'object') throw new PacketError('BAD_JSON', 'not a JSON object');
  if (typeof o.d === 'string' && o.d.toUpperCase() !== deviceCode.toUpperCase()) {
    throw new PacketError('DEVICE_MISMATCH', 'device id in the packet differs from the MQTT topic');
  }
  const t = num(o.t);
  if (t === null) throw new PacketError('BAD_JSON', 'temperature "t" is required');
  return check(
    {
      deviceCode,
      ts: new Date(typeof o.ts === 'string' || typeof o.ts === 'number' ? o.ts : NaN),
      seq: num(o.n),
      tempC: t,
      humidityPct: num(o.h),
      ax: num(o.ax),
      ay: num(o.ay),
      az: num(o.az),
      shockG: num(o.g),
      ethylenePpm: num(o.e),
      lat: num(o.lat),
      lng: num(o.lng),
      reeferOn: flag(o.r),
      setpointC: num(o.sp),
      doorOpen: flag(o.do),
      batteryPct: num(o.b),
      format: 'json',
    },
    now,
  );
}

export function decodeBinary(buf: Buffer, deviceCode: string, now = new Date()): Reading {
  if (buf.length !== BINARY_LENGTH) throw new PacketError('BAD_LENGTH', `expected ${BINARY_LENGTH} bytes, got ${buf.length}`);
  if (crc32(buf.subarray(0, 36)) !== buf.readUInt32LE(36)) throw new PacketError('BAD_CRC', 'CRC-32 mismatch');
  if (buf.readUInt8(0) !== BINARY_VERSION) throw new PacketError('BAD_VERSION', `unsupported version ${buf.readUInt8(0)}`);
  const flags = buf.readUInt8(1);
  return check(
    {
      deviceCode,
      ts: new Date(buf.readUInt32LE(4) * 1000),
      seq: buf.readUInt32LE(32),
      tempC: buf.readInt16LE(8) / 100,
      humidityPct: buf.readUInt16LE(10) / 100,
      ax: buf.readInt16LE(12) / 1000,
      ay: buf.readInt16LE(14) / 1000,
      az: buf.readInt16LE(16) / 1000,
      shockG: buf.readUInt16LE(18) / 100,
      ethylenePpm: buf.readUInt16LE(20) / 100,
      setpointC: buf.readInt16LE(22) / 100,
      lat: buf.readInt32LE(24) / 1e6,
      lng: buf.readInt32LE(28) / 1e6,
      reeferOn: (flags & 1) === 1,
      doorOpen: (flags & 2) === 2,
      batteryPct: buf.readUInt16LE(2) / 10,
      format: 'binary',
    },
    now,
  );
}

/** JSON starts with "{" (after optional whitespace); everything else is treated as binary. */
export function decode(payload: Buffer, deviceCode: string, now = new Date()): Reading {
  const first = payload.find((b) => b !== 0x20 && b !== 0x0a && b !== 0x0d && b !== 0x09);
  return first === 0x7b ? decodeJson(payload, deviceCode, now) : decodeBinary(payload, deviceCode, now);
}

/** Encoder (tests and tools). Mirrors simulator/sim.py `encode_binary`. */
export function encodeBinary(r: Omit<Reading, 'deviceCode' | 'format'> & { seq: number }): Buffer {
  const b = Buffer.alloc(BINARY_LENGTH);
  b.writeUInt8(BINARY_VERSION, 0);
  b.writeUInt8((r.reeferOn ? 1 : 0) | (r.doorOpen ? 2 : 0), 1);
  b.writeUInt16LE(Math.round((r.batteryPct ?? 0) * 10), 2);
  b.writeUInt32LE(Math.floor(r.ts.getTime() / 1000), 4);
  b.writeInt16LE(Math.round(r.tempC * 100), 8);
  b.writeUInt16LE(Math.round((r.humidityPct ?? 0) * 100), 10);
  b.writeInt16LE(Math.round((r.ax ?? 0) * 1000), 12);
  b.writeInt16LE(Math.round((r.ay ?? 0) * 1000), 14);
  b.writeInt16LE(Math.round((r.az ?? 0) * 1000), 16);
  b.writeUInt16LE(Math.round((r.shockG ?? 0) * 100), 18);
  b.writeUInt16LE(Math.round((r.ethylenePpm ?? 0) * 100), 20);
  b.writeInt16LE(Math.round((r.setpointC ?? 0) * 100), 22);
  b.writeInt32LE(Math.round((r.lat ?? 0) * 1e6), 24);
  b.writeInt32LE(Math.round((r.lng ?? 0) * 1e6), 28);
  b.writeUInt32LE(r.seq >>> 0, 32);
  b.writeUInt32LE(crc32(b.subarray(0, 36)), 36);
  return b;
}
