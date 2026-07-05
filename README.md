# Kubernetes Autoscaling Walkthroughs

Hands-on walkthroughs of the Kubernetes autoscaling stack, each run locally on
[Colima](https://github.com/abiosoft/colima) + [Kind](https://kind.sigs.k8s.io)
and following an official doc. Autoscaling happens at three tiers:

| Tier | What it scales | Signal | Walkthrough |
|------|----------------|--------|-------------|
| Pod count | replicas | CPU/memory usage (metrics-server) | [hpa-walkthrough](hpa-walkthrough/README.md) |
| Pod count | replicas | external events (queues, cron, ...); scale-to-zero | [keda-walkthrough](keda-walkthrough/README.md) |
| Pod size | resource requests | actual CPU/memory usage | [vpa-walkthrough](vpa-walkthrough/README.md) |
| Node count | nodes | pending pods' resource requests | [karpenter-walkthrough](karpenter-walkthrough/README.md) |

How they compose: HPA or KEDA adds replicas → the new pods' *requests* exceed
cluster capacity → they go Pending → the node autoscaler (Karpenter) adds
nodes. VPA rightsizes the requests themselves, which feeds both of the above.
(Don't point HPA and VPA at the same metric on the same workload — they'll
fight.)

- **[hpa-walkthrough](hpa-walkthrough/README.md)** — HorizontalPodAutoscaler:
  built-in, scales replicas on CPU utilization; load-generate against
  php-apache and watch it scale 1 → N and back.
- **[keda-walkthrough](keda-walkthrough/README.md)** — KEDA: event-driven
  replica scaling on ~70 external sources; drives an HPA under the hood and
  adds scale-to-zero. Demo uses the cron scaler (0 → 5 → 0 on a schedule).
- **[vpa-walkthrough](vpa-walkthrough/README.md)** — VerticalPodAutoscaler:
  watches actual usage and adjusts pods' resource requests; watch the
  under-provisioned hamster pods get evicted and rightsized.
- **[karpenter-walkthrough](karpenter-walkthrough/README.md)** — node
  autoscaling with Karpenter's KWOK provider (fake nodes, real control loop):
  watch pending pods provision nodes, then consolidation remove them.
