import type { Job } from 'bullmq';
import { DRIVER_FIX_RECHECK_JOB, type IncidentsService } from '../../modules/incidents/incidents.service';

export { DRIVER_FIX_RECHECK_JOB };

/** `driver-fix-recheck` (alerts queue, 15 min after DRIVER_FIX): recovered → RESOLVED, else SPOILAGE_RISK (W-2). */
export async function driverFixRecheck(job: Job, incidents: IncidentsService) {
  return { outcome: await incidents.recheckDriverFix((job.data as { incidentId: string }).incidentId) };
}
