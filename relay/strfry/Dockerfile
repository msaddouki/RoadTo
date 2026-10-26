# RoadTo relay: strfry with the RoadTo write-policy plugin.
# Build from the repository root:
#   docker build -f relay/strfry/Dockerfile -t roadto-relay .

FROM dart:3.13.7-sdk AS build
WORKDIR /src
COPY packages/roadto_core packages/roadto_core
COPY relay/strfry_policy relay/strfry_policy
COPY relay/traffic_bot relay/traffic_bot
WORKDIR /src/relay/strfry_policy
RUN dart pub get && dart build cli -t bin/roadto_policy.dart -o /out
# The traffic robot (docs/traffic-feed.md), started when ROADTO_TRAFFIC_KEY is set.
WORKDIR /src/relay/traffic_bot
RUN dart pub get && dart build cli -t bin/traffic_bot.dart -o /out-traffic

FROM dockurr/strfry:1.1.3
# The strfry image is Alpine (musl); the Dart binary needs glibc. The Dart
# image ships a minimal glibc runtime in /runtime, in paths musl does not use.
COPY --from=build /runtime/ /
COPY --from=build /out/bundle/bin/roadto_policy /app/roadto-policy
COPY --from=build /out-traffic/bundle/bin/traffic_bot /app/roadto-traffic
COPY relay/strfry/strfry.conf /etc/strfry.conf
COPY relay/strfry/roadto-start.sh /app/roadto-start.sh
COPY relay/strfry/redact_logs.py /app/redact_logs.py
# The router (replication) starts its own plugin instance: same rules, but it
# must not try to serve the metrics port the relay's instance already holds.
RUN printf '#!/bin/sh\nunset ROADTO_METRICS_PORT\nexec /app/roadto-policy "$@"\n' > /app/roadto-policy-peer \
 && chmod +x /app/roadto-start.sh /app/roadto-policy /app/roadto-policy-peer /app/roadto-traffic
CMD ["/app/roadto-start.sh"]
