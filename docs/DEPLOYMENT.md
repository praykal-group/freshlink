# Deployment

_Full AWS deployment is written in M14 (Section 17)._

## Supabase project settings (from Section 6.2)
Status: **not yet applied**. No Supabase project has been created for this repo yet. Apply these in the dashboard and record the project ref here (no secrets).

| Setting | Value |
|---------|-------|
| Region | `ap-south-1` (Mumbai) |
| JWT signing | Asymmetric keys (backend uses `.../auth/v1/.well-known/jwks.json`) |
| Providers | Google ON (web client + Android client for `in.iccms.manager`, debug + release SHA-1; "Skip nonce check" OFF); Email ON, Confirm email ON, Secure email change ON; Phone ON |
| Sign-ups | "Allow new users to sign up" **OFF** (D-23) |
| JWT expiry / refresh rotation | 3600 s / ON |
| SMTP | Custom SMTP = backend `SMTP_*` |
| URLs | Site `https://api.<domain>/console/`; redirects `https://api.<domain>/console/**`, `in.iccms.manager://login-callback` |
| Send SMS Hook | HTTPS to `https://api.<domain>/api/v1/hooks/supabase/send-sms`; secret in SSM `SUPABASE_SEND_SMS_HOOK_SECRET` (keep the `v1,whsec_` prefix) |
| SMS OTP template | `I-CCMS: your login code is {{ .Code }}. Valid for 5 minutes. Do not share it.` |
| Test phone numbers | Auth > Phone > test OTPs for the seed phones (`+9199999000xx`) |

Free Supabase projects pause when idle; open the dashboard before any demo.
