#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
REGION="${REGION:-eu-central-1}"
KMS_KEY_ID="${KMS_KEY_ID:-alias/norge360-ssm}"
BASE="/norge360/${ENVIRONMENT_NAME}"

echo "Example script only. Replace placeholder values at runtime."

put_param() {
  local name="$1"
  local type="$2"
  local value="$3"

  if [[ "${type}" == "SecureString" ]]; then
    echo aws ssm put-parameter --region "${REGION}" --name "${name}" --type "${type}" --value "${value}" --key-id "${KMS_KEY_ID}" --overwrite
  else
    echo aws ssm put-parameter --region "${REGION}" --name "${name}" --type "${type}" --value "${value}" --overwrite
  fi
}

put_param "${BASE}/shared/database/default-connection" "SecureString" "__REPLACE_AT_RUNTIME__"
put_param "${BASE}/shared/redis/connection-string" "SecureString" "__REPLACE_AT_RUNTIME__"
put_param "${BASE}/shared/rabbitmq/connection-string" "SecureString" "__REPLACE_AT_RUNTIME__"
put_param "${BASE}/auth/database/connection-string" "SecureString" "__REPLACE_AT_RUNTIME__"
put_param "${BASE}/auth/jwt/signing-keys" "SecureString" "__REPLACE_AT_RUNTIME_JSON_ARRAY__"
put_param "${BASE}/auth/dataprotection/key-ring" "String" "/var/lib/norge360/auth/dataprotection"
put_param "${BASE}/notification/email/provider" "String" "ses"
put_param "${BASE}/notification/email/from-address" "String" "notifications@norge360.com"
put_param "${BASE}/notification/email/from-name" "String" "Norge360 Notifications"
put_param "${BASE}/notification/email/ses/region" "String" "${REGION}"
put_param "${BASE}/notification/email/ses/configuration-set" "String" "__OPTIONAL_CONFIGURATION_SET__"
put_param "${BASE}/notification/email/smtp/host" "SecureString" "__REPLACE_AT_RUNTIME__"
put_param "${BASE}/notification/email/smtp/port" "String" "587"
put_param "${BASE}/notification/email/smtp/username" "SecureString" "__REPLACE_AT_RUNTIME__"
put_param "${BASE}/notification/email/smtp/password" "SecureString" "__REPLACE_AT_RUNTIME__"
