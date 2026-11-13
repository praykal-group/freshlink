import { HttpStatus, Injectable } from '@nestjs/common';
import type { AuthUser } from '../../common/auth/auth-user';
import { Ownership } from '../../common/auth/ownership';
import { AppError } from '../../common/errors/app-error';
import { S3Service } from '../../infra/s3/s3.service';
import { buildKey, checkUpload, type FilePurpose, parseKey } from './file-rules';

export interface VerifiedUpload {
  key: string;
  purpose: FilePurpose;
  sizeBytes: number;
  contentType?: string;
}

@Injectable()
export class FilesService {
  constructor(private readonly s3: S3Service) {}

  async presign(user: AuthUser, purpose: FilePurpose, contentType: string, sizeBytes: number) {
    const check = checkUpload(purpose, contentType, sizeBytes);
    if (!check.ok) {
      const status = check.code === 'FILE_TOO_LARGE' ? HttpStatus.PAYLOAD_TOO_LARGE : HttpStatus.BAD_REQUEST;
      throw new AppError(check.code, check.message, status);
    }
    const key = buildKey(purpose, check.ext);
    const expiresIn = 300;
    const uploadUrl = await this.s3.presignPut(key, contentType, sizeBytes, user.id, expiresIn);
    return {
      uploadUrl,
      key,
      expiresIn,
      // The client must send exactly these headers with the PUT (they are signed).
      headers: { 'Content-Type': contentType, 'Content-Length': String(sizeBytes), 'x-amz-meta-uploader': user.id },
    };
  }

  /**
   * Before attaching a key to a record (Section 14): the key matches the expected purpose,
   * the object exists, and it was uploaded by this user.
   */
  async verifyOwnUpload(user: AuthUser, key: string, expected: FilePurpose): Promise<VerifiedUpload> {
    const parsed = parseKey(key);
    if (!parsed || parsed.purpose !== expected) {
      throw new AppError('INVALID_FILE_KEY', `key must be a ${expected} upload`, HttpStatus.BAD_REQUEST);
    }
    const info = await this.s3.head(key);
    if (!info) throw new AppError('FILE_NOT_UPLOADED', 'Upload the file before attaching it', HttpStatus.CONFLICT);
    if (info.uploaderId !== user.id) {
      throw new AppError('FILE_NOT_OWNED', 'This file was uploaded by another user', HttpStatus.FORBIDDEN);
    }
    return { key, purpose: parsed.purpose, sizeBytes: info.sizeBytes, contentType: info.contentType };
  }

  /** Presigned GET (5 min). Managers/admins can read any file; others only what they uploaded. */
  async downloadUrl(user: AuthUser, key: string) {
    if (!parseKey(key)) throw new AppError('INVALID_FILE_KEY', 'Unknown file key', HttpStatus.NOT_FOUND);
    if (!Ownership.isPrivileged(user)) {
      const info = await this.s3.head(key);
      if (!info) throw new AppError('NOT_FOUND', 'File not found', HttpStatus.NOT_FOUND);
      if (info.uploaderId !== user.id) throw new AppError('FILE_NOT_OWNED', 'No access to this file', HttpStatus.FORBIDDEN);
    }
    return { url: await this.s3.presignGet(key), expiresIn: 300 };
  }
}
