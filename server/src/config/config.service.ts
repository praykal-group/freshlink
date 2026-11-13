import { Injectable } from '@nestjs/common';
import { Env, loadEnv } from './env.schema';

/** Typed, read-only access to validated env values. */
@Injectable()
export class AppConfig {
  private readonly env: Env = loadEnv();

  get<K extends keyof Env>(key: K): Env[K] {
    return this.env[key];
  }

  get isProduction(): boolean {
    return this.env.NODE_ENV === 'production';
  }
}
