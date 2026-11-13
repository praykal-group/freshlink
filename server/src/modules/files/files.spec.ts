import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { buildKey, checkUpload, parseKey } from './file-rules';
import { FilesService } from './files.service';

// M4: presign rejects a wrong type / size; attach only own uploads with the right purpose.
const op = { id: 'op-1', role: 'OPERATOR' } as AuthUser;
const other = { id: 'op-2', role: 'OPERATOR' } as AuthUser;
const manager = { id: 'm-1', role: 'MANAGER' } as AuthUser;

describe('checkUpload', () => {
  it('accepts jpeg/png/webp images up to 2 MB', () => {
    expect(checkUpload('BATCH_IMAGE', 'image/jpeg', 2 * 1024 * 1024)).toMatchObject({ ok: true, ext: 'jpg' });
    expect(checkUpload('POD_SIGNATURE', 'image/png', 1000)).toMatchObject({ ok: true, ext: 'png' });
  });

  it('rejects other types', () => {
    expect(checkUpload('BATCH_IMAGE', 'image/gif', 1000)).toMatchObject({ ok: false, code: 'UNSUPPORTED_TYPE' });
    expect(checkUpload('BATCH_IMAGE', 'audio/aac', 1000)).toMatchObject({ ok: false, code: 'UNSUPPORTED_TYPE' });
    expect(checkUpload('VOICE_NOTE', 'image/jpeg', 1000)).toMatchObject({ ok: false, code: 'UNSUPPORTED_TYPE' });
  });

  it('rejects images over 2 MB and audio over 5 MB', () => {
    expect(checkUpload('BATCH_IMAGE', 'image/jpeg', 2 * 1024 * 1024 + 1)).toMatchObject({ ok: false, code: 'FILE_TOO_LARGE' });
    expect(checkUpload('VOICE_NOTE', 'audio/aac', 5 * 1024 * 1024)).toMatchObject({ ok: true });
    expect(checkUpload('VOICE_NOTE', 'audio/aac', 5 * 1024 * 1024 + 1)).toMatchObject({ ok: false, code: 'FILE_TOO_LARGE' });
  });

  it('builds and parses keys <purpose>/<yyyy>/<mm>/<uuid>.<ext>', () => {
    const key = buildKey('BATCH_IMAGE', 'jpg', new Date('2026-03-05T00:00:00Z'), '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b');
    expect(key).toBe('BATCH_IMAGE/2026/03/0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b.jpg');
    expect(parseKey(key)).toEqual({ purpose: 'BATCH_IMAGE' });
    expect(parseKey('../etc/passwd')).toBeNull();
  });
});

describe('FilesService', () => {
  const key = 'BATCH_IMAGE/2026/11/0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b.jpg';
  const s3 = {
    presignPut: jest.fn().mockResolvedValue('https://s3/put'),
    presignGet: jest.fn().mockResolvedValue('https://s3/get'),
    head: jest.fn(),
  };
  const files = new FilesService(s3 as never);

  async function code(p: Promise<unknown>) {
    try {
      await p;
      return 'OK';
    } catch (e) {
      return e instanceof AppError ? `${e.getStatus()} ${e.code}` : String(e);
    }
  }

  it('presign rejects a wrong type with 400 and too large with 413', async () => {
    expect(await code(files.presign(op, 'BATCH_IMAGE', 'application/pdf', 100))).toBe('400 UNSUPPORTED_TYPE');
    expect(await code(files.presign(op, 'BATCH_IMAGE', 'image/jpeg', 3 * 1024 * 1024))).toBe('413 FILE_TOO_LARGE');
  });

  it('presign signs the uploader into the request and returns the headers to send', async () => {
    const r = await files.presign(op, 'BATCH_IMAGE', 'image/jpeg', 400_000);
    expect(s3.presignPut).toHaveBeenCalledWith(r.key, 'image/jpeg', 400_000, 'op-1', 300);
    expect(r.headers['x-amz-meta-uploader']).toBe('op-1');
    expect(r.expiresIn).toBe(300);
  });

  it('attach: right purpose + own upload passes', async () => {
    s3.head.mockResolvedValueOnce({ sizeBytes: 400_000, uploaderId: 'op-1' });
    expect(await files.verifyOwnUpload(op, key, 'BATCH_IMAGE')).toMatchObject({ sizeBytes: 400_000 });
  });

  it('attach: wrong purpose, missing object or someone else’s upload is refused', async () => {
    expect(await code(files.verifyOwnUpload(op, key, 'POD_PHOTO'))).toBe('400 INVALID_FILE_KEY');
    s3.head.mockResolvedValueOnce(null);
    expect(await code(files.verifyOwnUpload(op, key, 'BATCH_IMAGE'))).toBe('409 FILE_NOT_UPLOADED');
    s3.head.mockResolvedValueOnce({ sizeBytes: 1, uploaderId: 'op-1' });
    expect(await code(files.verifyOwnUpload(other, key, 'BATCH_IMAGE'))).toBe('403 FILE_NOT_OWNED');
  });

  it('download: managers read any file, others only their own', async () => {
    expect(await files.downloadUrl(manager, key)).toEqual({ url: 'https://s3/get', expiresIn: 300 });
    s3.head.mockResolvedValueOnce({ sizeBytes: 1, uploaderId: 'op-1' });
    expect(await code(files.downloadUrl(other, key))).toBe('403 FILE_NOT_OWNED');
  });
});
