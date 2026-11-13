-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('ADMIN', 'MANAGER', 'OPERATOR', 'DRIVER');

-- CreateEnum
CREATE TYPE "AuthMethod" AS ENUM ('PHONE', 'GOOGLE', 'EMAIL');

-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('INVITED', 'ACTIVE', 'DISABLED');

-- CreateEnum
CREATE TYPE "Language" AS ENUM ('en', 'hi', 'mr');

-- CreateEnum
CREATE TYPE "AppFlavor" AS ENUM ('driver', 'operator', 'manager', 'web');

-- CreateEnum
CREATE TYPE "SiteType" AS ENUM ('DOCK', 'FARM_GATE', 'COLD_STORAGE', 'WAREHOUSE', 'DISTRIBUTION_CENTRE');

-- CreateEnum
CREATE TYPE "StorageUnitType" AS ENUM ('BLAST_CHILLER', 'RIPENING_CHAMBER', 'COLD_ROOM');

-- CreateEnum
CREATE TYPE "VehicleStatus" AS ENUM ('AVAILABLE', 'IN_USE', 'MAINTENANCE', 'INACTIVE');

-- CreateEnum
CREATE TYPE "DeviceStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'FAULTY');

-- CreateEnum
CREATE TYPE "ProductCategory" AS ENUM ('FISH', 'PRODUCE');

-- CreateEnum
CREATE TYPE "BatchSourceType" AS ENUM ('FISHERY', 'FARM');

-- CreateEnum
CREATE TYPE "BatchStatus" AS ENUM ('REGISTERED', 'GRADED', 'STORED', 'ALLOCATED', 'LOADED', 'IN_TRANSIT', 'DIVERTED', 'DELIVERED', 'PARTIALLY_DELIVERED', 'REJECTED', 'SPOILED');

-- CreateEnum
CREATE TYPE "Grade" AS ENUM ('A', 'B', 'C');

-- CreateEnum
CREATE TYPE "TagType" AS ENUM ('NFC', 'UHF_RFID', 'QR');

-- CreateEnum
CREATE TYPE "ImageView" AS ENUM ('TOP', 'SIDE', 'CLOSEUP', 'RECEIVING', 'DAMAGE');

-- CreateEnum
CREATE TYPE "GradeSource" AS ENUM ('AUTO', 'MANUAL');

-- CreateEnum
CREATE TYPE "ReviewStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "ShelfLifeMethod" AS ENUM ('COX', 'Q10_FALLBACK');

-- CreateEnum
CREATE TYPE "ShelfLifeTrigger" AS ENUM ('BREACH', 'SCHEDULED', 'GRADE', 'MANUAL');

