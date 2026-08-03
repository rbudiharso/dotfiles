---
name: kubernetes-job-troubleshooting
description: "Use when diagnosing stuck/crashing k8s pods: Jobs, CronJobs, Deployments."
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [kubernetes, k8s, job, cronjob, deployment, troubleshooting, backup, pbm]
---

# Kubernetes Pod Troubleshooting

Diagnose and resolve stuck, long-running, or crashed Kubernetes pods — Jobs, CronJobs, and Deployments. Covers backup jobs, scheduled tasks, rollout failures, CrashLoopBackOff, and any pod that hangs or crashes beyond its expected behavior.

## When to Use

- A k8s Job/CronJob pod has been Running longer than expected
- User reports a stuck backup, cleanup, or scheduled task pod
- Job pod keeps CrashLoopBackOff-ing after a change
- Need to cancel an in-flight operation and restart a job
- CronJob not triggering or previous job blocking new runs
- A Deployment pod is CrashLoopBackOff-ing after a new image rollout
- Need to rollback a broken Deployment to a working revision
- Radar MCP reports issues on a cluster — need to triage which are manifest-fixable vs stale cache vs node-level
- Orphaned HPAs (Missing scaleTargetRef) need bulk cleanup from cluster + manifest repo
- Stale failed Jobs (BackoffLimitExceeded, DeadlineExceeded) accumulating across namespaces
- CronJobs missing failedJobsHistoryLimit/successfulJobsHistoryLimit causing job buildup
- RWO PVC Deployment rollout stuck — surge pod blocked waiting for volume
- TLS Certificate conflicts — duplicate Certificate resources writing to same Secret (Gateway-owned vs manual), causing `Ready=False` / `IncorrectCertificate`

## Diagnosis Workflow

### 1. Find the pod across all clusters

If the user gives a pod name but not the cluster/namespace, search both contexts:

```bash
kubectl --context <ctx-a> get pod <name> -A 2>/dev/null
kubectl --context <ctx-b> get pod <name> -A 2>/dev/null
# Or broad search:
kubectl --context <ctx> get pods -A | grep <keyword>
```

Never assume the default context is correct. The user's k8s infra may span stg + prd clusters (e.g. `jkt-stg-infra-eks-tada`, `jkt-prd-infra-eks-tada`).

### 2. Get pod status + age

```bash
kubectl --context <ctx> -n <ns> get pod <pod> -o wide
```

Check: STATUS (Running/CrashLoopBackOff/Completed), RESTARTS, AGE. A pod Running for hours/days when the job should take minutes is the primary signal.

### 3. Get logs — both current and previous

```bash
kubectl --context <ctx> -n <ns> logs <pod> --tail=50
kubectl --context <ctx> -n <ns> logs <pod> --previous --tail=50
```

If logs are huge (e.g. polling loops printing dots), grep for keywords:
```bash
kubectl --context <ctx> -n <ns> logs <pod> | grep -E "ERROR|FAIL|timeout|stuck|cancel" | head -20
```

### 4. Describe pod for events

```bash
kubectl --context <ctx> -n <ns> describe pod <pod> | tail -30
```

Look for: OOMKill, image pull failures, scheduling issues, volume mount errors.

### 5. Check the Job and CronJob status

```bash
kubectl --context <ctx> -n <ns> get job <job-name>
kubectl --context <ctx> -n <ns> get cronjob <cronjob-name>
```

Job STATUS shows COMPLETIONS (e.g. `0/1` = not done). A job stuck at `Running` for 31h with `0/1` completions is the classic stuck pattern.

Check if the CronJob has a `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` — old jobs may block new runs if concurrency policy is Forbid (default).

### 6. Identify the root cause pattern

Common stuck-job patterns:

| Pattern | Symptom | Root Cause |
|---------|---------|------------|
| Command polls forever | Logs show repeating dots/progress output | Underlying operation hung; `--wait` flag never returns |
| External dependency down | Connection errors in logs | DB node, S3, API endpoint unreachable |
| Agent reports OK but doesn't execute | Status shows "running" but 0 progress | Agent process alive but worker thread dead |
| Job pod can't start | CrashLoopBackOff immediately | Missing secret/configmap, wrong service account, bad image |
| Resource exhaustion | OOMKilled in events | Job needs more memory/CPU than limits allow |
| Pod Pending with node affinity | `FailedScheduling` + `node(s) didn't match Pod's node affinity/selector` | Pod targets a specific node that no longer exists (CAST.ai recycled node). Non-fatal if operator/controller creates new jobs for current nodes. |

### 7. Check the underlying system (not just k8s)

