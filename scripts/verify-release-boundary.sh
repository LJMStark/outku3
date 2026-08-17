#!/bin/bash
# Paired release-channel gate (AGENTS.md "Release Channel Policy").
#
# Builds both distribution configurations for the iOS simulator and asserts:
#   - InternalRelease  contains the KIROLE_INTERNAL boundary marker
#   - AppStoreRelease  does NOT contain it
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

INTERNAL_BIN="$DERIVED/Build/Products/InternalRelease-iphonesimulator/Kirole.app/Kirole"
APPSTORE_BIN="$DERIVED/Build/Products/AppStoreRelease-iphonesimulator/Kirole.app/Kirole"

# Dump strings to files first: piping `strings` straight into `grep -q` under
# pipefail turns an early match into SIGPIPE(141) for strings and flips the
# pipeline status — a found marker would be reported as missing.
strings "$INTERNAL_BIN" > "$DERIVED/internal.strings"
strings "$APPSTORE_BIN" > "$DERIVED/appstore.strings"

fail=0
if grep -q "$MARKER" "$DERIVED/internal.strings"; then
  echo "PASS  InternalRelease binary contains the boundary marker"
else
  echo "FAIL  InternalRelease binary is missing the boundary marker"
  fail=1
fi

if grep -q "$MARKER" "$DERIVED/appstore.strings"; then
  echo "FAIL  AppStoreRelease binary contains the boundary marker"
  fail=1
else
  echo "PASS  AppStoreRelease binary has no boundary marker"
fi

if [ "$fail" -eq 0 ]; then
  echo "Release-channel boundary verified."
else
  echo "Release-channel boundary VIOLATED — do not distribute."
fi
exit "$fail"
