import { Controller, Get } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { Public } from '../../common/auth/decorators';
import { HealthService } from './health.service';

@Public()
@SkipThrottle()
@Controller('health')
export class HealthController {
  constructor(private readonly health: HealthService) {}

  /** Liveness: the process is up. */
  @Get()
  live() {
    return { status: 'ok', uptimeS: Math.round(process.uptime()) };
  }

  /** Readiness: dependencies reachable (DB, Redis, Kafka, Influx checks join in later milestones). */
  @Get('ready')
  ready() {
    return this.health.readiness();
  }
}
