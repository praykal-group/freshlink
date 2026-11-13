import { Logger, Module } from '@nestjs/common';
import { AppConfig } from '../../config/config.service';
import { ConsoleSmsProvider, HttpSmsProvider, type SmsProvider } from './sms-provider';
import { SMS_PROVIDER, SmsService } from './sms.service';

@Module({
  providers: [
    SmsService,
    {
      provide: SMS_PROVIDER,
      inject: [AppConfig],
      useFactory: (config: AppConfig): SmsProvider => {
        if (config.get('SMS_PROVIDER') === 'httpsms') {
          return new HttpSmsProvider({
            apiUrl: config.get('HTTPSMS_API_URL') as string,
            apiKey: config.get('HTTPSMS_API_KEY') as string,
            from: config.get('HTTPSMS_FROM_NUMBER') as string,
          });
        }
        const logger = new Logger('SmsConsole');
        return new ConsoleSmsProvider((line) => logger.log(line));
      },
    },
  ],
  exports: [SmsService],
})
export class SmsModule {}
