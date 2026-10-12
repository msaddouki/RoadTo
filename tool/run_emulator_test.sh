#!/usr/bin/env bash
# Runs the end-to-end test (app/integration_test/app_test.dart) on the
# connected Android emulator or device, with a screenshot every few seconds.
#
#   tool/run_emulator_test.sh [output-dir]      (default: build/emulator-test)
#
# Embed the region first: tool/embed_region.sh lyon --with-routing
# The output directory gets the screenshots, the `flutter drive` log, the
# step timings (integration_response_data.json), logcat and the app's memory.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/emulator-test}"
APP_ID=org.roadto.roadto
mkdir -p "$OUT/screens"
# Absolute: the script changes directory before writing its results.
OUT="$(cd "$OUT" && pwd)"

adb wait-for-device
adb logcat -c || true

(
  i=0
  while true; do
    sleep 5
    adb exec-out screencap -p > "$OUT/screens/$(printf %03d "$i").png" 2>/dev/null || true
    i=$((i + 1))
  done
) &
SHOTS=$!
trap 'kill "$SHOTS" 2>/dev/null' EXIT

cd "$ROOT/app"
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart 2>&1 \
  | tee "$OUT/drive.log"
status=${PIPESTATUS[0]}

kill "$SHOTS" 2>/dev/null
cp build/integration_response_data.json "$OUT/" 2>/dev/null
adb shell dumpsys meminfo "$APP_ID" > "$OUT/meminfo.txt" 2>&1
adb logcat -d > "$OUT/logcat.txt" 2>&1
# Empty captures (device busy or screen not ready) are dropped.
find "$OUT/screens" -name '*.png' -size 0 -delete

echo "Steps:"
grep -o 'ROADTO_STEP .*' "$OUT/drive.log" || true
exit "$status"
