#!/usr/bin/env bash
# Frees disk on a GitHub-hosted Ubuntu runner by removing preinstalled
# toolchains RoadTo never uses. Keeps the Android SDK, Java and Python.
set -uo pipefail
df -h /
sudo rm -rf \
  /usr/share/dotnet \
  /usr/local/.ghcup /opt/ghc \
  /usr/local/share/boost \
  /usr/share/swift \
  /usr/local/julia* \
  /opt/hostedtoolcache/CodeQL \
  /opt/hostedtoolcache/go \
  /opt/hostedtoolcache/Ruby \
  /opt/hostedtoolcache/PyPy \
  /opt/microsoft /opt/google/chrome /usr/lib/firefox \
  /usr/local/share/powershell /usr/local/share/chromium
sudo docker image prune --all --force >/dev/null 2>&1 || true
df -h /
