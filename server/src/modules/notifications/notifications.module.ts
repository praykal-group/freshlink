import { Global, Module } from '@nestjs/common';
import { SmsModule } from '../sms/sms.module';
import { MailProvider } from './mail.provider';
import { NotificationsService } from './notifications.service';
import { PushProvider } from './push.provider';

@Global()
@Module({ imports: [SmsModule], providers: [NotificationsService, PushProvider, MailProvider], exports: [NotificationsService, SmsModule] })
export class NotificationsModule {}
