import { decode, decodeBinary, decodeJson, encodeBinary, PacketError } from './packet';

// M8 / SYN-01: JSON + binary packets; "binary CRC failure dropped".
const NOW = new Date('2026-11-14T05:00:00Z');

function reason(fn: () => unknown): string {
  try {
    fn();
    return 'OK';
  } catch (e) {
    return e instanceof PacketError ? e.reason : 'OTHER';
  }
}

describe('binary packet', () => {
  it('decodes a packet produced by the Python simulator (cross-language fixture)', () => {
    // simulator/sim.py encode_binary(), DEV-001, reefer_failure tick 1 (dry run)
    const hex = '01017703eb1bf86ac80023231a000400bb0308001700c800743a2b01b3c77d04010000001d4b5250';
    const r = decodeBinary(Buffer.from(hex, 'hex'), 'DEV-001', new Date(0x6af81beb * 1000 + 1000));
    expect(r).toMatchObject({
      deviceCode: 'DEV-001', format: 'binary', seq: 1, reeferOn: true, doorOpen: false, batteryPct: 88.7,
      tempC: 2, humidityPct: 89.95, ax: 0.026, ay: 0.004, az: 0.955, shockG: 0.08, ethylenePpm: 0.23, setpointC: 2,
      lat: 19.610228, lng: 75.351987,
    });
    expect(r.ts.getTime()).toBe(0x6af81beb * 1000);
  });

  const reading = {
    ts: new Date('2026-11-14T04:59:00Z'), seq: 42, tempC: -1.25, humidityPct: 91.5, ax: 0.01, ay: -0.02, az: 0.98, shockG: 1.1,
    ethylenePpm: 2.5, lat: 19.876213, lng: 75.343301, reeferOn: true, setpointC: 2, doorOpen: true, batteryPct: 81.3,
  };

  it('round-trips through encodeBinary (40 bytes, negative temps, both flags)', () => {
    const buf = encodeBinary(reading);
    expect(buf.length).toBe(40);
    expect(decodeBinary(buf, 'DEV-002', NOW)).toMatchObject({ ...reading, deviceCode: 'DEV-002' });
  });

  it('drops a packet whose CRC does not match (one flipped bit)', () => {
    const buf = encodeBinary(reading);
    buf[8] ^= 0x01; // temperature byte
    expect(reason(() => decodeBinary(buf, 'DEV-002', NOW))).toBe('BAD_CRC');
  });

  it('rejects wrong length and unknown version', () => {
    expect(reason(() => decodeBinary(Buffer.alloc(39), 'D', NOW))).toBe('BAD_LENGTH');
    const v2 = encodeBinary(reading);
    v2[0] = 2;
    // fix the CRC so only the version is wrong
    const { crc32 } = jest.requireActual('node:zlib') as typeof import('node:zlib');
    v2.writeUInt32LE(crc32(v2.subarray(0, 36)), 36);
    expect(reason(() => decodeBinary(v2, 'D', NOW))).toBe('BAD_VERSION');
  });
});

describe('JSON packet', () => {
  const json = { d: 'DEV-001', ts: '2026-11-14T04:59:00Z', t: 3.4, h: 88, ax: 0.01, ay: 0.02, az: 0.98, g: 1.1, e: 2.5, lat: 19.87, lng: 75.34, r: 1, sp: 2.0, do: 0, b: 81, n: 7 };

  it('decodes the Section 9.2 example', () => {
    expect(decodeJson(JSON.stringify(json), 'DEV-001', NOW)).toMatchObject({ tempC: 3.4, humidityPct: 88, reeferOn: true, doorOpen: false, seq: 7, format: 'json' });
  });

  it('device id must match the MQTT topic', () => {
    expect(reason(() => decodeJson(JSON.stringify({ ...json, d: 'DEV-999' }), 'DEV-001', NOW))).toBe('DEVICE_MISMATCH');
  });

  it('rejects impossible values, future timestamps and missing temperature', () => {
    expect(reason(() => decodeJson(JSON.stringify({ ...json, t: 85 }), 'DEV-001', NOW))).toBe('OUT_OF_RANGE');
    expect(reason(() => decodeJson(JSON.stringify({ ...json, h: 120 }), 'DEV-001', NOW))).toBe('OUT_OF_RANGE');
    expect(reason(() => decodeJson(JSON.stringify({ ...json, ts: '2026-11-14T06:00:00Z' }), 'DEV-001', NOW))).toBe('BAD_TIMESTAMP');
    expect(reason(() => decodeJson(JSON.stringify({ ...json, t: undefined }), 'DEV-001', NOW))).toBe('BAD_JSON');
    expect(reason(() => decodeJson('{not json', 'DEV-001', NOW))).toBe('BAD_JSON');
  });

  it('accepts old timestamps (network_dropout burst replays)', () => {
    expect(reason(() => decodeJson(JSON.stringify({ ...json, ts: '2026-11-13T22:00:00Z' }), 'DEV-001', NOW))).toBe('OK');
  });

  it('decode() picks the format from the first byte', () => {
    expect(decode(Buffer.from(` ${JSON.stringify(json)}`), 'DEV-001', NOW).format).toBe('json');
    expect(decode(encodeBinary({ ...json, ts: NOW, seq: 1, tempC: 2, humidityPct: 90, ax: 0, ay: 0, az: 1, shockG: 0, ethylenePpm: 0, lat: 19, lng: 75, reeferOn: true, setpointC: 2, doorOpen: false, batteryPct: 80 } as never), 'DEV-001', NOW).format).toBe('binary');
  });
});
