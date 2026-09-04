#!/bin/bash
# Paired release-channel gate (AGENTS.md "Release Channel Policy").
#
# Builds both distribution configurations for the iOS simulator and asserts:
#   - InternalRelease  contains the KIROLE_INTERNAL boundary marker
#   - AppStoreRelease  does NOT contain it
#   - InternalRelease  contains the internal-tool UI strings
#   - AppStoreRelease  does NOT contain those strings
#   - InternalRelease  contains the factory BLE implementations
#   - AppStoreRelease  does NOT contain the factory BLE implementations
#   - AppStoreRelease  does NOT package repository-only engineering files
#
# The marker lives in Kirole/InternalBuildBoundary.swift; keep the string
# below in sync with it. Run before producing any App Store candidate:
#
#   ./scripts/verify-release-boundary.sh
set -euo pipefail

cd "$(dirname "$0")/.."

MARKER="KIROLE-INTERNAL-CHANNEL-ACTIVE-3F9C"
DERIVED="$(mktemp -d /tmp/kirole-boundary.XXXXXX)"
trap 'rm -rf "$DERIVED"' EXIT

build() {
  local scheme="$1" config="$2"
  local log="$DERIVED/$config.log"
  echo "== Building $scheme ($config)"
  if ! xcodebuild -workspace Kirole.xcworkspace \
      -scheme "$scheme" \
      -configuration "$config" \
      -destination "generic/platform=iOS Simulator" \
      -derivedDataPath "$DERIVED" \
      build > "$log" 2>&1; then
    echo "BUILD FAILED ($config) — last 40 log lines:"
    tail -40 "$log"
    exit 2
  fi
}

build Kirole-Internal InternalRelease
build Kirole-AppStore AppStoreRelease

INTERNAL_APP="$DERIVED/Build/Products/InternalRelease-iphonesimulator/Kirole.app"
APPSTORE_APP="$DERIVED/Build/Products/AppStoreRelease-iphonesimulator/Kirole.app"
INTERNAL_BIN="$INTERNAL_APP/Kirole"
APPSTORE_BIN="$APPSTORE_APP/Kirole"

