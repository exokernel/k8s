# HPA Walkthrough (Kind)

Following https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

## Environment

### 1. Start the Docker runtime (Colima)

```sh
colima start
```

### 2. Create the Kind cluster

```sh
kind create cluster --name hpa
```

This sets your kubectl context to `kind-hpa`. Confirm:

```sh
kubectl config current-context   # -> kind-hpa
```

### 3. Pre-pull images (optional, for a reliable demo)

Image pulls from `registry.k8s.io` occasionally stall inside the Colima VM
(the blobs redirect to Artifact Registry, and the guest's containerd can wedge),
leaving pods stuck in `ContainerCreating` — including the metrics-server install
in the next step. Before presenting, pre-pull every image the demo uses into the
Kind node so nothing hits the network live (`colima restart` also clears a stuck
pull if one happens):

```sh
for img in \
  registry.k8s.io/metrics-server/metrics-server:v0.8.1 \
  registry.k8s.io/hpa-example \
  busybox:1.28 ; do
  docker exec hpa-control-plane crictl pull "$img"
done
```

(metrics-server version tracks whatever `components.yaml` pins; v0.8.1 is current.)

Note: `registry.k8s.io/hpa-example` is an old **amd64-only** image (no arm64
variant), so on Apple Silicon it pulls the amd64 build and runs under emulation.
That makes it the slow one to pull and start — expect the php-apache pod to take
a bit longer to come up. Pre-pulling it here gets that wait out of the way.

### 4. Install metrics-server

```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 5. Patch metrics-server for Kind

Kind's kubelets serve their metrics endpoint with a self-signed cert that
metrics-server won't trust by default, so it never becomes ready and
`kubectl top` returns `Metrics API not available`. Add `--kubelet-insecure-tls`
to skip that cert verification (fine for a local cluster):

```sh
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Wait for it to roll out and become available:

```sh
kubectl rollout status -n kube-system deployment/metrics-server
```

### Sanity check

Metrics take ~15-30s to start flowing after the patch. Then:

```sh
kubectl top nodes
```

## 1. Deploy the server

```sh
kubectl apply -f php-apache.yaml
kubectl get deployment php-apache
```

## 2. Create the HorizontalPodAutoscaler

Target 50% CPU, between 1 and 10 replicas:

```sh
# Note: --cpu-percent is deprecated in kubectl v1.36; use --cpu=50% instead.
kubectl autoscale deployment php-apache --cpu=50% --min=1 --max=10
kubectl get hpa
```

(First reading shows `<unknown>/50%` for ~15-30s until metrics arrive.)

**Faster for a demo:** the command above uses the default 300s (5-min)
scale-down stabilization window, so step 4 is slow to show. Apply
[hpa-demo.yaml](hpa-demo.yaml) instead — same 50% target and 1-10 range, but
with `behavior.scaleDown.stabilizationWindowSeconds: 15` so replicas drop back
within ~15-30s of load stopping (this needs the `autoscaling/v2` `behavior`
field, which `kubectl autoscale` can't set):

```sh
kubectl apply -f hpa-demo.yaml
kubectl get hpa
```

## 3. Increase load

In a **separate terminal**, generate load:

```sh
kubectl run -i --tty load-generator --rm --image=busybox:1.28 --restart=Never -- \
  /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
```

Watch it scale up (Ctrl+C to stop watching):

```sh
kubectl get hpa php-apache --watch
```

## 4. Stop load

Stop the load generator (Ctrl+C in its terminal). Replicas scale back down
to 1 after the scale-down stabilization window: a few minutes with the default
`kubectl autoscale` HPA, or ~15-30s if you applied [hpa-demo.yaml](hpa-demo.yaml).

## Optional: autoscale on multiple / custom metrics

See the walkthrough section "Autoscaling on multiple metrics and custom metrics"
for the v2 HPA API (`hpa-v2.yaml` style manifests).

## Teardown

```sh
kubectl delete -f php-apache.yaml
kind delete cluster --name hpa
colima stop        # optional: stop the Docker runtime
```
