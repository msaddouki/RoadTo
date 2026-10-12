#!/usr/bin/env bash
# Échoue si une dépendance Firebase, publicitaire ou de mesure d'audience
# apparaît dans le build Android (règle transverse du plan).
#
# Exception connue, à résorber au jalon J2 : play-services-location, tiré par
# geolocator. L'app force le LocationManager d'Android et n'appelle donc pas
# les services Google à l'exécution, mais la bibliothèque est embarquée.
set -euo pipefail
deps="${1:?usage: check_no_trackers.sh deps.txt}"

forbidden='com\.google\.firebase|com\.google\.android\.gms:play-services-(ads|analytics|measurement)|com\.crashlytics|io\.sentry|com\.facebook|com\.appsflyer|com\.adjust|com\.amplitude|com\.mixpanel|com\.segment'

if grep -Eo "$forbidden[^ ]*" "$deps" | sort -u | grep .; then
  echo "::error::Dépendance interdite dans le build (voir ci-dessus)."
  exit 1
fi

if grep -q 'com.google.android.gms' "$deps"; then
  echo "::warning::Services Google présents (dette connue, à retirer au J2) :"
  grep -Eo 'com\.google\.android\.gms:[a-z-]+' "$deps" | sort -u
fi
echo "Aucun traceur détecté."
