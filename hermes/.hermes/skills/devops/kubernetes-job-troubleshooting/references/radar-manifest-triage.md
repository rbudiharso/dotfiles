# Radar MCP Manifest Issue Triage

## Session: partner-web-php imagePullSecret false positive (2026-08-03)

### Symptom

Radar MCP `issues` reported critical `missing_config_ref` for `tada-partner/partner-web-php`:
- `imagePullSecrets references Secret "ecr-registry-secret" which does not exist`
- 2 affected pods, 32,423 warning events
- First seen: 2026-07-09, last seen: 2026-08-03

### Investigation

1. `get_dashboard` showed 352 total problems on prd cluster (jkt-prd-infra-eks-tada)
2. `get_resource` on the Deployment showed: 2/2 replicas ready, Available=True
3. `get_resource` on individual pods showed: phase=Running, ready=true, 0 restarts, ContainersReady=True
4. Conclusion: **false positive** — EKS node IAM instance role grants ECR access. k8s silently ignores missing imagePullSecret when node role suffices.

### Root Cause

Manifest (both stg + prd repos) had:
```yaml
      imagePullSecrets:
        - name: ecr-registry-secret  # Secret never created, not needed
```

No other Deployment in the manifest repos used `imagePullSecrets` — all rely on EKS node IAM. This was a leftover from an earlier setup.

### Fix

Removed `imagePullSecrets` block from both repos:
- `tada-prd-manifests/tada-partner/partner-web-php/deployment.yaml` (line 66-67)
- `tada-stg-manifest/tada-partner/tada-partner/deployment.yaml` (line 76-77)

### Verification

Python script validated both files:
- YAML parses correctly (1 doc, kind=Deployment, apiVersion=apps/v1)
- `imagePullSecrets` key absent from spec.template.spec
- `ecr-registry-secret` string absent from file
- Container spec intact (1 container, name=partner-web-php)

### Key Takeaways

1. **Radar missing_config_ref can be false positive** — always check live pod status via `get_resource` before fixing. If pods are Running/Ready with 0 restarts, the missing reference is cosmetic.
2. **EKS node IAM handles ECR auth** — `imagePullSecrets` is only needed for cross-account or external registries. Same-account ECR doesn't need it.
3. **Stg and prd have separate manifest repos** — `tada-stg-manifest` (HTTPS repoURL, path `tada-partner/tada-partner/`) vs `tada-prd-manifests` (SSH repoURL, path `tada-partner/partner-web-php/`). Fix both if the issue exists in both.
4. **Manifest paths differ between repos** — stg uses `<namespace>/<namespace>/` pattern, prd uses `<namespace>/<app-name>/` pattern. Don't assume same path.

## Other manifest-fixable issues from same session

### Orphaned HPAs — Bulk Cleanup (2026-08-03)
- 153 HPAs total: 152 in `runners` namespace + 1 in `avbo` namespace
- All `missing_scale_target` — HPAs point at Deployments that don't exist
- Some 383+ days old; runners likely migrated to KEDA ScaledObjects or decommissioned
- Each HPA was a lone `hpa.yaml` file in its own directory (no deployment.yaml, no scaledobject.yaml)
- Only 6 ScaledObjects exist in runners namespace — none matching orphaned HPA names
- Fix: deleted all 153 `hpa.yaml` files + 153 empty directories from prd manifest
- ArgoCD auto-sync (prune: true, selfHeal: true) removes from cluster on next sync
- STG manifest clean — 0 orphaned HPAs there

#### Bulk HPA cleanup technique
1. Use `mcp__radar__issues` to get all issues, filter `kind == "HorizontalPodAutoscaler"` or reason contains `scaleTargetRef`
2. Parse all `hpa.yaml` files from manifest repo, extract `scaleTargetRef.name`
3. Collect all Deployment names from manifest repo's `deployment.yaml` files
4. Orphans = HPAs whose `scaleTargetRef.name` not in Deployment name set
5. Verify each orphan dir contains ONLY `hpa.yaml` (no other resources to preserve)
6. Check for KEDA ScaledObjects/ScaledJobs on cluster that might have replaced the Deployments
7. Delete `hpa.yaml` files + empty dirs from manifest repo
8. Commit + push manifest
9. **CRITICAL: Verify ArgoCD actually manages these resources** — check if an ArgoCD Application exists for each orphan dir (`kubectl get app -n argocd | grep <name>`). If no Application exists, ArgoCD prune won't remove the resources from the cluster. Must `kubectl delete hpa -n <ns> <names>` directly.
10. After kubectl delete, verify with `kubectl get hpa -n <ns>` — orphan count should be 0. Cross-check: `comm -23 <(hpa_targets) <(deployment_names)` should produce empty output.

