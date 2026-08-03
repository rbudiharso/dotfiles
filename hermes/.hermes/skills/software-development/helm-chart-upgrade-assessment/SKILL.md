---
name: helm-chart-upgrade-assessment
description: Assess helm chart upgrades for manifest repos.
---

# Helm Chart Upgrade Assessment

## Trigger
User asks "can we upgrade X", "check if newer version available", "see if we can upgrade X image/chart version" for any helm-managed service in a manifest repo (e.g. `tada-stg-manifest`). Also use when planning a chart version bump.

## Workflow

1. **Find current version.** Check the chart's `README.md` (usually has `**Version**: <x>` line) and `values.yaml` in the helm subdirectory (e.g. `helm/<service>/`). The README version is the source of truth for the pinned chart version; values.yaml may override app-level config like `community.buildNumber` or `image.tag`.

2. **Find latest available version.**
   ```bash
   helm repo add <repo-name> <repo-url>   # from README
   helm repo update <repo-name>
   helm search repo <repo-name>/<chart-name> --versions | head -20
   ```
   Note: `helm repo add` from a non-Helm-ecosystem URL (GitHub Pages, etc.) may trigger a security scan flag — this is expected for official chart repos hosted on GitHub Pages (SonarSource, Grafana, etc.). Auto-approve is fine for known upstream repos.

3. **Check upgrade path requirements.** Some projects mandate intermediate stepping-stone versions — skipping them causes DB migration failures or data loss. Search:
   - Community forums (e.g. `community.sonarsource.com`) for release announcements mentioning "upgrade path must include"
   - Official docs for "upgrade path" / "determine path" pages
   - ArtifactHub changelog tab for the chart
   If a stepping stone is required, check whether the CURRENT deployment already runs it (chart defaults may ship it even if the chart version is older — e.g. sonarqube chart 2025.6.1 ships community build 25.12.0.117093 as its default `buildNumber`).

4. **Diff default values between current and target chart versions.** This is the core impact assessment:
   ```bash
   helm show values <repo>/<chart> --version <current> > /tmp/<chart>_current_values.yaml
   helm show values <repo>/<chart> --version <target>  > /tmp/<chart>_target_values.yaml
   diff /tmp/<chart>_current_values.yaml /tmp/<chart>_target_values.yaml
   ```
   Look for:
   - **Removed keys** — if our values.yaml sets a key the new chart deleted, helm upgrade fails or silently ignores it
   - **Renamed/restructured keys** — same risk
   - **Removed subchart dependencies** — common pattern (e.g. postgresql subchart removed); no impact if we already use `subchart.enabled=false` with external DB
   - **New sections** — usually disabled by default, low impact
   - **Probe/internal template changes** (wget to curl, etc.) — no values impact, but note them

5. **Cross-reference breaking changes with our values.yaml.** Read our `helm/<service>/values.yaml` and check every key we set against the diff. If none of our keys are in removed/renamed sections, the upgrade is values-compatible as-is.

6. **Check k8s version constraints.** New chart versions often bump minimum Kubernetes version. Check chart metadata or ArtifactHub for `Supported Kubernetes Versions`. Compare against the target cluster's version:
   ```bash
   kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'
   ```
   If the cluster is below the new minimum, the chart upgrade must wait for a cluster upgrade first.

7. **Summarize for the user:** current version, target version, upgrade path status, breaking changes vs our values, k8s compatibility, and whether values.yaml needs changes. Offer conservative (minimal jump) vs latest options when relevant.

## Key patterns

- **Chart version != app/community build version.** A chart at version 2025.6.1 may ship an app build from a different date (e.g. community build 25.12.0.117093). Always check `helm show values --version <x> | grep -A5 buildNumber` (or equivalent) to see what app version the chart actually deploys.
- **Stepping-stone versions may already be satisfied.** Even if the chart version is old, the chart's default app version may already be the required stepping stone. Check the chart's default values, not just the chart version number.
- **`helm show values` diff is the fastest impact assessment.** Don't read release notes line-by-line first — diff the values schemas and let the structural changes guide you to the relevant release notes.
- **External DB = no impact from subchart removal.** Charts commonly remove bundled DB subcharts (postgresql, etc.) across major versions. If values.yaml already has `postgresql.enabled: false` + `jdbcOverwrite.enabled: true` (or equivalent external DB config), this is a non-issue.
- **README.md version line is the pin.** When upgrading, update both `values.yaml` (if app version overrides exist) and `README.md` version references + install/upgrade command `--version` flags.