-- CreateEnum
CREATE TYPE "OrderStatus" AS ENUM ('DRAFT', 'APPROVED', 'PLANNED', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "OrderOrigin" AS ENUM ('PLANNER', 'ERP', 'CSV', 'MANUAL');

-- CreateEnum
CREATE TYPE "TripStatus" AS ENUM ('PLANNED', 'ASSIGNED', 'PRE_CHECK_DONE', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "StopType" AS ENUM ('PICKUP', 'DROP', 'DIVERSION_DROP', 'RESCUE_PICKUP', 'RESCUE_DROP', 'COLD_STORAGE_DROP');

-- CreateEnum
CREATE TYPE "StopStatus" AS ENUM ('PENDING', 'ARRIVED', 'COMPLETED', 'SKIPPED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "RouteReason" AS ENUM ('INITIAL', 'DELAY', 'INCIDENT', 'DIVERSION', 'RESCUE', 'MANUAL');

-- CreateEnum
CREATE TYPE "RoutePlanStatus" AS ENUM ('PROPOSED', 'ACCEPTED', 'DECLINED', 'SUPERSEDED');

-- CreateEnum
CREATE TYPE "TripEventType" AS ENUM ('PRE_TRIP_CHECK', 'START', 'INCIDENT_DELAY', 'INCIDENT_BREAKDOWN', 'INCIDENT_ACCIDENT', 'INCIDENT_ROADBLOCK', 'INCIDENT_REEFER_FAULT', 'SOS', 'ARRIVE', 'COMPLETE');

-- CreateEnum
CREATE TYPE "PodOutcome" AS ENUM ('ACCEPTED', 'PARTIAL', 'REJECTED');

-- CreateEnum
CREATE TYPE "AlertType" AS ENUM ('TEMP_EXCURSION', 'HUMIDITY', 'ETHYLENE', 'SHOCK', 'SPOILAGE_RISK', 'DEVICE_OFFLINE', 'SOS', 'REEFER_MAINTENANCE', 'DRIVER_FIX');

-- CreateEnum
CREATE TYPE "AlertSeverity" AS ENUM ('INFO', 'WARNING', 'CRITICAL');

-- CreateEnum
CREATE TYPE "AlertStatus" AS ENUM ('OPEN', 'ACKNOWLEDGED', 'ESCALATED', 'RESOLVED');

-- CreateEnum
CREATE TYPE "NotificationChannel" AS ENUM ('PUSH', 'SMS', 'EMAIL', 'IN_APP');

-- CreateEnum
CREATE TYPE "NotificationStatus" AS ENUM ('QUEUED', 'SENT', 'FAILED');

-- CreateEnum
CREATE TYPE "IncidentKind" AS ENUM ('TEMP_DRIFT', 'REEFER_FAILURE', 'SPOILAGE_RISK', 'DELAY', 'BREAKDOWN');

-- CreateEnum
CREATE TYPE "IncidentAction" AS ENUM ('DRIVER_FIX', 'DIVERT_BUYER', 'DIVERT_COLD_STORAGE', 'RESCUE_PICKUP', 'REPLAN', 'MANUAL');

-- CreateEnum
CREATE TYPE "IncidentStatus" AS ENUM ('OPEN', 'ACTION_IN_PROGRESS', 'RESOLVED', 'FAILED');

-- CreateEnum
CREATE TYPE "BuyerType" AS ENUM ('CANNING', 'PROCESSING', 'LOCAL_MARKET', 'DISCOUNT_RETAIL', 'COLD_STORAGE');

-- CreateEnum
CREATE TYPE "OfferStatus" AS ENUM ('SENT', 'ACCEPTED', 'REJECTED', 'EXPIRED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ReleaseChannel" AS ENUM ('stable', 'beta');

-- CreateEnum
CREATE TYPE "InstallStatus" AS ENUM ('STARTED', 'SUCCEEDED', 'FAILED');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "supabase_uid" UUID,
    "phone" TEXT,
    "email" TEXT,
    "email_verified_at" TIMESTAMPTZ(6),
    "auth_method" "AuthMethod" NOT NULL,
    "name" TEXT NOT NULL,
    "role" "UserRole" NOT NULL,
    "site_id" UUID,
    "language" "Language" NOT NULL DEFAULT 'en',
    "emergency_contact_phone" TEXT,
    "status" "UserStatus" NOT NULL DEFAULT 'INVITED',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_registrations" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_id" TEXT NOT NULL,
    "flavor" "AppFlavor" NOT NULL,
    "fcm_token" TEXT,
    "app_version_code" INTEGER,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "last_seen_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "device_registrations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sites" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "SiteType" NOT NULL,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "address" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "sites_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "storage_units" (
    "id" UUID NOT NULL,
    "site_id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "type" "StorageUnitType" NOT NULL,
    "temp_min" DECIMAL(5,2) NOT NULL,
    "temp_max" DECIMAL(5,2) NOT NULL,
    "capacity_kg" DECIMAL(12,3) NOT NULL,
    "used_kg" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "storage_units_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vehicles" (
    "id" UUID NOT NULL,
    "reg_no" TEXT NOT NULL,
    "capacity_kg" DECIMAL(12,3) NOT NULL,
    "reefer_min_temp" DECIMAL(5,2) NOT NULL,
    "reefer_max_temp" DECIMAL(5,2) NOT NULL,
    "home_site_id" UUID NOT NULL,
    "status" "VehicleStatus" NOT NULL DEFAULT 'AVAILABLE',
    "baseline_pulldown_rate" DOUBLE PRECISION,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "iot_devices" (
    "id" UUID NOT NULL,
    "device_code" TEXT NOT NULL,
    "vehicle_id" UUID,
    "storage_unit_id" UUID,
    "mqtt_username" TEXT NOT NULL,
    "secret_hash" TEXT NOT NULL,
    "status" "DeviceStatus" NOT NULL DEFAULT 'ACTIVE',
    "last_seen_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "iot_devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "products" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "name_hi" TEXT NOT NULL,
    "name_mr" TEXT NOT NULL,
    "category" "ProductCategory" NOT NULL,
    "is_climacteric" BOOLEAN NOT NULL,
    "is_ethylene_sensitive" BOOLEAN NOT NULL,
    "safe_temp_min" DECIMAL(5,2) NOT NULL,
    "safe_temp_max" DECIMAL(5,2) NOT NULL,
    "humidity_min" DECIMAL(5,2) NOT NULL,
    "humidity_max" DECIMAL(5,2) NOT NULL,
    "ethylene_max_ppm" DECIMAL(8,3),
    "shock_max_g" DECIMAL(6,2) NOT NULL,
    "base_shelf_life_h" DECIMAL(8,2) NOT NULL,
    "q10" DECIMAL(5,2) NOT NULL,
    "unit_price" DECIMAL(12,3) NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "products_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_config" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updated_by" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "app_config_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "batches" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "product_id" UUID NOT NULL,
    "source_type" "BatchSourceType" NOT NULL,
    "source_site_id" UUID NOT NULL,
    "current_site_id" UUID,
    "storage_unit_id" UUID,
    "vessel_id" TEXT,
    "farm_ref" TEXT,
    "caught_or_harvested_at" TIMESTAMPTZ(6) NOT NULL,
    "weight_kg" DECIMAL(12,3) NOT NULL,
    "ice_to_fish_ratio" DECIMAL(6,3),
    "initial_core_temp" DECIMAL(5,2),
    "maturity_index" DECIMAL(5,2),
    "brix" DECIMAL(5,2),
    "field_temp" DECIMAL(5,2),
    "field_humidity" DECIMAL(5,2),
    "status" "BatchStatus" NOT NULL DEFAULT 'REGISTERED',
    "current_grade" "Grade",
    "remaining_shelf_life_h" DECIMAL(8,2),
    "shelf_life_updated_at" TIMESTAMPTZ(6),
    "created_by" UUID NOT NULL,
    "device_id" TEXT NOT NULL,
    "captured_at" TIMESTAMPTZ(6) NOT NULL,
    "captured_lat" DOUBLE PRECISION,
    "captured_lng" DOUBLE PRECISION,
    "record_hash" CHAR(64) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "batches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "batch_tags" (
    "id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "tag_type" "TagType" NOT NULL,
    "tag_uid" TEXT NOT NULL,
    "attached_by" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "batch_tags_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "batch_images" (
    "id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "view" "ImageView" NOT NULL,
    "s3_key" TEXT NOT NULL,
    "size_bytes" INTEGER NOT NULL,
    "width" INTEGER NOT NULL,
    "height" INTEGER NOT NULL,
    "captured_at" TIMESTAMPTZ(6) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "batch_images_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quality_grades" (
    "id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "grade" "Grade" NOT NULL,
    "defects" JSONB NOT NULL DEFAULT '[]',
    "confidence" DECIMAL(5,4) NOT NULL,
    "model_version" TEXT NOT NULL,
    "source" "GradeSource" NOT NULL,
    "disputed" BOOLEAN NOT NULL DEFAULT false,
    "dispute_reason" TEXT,
    "resolved_by" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "quality_grades_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "batch_edit_requests" (
    "id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "requested_by" UUID NOT NULL,
    "changes" JSONB NOT NULL,
    "reason" TEXT NOT NULL,
    "status" "ReviewStatus" NOT NULL DEFAULT 'PENDING',
    "reviewed_by" UUID,
    "reviewed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "batch_edit_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "shelf_life_estimates" (
    "id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "remaining_h" DECIMAL(8,2) NOT NULL,
    "survival_curve" JSONB NOT NULL DEFAULT '[]',
    "method" "ShelfLifeMethod" NOT NULL,
    "model_version" TEXT NOT NULL,
    "trigger" "ShelfLifeTrigger" NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "shelf_life_estimates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "batch_exposure" (
    "batch_id" UUID NOT NULL,
    "degree_minutes_above" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "minutes_above_limit" INTEGER NOT NULL DEFAULT 0,
    "mean_temp" DECIMAL(5,2),
    "max_temp" DECIMAL(5,2),
    "shock_events" INTEGER NOT NULL DEFAULT 0,
    "max_ethylene_ppm" DECIMAL(8,3),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "batch_exposure_pkey" PRIMARY KEY ("batch_id")
);

-- CreateTable
CREATE TABLE "demand_forecasts" (
    "id" UUID NOT NULL,
    "site_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "forecast_date" DATE NOT NULL,
    "predicted_kg" DECIMAL(12,3) NOT NULL,
    "lower_kg" DECIMAL(12,3) NOT NULL,
    "upper_kg" DECIMAL(12,3) NOT NULL,
    "model_version" TEXT NOT NULL,
    "run_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "demand_forecasts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dispatch_orders" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "source_site_id" UUID NOT NULL,
    "destination_site_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "quantity_kg" DECIMAL(12,3) NOT NULL,
    "window_start" TIMESTAMPTZ(6) NOT NULL,
    "window_end" TIMESTAMPTZ(6) NOT NULL,
    "status" "OrderStatus" NOT NULL DEFAULT 'DRAFT',
    "origin" "OrderOrigin" NOT NULL,
    "external_ref" TEXT,
    "approved_by" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "dispatch_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "order_batches" (
    "order_id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "allocated_kg" DECIMAL(12,3) NOT NULL,

    CONSTRAINT "order_batches_pkey" PRIMARY KEY ("order_id","batch_id")
);

-- CreateTable
CREATE TABLE "trips" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "vehicle_id" UUID NOT NULL,
    "driver_id" UUID,
    "depot_site_id" UUID NOT NULL,
    "status" "TripStatus" NOT NULL DEFAULT 'PLANNED',
    "planned_start" TIMESTAMPTZ(6) NOT NULL,
    "started_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "bound_device_id" TEXT,
    "current_route_version" INTEGER NOT NULL DEFAULT 1,
    "distance_km" DECIMAL(10,3),
    "co2_kg" DECIMAL(12,3),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "trips_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_stops" (
    "id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "seq" INTEGER NOT NULL,
    "route_version" INTEGER NOT NULL,
    "type" "StopType" NOT NULL,
    "site_id" UUID,
    "buyer_id" UUID,
    "order_id" UUID,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "window_start" TIMESTAMPTZ(6),
    "window_end" TIMESTAMPTZ(6),
    "eta" TIMESTAMPTZ(6),
    "arrived_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "status" "StopStatus" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "trip_stops_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_batches" (
    "trip_id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "loaded_by" UUID NOT NULL,
    "loaded_at" TIMESTAMPTZ(6) NOT NULL,
    "unloaded_at" TIMESTAMPTZ(6),

    CONSTRAINT "trip_batches_pkey" PRIMARY KEY ("trip_id","batch_id")
);

-- CreateTable
CREATE TABLE "route_plans" (
    "id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "reason" "RouteReason" NOT NULL,
    "stops" JSONB NOT NULL,
    "polyline" TEXT,
    "fitness" DOUBLE PRECISION NOT NULL,
    "status" "RoutePlanStatus" NOT NULL DEFAULT 'PROPOSED',
    "responded_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "route_plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_events" (
    "id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "type" "TripEventType" NOT NULL,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "photo_key" TEXT,
    "voice_key" TEXT,
    "lat" DOUBLE PRECISION,
    "lng" DOUBLE PRECISION,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "trip_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "proof_of_delivery" (
    "id" UUID NOT NULL,
    "trip_stop_id" UUID NOT NULL,
    "batch_id" UUID NOT NULL,
    "outcome" "PodOutcome" NOT NULL,
    "accepted_kg" DECIMAL(12,3) NOT NULL,
    "reason" TEXT,
    "receiver_name" TEXT NOT NULL,
    "signature_key" TEXT NOT NULL,
    "photo_key" TEXT NOT NULL,
    "scanned_tag_uid" TEXT NOT NULL,
    "captured_at" TIMESTAMPTZ(6) NOT NULL,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "proof_of_delivery_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "alerts" (
    "id" UUID NOT NULL,
    "type" "AlertType" NOT NULL,
    "severity" "AlertSeverity" NOT NULL,
    "trip_id" UUID,
    "vehicle_id" UUID,
    "batch_id" UUID,
    "message" TEXT NOT NULL,
    "data" JSONB NOT NULL DEFAULT '{}',
    "status" "AlertStatus" NOT NULL DEFAULT 'OPEN',
    "acknowledged_by" UUID,
    "acknowledged_at" TIMESTAMPTZ(6),
    "escalated_at" TIMESTAMPTZ(6),
    "resolved_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "alerts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "alert_id" UUID,
    "user_id" UUID NOT NULL,
    "channel" "NotificationChannel" NOT NULL,
    "status" "NotificationStatus" NOT NULL DEFAULT 'QUEUED',
    "provider_ref" TEXT,
    "error" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "incidents" (
    "id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "alert_id" UUID,
    "kind" "IncidentKind" NOT NULL,
    "decided_action" "IncidentAction",
    "status" "IncidentStatus" NOT NULL DEFAULT 'OPEN',
    "decision_log" JSONB NOT NULL DEFAULT '[]',
    "resolved_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "incidents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "backup_buyers" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "type" "BuyerType" NOT NULL,
    "phone" TEXT NOT NULL,
    "email" TEXT,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "accepted_product_ids" UUID[],
    "min_grade" "Grade" NOT NULL,
    "discount_pct" DECIMAL(5,2) NOT NULL,
    "opening_hours" JSONB NOT NULL,
    "capacity_kg" DECIMAL(12,3),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "backup_buyers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "diversion_offers" (
    "id" UUID NOT NULL,
    "incident_id" UUID NOT NULL,
    "buyer_id" UUID NOT NULL,
    "batch_ids" UUID[],
    "quantity_kg" DECIMAL(12,3) NOT NULL,
    "token_hash" CHAR(64) NOT NULL,
    "status" "OfferStatus" NOT NULL DEFAULT 'SENT',
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "responded_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "diversion_offers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trace_events" (
    "id" BIGSERIAL NOT NULL,
    "batch_id" UUID NOT NULL,
    "seq" INTEGER NOT NULL,
    "event_type" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "actor_user_id" UUID,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "prev_hash" CHAR(64) NOT NULL,
    "hash" CHAR(64) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trace_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reefer_health" (
    "id" UUID NOT NULL,
    "vehicle_id" UUID NOT NULL,
    "period_start" TIMESTAMPTZ(6) NOT NULL,
    "period_end" TIMESTAMPTZ(6) NOT NULL,
    "pulldown_rate" DOUBLE PRECISION NOT NULL,
    "baseline_rate" DOUBLE PRECISION NOT NULL,
    "degradation_pct" DOUBLE PRECISION NOT NULL,
    "flagged" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "reefer_health_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_releases" (
    "id" UUID NOT NULL,
    "flavor" "AppFlavor" NOT NULL,
    "channel" "ReleaseChannel" NOT NULL DEFAULT 'stable',
    "version_name" TEXT NOT NULL,
    "version_code" INTEGER NOT NULL,
    "min_supported_code" INTEGER NOT NULL,
    "mandatory" BOOLEAN NOT NULL DEFAULT false,
    "notes_md" TEXT NOT NULL DEFAULT '',
    "features" JSONB NOT NULL DEFAULT '[]',
    "improvements" JSONB NOT NULL DEFAULT '[]',
    "fixes" JSONB NOT NULL DEFAULT '[]',
    "apk_url" TEXT NOT NULL,
    "apk_name" TEXT NOT NULL,
    "sha256" CHAR(64) NOT NULL,
    "size_bytes" BIGINT NOT NULL,
    "signing_cert_sha256" TEXT NOT NULL,
    "github_release_id" BIGINT NOT NULL,
    "published_at" TIMESTAMPTZ(6) NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "app_releases_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_installs" (
    "id" UUID NOT NULL,
    "device_id" TEXT NOT NULL,
    "flavor" "AppFlavor" NOT NULL,
    "from_code" INTEGER NOT NULL,
    "to_code" INTEGER NOT NULL,
    "status" "InstallStatus" NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "app_installs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sync_ops" (
    "client_op_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "result" JSONB NOT NULL,
    "received_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sync_ops_pkey" PRIMARY KEY ("client_op_id")
);

-- CreateTable
CREATE TABLE "integration_clients" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "key_hash" CHAR(64) NOT NULL,
    "scopes" TEXT[],
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "integration_clients_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL,
    "actor_id" UUID,
    "action" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "before" JSONB,
    "after" JSONB,
    "ip" TEXT,
    "request_id" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_supabase_uid_key" ON "users"("supabase_uid");

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_role_idx" ON "users"("role");

-- CreateIndex
CREATE INDEX "users_site_id_idx" ON "users"("site_id");

-- CreateIndex
CREATE UNIQUE INDEX "device_registrations_device_id_flavor_key" ON "device_registrations"("device_id", "flavor");

-- CreateIndex
CREATE UNIQUE INDEX "sites_code_key" ON "sites"("code");

-- CreateIndex
CREATE INDEX "sites_type_idx" ON "sites"("type");

-- CreateIndex
CREATE UNIQUE INDEX "storage_units_site_id_code_key" ON "storage_units"("site_id", "code");

-- CreateIndex
CREATE UNIQUE INDEX "vehicles_reg_no_key" ON "vehicles"("reg_no");

-- CreateIndex
CREATE UNIQUE INDEX "iot_devices_device_code_key" ON "iot_devices"("device_code");

-- CreateIndex
CREATE UNIQUE INDEX "iot_devices_mqtt_username_key" ON "iot_devices"("mqtt_username");

-- CreateIndex
CREATE UNIQUE INDEX "products_code_key" ON "products"("code");

-- CreateIndex
CREATE UNIQUE INDEX "batches_code_key" ON "batches"("code");

-- CreateIndex
CREATE INDEX "batches_current_site_id_status_idx" ON "batches"("current_site_id", "status");

-- CreateIndex
CREATE INDEX "batches_product_id_status_idx" ON "batches"("product_id", "status");

-- CreateIndex
CREATE INDEX "batches_created_at_idx" ON "batches"("created_at" DESC);

-- CreateIndex
CREATE INDEX "batches_remaining_shelf_life_h_idx" ON "batches"("remaining_shelf_life_h");

-- CreateIndex
CREATE UNIQUE INDEX "batch_tags_tag_uid_key" ON "batch_tags"("tag_uid");

-- CreateIndex
CREATE INDEX "batch_tags_batch_id_idx" ON "batch_tags"("batch_id");

-- CreateIndex
CREATE INDEX "batch_images_batch_id_idx" ON "batch_images"("batch_id");

-- CreateIndex
CREATE INDEX "quality_grades_batch_id_created_at_idx" ON "quality_grades"("batch_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "batch_edit_requests_status_idx" ON "batch_edit_requests"("status");

-- CreateIndex
CREATE INDEX "shelf_life_estimates_batch_id_created_at_idx" ON "shelf_life_estimates"("batch_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "demand_forecasts_site_id_product_id_forecast_date_run_id_key" ON "demand_forecasts"("site_id", "product_id", "forecast_date", "run_id");

-- CreateIndex
CREATE UNIQUE INDEX "dispatch_orders_code_key" ON "dispatch_orders"("code");

-- CreateIndex
CREATE INDEX "dispatch_orders_status_window_start_idx" ON "dispatch_orders"("status", "window_start");

-- CreateIndex
CREATE UNIQUE INDEX "dispatch_orders_origin_external_ref_key" ON "dispatch_orders"("origin", "external_ref");

-- CreateIndex
CREATE UNIQUE INDEX "trips_code_key" ON "trips"("code");

-- CreateIndex
CREATE INDEX "trips_driver_id_status_idx" ON "trips"("driver_id", "status");

-- CreateIndex
CREATE INDEX "trips_status_planned_start_idx" ON "trips"("status", "planned_start");

-- CreateIndex
CREATE INDEX "trip_stops_trip_id_route_version_seq_idx" ON "trip_stops"("trip_id", "route_version", "seq");

-- CreateIndex
CREATE UNIQUE INDEX "route_plans_trip_id_version_key" ON "route_plans"("trip_id", "version");

-- CreateIndex
CREATE INDEX "trip_events_trip_id_occurred_at_idx" ON "trip_events"("trip_id", "occurred_at");

-- CreateIndex
CREATE UNIQUE INDEX "proof_of_delivery_trip_stop_id_batch_id_key" ON "proof_of_delivery"("trip_stop_id", "batch_id");

-- CreateIndex
CREATE INDEX "alerts_status_created_at_idx" ON "alerts"("status", "created_at" DESC);

-- CreateIndex
CREATE INDEX "alerts_trip_id_idx" ON "alerts"("trip_id");

-- CreateIndex
CREATE INDEX "notifications_alert_id_idx" ON "notifications"("alert_id");

-- CreateIndex
CREATE INDEX "incidents_status_idx" ON "incidents"("status");

-- CreateIndex
CREATE INDEX "incidents_trip_id_idx" ON "incidents"("trip_id");

-- CreateIndex
CREATE INDEX "backup_buyers_type_active_idx" ON "backup_buyers"("type", "active");

-- CreateIndex
CREATE INDEX "backup_buyers_accepted_product_ids_idx" ON "backup_buyers" USING GIN ("accepted_product_ids");

-- CreateIndex
CREATE UNIQUE INDEX "diversion_offers_token_hash_key" ON "diversion_offers"("token_hash");

-- CreateIndex
CREATE INDEX "diversion_offers_incident_id_idx" ON "diversion_offers"("incident_id");

-- CreateIndex
CREATE UNIQUE INDEX "trace_events_batch_id_seq_key" ON "trace_events"("batch_id", "seq");

-- CreateIndex
CREATE INDEX "reefer_health_vehicle_id_period_start_idx" ON "reefer_health"("vehicle_id", "period_start" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "app_releases_github_release_id_key" ON "app_releases"("github_release_id");

-- CreateIndex
CREATE UNIQUE INDEX "app_releases_flavor_channel_version_code_key" ON "app_releases"("flavor", "channel", "version_code");

-- CreateIndex
CREATE INDEX "app_installs_flavor_created_at_idx" ON "app_installs"("flavor", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "integration_clients_key_hash_key" ON "integration_clients"("key_hash");

-- CreateIndex
CREATE INDEX "audit_logs_entity_entity_id_idx" ON "audit_logs"("entity", "entity_id");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "sites"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_registrations" ADD CONSTRAINT "device_registrations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "storage_units" ADD CONSTRAINT "storage_units_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicles" ADD CONSTRAINT "vehicles_home_site_id_fkey" FOREIGN KEY ("home_site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "iot_devices" ADD CONSTRAINT "iot_devices_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "iot_devices" ADD CONSTRAINT "iot_devices_storage_unit_id_fkey" FOREIGN KEY ("storage_unit_id") REFERENCES "storage_units"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "app_config" ADD CONSTRAINT "app_config_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batches" ADD CONSTRAINT "batches_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batches" ADD CONSTRAINT "batches_source_site_id_fkey" FOREIGN KEY ("source_site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batches" ADD CONSTRAINT "batches_current_site_id_fkey" FOREIGN KEY ("current_site_id") REFERENCES "sites"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batches" ADD CONSTRAINT "batches_storage_unit_id_fkey" FOREIGN KEY ("storage_unit_id") REFERENCES "storage_units"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batches" ADD CONSTRAINT "batches_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_tags" ADD CONSTRAINT "batch_tags_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_tags" ADD CONSTRAINT "batch_tags_attached_by_fkey" FOREIGN KEY ("attached_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_images" ADD CONSTRAINT "batch_images_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quality_grades" ADD CONSTRAINT "quality_grades_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quality_grades" ADD CONSTRAINT "quality_grades_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_edit_requests" ADD CONSTRAINT "batch_edit_requests_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_edit_requests" ADD CONSTRAINT "batch_edit_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_edit_requests" ADD CONSTRAINT "batch_edit_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "shelf_life_estimates" ADD CONSTRAINT "shelf_life_estimates_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "batch_exposure" ADD CONSTRAINT "batch_exposure_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "demand_forecasts" ADD CONSTRAINT "demand_forecasts_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "demand_forecasts" ADD CONSTRAINT "demand_forecasts_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dispatch_orders" ADD CONSTRAINT "dispatch_orders_source_site_id_fkey" FOREIGN KEY ("source_site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dispatch_orders" ADD CONSTRAINT "dispatch_orders_destination_site_id_fkey" FOREIGN KEY ("destination_site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dispatch_orders" ADD CONSTRAINT "dispatch_orders_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dispatch_orders" ADD CONSTRAINT "dispatch_orders_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_batches" ADD CONSTRAINT "order_batches_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "dispatch_orders"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_batches" ADD CONSTRAINT "order_batches_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_depot_site_id_fkey" FOREIGN KEY ("depot_site_id") REFERENCES "sites"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "sites"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_buyer_id_fkey" FOREIGN KEY ("buyer_id") REFERENCES "backup_buyers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_stops" ADD CONSTRAINT "trip_stops_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "dispatch_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_batches" ADD CONSTRAINT "trip_batches_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_batches" ADD CONSTRAINT "trip_batches_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_batches" ADD CONSTRAINT "trip_batches_loaded_by_fkey" FOREIGN KEY ("loaded_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "route_plans" ADD CONSTRAINT "route_plans_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_events" ADD CONSTRAINT "trip_events_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "proof_of_delivery" ADD CONSTRAINT "proof_of_delivery_trip_stop_id_fkey" FOREIGN KEY ("trip_stop_id") REFERENCES "trip_stops"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "proof_of_delivery" ADD CONSTRAINT "proof_of_delivery_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_acknowledged_by_fkey" FOREIGN KEY ("acknowledged_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "alerts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "incidents" ADD CONSTRAINT "incidents_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "incidents" ADD CONSTRAINT "incidents_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "alerts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "diversion_offers" ADD CONSTRAINT "diversion_offers_incident_id_fkey" FOREIGN KEY ("incident_id") REFERENCES "incidents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "diversion_offers" ADD CONSTRAINT "diversion_offers_buyer_id_fkey" FOREIGN KEY ("buyer_id") REFERENCES "backup_buyers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trace_events" ADD CONSTRAINT "trace_events_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "batches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trace_events" ADD CONSTRAINT "trace_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reefer_health" ADD CONSTRAINT "reefer_health_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sync_ops" ADD CONSTRAINT "sync_ops_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