#### Pitfall: ArgoCD prune only works for managed resources
Manifest repo deletion + ArgoCD auto-sync (prune: true) only removes resources that belong to an ArgoCD Application. If an ArgoCD Application was deleted but its resources were left in the cluster (orphaned), deleting the manifest file does nothing — the resource persists in the cluster with no ArgoCD owner. Always verify with `kubectl get <resource> -n <ns>` after manifest push, and `kubectl delete` directly if needed.

#### Pitfall: macOS `._*` AppleDouble files corrupt git pack index
On macOS external volumes, git produces `error: non-monotonic index .git/objects/pack/._pack-*.idx` spam. These are macOS AppleDouble metadata files, not real git objects. Git operations still succeed — filter with `2>&1 | grep -v 'non-monotonic'` to see real output. Does not corrupt repo.

### Failed Jobs — Bulk Cleanup + CronJob History Limits (2026-08-03)
- 75 failed/stuck jobs accumulated across 10 namespaces (scheduler: 55, adira: 5, bcas-staging: 4, others: 11)
- 70 CronJob-owned, 5 standalone (no owner)
- Some 157 days old (artotel/cms-app-scheduler)
- Root cause: CronJobs without `failedJobsHistoryLimit`/`successfulJobsHistoryLimit` retain failed jobs forever
- Fix: `kubectl delete jobs -A --field-selector=status.successful==0` — bulk deletes all failed jobs in one command
- Audit: parse all `cronjob.yaml` files in manifest repo, check for missing limits
- 134/135 CronJobs in prd manifest already had limits (mostly `1/1`) — stale jobs were from before limits were added
- 1 CronJob missing limits (`ai-tools/gdrive-gitlab`) — added `failedJobsHistoryLimit: 1` + `successfulJobsHistoryLimit: 1`
- After cleanup: 0 failed jobs remaining (only 2 freshly-created Running jobs from CronJob schedule)

#### Bulk CronJob history limit audit technique
```python
# Find CronJobs missing history limits in manifest repo
import yaml, subprocess
from collections import Counter

r = subprocess.run(["find", "<manifest-repo>", "-name", "cronjob.yaml", "-type", "f"],
                   capture_output=True, text=True, timeout=15)
cj_files = r.stdout.strip().split('\n')

missing = []
fail_limits = Counter()
for f in cj_files:
    with open(f) as fh:
        doc = yaml.safe_load(fh)
    if not doc or doc.get('kind') != 'CronJob':
        continue
    spec = doc.get('spec', {})
    fail_limits[spec.get('failedJobsHistoryLimit', 'MISSING')] += 1
    if 'failedJobsHistoryLimit' not in spec or 'successfulJobsHistoryLimit' not in spec:
        missing.append({'file': f, 'name': doc['metadata']['name'], 'namespace': doc['metadata']['namespace']})
```

#### Bulk failed job cleanup
```bash
# Delete ALL failed jobs across all namespaces in one command
kubectl delete jobs -A --field-selector=status.successful==0
# Verify — should show only header or freshly-created Running jobs
kubectl get jobs -A --field-selector=status.successful==0
```

#### Getting failed job details with owner info
```bash
# Get all failed jobs with CronJob owner info for triage
kubectl get jobs -A -o json | python3 -c "
import json,sys
data=json.load(sys.stdin)
for j in data['items']:
    ns=j['metadata']['namespace']; name=j['metadata']['name']
    succ=j.get('status',{}).get('succeeded',0)
    if succ==0:
        owners=j['metadata'].get('ownerReferences',[])
        owner_kind=owners[0]['kind'] if owners else 'None'
        owner_name=owners[0]['name'] if owners else 'None'
        ct=j['metadata']['creationTimestamp']
        fail=j.get('status',{}).get('failed',0)
        print(f'{ns}\t{name}\t{owner_kind}\t{owner_name}\t{succ}\t{fail}\t{ct}')
" | sort -t$'\t' -k7
```

### DaemonSet unavailable (node-level, not manifest)
- `kube-system/node-watchdog`, `istio-system/istio-cni-node`, `kube-system/node-local-dns`
- All on same node `ip-10-30-26-171` with shutdown events
- Fix: node-level issue, drain/remove problem node

### Radar issues output size handling
Radar `issues` tool can return 196K+ characters (193+ issues with full diagnostic context). Output is often too large for inline processing. Techniques:
- Use `get_dashboard` first for overview (30 of N problems, much smaller)
- When `issues` output is too large, it may be saved to a temp file — read with `read_file` and parse with `execute_code` using `json.loads`
- Filter issues by `kind`, `reason`, `namespace` in Python after parsing
- Radar cache doesn't refresh immediately after kubectl fixes — issues may still appear for minutes after resolution. Verify with `kubectl get` directly, don't rely on radar to confirm fixes.

## Session: trivy-system node-collector unschedulable (2026-08-03)

