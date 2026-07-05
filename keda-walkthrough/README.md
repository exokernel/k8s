# KEDA Walkthrough (Kind)

Following https://keda.sh/docs/latest/concepts/ and the
[deploy guide](https://keda.sh/docs/latest/deploy/).

KEDA (Kubernetes Event-Driven Autoscaling) lives on the same tier as HPA —
scaling *replica count* — but on different signals: where HPA reacts to
resource metrics (CPU/memory via metrics-server), KEDA reacts to external
event sources (~70 built-in scalers: queue depth, Kafka lag, Prometheus
queries, cron schedules, ...). It also does what plain HPA can't: **scale to
zero**. KEDA doesn't replace HPA — a `ScaledObject` creates and manages an
HPA under the hood, feeding it external metrics; KEDA itself handles the
0 ↔ 1 transition.

This walkthrough uses the **cron scaler** (a recurring schedule) because it
needs no event source to stand up — no metrics-server either.

## Environment

```sh
colima start
kind create cluster --name keda          # context: kind-keda
```

## 1. Install KEDA

```sh
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

Verify the three components are running:

```sh
kubectl get pods -n keda
# keda-operator-...                     Running
# keda-operator-metrics-apiserver-...   Running   (serves the external metrics API to HPA)
# keda-admission-webhooks-...           Running
```

## 2. Deploy the workload and ScaledObject

`cron-nginx.yaml` holds a plain nginx deployment plus a `ScaledObject` whose
cron trigger wants **5 replicas during the first half of every 10-minute
block** (:00–:05, :10–:15, ... UTC) and is inactive otherwise. With
`minReplicaCount: 0`, inactive means zero pods:

```sh
kubectl apply -f cron-nginx.yaml
kubectl get scaledobject
```

Note KEDA created an HPA to do the >1 scaling math:

```sh
kubectl get hpa
# keda-hpa-nginx-cron ...
```

## 3. Watch it scale (both directions)

```sh
kubectl get pods --watch
```

What you'll see, depending on where the clock is in the 10-minute cycle:

- **Inside a window** (minutes :00–:05): pods jump to 5.
- **Outside a window** (minutes :05–:10): the deployment drops to 0 within
  about a minute — the HPA scales 5 → 1, then KEDA scales 1 → 0 once
  `cooldownPeriod` (60s) has elapsed since the trigger last reported active.

`READY`/`ACTIVE` state is visible on the ScaledObject too:

```sh
kubectl get scaledobject nginx-cron --watch
```

You're never more than 5 minutes from the next transition; a full 0 → 5 → 0
cycle takes 10 minutes.

## Notes

- `cooldownPeriod` only governs the final drop to zero; scale-down from 5 → 1
  is normal HPA behavior (the demo sets its downscale stabilization window to
  0s; the HPA default is 5 minutes).
- Scaling on real event sources is the same shape: swap the cron trigger for
  e.g. `prometheus`, `kafka`, or `aws-sqs-queue` in `triggers` — see the
  [scaler catalog](https://keda.sh/docs/latest/scalers/).
- For scaling on *incoming HTTP traffic* (0 → N on requests), that's the
  separate [http-add-on](https://github.com/kedacore/http-add-on) project.

## Teardown

```sh
kubectl delete -f cron-nginx.yaml
helm uninstall keda -n keda
kind delete cluster --name keda
colima stop                              # optional: stop the Docker runtime
```
