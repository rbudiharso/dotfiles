# OpenCost Installation on EKS

OpenCost provides real-time cost monitoring for Kubernetes — per-namespace, per-workload, per-label CPU/memory allocation costs. Integrates with existing Prometheus + Grafana stack.

## Prerequisites

- Prometheus operator (kube-prometheus-stack) with ServiceMonitor discovery
- Grafana (optional, for dashboards)
- Node metrics source (kube-state-metrics + node-exporter or Grafana Alloy)
- EKS cluster (AWS pricing auto-detected from node provider ID)

## Installation

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update opencost
helm search repo opencost  # check latest version
```

## Key Values (opencost chart ~2.5.x)

```yaml
# CRITICAL: clusterName is the k8s DNS suffix, NOT the EKS cluster name
# Used to construct FQDN: http://<svc>.<ns>.svc.<clusterName>:<port>
clusterName: "cluster.local"

opencost:
  exporter:
    defaultClusterId: "jkt-stg-infra-eks-tada"  # actual cluster identifier

  prometheus:
    internal:
      enabled: true
      serviceName: prometheus-prometheus     # Prometheus service name
      namespaceName: monitoring              # Prometheus namespace
      port: 9090
      path: ""
      scheme: http

  # ServiceMonitor path is opencost.metrics.serviceMonitor (NOT opencost.serviceMonitor)
  metrics:
    serviceMonitor:
      enabled: true
      additionalLabels:
        release: prometheus    # MUST match Prometheus serviceMonitorSelector
      namespace: monitoring     # Deploy ServiceMonitor in Prometheus namespace
      scrapeInterval: 30s

  ui:
    enabled: true
```

## Critical Pitfalls

### 1. clusterName = DNS suffix, not EKS cluster name

The chart uses `clusterName` to build the Prometheus FQDN:
```
http://<serviceName>.<namespaceName>.svc.<clusterName>:<port>
```

Setting `clusterName: jkt-stg-infra-eks-tada` produces:
```
http://prometheus-prometheus.monitoring.svc.jkt-stg-infra-eks-tada:9090
```
Which fails DNS: `no such host`. Set `clusterName: cluster.local` (standard k8s DNS suffix).

Use `opencost.exporter.defaultClusterId` for the actual cluster name — this appears in cost reports.

Verify DNS resolution before deploying:
```bash
kubectl run dns-test --image=alpine:3.20 --rm -it -- nslookup prometheus-prometheus.monitoring.svc.cluster.local
```

### 2. ServiceMonitor values path

The ServiceMonitor is under `opencost.metrics.serviceMonitor`, NOT `opencost.serviceMonitor`. Check chart templates:
```bash
helm pull opencost/opencost --version <ver> --untar --untardir /tmp/oc
grep -rn "serviceMonitor" /tmp/oc/opencost/templates/
```

### 3. Prometheus endpoint configuration

NOT a single `endpoint` URL. Configure via separate fields:
- `opencost.prometheus.internal.serviceName` — Prometheus service name
- `opencost.prometheus.internal.namespaceName` — Prometheus namespace
- `opencost.prometheus.internal.port` — Prometheus port
- `opencost.prometheus.internal.scheme` — http or https
- `opencost.prometheus.internal.path` — path prefix (e.g. for Mimir: `/prometheus`)

The chart constructs the FQDN in `_helpers.tpl` using these + `clusterName`.

### 4. ServiceMonitor label matching

Prometheus operator's `serviceMonitorSelector` determines which ServiceMonitors are discovered. Check:
```bash
kubectl get prometheus -n monitoring -o json | jq '.items[0].spec.serviceMonitorSelector'
```

Common: `{"matchLabels": {"release": "prometheus"}}` — ServiceMonitor MUST have `release: prometheus` label.

### 5. Prometheus pod name differs from service name

The Prometheus StatefulSet pod is `prometheus-prometheus-prometheus-0` (double "prometheus"), but the service is `prometheus-prometheus`. Use the SERVICE name for `serviceName`, not the pod name.

## ECR Pull-Through Cache for OpenCost Images

OpenCost images (opencost, opencost-ui) are on ghcr.io. Use pull-through cache:

```yaml
opencostExporter:
  image:
    registry: "876683363342.dkr.ecr.ap-southeast-3.amazonaws.com"
    repository: "github/opencost/opencost"      # ghcr.io pull-through
    tag: "1.121.0"

opencostUI:
  image:
    registry: "876683363342.dkr.ecr.ap-southeast-3.amazonaws.com"
    repository: "github/opencost/opencost-ui"   # ghcr.io pull-through
    tag: "1.121.0"
```

Verify with `crane manifest` before deploying. On some clusters (stg), nodes can reach ghcr.io directly — pull-through cache still preferred for reliability.

## Verification

```bash
# Pod running (2 containers: opencost + opencost-ui)
kubectl get pods -n opencost
# Should see: opencost-xxx 2/2 Running

# Prometheus scraping opencost
kubectl exec -n monitoring <prometheus-pod> -c prometheus -- \
  sh -c 'wget -qO- "http://localhost:9090/api/v1/targets?state=active" | grep -c opencost'
# Should return: 1

# Cost allocation API working
kubectl exec -n opencost <opencost-pod> -c opencost -- \
  wget -qO- "http://localhost:9003/allocation/compute?window=1h"
# Should return JSON with namespace/pod cost data

# ServiceMonitor created with correct labels
kubectl get servicemonitor -n monitoring opencost -o yaml | grep "release: prometheus"
```

## Access UI

```bash
kubectl port-forward -n opencost svc/opencost 9090:9090
# Open http://localhost:9090
```

## Non-Fatal Warnings

- `/var/configs: permission denied` — collector falls back to in-memory. For persistence, enable PVC.
- `missing service key values for AWS cloud integration` — using node IAM role instead. Non-fatal.
- `No pricing-configs configmap found` — uses default AWS pricing. Create ConfigMap for custom pricing.

## AWS Integration

OpenCost auto-detects AWS provider from node ProviderID. Downloads:
- EC2 pricing from `pricing.us-east-1.amazonaws.com` (region-specific)
- EBS pricing
- Spot price history from AWS API

No explicit credentials needed if nodes have IAM permissions. For cloud cost integration (S3, RDS, etc.), create an IRSA role with ReadOnlyAccess and annotate the service account.

## Grafana Dashboard

OpenCost provides pre-built Grafana dashboards. Import from:
- OpenCost Grafana dashboards repo: https://github.com/opencost/opencost/tree/main/grafana

Or configure Grafana datasource pointing to Prometheus — OpenCost metrics are available as standard Prometheus metrics (`container_cpu_allocation`, `container_memory_allocation_bytes`, `kubecost_*`).
