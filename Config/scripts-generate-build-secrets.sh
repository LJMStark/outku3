#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="${SRCROOT}/Kirole/BuildSecrets.generated.swift"

escape_swift() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

SUPABASE_URL_VALUE="$(escape_swift "${SUPABASE_URL:-}")"
SUPABASE_ANON_KEY_VALUE="$(escape_swift "${SUPABASE_ANON_KEY:-}")"
OPENROUTER_API_KEY_VALUE="$(escape_swift "${OPENROUTER_API_KEY:-}")"
BLE_SHARED_SECRET_VALUE="$(escape_swift "${BLE_SHARED_SECRET:-}")"

cat >"${OUTPUT_FILE}" <<EOT
import Foundation

enum BuildSecrets {
    static let supabaseURL = "${SUPABASE_URL_VALUE}"
    static let supabaseAnonKey = "${SUPABASE_ANON_KEY_VALUE}"
    static let openRouterAPIKey = "${OPENROUTER_API_KEY_VALUE}"
    static let bleSharedSecret = "${BLE_SHARED_SECRET_VALUE}"
}
EOT

echo "Generated ${OUTPUT_FILE}"
