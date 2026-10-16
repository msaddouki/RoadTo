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
# A test that fails inside an async callback can leave `flutter drive`
# waiting forever: give up after 20 minutes (build included; a run takes ~7).
timeout --kill-after=30s 20m \
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
  > >(tee "$OUT/drive.log") 2>&1 &
DRIVE=$!

# The app prints its own verdict ("All tests passed!" / "Some tests failed.").
# The host side sometimes never receives the results afterwards and waits
# until the timeout (about one run in three on CI): once the app has spoken,
# give flutter drive 2 minutes to finish, then go by the app's verdict.
verdict=
while kill -0 "$DRIVE" 2>/dev/null; do
  if grep -qE 'I/flutter.*: All tests passed!' "$OUT/drive.log"; then verdict=pass; break; fi
  if grep -qE 'I/flutter.*: Some tests failed\.' "$OUT/drive.log"; then verdict=fail; break; fi
  sleep 5
done
if [[ -n $verdict ]]; then
  for _ in $(seq 24); do kill -0 "$DRIVE" 2>/dev/null || break; sleep 5; done
fi
if [[ -n $verdict ]] && kill -0 "$DRIVE" 2>/dev/null; then
  echo "::warning::flutter drive did not return after the app reported '$verdict'; using the app's verdict"
  kill "$DRIVE" 2>/dev/null
  wait "$DRIVE" 2>/dev/null
  [[ $verdict == pass ]] && status=0 || status=1
else
  wait "$DRIVE"
  status=$?
  [[ $status == 124 ]] && echo "::error::flutter drive did not finish within 20 minutes"
fi

kill "$SHOTS" 2>/dev/null
cp build/integration_response_data.json "$OUT/" 2>/dev/null
adb shell dumpsys meminfo "$APP_ID" > "$OUT/meminfo.txt" 2>&1
adb logcat -d > "$OUT/logcat.txt" 2>&1
# Empty captures (device busy or screen not ready) are dropped.
find "$OUT/screens" -name '*.png' -size 0 -delete

echo "Steps:"
grep -o 'ROADTO_STEP .*' "$OUT/drive.log" || true
exit "$status"
