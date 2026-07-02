# HPA Walkthrough (Kind)

Following https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

## Environment (already set up)

- Colima (Docker runtime) started
- Kind cluster `hpa` created — context `kind-hpa`
- metrics-server installed and patched with `--kubelet-insecure-tls` (required for Kind)

Sanity check:

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
