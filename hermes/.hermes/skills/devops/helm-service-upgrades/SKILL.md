---
name: helm-service-upgrades
description: "Use when upgrading helm charts on k8s."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [helm, kubernetes, upgrades, eks, sonarqube]
---

# Helm Service Upgrades

Manage helm chart upgrades for services running on Kubernetes. Covers version comparison, breaking change analysis, upgrade path verification, execution, and post-upgrade verification including DB migrations and new feature enablement.

## When to Use

- Upgrading a helm-deployed service to a newer chart version
- Enabling new features introduced in a chart version (sidecars, MCP servers, etc.)
- Installing helm-managed services on EKS (trivy-operator, opencost, etc.)
- Deploying companion UIs for helm-managed services (e.g., trivy-operator-dashboard)
- Researching upgrade paths and breaking changes before executing
- Post-upgrade verification (pod health, DB migration, feature functionality)

## Upgrade Workflow

### 1. Check Current vs Latest Version

```bash
helm repo add <repo> <url>
helm repo update <repo>
helm search repo <chart> --versions | head -20
```

Compare current chart version (from `helm list -n <ns>` or README.md) against latest available.

### 2. Breaking Change Analysis

Pull values from both versions and diff them:

```bash
helm show values <chart> --version <old> > /tmp/old_values.yaml
helm show values <chart> --version <new> > /tmp/new_values.yaml
diff /tmp/old_values.yaml /tmp/new_values.yaml
```

Key things to look for in the diff:
- Removed/renamed values keys (your values.yaml may break)
- New required fields
- Changed defaults
- Deprecated sections removed

Also check:
- Chart release notes on GitHub
- ArtifactHub changelog
- Community forums for upgrade path requirements (mandatory intermediate versions)

### 3. Verify Compatibility

- Kubernetes version: `kubectl --context <ctx> version` — ensure cluster meets new chart's k8s version requirement
- values.yaml: ensure no removed keys are still referenced
- README.md: update version references

### 4. Execute Upgrade

```bash
helm --kube-context <context> upgrade <release> <chart> \
  -n <namespace> \
  --version <new-version> \
  -f values.yaml
```

For prod clusters: always get explicit user confirmation before helm upgrade (per user preference).

### 5. Watch Rollout

```bash
kubectl --context <ctx> -n <ns> get pods -w
```

Wait for all pods to reach Ready state.

### 6. Post-Upgrade Verification

Check application health via API:

```bash
kubectl --context <ctx> -n <ns> exec <pod> -- curl -s http://localhost:<port>/api/system/status
```

### 7. DB Migration

Some applications require manual DB migration after version upgrade. Check status response for `DB_MIGRATION_NEEDED`:

```bash
# Trigger migration (example: SonarQube)
kubectl --context <ctx> -n <ns> exec <pod> -- curl -s -X POST http://localhost:<port>/api/system/migrate_db
```

Poll status until `UP`:

```bash
for i in $(seq 1 20); do
  status=$(kubectl --context <ctx> -n <ns> exec <pod> -- curl -s http://localhost:<port>/api/system/status)
  echo "$status"
  echo "$status" | grep -q '"UP"' && break
  sleep 15
done
```

## Enabling New Chart Features

New chart versions may introduce optional features (sidecars, MCP servers, etc.):

1. Check chart values for the new feature section: `helm show values <chart> --version <new> | sed -n '/^# <feature>/,/^## /p'`
2. Add feature config to values.yaml
3. Check if feature needs secrets (tokens, passcodes) — create k8s secrets separately
4. Check container image architecture compatibility (e.g., arm64 support for arm-node clusters)
5. helm upgrade with updated values.yaml
6. Verify new pod is Running and healthy
7. Check logs for initialization errors: `kubectl logs <pod> -c <container> --tail=30`

### PVC Permission Issues

If a new sidecar container runs as non-root (uid 1000) and uses a PVC, it may get `AccessDeniedException` creating directories. Workaround: disable persistence for that container (use emptyDir instead):

```yaml
<feature>:
  enabled: true
  persistence:
    enabled: false  # emptyDir workaround for non-root container + PVC permission issue
```

### Exposing New Services Externally

If the new feature needs external access (e.g., MCP server for AI agents):

1. Create HTTPRoute (Gateway API) pointing to the new service
2. Apply: `kubectl apply -f httproute-<feature>.yaml`
3. Verify route accepted: `kubectl get httproute <name> -o yaml | grep -A5 conditions`
4. Test external endpoint with auth

### Hermes MCP Client Configuration

To add an HTTP MCP server to Hermes Agent:

```bash
hermes config set mcp_servers.<name>.url "https://<endpoint>/mcp"
hermes config set mcp_servers.<name>.headers.Authorization "Bearer <token>"
```

Verify: `hermes config get mcp_servers.<name>`

Hermes auto-reloads MCP servers when config is added — no manual restart needed. If auto-reload doesn't trigger, restart Hermes.

## Pitfalls

