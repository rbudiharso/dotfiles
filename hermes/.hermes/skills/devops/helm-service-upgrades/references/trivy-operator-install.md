# Trivy Operator Installation on EKS

Trivy operator (aquasecurity) provides vulnerability scanning, SBOM generation, config audit, exposed secret detection, and RBAC/infra assessment for k8s workloads.

## Installation

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update aqua
helm search repo trivy-operator
```

## Key Values (trivy-operator chart ~0.34.x)

```yaml
operator:
  builtInTrivyServer: true        # Run trivy server in-cluster (avoids external server)
  vulnerabilityScannerEnabled: true
  sbomGenerationEnabled: true
  configAuditScannerEnabled: true
  exposedSecretScannerEnabled: true
  rbacAssessmentScannerEnabled: true
  infraAssessmentScannerEnabled: true
  scanJobsConcurrentLimit: 10
  scanJobTimeout: 10m
  scannerReportTTL: "24h"
  accessGlobalSecretsAndServiceAccount: true

trivy:
  createConfig: true
  mode: ClientServer
  image:
    registry: "<ECR-registry>"
    repository: aquasec/trivy
    tag: "0.72.0"
  # CRITICAL: dbRegistry and dbRepository are SEPARATE keys, combined in template
  dbRegistry: "<ECR-registry>"
  dbRepository: "aquasecurity/trivy-db"
  javaDbRegistry: "<ECR-registry>"
  javaDbRepository: "aquasecurity/trivy-java-db"
  ignoreUnfixed: false
  timeout: "10m"

nodeCollector:
  image:
    registry: "<ECR-registry>"
    repository: aquasecurity/node-collector
    tag: "0.3.1"

excludeNamespaces: "kube-system,kube-node-lease,kube-public"
```

## Registry Issues + Solutions

### Problem: ghcr.io 403 Forbidden from k8s nodes

k8s nodes (EKS) may get 403 from ghcr.io when pulling trivy images (trivy, trivy-db, node-collector). ghcr.io rate-limits anonymous pulls aggressively.

### Solution 1: ECR pull-through cache (preferred)

If ECR pull-through cache rules exist, use them. Check existing rules:
```bash
aws ecr describe-pull-through-cache-rules --region ap-southeast-3
```

Available upstream sources + prefixes (Tada ECR):
- `public.ecr.aws` → prefix `cache/` — has trivy, trivy-db, trivy-java-db
- `ghcr.io` → prefix `github/` — has node-collector (NOT on public.ecr.aws)
- `registry.k8s.io` → prefix `k8s/`
- `quay.io` → prefix `quay/`
- `registry-1.docker.io` → prefix `docker-hub/`

Pull-through cache config for trivy-operator:
```yaml
trivy:
  image:
    registry: "876683363342.dkr.ecr.ap-southeast-3.amazonaws.com"
    repository: cache/aquasecurity/trivy        # via public.ecr.aws pull-through
    tag: "0.72.0"
  dbRegistry: "876683363342.dkr.ecr.ap-southeast-3.amazonaws.com"
  dbRepository: "cache/aquasecurity/trivy-db"   # via public.ecr.aws pull-through
  javaDbRegistry: "876683363342.dkr.ecr.ap-southeast-3.amazonaws.com"
  javaDbRepository: "cache/aquasecurity/trivy-java-db"

nodeCollector:
  image:
    registry: "876683363342.dkr.ecr.ap-southeast-3.amazonaws.com"
    repository: github/aquasecurity/node-collector  # via ghcr.io pull-through (NOT on public.ecr.aws)
    tag: "0.3.1"
