-- M9: the trip that takes over the cargo of a RESCUE_PICKUP incident (D-103).
ALTER TABLE "incidents" ADD COLUMN "rescue_trip_id" UUID;
ALTER TABLE "incidents" ADD CONSTRAINT "incidents_rescue_trip_id_fkey" FOREIGN KEY ("rescue_trip_id") REFERENCES "trips"("id") ON DELETE SET NULL ON UPDATE CASCADE;
