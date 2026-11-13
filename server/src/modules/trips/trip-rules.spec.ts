import { allowedSetpoint, canDo, co2Kg, mapsLink, preCheckProblems } from './trip-rules';

describe('trip rules', () => {
  const reefer = { min: -5, max: 15 };

  it('allowed setpoint = intersection of the cargo safe ranges, clipped to the reefer', () => {
    expect(allowedSetpoint([{ min: 0, max: 4 }, { min: 0, max: 2 }], reefer)).toEqual({ min: 0, max: 2 });
    expect(allowedSetpoint([], reefer)).toEqual(reefer);
    expect(allowedSetpoint([{ min: 12, max: 20 }], reefer)).toEqual({ min: 12, max: 15 });
  });

  it('fish + banana on one truck has no common temperature', () => {
    expect(allowedSetpoint([{ min: 0, max: 4 }, { min: 13, max: 15 }], reefer)).toBeNull();
  });

  it('pre-check (DA-FR-03): reefer on, setpoint in range, doors closed', () => {
    const range = { min: 0, max: 4 };
    expect(preCheckProblems({ reeferOn: true, setpointC: 2, doorsClosed: true }, range)).toEqual([]);
    expect(preCheckProblems({ reeferOn: false, setpointC: 8, doorsClosed: false }, range).map((p) => p.code)).toEqual([
      'REEFER_OFF', 'DOORS_OPEN', 'SETPOINT_OUT_OF_RANGE',
    ]);
    expect(preCheckProblems({ reeferOn: true, setpointC: 2, doorsClosed: true }, null).map((p) => p.code)).toEqual(['INCOMPATIBLE_CARGO']);
  });

  it('status machine: start only after pre-check, PoD only in progress', () => {
    expect(canDo('ASSIGNED', 'start')).toBe(false);
    expect(canDo('PRE_CHECK_DONE', 'start')).toBe(true);
    expect(canDo('PRE_CHECK_DONE', 'pod')).toBe(false);
    expect(canDo('IN_PROGRESS', 'pod')).toBe(true);
    expect(canDo('IN_PROGRESS', 'load')).toBe(false);
  });

  it('CO2 = distance × factor (SYN-16)', () => {
    expect(co2Kg(120.5, 0.9)).toBe(108.45);
  });

  it('maps link for SOS', () => {
    expect(mapsLink(19.8762, 75.3433)).toBe('https://maps.google.com/?q=19.876200,75.343300');
  });
});
