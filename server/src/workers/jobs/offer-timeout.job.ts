import type { Job } from 'bullmq';
import { OFFER_TIMEOUT_JOB } from '../../modules/diversions/offers.service';
import type { IncidentsService } from '../../modules/incidents/incidents.service';

export { OFFER_TIMEOUT_JOB };

/** `offer-timeout` (alerts queue, delayed `offerMinutes`): still unanswered → EXPIRED → next buyer (W-1). */
export async function offerTimeout(job: Job, incidents: IncidentsService) {
  return { expired: await incidents.expireOffer((job.data as { offerId: string }).offerId) };
}
