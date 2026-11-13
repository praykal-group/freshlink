import { eventDetail, EVENT_LABELS } from './trace-view';
import { TRACE_EVENT_TYPES } from '../trace/trace.service';

describe('public trace view', () => {
  it('has a label for every trace event type', () => {
    for (const t of TRACE_EVENT_TYPES) expect(EVENT_LABELS[t]).toBeTruthy();
  });

  it('never exposes tag UIDs, file keys or user ids', () => {
    const shown = [
      eventDetail('TAGGED', { tagType: 'UHF_RFID', tagUid: 'E200-SECRET-EPC' }),
      eventDetail('IMAGED', { view: 'TOP', key: 'BATCH_IMAGE/2026/11/x.jpg' }),
      eventDetail('RECEIVED', { siteCode: 'DC-CSN', outcome: 'PARTIAL', imageKeys: ['BATCH_IMAGE/a.jpg'], actorUserId: 'u1' }),
    ].join(' ');
    expect(shown).not.toMatch(/SECRET|BATCH_IMAGE|u1/);
    expect(shown).toContain('UHF RFID');
    expect(shown).toContain('DC-CSN · PARTIAL');
  });
});
