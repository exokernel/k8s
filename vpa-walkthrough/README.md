# VPA Walkthrough (Kind)

Following https://kubernetes.io/docs/concepts/workloads/autoscaling/vertical-pod-autoscale/
and the VPA project [quickstart](https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/docs/quickstart.md).

Where HPA scales the number of replicas, VPA rightsizes each pod: it watches
actual CPU/memory usage and adjusts the pods' resource requests to match.
VPA is not part of core Kubernetes; it's a CRD plus three controllers
(recommender, updater, admission webhook) installed from the
[kubernetes/autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) repo.

## Environment

Same base setup as the HPA walkthrough (see [../hpa-walkthrough/README.md](../hpa-walkthrough/README.md)
for details on each step):

```sh
colima start
kind create cluster --name vpa           # context: kind-vpa
```

### Pre-pull images (optional, for a reliable demo)

Image pulls from `registry.k8s.io` occasionally stall inside the Colima VM
(the blobs redirect to Artifact Registry, and the guest's containerd can wedge),
leaving pods stuck in `ContainerCreating` — including the metrics-server and VPA
installs below. Before presenting, pre-pull every image the demo uses
(metrics-server, the three VPA components, and the hamster workload) into the
Kind node so nothing hits the network live (`colima restart` also clears a stuck
pull if one happens):

```sh
for img in \
  registry.k8s.io/metrics-server/metrics-server:v0.8.1 \
  registry.k8s.io/autoscaling/vpa-recommender:1.7.0 \
  registry.k8s.io/autoscaling/vpa-updater:1.7.0 \
  registry.k8s.io/autoscaling/vpa-admission-controller:1.7.0 \
  registry.k8s.io/ubuntu-slim:0.14 ; do
  docker exec vpa-control-plane crictl pull "$img"
done
```

(Versions track the manifests: metrics-server from `components.yaml`, the
`vpa-*` images from the autoscaler `deploy/` manifests, both current above.)

### Install metrics-server

VPA's recommender reads from the resource metrics API:

```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status -n kube-system deployment/metrics-server
```

Sanity check (metrics take ~15-30s to start flowing):

```sh
kubectl top nodes
```

## 1. Install VPA

VPA is installed from the autoscaler repo's install script, which deploys the
CRDs and the three components into `kube-system` (it also generates certs for
the admission webhook, so it needs `openssl` on your PATH):

```sh
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
```

Verify all three components are running:

```sh
kubectl get pods -n kube-system | grep vpa
# vpa-admission-controller-...   Running
# vpa-recommender-...            Running
# vpa-updater-...                Running
```

## 2. Deploy the example workload

The `hamster` deployment (the VPA project's official example) runs 2 pods that
burn CPU in half-second bursts, requesting only 100m CPU / 50Mi memory, less
than they actually use. The accompanying VerticalPodAutoscaler targets the
deployment with min/max bounds per container:

```sh
kubectl apply -f hamster.yaml
kubectl get pods -l app=hamster
```

Note the initial requests on a pod (100m CPU, 50Mi memory):

```sh
kubectl describe pod -l app=hamster | grep -A2 Requests
```

## 3. Watch VPA recommend and apply

The recommender needs a few minutes of usage history. Watch the
recommendation appear in the VPA status:

```sh
kubectl get vpa hamster-vpa --watch
```

Once `TARGET CPU` shows a value (typically ~500m+), inspect the full
recommendation (lower bound / target / upper bound):

```sh
kubectl describe vpa hamster-vpa
```

The default update mode (`Auto`, currently an alias for `Recreate`) means the
updater will **evict** pods whose requests drift too far from the target; the
admission webhook then sets the new requests on the replacement pods. Watch
pods get recreated (usually within ~5 minutes of the recommendation appearing):

```sh
kubectl get pods -l app=hamster --watch
```

Then confirm the new pods got higher requests:

```sh
kubectl describe pod -l app=hamster | grep -A2 Requests
```

Note: the updater only evicts when at least 2 replicas exist (its default
`--min-replicas=2`), which is why the example runs 2 pods.

## Update modes

Set via `spec.updatePolicy.updateMode` in the VPA object:

| Mode                | Behavior                                                        |
|---------------------|-----------------------------------------------------------------|
| `Off`               | Recommendations only (in `.status`); nothing applied. Good for dry-run rightsizing. |
| `Initial`           | Applied only when pods are created; running pods untouched.     |
| `Recreate`          | Evicts pods so replacements pick up new requests.               |
| `Auto` (default)    | Deprecated alias for `Recreate`.                                |
| `InPlaceOrRecreate` | Resizes in place when possible, falls back to eviction (needs K8s 1.33+ in-place pod resize). |

## Teardown

```sh
kubectl delete -f hamster.yaml
./hack/vpa-down.sh          # from autoscaler/vertical-pod-autoscaler
kind delete cluster --name vpa
colima stop                 # optional: stop the Docker runtime
```
