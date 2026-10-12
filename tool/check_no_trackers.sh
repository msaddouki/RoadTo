#!/usr/bin/env bash
# Fails if a Firebase, advertising or analytics dependency, or any Google Play
# Services library, shows up in the Android build (cross-cutting rule of the
# plan: the app runs on phones without Google services, e.g. de-Googled ones).
set -euo pipefail
deps="${1:?usage: check_no_trackers.sh deps.txt}"

forbidden='com\.google\.firebase|com\.google\.android\.gms|com\.crashlytics|io\.sentry|com\.facebook|com\.appsflyer|com\.adjust|com\.amplitude|com\.mixpanel|com\.segment'

if grep -Eo "($forbidden)[^ ]*" "$deps" | sort -u | grep .; then
  echo "::error::Forbidden dependency in the build (see above)."
  exit 1
fi

echo "No tracker found."
