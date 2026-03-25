#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="${SRCROOT}/Kirole/BuildSecrets.generated.swift"

escape_swift() {
  local value="${1:-}"
  # Only escape backslashes and double quotes for Swift string literals
  # Use sed to avoid bash parameter expansion issues with URLs
  value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '%s' "$value"
}

SUPABASE_URL_VALUE="$(escape_swift "${SUPABASE_URL:-}")"
SUPABASE_ANON_KEY_VALUE="$(escape_swift "${SUPABASE_ANON_KEY:-}")"
OPENROUTER_API_KEY_VALUE="$(escape_swift "${OPENROUTER_API_KEY:-}")"
BLE_SHARED_SECRET_VALUE="$(escape_swift "${BLE_SHARED_SECRET:-}")"
DEEP_FOCUS_FEATURE_ENABLED_VALUE="$(escape_swift "${DEEP_FOCUS_FEATURE_ENABLED:-0}")"
NOTION_OAUTH_CLIENT_ID_VALUE="$(escape_swift "${NOTION_OAUTH_CLIENT_ID:-}")"
NOTION_OAUTH_CLIENT_SECRET_VALUE="$(escape_swift "${NOTION_OAUTH_CLIENT_SECRET:-}")"
TASKADE_OAUTH_CLIENT_ID_VALUE="$(escape_swift "${TASKADE_OAUTH_CLIENT_ID:-}")"
TASKADE_OAUTH_CLIENT_SECRET_VALUE="$(escape_swift "${TASKADE_OAUTH_CLIENT_SECRET:-}")"

cat >"${OUTPUT_FILE}" <<EOT
import Foundation

enum BuildSecrets {
    static let supabaseURL = "${SUPABASE_URL_VALUE}"
    static let supabaseAnonKey = "${SUPABASE_ANON_KEY_VALUE}"
    static let openRouterAPIKey = "${OPENROUTER_API_KEY_VALUE}"
    static let bleSharedSecret = "${BLE_SHARED_SECRET_VALUE}"
    static let deepFocusFeatureEnabled = "${DEEP_FOCUS_FEATURE_ENABLED_VALUE}" == "1"
    static let notionClientId = "${NOTION_OAUTH_CLIENT_ID_VALUE}"
    static let notionClientSecret = "${NOTION_OAUTH_CLIENT_SECRET_VALUE}"
    static let taskadeClientId = "${TASKADE_OAUTH_CLIENT_ID_VALUE}"
    static let taskadeClientSecret = "${TASKADE_OAUTH_CLIENT_SECRET_VALUE}"
}
EOT

echo "Generated ${OUTPUT_FILE}"
