# roadto-relay (Helm chart)

Federated RoadTo relays on Kubernetes: strfry with the RoadTo write-policy
plugin (`relay/strfry`), as a StatefulSet. Each relay keeps its own database
on a volume and replicates with every other relay of the release: live
stream (strfry router) plus periodic negentropy reconciliation, both through
the same policy. CI installs it on a kind cluster with two relays, publishes
on one and reads from the other, and checks metrics and logs.

## Install

The image is built from the repository root:

```bash
docker build -f relay/strfry/Dockerfile -t <registry>/roadto-relay:0.1.0 .
docker push <registry>/roadto-relay:0.1.0

helm install roadto-relay deploy/helm/roadto-relay \
  --set image.repository=<registry>/roadto-relay \
  --set ingress.enabled=true --set ingress.host=relay.example.org \
  --set ingress.tlsSecretName=relay-tls --set realIpHeader=x-forwarded-for
```

The app's relay list then gets `wss://relay.example.org`. Clients may reach
any relay: they hold the same events.

## Values that matter

| Value | Default | |
| --- | --- | --- |
| `replicaCount` | 2 | relays replicating each other |
| `realIpHeader` | empty | **set it behind an ingress** (`x-forwarded-for` with ingress-nginx): otherwise every client shares the ingress address, and its rate limit |
| `ratePerMinute` | 30 | events accepted per client address and per minute |
| `syncIntervalSeconds` | 300 | negentropy reconciliation with each peer |
| `persistence.size` | 10Gi | LMDB database of each relay |
| `metrics.enabled` / `metrics.port` | true / 9464 | Prometheus counters, pod annotations for scraping |
| `metrics.serviceMonitor.enabled` | false | ServiceMonitor (Prometheus Operator) |

## Metrics

The write-policy plugin counts its decisions:

```
roadto_policy_decisions_total{action="accept",reason="ok",source="client",kind="alert"} 12
roadto_policy_decisions_total{action="reject",reason="rate-limited",source="client",kind="alert"} 3
roadto_policy_rate_limit_sources 41
```

Labels are classes only (`reason`: ok, blocked, invalid, pow, rate-limited;
`source`: client, stream, sync; `kind`: alert, confirmation, other), never
an address, a key, an event or a position. The counters live in the
plugin process that strfry starts for client events; the router's own
plugin instance (replication) serves none.

## Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: roadto-relay
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/msaddouki/RoadTo.git
    targetRevision: master
    path: deploy/helm/roadto-relay
    helm:
      valuesObject:
        image:
          repository: <registry>/roadto-relay
        realIpHeader: x-forwarded-for
        ingress:
          enabled: true
          host: relay.example.org
          tlsSecretName: relay-tls
  destination:
    server: https://kubernetes.default.svc
    namespace: roadto
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

A second, independent operator federates by listing their relay next to
yours in the app; relays of different operators do not need to replicate.