### Symptom
Radar reported critical `unschedulable` for `trivy-system/node-collector` — node hostname not found.

### Investigation (first pass — WRONG conclusion)
1. `kubectl get ns trivy-system` → NotFound (at the time, on stg context)
2. `kubectl get crd | grep aquasec` → empty (same wrong context)
3. Concluded trivy was fully removed. Deleted `trivy-system/` manifest files from prd repo.

### Investigation (second pass — CORRECT)
1. After switching to prd context: `kubectl get ns trivy-system` → Active, 2d23h old
2. `kubectl get all -n trivy-system` → trivy-operator, trivy-server, trivy-dashboard all Running
3. Trivy was reinstalled (per memory: "Trivy operator reinstalled on prd")
4. Manifest files I deleted were actually in use (deployed via `kubectl apply`, not ArgoCD)
5. Had to `git revert` the deletion commit to restore them

### Root Cause of the Issue
- `node-collector` is a Job created by trivy-operator for CIS benchmark scanning
- Job has `nodeSelector: kubernetes.io/hostname=<specific-node>` 
- Node was cordoned/shutting down (NotReady, SchedulingDisabled)
- Job pinned to dying node → FailedScheduling
- This is transient — trivy-operator creates new node-collector Jobs for healthy nodes

### Fix
- Deleted the stale node-collector Job (`kubectl delete job -n trivy-system`)
- Trivy-operator will recreate for healthy nodes on next scan cycle
- No manifest change needed for this specific issue

### Pattern: trivy-operator node-collector
node-collector Jobs are ephemeral, created per-node by trivy-operator. When a node is cordoned/terminated, the Job targeting that node becomes unschedulable. Simply delete the stale Job. Do NOT delete trvy-system manifest files or conclude trivy is broken.

### Pitfall: Verify cluster context BEFORE any kubectl commands
The entire first-pass investigation ran against stg context (kubectl was pointing at `jkt-stg-infra-eks-tada`). All `kubectl get` commands returned NotFound/empty because trivy was on prd, not stg. This led to wrong conclusion that trivy was removed, resulting in accidental deletion of valid manifest files. ALWAYS run `kubectl config current-context` first.

### Pitfall: Manifest files deployed via kubectl apply (not ArgoCD) are still valid
Just because a manifest dir has no ArgoCD Application doesn't mean the files are orphaned. Some resources are deployed via `kubectl apply` directly (e.g., trvy dashboard). Check if the resources exist in the cluster before deleting manifest files. If resources exist and were applied manually, the manifest files are their source of truth — deleting them loses the ability to recreate or update them.

### Pattern: Orphaned HPA bulk cleanup

HPAs left behind after Deployments are deleted (e.g., migrated to KEDA ScaledObjects or decommissioned) produce `Missing scaleTargetRef` critical issues in radar.

Detection + deletion workflow:
```bash
# 1. Find orphaned HPAs in cluster (HPAs targeting non-existent Deployments)
HPAS=$(kubectl get hpa -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.scaleTargetRef.name}{"\n"}{end}')
DEPS=$(kubectl get deploy -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort -u)
echo "$HPAS" | while IFS=' ' read -r hpa target; do
  [ -z "$hpa" ] && continue
  echo "$DEPS" | grep -qx "$target" || echo "ORPHAN: $hpa -> $target"
done

# 2. Delete orphaned HPAs from cluster
# (not managed by ArgoCD → manifest deletion alone won't prune)
kubectl delete hpa -n <namespace> <orphan1> <orphan2> ...

# 3. Delete orphaned HPA manifest files from repo
# Each orphan is typically a lone hpa.yaml in its own dir
# Verify: ls <dir> should show only hpa.yaml
find <manifest-repo>/<namespace> -name hpa.yaml -type f | while read f; do
  dir=$(dirname "$f")
  files=$(ls "$dir" | wc -l)
  if [ "$files" -eq 1 ]; then
    echo "LONE HPA: $f"
  fi
done
# Then rm -rf the lone-hpa dirs
```

Key lessons:
- HPAs not managed by ArgoCD won't be pruned by manifest deletion alone — need direct `kubectl delete hpa`
- Some HPAs are years old (271-383 days) — always check if they're truly orphaned (no Deployment, no ScaledObject, no CronJob with same name)
- STG and PRD manifest repos are separate — check both if both clusters affected

### Pattern: Stale Job bulk cleanup

Failed Jobs (BackoffLimitExceeded, DeadlineExceeded) accumulate when CronJobs lack `failedJobsHistoryLimit` or when limits were added after jobs already accumulated.

