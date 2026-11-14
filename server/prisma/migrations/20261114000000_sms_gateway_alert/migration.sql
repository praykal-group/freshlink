-- Section 15: "SMS gateway down" manager alert after 3 failed sends in a row.
ALTER TYPE "AlertType" ADD VALUE IF NOT EXISTS 'SMS_GATEWAY_DOWN';
