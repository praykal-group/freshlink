import { HeadObjectCommand, NotFound, PutObjectCommand, GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { HttpStatus, Injectable } from '@nestjs/common';
import { AppError } from '../../common/errors/app-error';
import { AppConfig } from '../../config/config.service';

export interface ObjectInfo {
  sizeBytes: number;
  contentType?: string;
  uploaderId?: string;
}

/**
 * One private bucket (D-07). Credentials come from the default chain (EC2 instance role in prod);
 * no keys are configured in the app.
 */
@Injectable()
export class S3Service {
  private client?: S3Client;

  constructor(private readonly config: AppConfig) {}

  private get bucket(): string {
    const b = this.config.get('S3_BUCKET');
    if (!b) throw new AppError('STORAGE_NOT_CONFIGURED', 'S3_BUCKET is not set', HttpStatus.SERVICE_UNAVAILABLE);
    return b;
  }

  private s3(): S3Client {
    const endpoint = this.config.get('S3_ENDPOINT');
    this.client ??= new S3Client({ region: this.config.get('AWS_REGION'), ...(endpoint ? { endpoint, forcePathStyle: true } : {}) });
    return this.client;
  }

  /**
   * Presigned PUT. Content-Type, Content-Length and the uploader metadata are part of the
   * signature, so the client cannot upload a different type/size or claim someone else's upload.
   */
  presignPut(key: string, contentType: string, sizeBytes: number, uploaderId: string, expiresIn = 300) {
    const cmd = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
      ContentLength: sizeBytes,
      Metadata: { uploader: uploaderId },
    });
    return getSignedUrl(this.s3(), cmd, { expiresIn, signableHeaders: new Set(['content-type', 'content-length']) });
  }

  presignGet(key: string, expiresIn = 300) {
    return getSignedUrl(this.s3(), new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn });
  }

  /** null when the object does not exist (not uploaded yet). */
  async head(key: string): Promise<ObjectInfo | null> {
    try {
      const r = await this.s3().send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return { sizeBytes: r.ContentLength ?? 0, contentType: r.ContentType, uploaderId: r.Metadata?.uploader };
    } catch (e) {
      if (e instanceof NotFound || (e as { name?: string }).name === 'NotFound') return null;
      throw new AppError('STORAGE_ERROR', `S3 head failed: ${(e as Error).message}`, HttpStatus.BAD_GATEWAY);
    }
  }
}
