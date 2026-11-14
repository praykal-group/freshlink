import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { loadEnv } from './config/env.schema';
import { RedisIoAdapter } from './modules/realtime/redis-io.adapter';

async function bootstrap() {
  const env = loadEnv();
  // rawBody: the Send SMS Hook signature is computed over the exact bytes Supabase sent.
  const app = await NestFactory.create(AppModule, { bufferLogs: true, rawBody: true });
  app.useLogger(app.get(Logger));
  // Public trace pages live at /t/... (the URL printed on labels), outside the API prefix.
  app.setGlobalPrefix('api/v1', { exclude: ['t/:code', 't/:code/verify', 'offer/:token', 'offer/:token/accept', 'offer/:token/reject'] });
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  const origins = env.CORS_ORIGINS.split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  app.enableCors({ origin: origins.length ? origins : false });
  app.getHttpAdapter().getInstance().set('trust proxy', 'loopback'); // real client IP behind nginx

  if (env.NODE_ENV !== 'production') {
    const doc = new DocumentBuilder()
      .setTitle('I-CCMS API')
      .setVersion('0.3.0')
      .addBearerAuth()
      .addGlobalParameters(
        { name: 'X-App-Flavor', in: 'header', required: false, schema: { enum: ['driver', 'operator', 'manager', 'web'] } },
        { name: 'X-Device-Id', in: 'header', required: false, schema: { type: 'string' } },
        { name: 'X-App-Version-Code', in: 'header', required: false, schema: { type: 'integer' } },
      )
      .build();
    SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, doc));
  }

  // Socket.IO over Redis: events from the worker (Redis emitter) and from other API instances reach every client.
  if (env.REDIS_URL) app.useWebSocketAdapter(await RedisIoAdapter.create(app, env.REDIS_URL));

  app.enableShutdownHooks();
  await app.listen(env.PORT);
}

void bootstrap();