For backup/monitoring jobs, the k8s pod is often just a client calling an external system. The actual work happens elsewhere:
- PBM backups: agents run on MongoDB EC2 instances, not k8s pods
- Velero backups: controller runs in k8s but targets are external volumes
- Database jobs: may connect to external RDS/EC2 databases

The k8s pod being "Running" doesn't mean the external operation is progressing. Check the external system's status directly if possible (API calls, CLI tools installed in the pod).

## Resolution Patterns

### Cancel + restart

For jobs where the underlying operation supports cancellation:

1. Cancel the operation from inside the pod (or a helper pod with same credentials):
   ```bash
   kubectl --context <ctx> -n <ns> exec <pod> -- <cancel-command>
   ```
2. If `--wait` command doesn't exit after cancel (it may not know the operation was cancelled externally), delete the pod:
   ```bash
   kubectl --context <ctx> -n <ns> delete pod <pod>
   ```
3. Job controller creates a new pod. Check if the new attempt succeeds.
4. If the same failure recurs, the root cause is in the external system, not the job config.

### Triggering a manual job from CronJob

```bash
# Create a one-off job from cronjob template:
kubectl --context <ctx> -n <ns> create job <manual-name> --from=cronjob/<cronjob-name>
```

WARNING: the cronjob's default `backoffLimit` may be 0 or 1, causing the job to fail fast before you can grab logs. For debugging, create a custom Job spec from the cronjob template with higher `backoffLimit` and a modified command (e.g. just run status checks, not the full backup):

```python
import json
# Get cronjob spec, build custom job with modified command
cj = json.loads(kubectl_get_cronjob_output)
job = {
    "apiVersion": "batch/v1",
    "kind": "Job",
    "metadata": {"name": "<debug-name>", "namespace": "<ns>"},
    "spec": {
        "template": cj["spec"]["jobTemplate"]["spec"]["template"],
        "backoffLimit": 3,
        "ttlSecondsAfterFinished": 300
    }
}
# Override command for diagnostics
job["spec"]["template"]["spec"]["containers"][0]["command"] = ["/bin/sh", "-c", "<diagnostic-commands>"]
```

### Running ad-hoc pods with same credentials

When you need to run CLI commands against an external system using the job's service account and secrets:

```bash
cat <<'EOF' | kubectl --context <ctx> -n <ns> apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: <debug-pod-name>
  namespace: <ns>
spec:
  restartPolicy: Never
  serviceAccountName: <sa-from-cronjob>
  containers:
  - name: debug
    image: <image-from-cronjob>
    command: ["/bin/sh", "-c", "<commands>"]
    env:
    - name: <ENV>
      valueFrom:
        secretKeyRef:
          name: <secret-from-cronjob>
          key: <key>
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 256Mi
EOF
```

Then:
```bash
sleep 10 && kubectl --context <ctx> -n <ns> logs <debug-pod-name>
kubectl --context <ctx> -n <ns> delete pod <debug-pod-name>
```

NOTE: `kubectl run --serviceaccount` is NOT a valid flag. Use a Pod manifest or `--overrides` JSON instead.

### Cleanup after diagnosis

```bash
# Delete debug jobs/pods
kubectl --context <ctx> -n <ns> delete job <debug-job-name>
kubectl --context <ctx> -n <ns> delete pod <debug-pod-name>

# Delete failed/stuck jobs blocking cronjob
kubectl --context <ctx> -n <ns> delete job <stuck-job-name>
```

## User Preferences

- **Before deleting any Certificate or Secret**: ALWAYS verify no other resources reference it first. Check manifest repo (`grep -rl '<secret-name>' --include='*.yaml'`) and cluster (`kubectl get cert -A -o jsonpath=...`). User explicitly corrected this during TLS cert cleanup — "before delete cert make sure it is not referenced by other resources".
- **Prod k8s changes**: require explicit go-ahead. User expects confirmation before helm upgrades, deletions, or any infra changes affecting prod clusters.
- **Real executed proof**: user wants actual command output before accepting a fix as verified, not inferred/plausible results.

## Pitfalls

