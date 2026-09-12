// Wrangler generates Env from wrangler.toml. Secrets are intentionally absent
// from that file, so their server-side contract is augmented here without
// storing any secret values in the repository.
interface Env {
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  PUSH_WEBHOOK_SECRET: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_BUNDLE_ID: string;
  APNS_PRIVATE_KEY: string;
  CF_IMAGES_ACCOUNT_ID: string;
  CF_IMAGES_API_TOKEN: string;
  GOOGLE_VISION_API_KEY: string;
}
