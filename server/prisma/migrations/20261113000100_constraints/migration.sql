-- Constraints Prisma cannot express (Section 7), plus the W-4 trace_events revoke.

-- users: at least one contact; field staff log in by phone OTP (AUTH-02).
ALTER TABLE "users"
  ADD CONSTRAINT "users_contact_chk" CHECK (phone IS NOT NULL OR email IS NOT NULL),
  ADD CONSTRAINT "users_field_staff_phone_chk" CHECK (role NOT IN ('DRIVER', 'OPERATOR') OR phone IS NOT NULL),
  ADD CONSTRAINT "users_email_lower_chk" CHECK (email IS NULL OR email = lower(email));

-- One active device per user and flavor (DA-FR-01, AUTH-07).
CREATE UNIQUE INDEX "device_registrations_user_flavor_active_key"
  ON "device_registrations" ("user_id", "flavor") WHERE active;

-- Sanity checks on numeric ranges.
ALTER TABLE "storage_units"
  ADD CONSTRAINT "storage_units_temp_range_chk" CHECK (temp_min <= temp_max),
  ADD CONSTRAINT "storage_units_capacity_chk" CHECK (used_kg >= 0 AND capacity_kg > 0);
ALTER TABLE "products"
  ADD CONSTRAINT "products_temp_range_chk" CHECK (safe_temp_min <= safe_temp_max),
  ADD CONSTRAINT "products_humidity_range_chk" CHECK (humidity_min <= humidity_max);
ALTER TABLE "batches"
  ADD CONSTRAINT "batches_weight_chk" CHECK (weight_kg > 0);
ALTER TABLE "trace_events"
  ADD CONSTRAINT "trace_events_seq_chk" CHECK (seq >= 1);

-- W-4: re-apply the insert-only rule after the table exists (roles.sql may have run before it).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iccms_app') THEN
    REVOKE UPDATE, DELETE, TRUNCATE ON "trace_events" FROM iccms_app;
  END IF;
END
$$;
