#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="${SRCROOT}/Kirole/BuildSecrets.generated.swift"
SECRETS_FILE="${SRCROOT}/Config/Secrets.xcconfig"

escape_swift() {
  local value="${1:-}"
  # Only escape backslashes and double quotes for Swift string literals
  # Use sed to avoid bash parameter expansion issues with URLs
  value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '%s' "$value"
}

# xcconfig treats `//` as a comment delimiter, so `SUPABASE_URL = https://host`
# gets silently truncated to `https:` before Xcode exports it to this script.
# The `$()` empty-expansion workaround in the xcconfig survives xcconfig's
# `$(VAR)` interpolation but is still eaten by xcconfig's comment pass.
# Fix: when the env var looks truncated, read the raw line from the xcconfig
# file directly and strip the sentinel.
recover_from_xcconfig() {
  local key="$1"
  if [[ ! -f "${SECRETS_FILE}" ]]; then
    return
  fi
  { grep -E "^[[:space:]]*${key}[[:space:]]*=" "${SECRETS_FILE}" || true; } \
    | head -n1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" \
    | sed 's/\$()//g' \
    | sed 's/[[:space:]]*$//'
}

SUPABASE_URL_RAW="${SUPABASE_URL:-}"
if [[ "${SUPABASE_URL_RAW}" == "https:" || "${SUPABASE_URL_RAW}" == "http:" || -z "${SUPABASE_URL_RAW}" ]]; then
  RECOVERED="$(recover_from_xcconfig SUPABASE_URL)"
  if [[ -n "${RECOVERED}" && "${RECOVERED}" != "https:" && "${RECOVERED}" != "http:" ]]; then
    SUPABASE_URL_RAW="${RECOVERED}"
  fi
fi
SUPABASE_URL_VALUE="$(escape_swift "${SUPABASE_URL_RAW}")"
SUPABASE_ANON_KEY_VALUE="$(escape_swift "${SUPABASE_ANON_KEY:-$(recover_from_xcconfig SUPABASE_ANON_KEY)}")"
OPENROUTER_API_KEY_VALUE="$(escape_swift "${OPENROUTER_API_KEY:-}")"
# The BLE secure channel is gated by firmware readiness, not by release
# channel (BLE protocol §3.3 / §4.17): an App package without a secret runs
# the plaintext MVP mode the firmware actually implements, and secure mode may
# only be enabled after both sides explicitly confirm the firmware holds the
# same secret. Until then every configuration — AppStoreRelease included —
# must ship plaintext: a signed customer binary cannot pair with firmware that
# has no key (App Store candidate 655 was archived that way).
# Single source of truth: BLE_SECURE_CHANNEL_ENABLED in Config/Secrets.xcconfig.
BLE_SECURE_CHANNEL_ENABLED="${BLE_SECURE_CHANNEL_ENABLED:-$(recover_from_xcconfig BLE_SECURE_CHANNEL_ENABLED)}"
if [[ "${BLE_SECURE_CHANNEL_ENABLED:-0}" != "1" ]]; then
  BLE_SHARED_SECRET=""
elif [[ -z "${BLE_SHARED_SECRET:-}" ]]; then
  BLE_SHARED_SECRET="$(recover_from_xcconfig BLE_SHARED_SECRET)"
fi
# Once the switch is on, device / archive AppStoreRelease must fail closed.
# Simulator builds stay allowed so scripts/verify-release-boundary.sh and
# local Settings smoke can still run with an empty development secret.
if [[ "${BLE_SECURE_CHANNEL_ENABLED:-0}" == "1" && "${CONFIGURATION:-}" == "AppStoreRelease" && "${PLATFORM_NAME:-}" == "iphoneos" && -z "${BLE_SHARED_SECRET:-}" ]]; then
  echo "error: BLE_SECURE_CHANNEL_ENABLED=1 but BLE_SHARED_SECRET is empty — AppStoreRelease device/archive builds fail closed (empty would ship an unsigned BLE channel)." >&2
  exit 1
fi
BLE_SHARED_SECRET_VALUE="$(escape_swift "${BLE_SHARED_SECRET:-}")"
DEEP_FOCUS_FEATURE_ENABLED_VALUE="$(escape_swift "${DEEP_FOCUS_FEATURE_ENABLED:-0}")"

# AI provider base URL — contains `//`, so it hits the same xcconfig comment-pass
# truncation as SUPABASE_URL; recover from the raw xcconfig line when truncated.
OPENAI_BASE_URL_RAW="${OPENAI_BASE_URL:-}"
if [[ "${OPENAI_BASE_URL_RAW}" == "https:" || "${OPENAI_BASE_URL_RAW}" == "http:" || -z "${OPENAI_BASE_URL_RAW}" ]]; then
  RECOVERED="$(recover_from_xcconfig OPENAI_BASE_URL)"
  if [[ -n "${RECOVERED}" && "${RECOVERED}" != "https:" && "${RECOVERED}" != "http:" ]]; then
    OPENAI_BASE_URL_RAW="${RECOVERED}"
  fi
fi
OPENAI_BASE_URL_VALUE="$(escape_swift "${OPENAI_BASE_URL_RAW}")"
OPENAI_MODEL_VALUE="$(escape_swift "${OPENAI_MODEL:-$(recover_from_xcconfig OPENAI_MODEL)}")"
FALLBACK_API_KEY_VALUE="$(escape_swift "${FALLBACK_API_KEY:-$(recover_from_xcconfig FALLBACK_API_KEY)}")"

cat >"${OUTPUT_FILE}" <<EOT
import Foundation

enum BuildSecrets {
    static let supabaseURL = "${SUPABASE_URL_VALUE}"
    static let supabaseAnonKey = "${SUPABASE_ANON_KEY_VALUE}"
    static let openRouterAPIKey = "${OPENROUTER_API_KEY_VALUE}"
    static let bleSharedSecret = "${BLE_SHARED_SECRET_VALUE}"
    static let deepFocusFeatureEnabled = "${DEEP_FOCUS_FEATURE_ENABLED_VALUE}" == "1"
    static let openAIBaseURL = "${OPENAI_BASE_URL_VALUE}"
    static let chatModelID = "${OPENAI_MODEL_VALUE}"
    static let fallbackAPIKey = "${FALLBACK_API_KEY_VALUE}"
}
EOT

echo "Generated ${OUTPUT_FILE}"
