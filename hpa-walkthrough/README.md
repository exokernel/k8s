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

### 3. Install metrics-server

```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 4. Patch metrics-server for Kind

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
to 1 after a few minutes (default 5-min stabilization window).

## Optional: autoscale on multiple / custom metrics

See the walkthrough section "Autoscaling on multiple metrics and custom metrics"
for the v2 HPA API (`hpa-v2.yaml` style manifests).

## Teardown

```sh
kubectl delete -f php-apache.yaml
kind delete cluster --name hpa
colima stop        # optional: stop the Docker runtime
```
