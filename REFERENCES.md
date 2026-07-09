# References & Speaking Prep

Reading list to back the [autoscaling walkthroughs](README.md) and a short talk on
the topic. Ordered roughly by priority within each section; ⭐ = read this one if
you read nothing else. All links verified 2026-07.

## Start here (the framing)

- ⭐ [Autoscaling Workloads](https://kubernetes.io/docs/concepts/workloads/autoscaling/)
  — the overview that splits autoscaling into scaling *workloads* (HPA/VPA) vs.
  scaling the *cluster* (nodes). Good for the "What and Why" and "Breakdown" slides.
- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
  — where CPU/memory numbers come from (metrics-server → `metrics.k8s.io`). Both
  HPA and VPA depend on this; be ready to explain why `kubectl top` and the demos
  need metrics-server, and why Kind needs the `--kubelet-insecure-tls` patch.

## HPA

- ⭐ [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
  — the concept + the exact algorithm behind your formula slide
  (`desiredReplicas = ceil[currentReplicas × (currentMetric / desiredMetric)]`).
  Know the tolerance (no action within ~10% of target), the sync period (~15s),
  and the scale-down stabilization window (default 300s — the knob the demo
  shortens).
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
  — the upstream php-apache demo the [hpa-walkthrough](hpa-walkthrough/README.md)
  is based on.

Likely questions to have an answer for: multiple metrics (highest wins), why it
won't scale below 1 by default (scale-to-zero is gated — see KEDA), and how HPA
and VPA conflict on the same metric.

## VPA

- ⭐ [Vertical Pod Autoscaling](https://kubernetes.io/docs/concepts/workloads/autoscaling/vertical-pod-autoscale/)
  — components (recommender / updater / admission controller), update modes, and
  the resource-policy bounds. Matches your VPA architecture-diagram slide.
- [VPA project (kubernetes/autoscaler)](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
  — install (`vpa-up.sh`), the hamster example, and the known-limitations doc.

Be ready to explain: why the default mode *evicts* pods (and how
`InPlaceOrRecreate` changes that on 1.33+), and why you shouldn't point HPA and
VPA at the same resource.

## KEDA

- ⭐ [KEDA Concepts](https://keda.sh/docs/latest/concepts/)
  — how KEDA relates to HPA (it *creates and drives* an HPA) and owns the 0↔1
  transition for scale-to-zero.
- [Scaling Deployments (ScaledObject)](https://keda.sh/docs/latest/concepts/scaling-deployments/)
  — `minReplicaCount: 0`, `cooldownPeriod`, and the activation vs. scaling
  distinction that the cron demo relies on.
- [Scaler catalog](https://keda.sh/docs/latest/scalers/) — the ~70 event sources;
  skim so you can name real ones (Kafka lag, SQS, Prometheus) beyond the cron demo.

## Node autoscaling

- ⭐ [Node Autoscaling](https://kubernetes.io/docs/concepts/cluster-administration/node-autoscaling/)
  — the concept and the Cluster Autoscaler vs. Karpenter comparison.
- [Karpenter concepts](https://karpenter.sh/docs/concepts/) — NodePool / NodeClass,
  provisioning, and consolidation (the disruption controls). Backs your Karpenter slide.
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
  — the definitive "how does scale-down decide" reference (PodDisruptionBudgets,
  what blocks a node from being removed).

### GKE (what we actually run)

- [About GKE cluster autoscaling](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler)
  — resizes node pools within min/max; decides on requests, not usage.
- [Configure node pool auto-creation](https://cloud.google.com/kubernetes-engine/docs/how-to/node-auto-provisioning)
  — GKE's Karpenter-like model (node auto-provisioning / ComputeClasses).
- [GKE Autopilot overview](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)
  — Google's *recommended* default; nodes fully managed. Know the Autopilot-vs-Standard
  decision, since "is NAP the best practice?" really resolves to that.
