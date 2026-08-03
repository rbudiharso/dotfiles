# Batch Scan Empirical Data

Real-world scan times and failure modes from SBOM batch scans. Use to estimate batch duration and identify slow images before launching.

## Complete 3-Batch Run — 297 images (prd cluster, jkt-prd-infra-eks-tada)

### Summary

| Batch | Images | Success | Failed | Duration | Output size |
|-------|--------|---------|--------|----------|-------------|
| 1 | 99 | 97 | 2 | ~57 min | 97 MB |
| 2 | 99 | 98 | 1 | ~92 min | 184 MB |
| 3 | 99 | 96 | 3 | ~86 min | 144 MB |
| **Total** | **297** | **291** | **6** | ~2.5 hr (parallel) | **425 MB** |

### Aggregate stats

- 257,571 total packages across all images
- 23,114 unique packages
- Top types: npm (13,917), go-module (4,091), deb (1,908), java-archive (1,162), apk (1,153)
- Top languages: javascript, go, java, php, python
- Base OS: mostly Alpine Linux (3.21.x, 3.23.x variants)

### Scan time distribution

| Time range | Count | Notes |
|------------|-------|-------|
| 2-10s | ~15 | Small alpine/distroless images (redis:alpine, curl, alpine:3, python:3.11-alpine) |
| 10-30s | ~40 | Most CASTai agent images, aggregator services, argocd, dex, keda |
| 30-60s | ~50 | annesa/backend, artotel/cms-app, inventory, scheduler, sika |
| 60-100s | ~60 | bridge images, loyalty, report, notification workers |
| 100-180s | ~40 | **Slow families** — runners/* (1480 pkgs each), integration-collector, keycloak |
| Failed | 6 | See failure modes below |

### Slow image families (consistently >100s)

| Family | Package count | Scan time | Pattern |
|--------|--------------|-----------|---------|
| `runners/*` (~60+ images) | 1480-1518 | 47-90s each | Same base image, many variants. Batch 2 dominated by these. |
| `bridge:*` (3 images) | 1683 | 96-179s | Large Go binary bundles |
| `integration-collector` | 1074 | 163s | |
| `dashboard:3.82.10` | 3971 | 118s | Largest package count |
| `keycloak:20.0.1` (quay.io) | 765 | 87s | |
| `kafbat/kafka-ui` | 284 | 96s | |
| `campaign-logger/*` (7 images) | 1763 | 44-98s | Same base, 7 variants |
| `tadakado-transactions` | 815 | 127s | |

### Estimated batch duration

- **99 images, mixed**: 57-92 min wall time (avg ~50s/image)
- **Runner-heavy batch**: ~92 min (batch 2 had 30+ runner images at 47-90s each)
- **3 batches in parallel**: ~92 min total (limited by slowest batch)
- **With slow families**: Add ~2min per bridge image, ~1.5min per runner image

### All 6 failure modes

| # | Image | Error | Root cause | Action |
|---|-------|-------|------------|--------|
| 1 | `876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/dashboard:3.73.10-d38d07db-beta` | `MANIFEST_UNKNOWN` | Beta tag garbage-collected from ECR after promotion | Report stale, don't retry |
| 2 | `debezium/debezium-ui` (Docker Hub, no tag) | `containerd not available` | Syft needs containerd for this image manifest format | Mark failed, needs containerd |
| 3 | `docker.getoutline.com/outlinewiki/outline:latest` | OCI pull error, failed to fetch descriptor | Third-party registry auth/availability issue | Mark failed, registry may not support anonymous OCI |
| 4 | `876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/runners/temporal-general1:be3c5099` | syft timeout 180s | Very large image, exceeded per-image timeout | Increase timeout to 300s or skip |
| 5 | `public.ecr.aws/tada/pbm:2.4.1` | `containerd not available` | Public ECR image, same as debezium | Mark failed |
| 6 | `876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/data-check-sum:17369b62` | `MANIFEST_UNKNOWN` | Image tag deleted from ECR | Report stale |

### Successful public registry images (for reference)

- `quay.io/argoproj/argocd:v3.3.6` — 578 pkg, 29s
- `ghcr.io/dexidp/dex:v2.45.1` — 286 pkg, 26s
- `docker.io/istio/proxyv2:1.28.3-distroless` — 104 pkg, 10s
- `quay.io/keycloak/keycloak:20.0.1` — 765 pkg, 87s
- `ghcr.io/kedacore/keda:2.18.2` — 303 pkg, 39s
- `confluentinc/cp-schema-registry:5.5.3` — 1715 pkg, 46s
- `us-docker.pkg.dev/castai-hub/library/*` (10 images) — all succeeded
- `crane copy` + ECR pull-through cache worked for all test images

### Process monitoring data

- `process wait` clamps to ~60s per call regardless of requested timeout
- A 99-image batch requires ~40-90 polling cycles if actively monitored → **will hit tool-call iteration limit**
- `notify_on_complete=true` is the only viable monitoring strategy for batches >8 images
- Background process PID persists across tool calls — safe to launch and leave
- **3 parallel subagents** (delegate_task) all hit ~50 iteration limit mid-scan, but processes continued running in background. Results collected after all 3 completed via `notify_on_complete` on parent watcher process.
- **Better approach for future**: Launch 3 background terminal processes from parent session (not subagents), use single watcher loop with `notify_on_complete`. Subagents waste iterations polling.