- **ConfigMap not updated on `helm upgrade`**: Helm does NOT always update existing ConfigMaps on `helm upgrade` — the chart template may check for existing resources and skip creation. If you change values that affect ConfigMap data (e.g. image registry, DB repository paths), the ConfigMap retains OLD values. Fix: delete the ConfigMap manually before re-running `helm upgrade`:
  ```bash
  kubectl delete cm <configmap-name> -n <ns>
  helm upgrade <release> <chart> --version <ver> -n <ns> -f values.yaml
  ```
  Verify after: `kubectl get cm <configmap-name> -n <ns> -o yaml | grep <key>`. This is a general Helm issue, not specific to any chart.
- **Chart values key structure**: Charts may use compound keys split across multiple values (e.g. trivy-operator uses `trivy.dbRegistry` + `trivy.dbRepository` separately, combined as `{{ .Values.trivy.dbRegistry }}/{{ .Values.trivy.dbRepository }}` in templates). Setting only `dbRepository` without `dbRegistry` leaves the default registry prepended (mirror.gcr.io). Always check `helm show values` + `helm template` to understand how values are composed in templates before overriding. Verify rendered output: `helm template <release> <chart> --version <ver> -f values.yaml | grep <key>`.
- **Registry availability varies by source**: trivy + trivy-db available on `public.ecr.aws/aquasecurity/` but node-collector is only on `ghcr.io`. When using ECR pull-through cache, use `cache/` prefix for public.ecr.aws sources and `github/` prefix for ghcr.io sources. Verify with `crane manifest <image>` before deploying.
- **Mandatory upgrade paths**: Some applications require passing through specific intermediate versions before jumping to latest. Always check release notes and community posts. Example: SonarQube Community Build requires 25.12.0.117093 before any 26.x release.
- **Chart version jumps**: Chart versions may not be linear (e.g., SonarQube chart jumps 2025.6.1 to 2026.1.0, no 25.7-25.12 chart releases). The app build number inside the chart may differ from the chart version.
- **DB migration**: After major version upgrades, apps may report `DB_MIGRATION_NEEDED` status. This requires manual API trigger, not automatic.
- **Token auth for new features**: New sidecar containers may need tokens passed via environment variables. Chart `env` field with `toYaml` template supports `valueFrom.secretKeyRef` — create k8s secret separately, reference in values.yaml.
- **PVC permissions**: Non-root containers with PVCs can hit AccessDeniedException. Use emptyDir if data is ephemeral.
- **Container image arch**: Verify new container images support your node architecture (e.g., arm64 for arm nodes). Check with: `docker manifest inspect <image> | python3 -c "import sys,json; m=json.load(sys.stdin); print([x['platform']['architecture'] for x in m.get('manifests',[])])"`
- **Admin password changed**: Do not assume default credentials work. Check existing secrets or ask user for credentials/tokens.
- **Community Build plugin sync failures**: SonarQube Community Build doesn't expose a plugin update center the same way as full SonarQube Server. MCP server plugin downloads (especially javascript) may fail with `Connection closed by peer`, causing `IOReactorShutdownException`. This is NON-FATAL — REST API tools (search_projects, list_quality_gates, get_measures, etc.) still work. Only inline code analysis tools are affected.
- **MCP server endpoint quirks**: Root `/` returns 401 (auth required). `/mcp` with GET returns 405 (POST only). `/mcp` with POST + auth but missing `Accept: application/json, text/event-stream` header returns 400. These are protocol details, not errors.

- **OpenCost clusterName is DNS suffix, not cluster name**: OpenCost chart uses `clusterName` value to construct FQDN for Prometheus: `http://<serviceName>.<namespace>.svc.<clusterName>:<port>`. Setting `clusterName: jkt-stg-infra-eks-tada` produces `prometheus-prometheus.monitoring.svc.jkt-stg-infra-eks-tada:9090` which fails DNS lookup. Set `clusterName: cluster.local` (the k8s DNS suffix). Use `opencost.exporter.defaultClusterId` for the actual cluster identifier. Verify with: `kubectl run dns-test --image=alpine --rm -it -- nslookup <prometheus-svc>.<ns>.svc.cluster.local`.
- **OpenCost ServiceMonitor path is `opencost.metrics.serviceMonitor`**: Not `opencost.serviceMonitor`. Check chart templates with `helm pull` + `grep -rn serviceMonitor templates/` to find correct values path before configuring.
- **OpenCost Prometheus endpoint uses internal serviceName/namespaceName**: Not a single `endpoint` URL. Configure via `opencost.prometheus.internal.serviceName`, `namespaceName`, `port`, `scheme`. The chart constructs the FQDN using these + `clusterName`.

## References

- `references/sonarqube-upgrade.md` — SonarQube Community Build specific upgrade details, MCP server enablement, DB migration commands
- `references/trivy-operator-install.md` — Trivy operator installation on EKS: values structure, registry issues (ghcr.io 403, mirror.gcr.io missing tags), ConfigMap update fix, cleanup before reinstall, verification steps
- `references/trivy-operator-dashboard.md` — Third-party trivy UI: static manifest adaptation, ECR images, OTel env pitfalls, HTTPRoute + Route53 DNS
- `references/opencost-install.md` — OpenCost installation on EKS: Prometheus integration, clusterName DNS pitfall, ServiceMonitor label matching, values key structure
