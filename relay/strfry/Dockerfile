# RoadTo relay: strfry with the RoadTo write-policy plugin.
# Build from the repository root:
#   docker build -f relay/strfry/Dockerfile -t roadto-relay .

FROM dart:3.13.5-sdk AS build
WORKDIR /src
COPY packages/roadto_core packages/roadto_core
COPY relay/strfry_policy relay/strfry_policy
WORKDIR /src/relay/strfry_policy
RUN dart pub get && dart build cli -t bin/roadto_policy.dart -o /out

FROM dockurr/strfry:1.1.3
# The strfry image is Alpine (musl); the Dart binary needs glibc. The Dart
# image ships a minimal glibc runtime in /runtime, in paths musl does not use.
COPY --from=build /runtime/ /
COPY --from=build /out/bundle/bin/roadto_policy /app/roadto-policy
COPY relay/strfry/strfry.conf /etc/strfry.conf
COPY relay/strfry/roadto-start.sh /app/roadto-start.sh
COPY relay/strfry/redact_logs.py /app/redact_logs.py
RUN chmod +x /app/roadto-start.sh /app/roadto-policy
CMD ["/app/roadto-start.sh"]
