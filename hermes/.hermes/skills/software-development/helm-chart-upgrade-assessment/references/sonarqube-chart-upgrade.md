# SonarQube Community Build Chart Upgrade (2025.6.1 -> 2026.4.0)

Assessed + executed July 31, 2026 for `tada-stg-manifest` repo.
Target cluster: `jkt-stg-infra-eks-tada` (stg).

## Current state (before upgrade)
- Chart: `sonarqube/sonarqube` version `2025.6.1`
- Community build: `25.12.0.117093` (chart default; our values.yaml sets `community.enabled: true` but does NOT override `buildNumber`)
- External PostgreSQL on AWS RDS (`jdbcOverwrite.enabled: true`, `postgresql.enabled: false`)
- Deployed to EKS, arm64 node pool (`gitlab-arm64` CAST.ai template)
- Pod: `sonarqube-sonarqube-0`, 1/1 Running

## Latest available
- Chart: `2026.4.0` (released Jul 23, 2026)
- Community build: `26.7.0.124771`
- Chart repo: `https://SonarSource.github.io/helm-chart-sonarqube/sonarqube`

## Upgrade path requirement
SonarSource mandates community build `25.12.0.117093` as stepping stone before any 26.x release.
Source: `community.sonarsource.com/t/sonarqube-community-build-26-1-0-118079-released/172488`
Quote: "To ensure a smooth upgrade to this and subsequent Community Build releases this year, your upgrade path must include version 25.12.0.117093."

**Status: STEPPING STONE SATISFIED.** Chart 2025.6.1 ships `25.12.0.117093` as its default `community.buildNumber`, and our values.yaml does not override it. Can go straight to 26.x without intermediate step.

## Values diff (2025.6.1 vs 2026.4.0)

Key changes found via `helm show values` diff:

1. **postgresql subchart REMOVED** — entire `postgresql:` section deleted from chart defaults.
   - Impact: NONE. Our values.yaml already has `postgresql.enabled: false` + external RDS via `jdbcOverwrite`.

2. **Probe templates changed wget -> curl** — readinessProbe and livenessProbe now use `curl --noproxy` instead of `wget --no-proxy`.
   - Impact: NONE. Internal chart template change, no values keys affected.

3. **ingress-nginx deprecated** — chart notes say controller retired Nov 2025, best-effort support ended Mar 2026.
   - Impact: NONE. We use Gateway API / HTTPRoute, not ingress-nginx.

4. **New `mcp:` section** — Model Context Protocol server sidecar (sonarsource/sonarqube-mcp).
   - Impact: NONE. Disabled by default (`mcp.enabled: false`). Candidate for post-upgrade enablement.

5. **`jdbcOverwrite` structure unchanged** — same keys: `enabled`, `jdbcUrl`, `jdbcUsername`, `jdbcSecretName`, `jdbcSecretPasswordKey`.
   - Impact: NONE. Our values.yaml fully compatible.

6. **`community.buildNumber` default changed** — `25.12.0.117093` -> `26.7.0.124771`.
   - Impact: app will upgrade to new community build. Expected.

## Our values.yaml compatibility
NO CHANGES NEEDED. All keys we set (`community.enabled`, `postgresql.enabled`, `monitoringPasscodeSecretName`, `monitoringPassCodeSecretKey`, `jdbcOverwrite.*`, `resources`, `affinity`) remain valid in chart 2026.4.0.

## k8s version check
Chart 2026.4.0 requires Kubernetes >= 1.32.
EKS cluster `jkt-stg-infra-eks-tada`: v1.36.2-eks-8f14419 — PASS.

## Execution (stg cluster, 2026-07-31)

### Helm upgrade command
```bash
helm --kube-context jkt-stg-infra-eks-tada upgrade sonarqube sonarqube/sonarqube \
  -n sonarqube --version 2026.4.0 -f values.yaml
```
Result: Release upgraded, revision 2, status deployed.

### Pod rollout
Pod recycled: Init:0/1 → PodInitializing → Running (0/1) → Running (1/1) in ~90s.
No restarts. New IP assigned.

### DB migration
After pod came up, status API returned:
```json
{"version":"26.7.0.124771","status":"DB_MIGRATION_NEEDED"}
```
Triggered migration via API (not browser):
```bash
kubectl --context jkt-stg-infra-eks-tada -n sonarqube exec sonarqube-sonarqube-0 \
  -- curl -s -X POST http://localhost:9000/api/system/migrate_db
```
Response: `{"state":"MIGRATION_RUNNING","message":"Database migration is running."}`

Polled status every 15s. Migration took ~3 min:
- 09:28:13 STARTING
- 09:28:29 STARTING
- 09:28:45 STARTING
- 09:29:01 STARTING
- 09:29:01 UP

### Final state
- Helm: sonarqube-2026.4.0, revision 2, APP VERSION 2026.4.0
- Pod: 1/1 Running, 0 restarts
- API: `{"id":"6E1ED07F-AXqFdeRgE9k1dK85jy7G","version":"26.7.0.124771","status":"UP"}`

## Post-upgrade: MCP server

Chart 2026.4.0 ships optional MCP sidecar (`mcp.enabled`, default false).
**ENABLED** — added to values.yaml, deployed, and registered as Hermes MCP server.

### values.yaml additions
```yaml
mcp:
  enabled: true
  persistence:
    enabled: false  # emptyDir — chart lacks fsGroup for MCP pod
  env:
    - name: SONARQUBE_TOKEN
      valueFrom:
        secretKeyRef:
          name: sonarqube-mcp-token
          key: SONARQUBE_TOKEN
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

### Key decisions
- **persistence: false**: Chart doesn't support pod-level fsGroup for MCP container. Non-root container (uid 1000) + PVC = AccessDeniedException. emptyDir avoids this; plugin data is ephemeral and re-syncs on restart.
- **Token via secret**: `mcp.env` uses `toYaml` in chart template, supporting `valueFrom.secretKeyRef`. Secret `sonarqube-mcp-token` created manually via kubectl.
- **HTTPRoute for external access**: Created `sonarqube/sonarqube-sonarqube/httproute-mcp.yaml` exposing `sonarqube-mcp.usetada.dev/mcp` via existing external-gateway.

### Results
- MCP pod: 1/1 Running, 0 restarts
- 19 SonarQube MCP tools discovered by Hermes (223 total MCP tools with gitlab)
- Verified: `search_my_sonarqube_projects` returned 218 projects, `list_quality_gates` returned 3 quality gates
- Hermes auto-reloaded MCP servers after config set (no restart needed)

### Known issue: plugin sync failure (non-critical)
MCP server downloads analyzers from SonarQube on startup. Community Build update center unavailable — javascript plugin download fails with `Connection closed by peer`, causing `IOReactorShutdownException`. NON-FATAL: REST API tools all work. Only `analyze_code_snippet` (inline code analysis) is affected.

## Files changed in manifest repo
- `helm/sonarqube/README.md`: version 2025.6.1 -> 2026.4.0, --version flags updated, MCP section with full config + troubleshooting
- `helm/sonarqube/values.yaml`: mcp config added (enabled, persistence off, token via secret, resources)
- `sonarqube/sonarqube-sonarqube/httproute-mcp.yaml`: NEW — HTTPRoute for MCP external access