## Pitfalls
- Don't jump straight to latest without checking upgrade path requirements — some projects (SonarQube, Elasticsearch, etc.) mandate intermediate versions.
- Don't assume values.yaml needs changes — diff first, many upgrades are values-compatible as-is.
- Don't forget k8s version constraints — a chart requiring k8s 1.32 won't install on 1.30.
- Don't skip the `helm show values` diff — release notes don't always surface values-schema breaking changes clearly.
- Don't forget to check `community.buildNumber` or equivalent app-version overrides in our values.yaml — if we pin an old build number, upgrading the chart alone won't upgrade the app.

## Execution (after user confirms)

1. **Verify cluster version.** Check target cluster k8s version meets chart minimum:
   ```bash
   kubectl --context <ctx> version -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['serverVersion']['gitVersion'])"
   ```

2. **Check current deployment state.** Confirm pod healthy + helm release status:
   ```bash
   kubectl --context <ctx> -n <ns> get pods -o wide
   helm --kube-context <ctx> list -n <ns>
   ```

3. **Run helm upgrade.** Use `--kube-context` to target correct cluster:
   ```bash
   helm --kube-context <ctx> upgrade <release> <repo>/<chart> -n <ns> --version <target> -f values.yaml
   ```

4. **Watch pod rollout.** Pod will recycle (Init → PodInitializing → Running → 1/1):
   ```bash
   kubectl --context <ctx> -n <ns> get pods -o wide -w
   ```
   Timeout after ~90s. If pod not 1/1, check events/logs.

5. **Check app status.** SonarQube (and similar) expose status via API:
   ```bash
   kubectl --context <ctx> -n <ns> exec <pod> -- curl -s http://localhost:9000/api/system/status
   ```
   Possible statuses: `STARTING`, `DB_MIGRATION_NEEDED`, `DB_MIGRATION_RUNNING`, `UP`.

6. **Trigger DB migration if needed.** If status is `DB_MIGRATION_NEEDED`, trigger via API (not browser):
   ```bash
   kubectl --context <ctx> -n <ns> exec <pod> -- curl -s -X POST http://localhost:9000/api/system/migrate_db
   ```
   Returns `{"state":"MIGRATION_RUNNING"}`. App auto-restarts after migration.

7. **Poll until UP.** Loop every 15s until status is `UP`:
   ```bash
   for i in $(seq 1 20); do
     status=$(kubectl --context <ctx> -n <ns> exec <pod> -- curl -s http://localhost:9000/api/system/status 2>/dev/null)
     echo "$(date +%H:%M:%S) $status"
     echo "$status" | grep -q '"UP"' && break
     sleep 15
   done
   ```

8. **Confirm final state.** Helm release shows new chart version + APP VERSION, pod 1/1, status UP.

## Post-upgrade: optional features

After upgrade succeeds, check if new chart version added optional features worth enabling (e.g. SonarQube MCP sidecar, monitoring hooks). Document in README.md with config snippet + checklist:
- App pod healthy (status UP)
- Sufficient node resources for sidecar/additions
- PVC provisioned if feature needs storage

### Enabling MCP/HTTP-based sidecars

When enabling an MCP server sidecar (e.g. SonarQube MCP):
1. Check if chart template supports `env` with `valueFrom.secretKeyRef` (grep the chart template: `grep -n "env\|envFrom" /tmp/<chart>/templates/<feature>.yaml`)
2. Create k8s secret for auth tokens separately: `kubectl create secret generic <name> --from-literal=KEY=val`
3. If sidecar uses PVC and runs as non-root, check if chart supports pod-level `fsGroup`. If not, disable persistence (`persistence.enabled: false`) and use emptyDir.
4. Expose externally via HTTPRoute if the MCP server needs remote access (e.g. for Hermes MCP client)
5. Register in Hermes config: `hermes config set mcp_servers.<name>.url "https://<endpoint>/mcp"` + `hermes config set mcp_servers.<name>.headers.Authorization "Bearer <token>"`
6. Hermes auto-reloads MCP servers — no restart needed
7. Verify tool discovery: `tool_search(query="<name>")` should show `mcp__<name>__*` tools
8. Functional test: call a simple tool (e.g. list_quality_gates) to verify end-to-end connectivity

## Before executing the upgrade
- Prod-affecting helm upgrades require explicit user confirmation (per user preference).
- Stg cluster upgrades: proceed after assessment clear, still confirm if user hesitant.
- Check for in-flight jobs/pods in the target namespace before upgrading.
- Recommend DB backup for services with external databases before any major version jump.
- After upgrade, trigger DB migration via API if status is `DB_MIGRATION_NEEDED` (not browser `/setup` — API is faster + scriptable).

## References
- `references/sonarqube-chart-upgrade.md` — SonarQube Community Build chart upgrade assessment (2025.6.1 to 2026.4.0), including stepping-stone version requirement and values diff findings.