- **`--wait` flag traps**: Commands like `pbm backup --wait` or `velero backup wait` block forever if the underlying operation is stuck. The pod shows "Running" but no progress. Cancelling the operation externally may not cause the wait command to exit — you often need to delete the pod.
- **Agent health vs execution health**: Agents (PBM, Velero, etc.) may report "OK" to the control plane but fail to actually execute. Status checks show green; actual work produces 0 bytes. Always check output/progress, not just agent status.
- **Same node selection**: Some systems deterministically select the same node for operations (e.g. PBM selects a specific secondary for backup). If that node is broken, ALL retries fail identically. The fix must be on that node, not in the job config.
- **`kubectl run` limitations**: `--serviceaccount` is not a valid flag for `kubectl run`. Use Pod manifests or `--overrides` JSON when you need service account, secrets, or volume mounts.
- **CronJob concurrency blocking**: If CronJob `concurrencyPolicy: Forbid` (default), a stuck job blocks all future scheduled runs. Clean up the stuck job before the next scheduled run.
- **Pod deleted before logs grabbed**: Jobs with `backoffLimit: 0` delete pods immediately on failure. Use higher `backoffLimit` for debugging, or check events for container exit reasons.
- **External systems not visible from k8s**: Backup/monitoring agents often run on EC2 instances outside the cluster. `kubectl get nodes` won't show them. Need SSH, SSM, or the agent's own CLI to diagnose.
- **SSM send-command when session-manager-plugin missing**: If `aws ssm start-session` fails ("SessionManagerPlugin is not found"), use `aws ssm send-command` + `get-command-invocation` instead — no plugin required. Send shell commands, poll for output 5s later.
- **"0 bytes" in backup status is misleading**: PBM (and similar tools) only update size metadata after backup completes. A backup actively dumping 206GB shows `0 B` in `describe-backup` while mongodump is running. Check the agent's local logs (journalctl on EC2) for real progress, not the control plane metadata.
- **Agent restart = stale lock**: If a backup agent (PBM, etc.) is restarted mid-backup (systemd, reboot, package update), the backup lock is never released. New agent process sees stale lock, pauses dependent operations (PITR slicer), and the job polls forever. Fix: cancel the stuck backup via CLI to release the lock, then trigger a fresh run.
- **Multiple stuck backups accumulate**: Each failed/cancelled backup may leave a snapshot entry in the backup system's metadata. These don't block new backups but clutter status output. Clean them up with the backup system's CLI if needed.
- **Broken image rollout leaves stuck RS**: A Deployment rollout to a broken image (e.g. missing node_modules) leaves the new ReplicaSet at desired=1 with CrashLoopBackOff pods, while the old RS keeps running. `kubectl rollout undo --to-revision=<N>` is the fastest fix. Scaling the broken RS to 0 manually may be needed if the Deployment controller keeps restoring it.
- **`rollout undo` warning is cosmetic**: `rollout undo` warns about `last-applied-configuration` annotation not being updated when the Deployment was previously managed with `kubectl apply`. The rollback still works — just update the applied config file before the next `kubectl apply` to avoid drift.
- **macOS AppleDouble files corrupt git pack indexes**: On macOS, `.git/objects/pack/._pack-*.idx` files (AppleDouble resource forks) cause `error: non-monotonic index` spam on every git command. Non-fatal — commits/pushes still work. Filter with `2>&1 | grep -v 'non-monotonic'` to reduce noise. Permanent fix: `git config core.precomposeunicode false` or remove the `._` files.
- **Stg and prd manifest repos differ in structure**: `tada-stg-manifest` uses `<namespace>/<namespace>/` paths (e.g. `tada-partner/tada-partner/deployment.yaml`), `tada-prd-manifests` uses `<namespace>/<app-name>/` paths (e.g. `tada-partner/partner-web-php/deployment.yaml`). Don't assume same path across repos.
- **ArgoCD prune only works for managed resources**: Deleting a manifest file from repo + ArgoCD auto-sync (prune: true) only removes resources that belong to an active ArgoCD Application. If the Application was deleted but its resources were left in the cluster (orphaned), manifest deletion does nothing — the resource persists with no ArgoCD owner. Always verify with `kubectl get <resource> -n <ns>` after manifest push, and `kubectl delete` directly if needed.
- **TLS Certificate conflicts via Gateway annotation**: When a Gateway has `cert-manager.io/cluster-issuer` annotation, cert-manager auto-creates Certificate objects for each TLS listener. If manual Certificate resources (from manifest or kubectl apply) also write to the same Secret, both report `Ready=False` with reason `IncorrectCertificate`. Resolution: (1) find all Certs writing to each conflicting Secret, (2) identify Gateway-owned (have `ownerReferences: Gateway/...`) vs manual (no owner), (3) delete manual Certificate resources from manifest + cluster, (4) clear stale `cert-manager.io/*` annotations from Secrets so Gateway-owned cert can claim them, (5) if Secret still shows `IncorrectIssuer`, delete the Secret entirely — cert-manager re-creates it fresh, (6) wait ~30s for Gateway-owned certs to become `Ready=True`. See `references/tls-certificate-conflicts.md` for worked example.
- **Node.js `Cannot find module` in prod image**: Common in multi-stage Docker builds where `npm prune --production` or `npm ci --omit=dev` removes a module that runtime code actually needs. Two sub-patterns:
  - **devDependency required at runtime** (e.g. `tsconfig-paths/register`): Moving to `dependencies` fixes the install step, BUT `tsconfig-paths` also needs `tsconfig.json` copied to the prod image AND its path mappings (`@/*` → `src/*`) point to source dirs that don't exist in production (only `dist/` is copied). For compiled-to-dist projects, revert to `module-alias/register` instead — it reads `_moduleAliases` from `package.json` (already in prod image) and maps `@` → `./dist/src` correctly.
  - **Path resolver swap** (`module-alias` → `tsconfig-paths`): If a commit switches the runtime path resolver from `module-alias/register` to `tsconfig-paths/register`, reverting `bin/www.ts` (or equivalent entrypoint) back to `module-alias/register` is the correct fix. `module-alias` was designed for compiled JS in production; `tsconfig-paths` was designed for `ts-node` dev workflows.

