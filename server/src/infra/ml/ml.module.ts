import { Global, Module } from '@nestjs/common';
import { MlClient } from './ml-client.service';

/** One ML client for every module (grading, shelf life, forecast, routing). */
@Global()
@Module({ providers: [MlClient], exports: [MlClient] })
export class MlModule {}
