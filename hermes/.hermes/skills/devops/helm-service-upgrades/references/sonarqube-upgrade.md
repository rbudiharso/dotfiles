# SonarQube Community Build Upgrade

Specific details for upgrading SonarQube Community Build on Kubernetes via the official helm chart `sonarqube/sonarqube`.

## Chart Repository

```bash
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube/sonarqube
helm repo update
```

## Key Facts

- Chart version and app version are aligned (e.g., chart 2026.4.0 = app 2026.4.0)
- Community build version is set via `community.buildNumber` in values.yaml
- Chart may ship a newer community build than the chart version number suggests (e.g., chart 2025.6.1 ships community build 25.12.0.117093, not 25.6.1)
- Chart requires Kubernetes >= 1.32 (as of 2026.4.0)

## Mandatory Upgrade Path

SonarQube Community Build 26.1.0+ requires that the upgrade path includes version 25.12.0.117093. This is a mandatory stepping stone.

Source: https://community.sonarsource.com/t/sonarqube-community-build-26-1-0-118079-released/172488

If already running a chart version that ships community build 25.12.0.117093 (e.g., chart 2025.6.1), the stepping stone is satisfied and you can jump directly to 26.x.

## Breaking Changes: 2025.6.1 to 2026.4.0

- **postgresql subchart removed**: No impact if using external RDS (`postgresql.enabled: false`). If using the bundled postgresql, must migrate to external DB first.
- **Probes changed wget to curl**: Internal template change, no values impact.
- **ingress-nginx deprecated**: No impact if using Gateway API/HTTPRoute.
- **MCP server added**: Optional sidecar (`mcp.enabled`, default false). New section in values.
- **jdbcOverwrite structure unchanged**: Existing values.yaml fully compatible.

## DB Migration After Upgrade

After upgrading to a new major version, SonarQube reports `DB_MIGRATION_NEEDED`:

```bash
# Check status
kubectl --context <ctx> -n sonarqube exec <pod> -- curl -s http://localhost:9000/api/system/status

# Trigger migration
kubectl --context <ctx> -n sonarqube exec <pod> -- curl -s -X POST http://localhost:9000/api/system/migrate_db

# Poll until UP (takes ~2-4 min)
for i in $(seq 1 20); do
  status=$(kubectl --context <ctx> -n sonarqube exec <pod> -- curl -s http://localhost:9000/api/system/status)
  echo "$status"
  echo "$status" | grep -q '"UP"' && break
  sleep 15
done
```

Migration is automatic once triggered. Status transitions: DB_MIGRATION_NEEDED -> MIGRATION_RUNNING -> STARTING -> UP.

## MCP Server Enablement

Chart 2026.4.0 ships optional MCP (Model Context Protocol) sidecar for AI agent integration.

### values.yaml Config

```yaml
mcp:
  enabled: true
  persistence:
    enabled: false  # emptyDir workaround — non-root container + PVC = AccessDeniedException
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

### Token Setup

MCP server requires a SonarQube user token for auth. Create k8s secret:

```bash
kubectl --context <ctx> -n sonarqube create secret generic sonarqube-mcp-token \
  --from-literal=SONARQUBE_TOKEN=squ_<token> \
  --dry-run=client -o yaml | kubectl --context <ctx> apply -f -
```

Generate token via SonarQube web UI: User > My Account > Security > Generate Token.

### MCP Endpoint

- Internal: `http://sonarqube-sonarqube-mcp:8080/mcp`
- Auth: `Authorization: Bearer <token>` header
- Protocol: MCP StreamableHTTP (POST with `Accept: application/json, text/event-stream`)
- Health: `GET /health` (no auth required)

### Exposing Externally via Gateway API

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: sonarqube-sonarqube-mcp
  namespace: sonarqube
spec:
  hostnames:
  - sonarqube-mcp.usetada.dev
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: external-gateway
    namespace: istio-system
    sectionName: https-usetada-dev
  rules:
  - backendRefs:
    - group: ''
      kind: Service
      name: sonarqube-sonarqube-mcp
      port: 8080
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
```

### Hermes Agent MCP Client Config

```bash
hermes config set mcp_servers.sonarqube.url "https://sonarqube-mcp.usetada.dev/mcp"
hermes config set mcp_servers.sonarqube.headers.Authorization "Bearer squ_<token>"
```

Hermes auto-reloads MCP servers when config is added — no restart needed. System message confirms: "MCP servers have been reloaded. Added servers: sonarqube. N tool(s) now available."

### Troubleshooting MCP

- **401 Unauthorized on root /**: Normal — MCP endpoint is `/mcp`, not `/`. Root requires auth too.
- **405 Method Not Allowed on /mcp with GET**: Normal — MCP protocol uses POST.
- **AccessDeniedException /data/plugins**: PVC permission issue. Container runs as uid 1000, PVC owned by root. Fix: `mcp.persistence.enabled: false` (use emptyDir).
- **"Missing or empty SonarQube token"**: Token env var not set. Add via `mcp.env` with `valueFrom.secretKeyRef`.
- **"Backend already initialized"**: Non-fatal race condition in MCP server. Self-resolves. Check that "Background initialization completed successfully" appears in logs.
- **Admin password not default**: Don't assume admin:admin works. Ask user for credentials or token.
- **Javascript plugin download failure (Community Build)**: MCP server downloads analyzers from SonarQube on startup. Community Build's update center is unavailable — SonarQube logs show "The plugin 'javascript' version : X has not been found on the update center" for ALL plugins. MCP downloads some plugins directly (go, web, iac, java, javasymbolicexecution) but javascript fails with `Connection closed by peer`. This causes `IOReactorShutdownException` in the HTTP client reactor. NON-FATAL: REST API tools (search_projects, list_quality_gates, get_measures, search_sonar_issues, etc.) work fine. Only inline code analysis tools (analyze_code_snippet) are affected. Error appears in logs but does not prevent MCP server from starting or serving REST API tools.
- **MCP endpoint paths**: Valid endpoint is `/mcp` (POST only, requires `Accept: application/json, text/event-stream` header). Root `/` returns 401. `/sse` returns 401. `/health` returns 200 (no auth). These are correct behaviors, not misconfiguration.
- **Hermes MCP auto-reload**: Adding MCP server to Hermes config via `hermes config set` triggers auto-reload. No restart needed.