```bash
# Delete all failed jobs cluster-wide (safe — CronJobs create new ones on schedule)
kubectl delete jobs -A --field-selector=status.successful==0

# Check CronJob history limits across manifest repo
find <manifest-repo> -name cronjob.yaml -type f | while read f; do
  python3 -c "
import yaml
doc = yaml.safe_load(open('$f'))
if doc and doc.get('kind') == 'CronJob':
    spec = doc.get('spec', {})
    fl = spec.get('failedJobsHistoryLimit', 'MISSING')
    sl = spec.get('successfulJobsHistoryLimit', 'MISSING')
    if fl == 'MISSING' or sl == 'MISSING':
        print(f'MISSING LIMITS: {doc[\"metadata\"][\"name\"]} ({f})')
"
done
```

Recommended limits: `failedJobsHistoryLimit: 1`, `successfulJobsHistoryLimit: 1` (or 3 if debugging needed).

### Pattern: RWO PVC rollout stuck

Deployments using ReadWriteOnce PVCs with RollingUpdate strategy can get stuck — surge pod can't mount the volume while old pod holds it. Radar reports `Rollout stuck`.

Fix: change Deployment strategy to `Recreate` (kills old pod before creating new one), or use ReadWriteMany volume, or per-replica volumes.

### Pitfall: Radar cluster context can switch between calls
`get_dashboard` can return different clusters between calls (e.g., stg `jkt-stg-infra-eks-tada` vs prd `jkt-prd-infra-eks-tada`). Always check `cluster.name` in dashboard response before acting.

### Session 2: HPA + TLS cert cleanup (2026-08-03, continued)

#### Remaining HPA orphans after bulk cleanup

After deleting 153 runner HPAs, 2 remained:
- `avbo/avbo-beta` — not in manifest repo, HPA existed only in cluster (manually created, Deployment never existed). Deleted via `kubectl delete hpa avbo-beta -n avbo`.
- `sunday/sunday-downloader` — orphan HPA file at `sunday/sunday-downloader/hpa.yaml` (namespace `sunday`). App had been moved to `sunday-downloader/sunday-downloader/` (namespace `sunday-downloader`). Deleted orphan file from manifest + HPA from cluster.

#### kubectl context mismatch (recurring)

153 HPAs were deleted via `kubectl delete hpa -n runners ...` but kubectl was on stg context. HPAs persisted on prd. Had to re-run deletion after `kubectl config use-context jkt-prd-infra-eks-tada`. Always run `kubectl config current-context` before destructive operations.

#### TLS Certificate conflicts — see `references/tls-certificate-conflicts.md`

5 Certificate conflicts resolved. Gateway `external-gateway` owns all certs via `cert-manager.io/cluster-issuer` annotation. Manual Certificate resources deleted from manifest + cluster. Secret annotations cleared. All 5 Gateway-owned certs became `Ready=True` after reconciliation.

### Pattern: PDB blocks evictions (minAvailable on single-replica)

PodDisruptionBudget with `minAvailable: 1` on a single-replica Deployment sets `allowedDisruptions: 0` — blocks all voluntary evictions (node drains, CAST.ai rebalancing). Radar reports as critical.

Fix: change to `maxUnavailable: 1` in manifest. Allows 1 pod down during drains while still protecting the workload.

**Pitfall: `kubectl apply` fails when both minAvailable and maxUnavailable exist in the patch.** Use JSON patch instead:
```bash
kubectl patch pdb <name> -n <ns> --type=json \
  -p='[{"op":"remove","path":"/spec/minAvailable"},{"op":"add","path":"/spec/maxUnavailable","value":1}]'
```

Verify: `kubectl get pdb <name> -n <ns>` should show `ALLOWED DISRUPTIONS: 1`.

### Pattern: Scaled-to-0 Deployment + no-endpoint Service cleanup

Deployments intentionally scaled to 0 replicas (decommissioned but not removed) produce radar warnings: "Backing workload scaled to 0" + "service_no_endpoints" for matching Services. Common with exporters (e.g., pgbouncer-exporter).

Cleanup:
1. Check if helm-managed: `helm list -n <ns> | grep <name>`
2. If helm: `helm uninstall <release> -n <ns>`
3. Delete orphan resources not removed by helm (older manual Deployment + Service):
   ```bash
   kubectl delete deploy <name> -n <ns>
   kubectl delete svc <name> -n <ns>
   ```
4. Remove manifest files (helm values dir, metadata, etc.)
5. Verify: `kubectl get all -n <ns> | grep <name>` → empty

#### Trivy-system manifest files accidentally deleted

Trivy-operator was reinstalled on prd (namespace active, operator+server+dashboard running). Manifest files at `trivy-system/trivy-dashboard.yaml` + `trivy-system/vdb-httproute.yaml` were NOT ArgoCD-managed (deployed via `kubectl apply`). They were mistakenly deleted thinking trivy was fully removed. Had to `git revert` to restore them. Lesson: always check `kubectl get ns <ns>` + `kubectl get all -n <ns>` before deleting manifest files, even if radar shows no resources (radar cache may be stale).
