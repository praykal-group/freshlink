import { HttpStatus, Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { TtlCache } from '../../common/cache/ttl-cache';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { CONFIG_SCHEMAS, type ConfigKey, type ConfigValue, isConfigKey } from './config-keys';

/** Typed access to app_config. Other modules read thresholds/timers through `get`. */
@Injectable()
export class RemoteConfigService {
  private readonly cache = new TtlCache<unknown>(30_000);

  constructor(private readonly prisma: PrismaService) {}

  async get<K extends ConfigKey>(key: K): Promise<ConfigValue<K>> {
    const hit = this.cache.get(key);
    if (hit !== undefined) return hit as ConfigValue<K>;
    const row = await this.prisma.appConfig.findUnique({ where: { key } });
    if (!row) throw new AppError('CONFIG_MISSING', `Config "${key}" is not set (run the seed)`, HttpStatus.INTERNAL_SERVER_ERROR);
    const value = CONFIG_SCHEMAS[key].parse(row.value) as ConfigValue<K>;
    this.cache.set(key, value);
    return value;
  }

  async read(key: string) {
    const k = this.assertKey(key);
    const row = await this.prisma.appConfig.findUnique({ where: { key: k } });
    if (!row) throw new AppError('NOT_FOUND', `Config "${key}" is not set`, HttpStatus.NOT_FOUND);
    return { key: row.key, value: row.value, updatedAt: row.updatedAt, updatedBy: row.updatedBy };
  }

  async write(key: string, value: unknown, actorId: string) {
    const k = this.assertKey(key);
    const parsed = CONFIG_SCHEMAS[k].safeParse(value);
    if (!parsed.success) {
      throw new AppError('INVALID_CONFIG_VALUE', `Invalid value for "${key}"`, HttpStatus.BAD_REQUEST, {
        issues: parsed.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      });
    }
    const json = parsed.data as Prisma.InputJsonValue;
    const row = await this.prisma.appConfig.upsert({
      where: { key: k },
      update: { value: json, updatedBy: actorId },
      create: { key: k, value: json, updatedBy: actorId },
    });
    this.cache.delete(k);
    return { key: row.key, value: row.value, updatedAt: row.updatedAt, updatedBy: row.updatedBy };
  }

  private assertKey(key: string): ConfigKey {
    if (!isConfigKey(key)) throw new AppError('UNKNOWN_CONFIG_KEY', `Unknown config key "${key}"`, HttpStatus.NOT_FOUND);
    return key;
  }
}
