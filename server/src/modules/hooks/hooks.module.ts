import { Module } from '@nestjs/common';
import { SmsModule } from '../sms/sms.module';
import { HooksController } from './hooks.controller';

@Module({ imports: [SmsModule], controllers: [HooksController] })
export class HooksModule {}
