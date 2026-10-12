#!/usr/bin/env bash
# Fails if a Firebase, advertising or analytics dependency shows up in the
# Android build (cross-cutting rule of the plan).
#
# Known exception, to remove in milestone J2: play-services-location, pulled
# by geolocator. The app forces Android's LocationManager and so never calls
# Google services at run time, but the library is shipped.
set -euo pipefail
deps="${1:?usage: check_no_trackers.sh deps.txt}"

forbidden='com\.google\.firebase|com\.google\.android\.gms:play-services-(ads|analytics|measurement)|com\.crashlytics|io\.sentry|com\.facebook|com\.appsflyer|com\.adjust|com\.amplitude|com\.mixpanel|com\.segment'

if grep -Eo "$forbidden[^ ]*" "$deps" | sort -u | grep .; then
  echo "::error::Forbidden dependency in the build (see above)."
  exit 1
fi

if grep -q 'com.google.android.gms' "$deps"; then
  echo "::warning::Google services present (known debt, to remove in J2):"
  grep -Eo 'com\.google\.android\.gms:[a-z-]+' "$deps" | sort -u
fi
echo "No tracker found."