# Search the Mach-O for UTF-8 or UTF-16LE. `strings` misses Swift small-string
# immediates (<=15 UTF-8 bytes) and UTF-16 literals. InternalBuildBoundary
# keeps a longer `toolPhrases` table so short UI titles remain findable.
binary_contains() {
  local bin="$1"
  local phrase="$2"
  python3 - "$bin" "$phrase" <<'PY'
import sys
path, phrase = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
if phrase.encode("utf-8") in data or phrase.encode("utf-16le") in data:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

demangle_symbols() {
  local bin="$1"
  local output="$2"
  nm -gj "$bin" 2>/dev/null | xcrun swift-demangle > "$output"
}

fail=0
if binary_contains "$INTERNAL_BIN" "$MARKER"; then
  echo "PASS  InternalRelease binary contains the boundary marker"
else
  echo "FAIL  InternalRelease binary is missing the boundary marker"
  fail=1
fi

if binary_contains "$APPSTORE_BIN" "$MARKER"; then
  echo "FAIL  AppStoreRelease binary contains the boundary marker"
  fail=1
else
  echo "PASS  AppStoreRelease binary has no boundary marker"
fi

# Exact UI phrases that must compile only into InternalRelease. Keep these
# case-sensitive and in sync with Kirole/Internal/*.swift.
INTERNAL_ONLY_STRINGS=(
  "Wi-Fi PC Debug"
  "Focus Debug"
  "Shipping Mode"
  "Start Test Focus Session"
  "1 second = 1 minute"
)

for phrase in "${INTERNAL_ONLY_STRINGS[@]}"; do
  if binary_contains "$INTERNAL_BIN" "$phrase"; then
    echo "PASS  InternalRelease binary contains '$phrase'"
  else
    echo "FAIL  InternalRelease binary is missing '$phrase'"
    fail=1
  fi
  if binary_contains "$APPSTORE_BIN" "$phrase"; then
    echo "FAIL  AppStoreRelease binary contains '$phrase'"
    fail=1
  else
    echo "PASS  AppStoreRelease binary has no '$phrase'"
  fi
done

INTERNAL_SYMBOLS="$DERIVED/InternalRelease.symbols"
APPSTORE_SYMBOLS="$DERIVED/AppStoreRelease.symbols"
demangle_symbols "$INTERNAL_BIN" "$INTERNAL_SYMBOLS"
demangle_symbols "$APPSTORE_BIN" "$APPSTORE_SYMBOLS"

INTERNAL_ONLY_SYMBOLS=(
  "Kirole.BLEWiFiDebugCoordinator"
  "Kirole.BLEShippingModeCoordinator"
)

for symbol in "${INTERNAL_ONLY_SYMBOLS[@]}"; do
  if grep -Fq "$symbol" "$INTERNAL_SYMBOLS"; then
    echo "PASS  InternalRelease binary contains '$symbol'"
  else
    echo "FAIL  InternalRelease binary is missing '$symbol'"
    fail=1
  fi
  if grep -Fq "$symbol" "$APPSTORE_SYMBOLS"; then
    echo "FAIL  AppStoreRelease binary contains '$symbol'"
    fail=1
  else
    echo "PASS  AppStoreRelease binary has no '$symbol'"
  fi
done

LEGACY_CUSTOMER_SYMBOLS=(
  "KiroleFeature.BLEWiFiDebugCoordinator"
  "KiroleFeature.BLEShippingModeCoordinator"
  "KiroleFeature.BLEService.sendWiFiDebugCommand"
  "KiroleFeature.BLEService.sendShippingModeCommand"
)

for symbol in "${LEGACY_CUSTOMER_SYMBOLS[@]}"; do
  if grep -Fq "$symbol" "$APPSTORE_SYMBOLS"; then
    echo "FAIL  AppStoreRelease binary contains legacy internal symbol '$symbol'"
    fail=1
  else
    echo "PASS  AppStoreRelease binary has no legacy internal symbol '$symbol'"
  fi
done

# Diagnostic os.Logger categories reachable from the customer binary.
#
# AGENTS.md "Release Channel Policy" bans internal diagnostics from
# AppStoreRelease, with one narrow exception for passive, anomaly-only fault
# records (see the authorised-records table there). This check enforces the
# "Registered" condition of that exception: every logger category compiled
# into the customer binary must appear below. A new ungated diagnostic
# therefore fails the gate instead of shipping unnoticed — which is the whole
# point of allow-listing rather than simply dropping the rule.
#
# Adding a category here is a policy decision: it must first satisfy all four
# conditions in AGENTS.md and be listed in that table.
AUTHORISED_CUSTOMER_LOG_CATEGORIES=(
  "FocusReconnect"
)

# Categories that must never reach the customer binary. These back capabilities
# (raw frame traces, factory tooling), not fault records.
INTERNAL_ONLY_LOG_CATEGORIES=(
  "BLEDisconnect"
)

for category in "${AUTHORISED_CUSTOMER_LOG_CATEGORIES[@]}"; do
  if binary_contains "$APPSTORE_BIN" "$category"; then
    echo "PASS  AppStoreRelease binary carries authorised log category '$category'"
  else
    # Not fatal on its own, but the table in AGENTS.md is then stale.
    echo "FAIL  AppStoreRelease binary is missing authorised log category '$category' (AGENTS.md table is out of date?)"
    fail=1
  fi
done

for category in "${INTERNAL_ONLY_LOG_CATEGORIES[@]}"; do
  if binary_contains "$APPSTORE_BIN" "$category"; then
    echo "FAIL  AppStoreRelease binary contains internal-only log category '$category'"
    fail=1
  else
    echo "PASS  AppStoreRelease binary has no internal-only log category '$category'"
  fi
done

# Files used by Xcode, local tooling, or backend setup must remain in the
# repository but must not be copied into the customer application bundle.
APPSTORE_FORBIDDEN_RESOURCES=(
  "Kirole.xctestplan"
  "Secrets.xcconfig.template"
  "generate-prompt-spec.py"
  "scripts-generate-build-secrets.sh"
  "supabase-schema.sql"
)

for resource in "${APPSTORE_FORBIDDEN_RESOURCES[@]}"; do
  if find "$APPSTORE_APP" -type f -name "$resource" -print -quit | grep -q .; then
    echo "FAIL  AppStoreRelease bundle contains engineering file '$resource'"
    fail=1
  else
    echo "PASS  AppStoreRelease bundle has no engineering file '$resource'"
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "Release-channel boundary verified."
else
  echo "Release-channel boundary VIOLATED — do not distribute."
fi
exit "$fail"
