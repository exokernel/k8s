# Node Autoscaling Walkthrough (Karpenter + KWOK on Kind)

Following https://kubernetes.io/docs/concepts/cluster-administration/node-autoscaling/
using [Karpenter](https://karpenter.sh) with its
[KWOK provider](https://github.com/kubernetes-sigs/karpenter/tree/main/kwok).

Where HPA scales replica count and VPA rightsizes each pod, node autoscaling
changes the number of *nodes*: provision more when pods can't schedule, remove
them when they're underutilized. Real node autoscalers create cloud VMs, which
a local Kind cluster can't do — so this walkthrough uses KWOK (Kubernetes
WithOut Kubelet), which fakes the nodes. The Karpenter control loop is real
(watching pending pods, picking instance types, consolidating); only the
compute behind the `Node` objects is simulated.

Unlike HPA/VPA, node autoscaling keys off pod **resource requests**, not live
usage — so no metrics-server this time.

## Environment

```sh
colima start
kind create cluster --name karpenter     # context: kind-karpenter
```

## 1. Install Karpenter (KWOK provider)

Karpenter's KWOK flavor is built from source out of the
[kubernetes-sigs/karpenter](https://github.com/kubernetes-sigs/karpenter) repo.
Needs **Go**, **Helm**, **ko**, and **yq** on your PATH (plus Docker):

```sh
go install github.com/google/ko@latest          # builds/sideloads the image
go install github.com/mikefarah/yq/v4@latest    # used by the repo's codegen scripts
```

```sh
git clone https://github.com/kubernetes-sigs/karpenter.git
cd karpenter

export KWOK_REPO=kind.local              # tells ko to load the image into Kind
export KIND_CLUSTER_NAME=karpenter
make install-kwok                        # installs the KWOK controller
make apply                               # builds Karpenter and helm-installs it
```

Verify both are running:

```sh
kubectl get pods -n kube-system | grep -E 'karpenter|kwok'
```

**If the karpenter pod shows `InvalidImageName`:** the Makefile expects ko to
print an image digest, but ko's Kind sideload returns a tag-only ref, so the
chart renders a garbage `repo:tag@repo:tag` image. Clear the digest and let it
roll out:

```sh
helm upgrade karpenter kwok/charts -n kube-system --reuse-values \
  --set controller.image.digest=""
kubectl rollout status -n kube-system deployment/karpenter
```

## 2. Create the NodePool

A `NodePool` declares *constraints* on the nodes Karpenter may create
(arch, OS, capacity type), a CPU limit for the whole pool, and the
consolidation policy for scale-down. The `KWOKNodeClass` is the provider-
specific half (real providers use e.g. `EC2NodeClass` here). Note the pool
allows only `on-demand` capacity: with `spot`, Karpenter would refuse the
scale-down demo below (`SpotToSpotConsolidation` is off by default — check
`kubectl get events` for `Unconsolidatable` if consolidation ever seems stuck):

```sh
kubectl apply -f nodepool.yaml
kubectl get nodepool
```

## 3. Taint the existing node

Taint the Kind control-plane node so demo pods can't land on it and must wait
for Karpenter-provisioned nodes (already-running pods are unaffected):

```sh
kubectl taint nodes karpenter-control-plane CriticalAddonsOnly:NoSchedule
```

## 4. Trigger scale-up

The `inflate` deployment runs pause containers requesting 1 CPU each (starts
at 0 replicas). In a **separate terminal**, watch nodes and nodeclaims:

```sh
kubectl get nodeclaims,nodes --watch
```

Then scale up:

```sh
kubectl apply -f inflate.yaml
kubectl scale deployment inflate --replicas=5
```

The 5 pods go Pending, Karpenter bin-packs their requests, picks an instance
type from KWOK's fake catalog, and a NodeClaim → Node appears within ~30s
(typically a single `c-8x` node holding all 5 pods). Confirm the pods landed
on it:

```sh
kubectl get pods -o wide
kubectl get nodes -L node.kubernetes.io/instance-type -L karpenter.sh/capacity-type
```

## 5. Trigger consolidation (scale-down)

The NodePool's disruption policy is `WhenEmptyOrUnderutilized` with
`consolidateAfter: 10s`. Drop to 1 replica and watch Karpenter consolidate —
replacing the now-underutilized node with a smaller one (e.g. `c-8x` → `c-2x`).
Each consolidation takes a minute or two: Karpenter validates the decision,
launches any replacement, then drains the old node:

```sh
kubectl scale deployment inflate --replicas=1
```

Then scale to 0 and watch the remaining empty node get removed, leaving only
the Kind control-plane:

```sh
kubectl scale deployment inflate --replicas=0
```

## Cluster Autoscaler vs Karpenter

The two main node autoscalers, per the k8s docs:

|                    | Cluster Autoscaler                          | Karpenter                                    |
|--------------------|---------------------------------------------|----------------------------------------------|
| Scaling model      | Resizes pre-defined node groups (ASG/MIG)   | Group-less; provisions individual nodes      |
| Instance types     | Fixed per group, chosen up front            | Chosen per-node at provision time from constraints |
| Configuration      | Cloud-provider side (group min/max) + flags | In-cluster CRDs (`NodePool`, `NodeClass`)    |
| Scale-down         | Removes underutilized nodes                 | Full consolidation, drift, expiry, budgets   |
| Provider support   | Very broad (~30 providers)                  | AWS/Azure mature, others emerging            |

Both decide based on pod *requests* and scheduling constraints — a node full
of idle-but-requesting pods will not be scaled down.

## Teardown

```sh
kubectl delete -f inflate.yaml
kubectl delete -f nodepool.yaml     # drains and removes Karpenter's nodes
make delete                         # from the karpenter repo: uninstalls Karpenter
make uninstall-kwok
kind delete cluster --name karpenter
colima stop                         # optional: stop the Docker runtime
```