## Deployment Pod Troubleshooting

When a Deployment pod is CrashLoopBackOff-ing (not a Job/CronJob), the diagnosis path differs: focus on image/entrypoint failures and rollout rollback rather than external operations.

### 1. Get logs + identify crash reason

```bash
kubectl --context <ctx> -n <ns> logs <pod> --tail=30
kubectl --context <ctx> -n <ns> logs <pod> --previous --tail=30
```

Common crash patterns:
- `Error: Cannot find module 'X'` — missing dependency in image (node_modules incomplete, wrong base image, multi-stage build forgot install step)
- `exec format error` — wrong architecture image on wrong node (amd64 image on arm64 node)
- `permission denied` — container runs as non-root but files owned by root
- `OOMKilled` — check `kubectl describe pod <pod>` events section

### 2. Check which ReplicaSet is current vs old

```bash
kubectl --context <ctx> -n <ns> get rs -l <selector>
```

A broken rollout leaves TWO ReplicaSets: the new one (CrashLoopBackOff, desired=1) and the old one (Running, desired=N). The Deployment status shows "ReplicaSet X is progressing" — stuck mid-rollout.

Check revision annotations to identify which is which:
```bash
kubectl --context <ctx> -n <ns> get rs -l <selector> -o jsonpath='{range .items[*]}{.metadata.name}{"  rev="}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"  desired="}{.spec.replicas}{"  image="}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

### 3. Rollback to working revision

If the new image is broken, rollback to the previous working revision:

```bash
kubectl --context <ctx> -n <ns> rollout undo deploy/<deployment> --to-revision=<N>
```

Find the working revision number from the RS list (the one with desired=replicas and READY pods).

WARNING: `rollout undo` prints a warning if the Deployment was previously managed with `kubectl apply` — the last-applied-configuration annotation won't be updated. This is cosmetic; the rollback still works. Future `kubectl apply` calls should use the corrected config.

### 4. Verify rollout

```bash
kubectl --context <ctx> -n <ns> rollout status deploy/<deployment>
kubectl --context <ctx> -n <ns> get pods -l <selector>
```

All pods should be Running with 0 restarts. The crashed pod from the broken revision terminates automatically.

### 5. Scale stuck ReplicaSet manually (if rollback doesn't clean up)

Sometimes a broken ReplicaSet stays at desired=1 after rollback. Scale it to 0:
```bash
kubectl --context <ctx> -n <ns> scale rs <broken-rs-name> --replicas=0
```

If the Deployment controller keeps restoring it, the RS may still be the active revision. Check `kubectl get deploy <name> -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'` to confirm which revision is current.

### Common Deployment crash patterns

| Pattern | Symptom | Root Cause |
|---------|---------|------------|
| Missing node module | `Cannot find module 'tsconfig-paths/register'` | Image build missing devDependency or production install stripped it |
| Wrong arch | `exec format error` or `standard_init_linux.go:190` | amd64 image on arm64 node or vice versa |
| Init container failure | `Init:Error` or `Init:CrashLoopBackOff` | Init container command fails (e.g. `touch` on read-only path) |
| Probe failure | Pod Running but not Ready | Liveness/readiness probe path or port wrong |
| Secret/config missing | `ContainerCreating` stuck or crash on env load | Reference to non-existent secret/configmap key |
| Image pull failure | `ImagePullBackOff` | ECR/registry permissions, wrong tag, image not pushed |
| **Missing imagePullSecret (false positive)** | Radar reports `Missing imagePullSecret` but pods are Running/Ready with 0 restarts | `imagePullSecrets` references a Secret that doesn't exist, but EKS node IAM instance role already grants ECR access. k8s silently ignores missing pull secret when node role suffices. Fix: remove `imagePullSecrets` from manifest to stop radar noise. Check pod status before fixing — if pods are healthy, it's cosmetic. |