```

**IMPORTANT**: `public.ecr.aws/aquasecurity/trivy` and `public.ecr.aws/aquasecurity/trivy-db` are available. Use the `cache/` prefix (public.ecr.aws pull-through). `node-collector` is only on ghcr.io — use `github/` prefix. Verify with `crane manifest <full-image>` before deploying.

**trivy-java-db tag**: As of 2026-07, `ghcr.io/aquasecurity/trivy-java-db:2` does NOT exist (MANIFEST_UNKNOWN). Use tag `1` instead. Verify with `crane ls ghcr.io/aquasecurity/trivy-java-db`.

**Stale image check**: After copying or configuring pull-through cache, verify image manifests exist:
```bash
crane manifest 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/cache/aquasecurity/trivy:0.72.0 | head -3
crane manifest 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/cache/aquasecurity/trivy-db:2 | head -3
crane manifest 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/github/aquasecurity/node-collector:0.3.1 | head -3
```

### Solution 2: Direct copy to ECR

```bash
# crane is available on macOS via homebrew
crane copy ghcr.io/aquasecurity/trivy:0.72.0 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/aquasec/trivy:0.72.0
crane copy ghcr.io/aquasecurity/trivy-db:2 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/aquasecurity/trivy-db:2
crane copy ghcr.io/aquasecurity/trivy-java-db:1 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/aquasecurity/trivy-java-db:1
crane copy ghcr.io/aquasecurity/node-collector:0.3.1 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/aquasecurity/node-collector:0.3.1
```

Note: trivy-java-db uses tag `1` not `2` (as of 2026-07). trivy-db uses tag `2`. Large image (943MB layer) — copy may take 2+ minutes.

### Problem: mirror.gcr.io missing trivy-db

mirror.gcr.io does NOT cache trivy-db (manifest unknown). Don't use `mirror.gcr.io/aquasecurity/trivy-db` — it fails with `MANIFEST_UNKNOWN: Failed to fetch "2"`.

## ConfigMap Update Issue

**CRITICAL**: `helm upgrade` does NOT update existing ConfigMaps for this chart. If you change `trivy.dbRegistry` or `trivy.image.registry`, you MUST delete the ConfigMaps first:

```bash
kubectl delete cm trivy-operator-trivy-config -n trivy-system
kubectl delete cm trivy-operator-config -n trivy-system
helm upgrade trivy-operator aqua/trivy-operator --version 0.34.0 -n trivy-system -f values.yaml
```

Verify ConfigMap has correct values:
```bash
kubectl get cm trivy-operator-trivy-config -n trivy-system -o yaml | grep "dbRepository"
```

## Cleanup Before Reinstall

If trivy-operator was previously removed (manually, not via helm uninstall), stale resources remain:

```bash
# Delete stale CRDs (removes all reports too)
kubectl delete crd \
  clustercompliancereports.aquasecurity.github.io \
  clusterconfigauditreports.aquasecurity.github.io \
  clusterinfraassessmentreports.aquasecurity.github.io \
  clustervulnerabilityreports.aquasecurity.github.io \
  configauditreports.aquasecurity.github.io \
  exposedsecretreports.aquasecurity.github.io \
  vulnerabilityreports.aquasecurity.github.io

# Delete orphaned jobs + namespace
kubectl delete jobs -n trivy-system --all
kubectl delete namespace trivy-system
```

## Verification

```bash
# Pods running
kubectl get pods -n trivy-system
# Should see: trivy-operator-xxx (1/1 Running), trivy-server-0 (1/1 Running)

# Reports being generated
kubectl get vulnerabilityreports -A | wc -l
kubectl get configauditreports -A | wc -l
kubectl get exposedsecretreports -A | wc -l

# Server logs — DB download success
kubectl logs trivy-server-0 -n trivy-system | tail -15
# Should see "Downloading vulnerability DB..." then scanning messages, no FATAL

# Operator logs — controllers started
kubectl logs deployment/trivy-operator -n trivy-system | tail -20
```

## Node-Collector Pending

node-collector pods may stay Pending if they target a specific node that no longer exists (CAST.ai recycled node). This only affects infra assessment node scans, NOT image vulnerability scanning. The operator will create new node-collector jobs for current nodes automatically.
