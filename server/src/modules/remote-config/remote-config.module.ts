import { Global, Module } from '@nestjs/common';
import { RemoteConfigController } from './remote-config.controller';
import { RemoteConfigService } from './remote-config.service';

@Global()
@Module({ controllers: [RemoteConfigController], providers: [RemoteConfigService], exports: [RemoteConfigService] })
export class RemoteConfigModule {}

/** Worker: config reads only, no HTTP routes. */
@Global()
@Module({ providers: [RemoteConfigService], exports: [RemoteConfigService] })
export class RemoteConfigCoreModule {}