## Using Radar MCP for Cluster-Wide Triage

When diagnosing issues across a large cluster (300+ workloads), use Radar MCP tools instead of manual kubectl:

1. **`get_dashboard`** — cluster overview: node health, problem count, top issues by severity. Shows 30 of N problems sorted by severity. Use `namespace=` param to narrow.
2. **`issues`** — full list of all detected issues with severity, category, affected pods, first/last seen, diagnostic context. Output can be very large (100K+ chars) — pipe through filtering.
3. **`get_resource`** — drill into a specific resource (Deployment, Pod, Job) for full spec + status + issue summary + audit summary.
4. **`diagnose`** — guided diagnosis for specific symptoms (CrashLoopBackOff, OOMKilled, ImagePullBackOff).

### Manifest-related issue categories from Radar

| Category | Meaning | Fix location |
|----------|---------|-------------|
| `missing_config_ref` | References a Secret/ConfigMap that doesn't exist | Manifest repo — add the resource or remove the reference |
| `missing_scale_target` | HPA points at non-existent Deployment | Manifest repo — remove orphaned HPA or add missing Deployment. For bulk cleanup: parse all hpa.yaml files, cross-ref scaleTargetRef.name against Deployment names, delete orphans. See `references/radar-manifest-triage.md` for the 153-HPA bulk cleanup technique. |
| `probe_failure` | Liveness/readiness probe failing | Manifest repo — check probe path/port/timeout, may need resource limit tuning |
| `job_backoff_exceeded` | Job reached backoff limit | Manifest repo — check job command, resources, concurrency; may be app-level |
| `deadline_exceeded` | Job exceeded activeDeadlineSeconds | Manifest repo — increase deadline or fix the underlying slow operation |
| `incorrect_certificate` | Two Certificate resources write to same Secret | Manifest repo — delete manual Certificate, let Gateway own it. See `references/tls-certificate-conflicts.md` |

### Triage workflow

1. Call `get_dashboard` for overview — identify critical issues
2. Call `issues` for full list — filter by manifest-fixable categories
3. Call `get_resource` for each affected workload — verify if issue is real (pods may be healthy despite radar report)
4. Fix manifest in the correct repo (stg vs prd have separate repos: `tada-stg-manifest` and `tada-prd-manifests`)
5. Verify fix with a YAML validation script (parse + assert structure)

### Stale issue detection

Radar issues have `first_seen` and `last_seen` timestamps. If `last_seen` is days/weeks old and the pod is currently Running/Ready, the issue is likely stale or a false positive. Always cross-reference with live pod status via `get_resource` before fixing.

**Deleted namespaces:** Radar cache retains issues for namespaces that no longer exist. If `kubectl get ns <namespace>` returns NotFound, the radar issue is stale — no cluster action needed. Check for orphaned manifest files in the repo and clean them up if found.

**Cluster context switching:** Radar `get_dashboard` can return different clusters between calls (e.g., stg vs prd). Always check `cluster.name` in the dashboard response before acting on issues. Radar MCP connects to whichever cluster its server-side kubeconfig points at — switching `kubectl config use-context` does NOT change radar's target cluster.

**kubectl context mismatch:** Before running kubectl delete/apply commands, ALWAYS verify `kubectl config current-context` matches the target cluster. If radar reports prd issues but kubectl is on stg context, kubectl commands will silently operate on the wrong cluster. This is especially dangerous when deleting resources (HPAs, Jobs) — the deletion succeeds on the wrong cluster with no error, and the prd resources persist unnoticed until re-checked.

## References

- `references/pbm-stuck-backup.md` — Percona Backup for MongoDB (PBM) stuck backup diagnosis: pbm CLI commands, common failure modes, node-specific agent issues
- `references/deployment-crashloop.md` — Deployment CrashLoopBackOff diagnosis: broken image rollback, RS revision management, Node.js missing module patterns
- `references/radar-manifest-triage.md` — Radar MCP cluster-wide triage: imagePullSecret false-positive, HPA orphan bulk cleanup (cluster + manifest), stale Job cleanup + CronJob history limits, RWO PVC rollout stuck, trivy node-collector stale node, kubectl context mismatch pitfall, stg vs prd manifest repo paths
- `references/tls-certificate-conflicts.md` — cert-manager Gateway-owned vs manual Certificate conflicts: identifying duplicates, clearing Secret annotations, re-issuing after IncorrectIssuer
