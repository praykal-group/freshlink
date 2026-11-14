import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import type { EachBatchPayload } from 'kafkajs';
import { KafkaService } from '../../infra/kafka/kafka.service';
import { IncidentsService, type Trigger } from '../../modules/incidents/incidents.service';

interface AlertsTopicMessage {
  type?: string;
  alertType?: string;
  severity?: string;
  tripId?: string | null;
  alertId?: string;
  eventId?: string;
  kind?: string;
}

/** Turns an `alerts` topic message into an engine trigger, or null when the engine does not act on it. */
export function toTrigger(m: AlertsTopicMessage): Trigger | null {
  if (!m.tripId) return null;
  if (m.type === 'ALERT_RAISED' && m.alertType === 'TEMP_EXCURSION' && m.severity === 'CRITICAL') {
    return { tripId: m.tripId, source: 'TEMP_ALERT', alertId: m.alertId ?? null };
  }
  if (m.type === 'DRIVER_INCIDENT' && m.kind) return { tripId: m.tripId, source: 'DRIVER_REPORT', eventType: m.kind, eventId: m.eventId };
  return null;
}

/**
 * Consumer group `incident-engine` on `alerts` (Section 9.3): critical temperature alerts (from the
 * threshold processor) and driver incident reports (from the API) start the incident engine.
 * The topic is keyed by alert/trip; the engine itself keeps one active incident per trip.
 */
@Injectable()
export class IncidentEngineConsumer implements OnApplicationBootstrap {
  private readonly logger = new Logger(IncidentEngineConsumer.name);

  constructor(
    private readonly kafka: KafkaService,
    private readonly incidents: IncidentsService,
  ) {}

  async onApplicationBootstrap() {
    await this.kafka.consume('incident-engine', 'alerts', (b) => this.handle(b));
  }

  async handle({ batch, resolveOffset, heartbeat }: EachBatchPayload) {
    for (const msg of batch.messages) {
      let m: AlertsTopicMessage | null = null;
      try {
        m = JSON.parse(msg.value?.toString('utf8') ?? 'null');
      } catch {
        this.logger.warn({ msg: 'unparseable alerts message skipped', offset: msg.offset });
      }
      const trigger = m ? toTrigger(m) : null;
      if (trigger) {
        try {
          await this.incidents.handleTrigger(trigger);
        } catch (e) {
          // Logged and skipped: one bad trip must not block the topic. The manager still has the alert.
          this.logger.error({ msg: 'incident engine failed', tripId: trigger.tripId, source: trigger.source, error: (e as Error).message });
        }
      }
      resolveOffset(msg.offset);
      await heartbeat();
    }
  }
}
