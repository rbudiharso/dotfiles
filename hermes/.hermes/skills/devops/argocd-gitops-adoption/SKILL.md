---
name: argocd-gitops-adoption
description: "Adopt unmanaged k8s namespaces into ArgoCD GitOps. Single or batch (50+)."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [argocd, gitops, kubernetes, k8s, application, sync, externalsecret, infisical, migration]
---

# ArgoCD GitOps Adoption

Adopt unmanaged Kubernetes namespaces into ArgoCD GitOps management. Export live cluster state as source of truth, create ArgoCD Application CRDs, fix sync drift, and migrate from deprecated secret tools (Infisical) to ExternalSecret/vault.

## When to Use

- Namespace is deployed manually (kubectl apply) and needs ArgoCD management
- User asks to "create argocd application" for existing workloads
- User asks to find all unmanaged namespaces and bring them under ArgoCD
- Need to batch-adopt many namespaces (50+) with existing manifests but no Application CRs
- Need to migrate from Infisical to ExternalSecret/vault
- ArgoCD Application created but stuck OutOfSync or auth errors
- Need to replace old ingress resources with Gateway API HTTPRoutes

## Batch Adoption (Multiple Namespaces at Once)

When adopting many namespaces simultaneously (e.g. 50+), use this pattern instead of one-at-a-time:

### 1. Classify all namespaces

Compare cluster namespaces against ArgoCD apps AND manifest repo dirs to categorize:

```python
import os, json, subprocess

# Get all namespaces
result = subprocess.run(["kubectl", "get", "ns", "-o", "json"], capture_output=True, text=True, timeout=30)
all_ns = [ns["metadata"]["name"] for ns in json.loads(result.stdout)["items"]]

# Get ArgoCD app target namespaces
result = subprocess.run(["kubectl", "get", "applications", "-n", "argocd", "-o", "json"], capture_output=True, text=True, timeout=30)
argo_ns = {app["spec"]["destination"]["namespace"] for app in json.loads(result.stdout)["items"]}

# Get manifest repo top-level dirs
repo_dirs = {d for d in os.listdir("<manifest-repo>") if os.path.isdir(os.path.join("<manifest-repo>", d))}

# Classify
fully_managed = argo_ns                                          # has app + manifests
has_manifests_no_app = repo_dirs - argo_ns - {"argocd", "helm"} # manifests exist, no Application CR
running_no_manifests = set(all_ns) - repo_dirs - argo_ns         # need manifests extracted first
```

Three categories:
- **Fully managed** — ArgoCD app exists + manifests in repo. No action.
- **Has manifests, no ArgoCD app** — just create Application CRs. Most common case. 54 of 75 unmanaged namespaces fell here.
- **Running, no manifests anywhere** — need to export live state first, then create app.

Also classify by type: infrastructure (Helm-managed: cert-manager, external-secrets, ingress-controller, istio-system, keda, monitoring, reloader, trivy-system, gitlab-runner, backup, exporters, memcached) vs SaaS applications vs empty/stale namespaces.

### 2. Check subdirectory structure

Manifest repos use `<namespace>/<app-dir>/` structure. Check if each namespace dir has subdirs (multi-app) or flat YAMLs:

```python
for ns in has_manifests_no_app:
    path = os.path.join(repo_base, ns)
    subdirs = [d for d in os.listdir(path) if os.path.isdir(os.path.join(path, d)) and not d.startswith(".")]
    yaml_files = [f for f in os.listdir(path) if f.endswith(".yaml")]
    # subdirs and no flat yamls -> one app per namespace pointing at top-level dir
    # ArgoCD syncs all subdirs recursively
```

### 3. Batch-generate Application YAMLs

Generate one Application per namespace pointing at namespace top-level dir. ArgoCD syncs all subdirs recursively:

```python
for ns in sorted(has_manifests_no_app):
    content = f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {ns}
  namespace: argocd
spec:
  project: saas
  source:
    repoURL: git@gitlab.gift.id:infra/<manifest-repo>.git
    targetRevision: main
    path: {ns}
  destination:
    server: https://kubernetes.default.svc
    namespace: {ns}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
"""
    with open(f"<repo>/argocd/{ns}.yaml", "w") as f:
        f.write(content)
```

**Key differences from single-app adoption:**
- `targetRevision: main` (not `HEAD`) — matches existing pattern in prd manifest repo
- `prune: true` + `selfHeal: true` — auto-sync with resource pruning, self-heal drift
- `repoURL` uses SSH form (`git@gitlab.gift.id:...`) for prd repo, HTTPS (`https://gitlab.gift.id/...`) for stg repo — match what existing apps use
- One app per namespace (not per subdirectory) — ArgoCD syncs all YAMLs in subdirs recursively

### 4. Apply all + commit

```bash
# Apply all Application YAMLs at once
kubectl apply -f argocd/ -n argocd

# Verify all synced + healthy (wait 15s after apply)
sleep 15
kubectl get applications -n argocd | grep -v "Synced.*Healthy" | head -20

# Commit + push
git add argocd/*.yaml
git commit -m "Add N ArgoCD applications for unmanaged namespaces"
git pull --rebase  # handle concurrent pushes
git push
```

### 5. Batch-patch syncPolicy on all existing apps

After batch adoption (or for existing apps), ensure ALL apps have `automated.enabled=true`, `prune=true`, `selfHeal=true`. Use `kubectl patch` — NOT `kubectl apply` (apply needs full spec, patch only updates target field):

```bash
# Find all non-compliant apps
kubectl get applications -n argocd -o json | jq -r \
  '.items[] | select(.spec.syncPolicy.automated.enabled != true or .spec.syncPolicy.automated.prune != true or .spec.syncPolicy.automated.selfHeal != true) | .metadata.name'

# Batch-patch (50 at a time via grouped shell command)
PATCH='{"spec":{"syncPolicy":{"automated":{"enabled":true,"prune":true,"selfHeal":true}}}}'
# For each app: kubectl patch application <name> -n argocd --type=merge -p "$PATCH"
```

Also update YAML files in `argocd/` dir to match (so future git sync doesn't revert):
```python
import yaml, glob
for f in glob.glob("argocd/*.yaml"):
    doc = yaml.safe_load(open(f))
    auto = doc.setdefault("spec",{}).setdefault("syncPolicy",{}).setdefault("automated",{})
    auto["enabled"] = True; auto["prune"] = True; auto["selfHeal"] = True
    yaml.safe_dump(doc, open(f,"w"), default_flow_style=False, sort_keys=False)
```

**Real-world result**: 285 of 299 apps needed patching (54 new apps had `automated=false`, 231 old apps had `prune=false, selfHeal=false`). All 285 patched via kubectl patch in 6 batches of 50. YAML files updated to match. Commit + push.

### 6. Verify

- `kubectl get applications -n argocd | wc -l` — total app count matches expected
- `kubectl get applications -n argocd | grep -v "Synced.*Healthy"` — should be empty or only pre-existing Unknown apps
- Filter for only new apps to check their status specifically
- Pre-existing apps may show `Unknown` sync (e.g. scheduler apps already in that state before batch adoption). Don't confuse with new app issues.
- For Unknown apps, check `.status.conditions[].message` for root cause — usually YAML syntax errors or path mismatches.

**Real-world result**: 54 Application YAMLs generated, applied, all 54 Synced + Healthy within 15s. Total apps went from 245 to 299. Commit + push completed with `git pull --rebase` for concurrent push handling.

## Workflow

### 1. Check if namespace is already ArgoCD-managed

```bash
# Check ArgoCD applications
kubectl --context <ctx> -n argocd get applications | grep <namespace>

# Check for ArgoCD labels on deployments
kubectl --context <ctx> -n <ns> get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels}{"\n"}{end}' | grep argocd
```

If no ArgoCD apps and no argocd labels → namespace is unmanaged.

### 2. Export live resources as source of truth

Export all resources from the live cluster. Strip cluster-specific fields that ArgoCD should not manage:

```python
import yaml, subprocess

def export_resource(ctx, ns, rtype, name):
    cmd = f"kubectl --context {ctx} -n {ns} get {rtype} {name} -o yaml 2>/dev/null"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
    doc = yaml.safe_load(result.stdout)
    # Strip cluster-specific metadata
    for k in ['resourceVersion','uid','generation','creationTimestamp','managedFields','status','selfLink']:
        doc['metadata'].pop(k, None)
    anns = doc['metadata'].get('annotations', {})
    for k in ['kubectl.kubernetes.io/last-applied-configuration','deployment.kubernetes.io/revision']:
        anns.pop(k, None)
    # Strip pod template cluster-injected annotations
    if 'spec' in doc and 'template' in doc.get('spec', {}):
        t = doc['spec']['template']
        tanns = t.get('metadata', {}).get('annotations', {})
        for k in ['kubectl.kubernetes.io/restartedAt','autoscaling.cast.ai/recommendation-applied-at',
                   'autoscaling.cast.ai/vertical-recommendation-hash']:
            tanns.pop(k, None)
        for c in t.get('spec',{}).get('containers',[]):
            c.pop('imagePullPolicy', None)
    doc.pop('status', None)
    return doc
```

**Critical: strip clusterIP from Services** — let k8s assign dynamically:
```python
doc['spec'].pop('clusterIP', None)
doc['spec'].pop('clusterIPs', None)
```

### 3. Match existing ArgoCD app structure

Check an existing working Application in the same cluster to copy the pattern:

```bash
kubectl --context <ctx> -n argocd get application <working-app> -o jsonpath='{.spec}' | python3 -m json.tool
```

Key fields to match:
- `project` — MUST match a project that has a repo secret (see pitfall below)
- `source.repoURL` — same manifest repo as other apps
- `source.targetRevision: HEAD`
- `syncPolicy.automated.enabled: true`
- `syncOptions: [CreateNamespace=true]`

### 4. Create Application manifests

One Application per logical unit (e.g. per deployment + its services + routes):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  destination:
    namespace: <ns>
    server: https://kubernetes.default.svc
  project: <project>  # MUST match working app's project
  source:
    path: <ns>/<app-dir>
    repoURL: https://gitlab.gift.id/infra/<manifest-repo>.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      enabled: true
    syncOptions:
    - CreateNamespace=true
```

### 5. Add ignoreDifferences for cluster-injected annotations

Cluster autoscalers (CAST.ai) and kubectl inject annotations that ArgoCD sees as drift. Add `ignoreDifferences` to Application spec:

```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/template/metadata/annotations/autoscaling.cast.ai~1recommendation-applied-at
    - /spec/template/metadata/annotations/autoscaling.cast.ai~1vertical-recommendation-hash
    - /spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt
```

Note: `/` in annotation keys must be escaped as `~1` in JSON pointer syntax.

### 6. Ensure pod template labels are in manifest

ArgoCD sees missing pod template labels as OutOfSync. The live pod has labels (e.g. `app: <name>`) injected by the Deployment selector, but if the manifest's `spec.template.metadata.labels` is empty, ArgoCD flags it. Add labels explicitly:

```yaml
spec:
  template:
    metadata:
      labels:
        app: <app-name>
```

### 7. Commit + push, then apply Applications

```bash
git add <ns>/
git commit -m "feat(<ns>): add ArgoCD applications, sync manifests from live cluster"
git pull --no-rebase  # avoid rebase conflicts on shared manifest repos
git push

# Apply Application CRDs to cluster
kubectl --context <ctx> apply -f <ns>/<app>/application.yaml
```

### 8. Force refresh if apps stay Unknown

Newly created Applications may stay `Unknown` sync status. Force refresh:

```bash
kubectl --context <ctx> -n argocd patch application <app-name> --type=merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

Wait 15-20s, then check status again.

### 9. Migrate from Infisical to ExternalSecret/vault

If the namespace uses Infisical for secrets and ExternalSecret is already synced from vault:

1. Verify ExternalSecret is synced:
```bash
kubectl --context <ctx> -n <ns> get externalsecret <name> -o jsonpath='{.status.conditions[0].reason}'
# Should show "SecretSynced"
```

2. Remove Infisical annotations from deployment manifests:
   - `secrets.infisical.com/auto-reload`
   - `secrets.infisical.com/managed-secret.*`

3. Remove infisical ConfigMap and ServiceAccount from repo manifests.

4. Delete Infisical resources from cluster:
```bash
kubectl --context <ctx> -n <ns> delete configmap infisical-config-map
kubectl --context <ctx> -n <ns> delete serviceaccount <name>-infisical-auth
```

5. Force ArgoCD refresh to sync deployment without Infisical annotations.

6. Verify pods restart cleanly with vault-backed secret.

### 10. Create ExternalSecret with Vault Kubernetes Auth (Fresh Creation)

When a namespace needs a NEW secret backed by Vault (not migrating from Infisical):

#### Vault k8s auth pattern

All ExternalSecrets use the same Vault k8s auth pattern:
- Vault server: `https://vault.internal.gift.id`
- Kubernetes auth mount path: `kubernetes-stg` (stg) or `kubernetes-prd` (prd)
- Vault KV path: `secret` (v2)
- Secret key pattern: `<namespace>/<env>/<service>/env` (e.g. `bp-akr/staging/webhook/env`)
- Role pattern: `<service>-stg-reader` (stg) or `<service>-prd-reader` (prd)
- SA pattern: `<service>-staging` (stg) or `<service>-production` (prd)

#### Steps

1. Check if resources already exist (SA, SecretStore, ExternalSecret, target Secret, Vault role):
```bash
kubectl get sa <service>-staging -n <ns>
kubectl get secretstore <service>-staging-vault-store -n <ns>
kubectl get externalsecret <target-secret> -n <ns>
kubectl get secret <target-secret> -n <ns>  # may exist as manual secret
export VAULT_ADDR=https://vault.internal.gift.id
vault read auth/kubernetes-stg/role/<service>-stg-reader
```

2. Create ServiceAccount + Vault policy + Vault k8s auth role:
```bash
kubectl create sa <service>-staging -n <ns>

export VAULT_ADDR=https://vault.internal.gift.id
vault policy write <service>-stg-reader - <<'EOF'
path "secret/data/<namespace>/<env>/<service>/env" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes-stg/role/<service>-stg-reader \
  bound_service_account_names=<service>-staging \
  bound_service_account_namespaces=<ns> \
  policies=<service>-stg-reader \
  ttl=1h
```

3. Create SecretStore + ExternalSecret manifest (see `references/argocd-app-structure.md` for YAML template).

4. Apply + verify: SecretStore `Valid` + `Ready`, ExternalSecret `SecretSynced` + `Ready`. Check secret keys match Vault.

#### Pitfalls (ExternalSecret)

- **Existing manual secret**: Target may already exist (manually created). `creationPolicy: Owner` overwrites with Vault data. Vault may have more keys than manual secret had.
- **Vault CLI needs VAULT_ADDR**: Set `export VAULT_ADDR=https://vault.internal.gift.id` or CLI defaults to `127.0.0.1:8200` (connection refused).
- **mountPath is not a URL**: `mountPath: kubernetes-stg` is the Vault auth backend mount point, not a Kubernetes API path.
- **dataFrom extract vs data**: Use `dataFrom.extract` for flat key-value maps (all keys become secret keys). Use `data` with `secretKey` + `remoteRef` for individual key mapping.

## Pitfalls

- **ArgoCD project must match repo secret scope.** ArgoCD repo credentials are stored as secrets (e.g. `repo-3501802019`) and are project-scoped. If you create an Application with `project: default` but the repo secret is scoped to `project: saas`, ArgoCD gets "authentication required: HTTP Basic: Access denied" even though the repo URL is identical to a working app. Fix: use the same project as an existing working app that references the same manifest repo.
- **JSON pointer escaping for annotation keys.** Annotation keys containing `/` (e.g. `autoscaling.cast.ai/recommendation-applied-at`) must use `~1` in JSON pointer syntax: `/spec/template/metadata/annotations/autoscaling.cast.ai~1recommendation-applied-at`. Without escaping, ArgoCD silently ignores the ignoreDifferences rule.
- **Pod template labels cause OutOfSync.** Live pods have labels from the Deployment selector, but if `spec.template.metadata.labels` is empty in the manifest, ArgoCD flags it as OutOfSync. Always include pod template labels explicitly.
- **Service clusterIP must be stripped.** Exported Services have `clusterIP` and `clusterIPs` set by the cluster. If left in the manifest, ArgoCD tries to assign a specific IP on new clusters and conflicts. Strip these fields.
- **Istio waypoint deployments should NOT have ArgoCD apps.** Waypoint deployments have `ownerReferences` pointing to a Gateway resource — Istio manages them. Adding an ArgoCD Application causes conflicts. Leave waypoint resources outside ArgoCD management.
- **Old nginx ingress to HTTPRoute replacement.** When adopting a namespace that uses old `networking.k8s.io/v1 Ingress` with nginx, replace with `gateway.networking.k8s.io/v1 HTTPRoute` in the manifest. The live cluster may already have HTTPRoutes — export those instead of the old ingress.
- **git pull --no-rebase on shared manifest repos.** Manifest repos are shared across teams. `git pull --rebase` can conflict with concurrent pushes. Use `git pull --no-rebase` to merge instead. **Recovery from stuck rebase**: if `git pull --rebase` enters an interactive rebase state (`It has been rescheduled; edit the todo list`), recover with `git rebase --abort && git pull --no-rebase`. **Note**: On macOS with external drives, `git pull --rebase` may produce `error: non-monotonic index .git/objects/pack/._pack-*.idx` warnings from Spotlight metadata files. These are HARMLESS — the rebase + push still succeed. Don't abort on these errors.
- **macOS ._* files pollute git.** On macOS with external drives, `._*` resource fork files appear in directories. Use `.gitignore` or `git add` with explicit file paths to avoid committing them.
- **Verify ArgoCD app spec matches file on disk.** After applying an Application CRD, verify the cluster spec matches the file:
  ```bash
  kubectl get application <name> -n argocd -o json | jq '.spec' > /tmp/_cluster.json
  python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('<file>'))['spec'], indent=2, sort_keys=True))" > /tmp/_file.json
  diff /tmp/_cluster.json /tmp/_file.json
  ```
  Also verify sync status is `Synced` and health is `Healthy`. This catches typos in repoURL, path, namespace, or project that ArgoCD silently accepts but won't sync correctly.
- **Existing manifests may already be in repo.** Before generating new manifests, check if the namespace already has a directory in the manifest repo. Often manifests exist but lack an ArgoCD Application CRD — in that case, just create the Application and commit it. Compare live cluster state with repo manifests to identify drift (e.g. env vars injected by Reloader, HPA-scaled replicas) — these are runtime-only differences, not drift to fix.
- **ArgoCD auto-sync may restart pods.** When ArgoCD syncs a deployment for the first time (especially after removing annotations), it applies the manifest which triggers a rolling restart. This is expected — verify new pods come up healthy.
- **`kubectl apply -f argocd/` touches ALL files in dir.** When batch-applying, `kubectl apply -f argocd/` applies every YAML in the directory, including existing Application CRDs and any non-Application resources (e.g. HTTPRoute for argocd-server). Existing apps show "configured" (harmless update), but non-Application resources like HTTPRoutes also get re-applied. This is safe but be aware the apply scope is wider than just new files.
- **Batch adoption commit may need rebase.** Manifest repos are shared. `git push` may be rejected if someone else pushed first. `git pull --rebase` handles this. On macOS external drives, `non-monotonic index` errors from `._*` Spotlight files are harmless — don't abort.
- **Unquoted cronjob schedule causes Unknown sync.** CronJob manifests with `schedule: */30 * * * *` (unquoted) cause YAML parse errors — YAML interprets `*` as an alias reference. ArgoCD shows `Unknown` sync with error `did not find expected alphabetic or numeric character`. Fix: quote the schedule value: `schedule: "*/30 * * * *"`. This affected 7 scheduler apps simultaneously — all had the same unquoted schedule pattern. Check all CronJob manifests when batch-adopting scheduler namespaces.
- **App source path mismatch causes Unknown sync.** Apps may have `source.path: sika-vn/backend` but the actual repo structure is `sika/vn/backend` (nested dirs). ArgoCD shows `Unknown` with `app path does not exist`. Fix: update the Application spec path to match actual repo dir structure. Use `kubectl patch application <name> -n argocd --type=merge -p '{"spec":{"source":{"path":"<correct-path>"}}}'` and update the YAML file in `argocd/` dir.
- **Force refresh after fixing manifest errors.** After fixing YAML syntax or path issues in git, ArgoCD may not re-sync immediately. Force hard refresh: `kubectl patch application <name> -n argocd --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`. Wait 15-20s, then check status.
- **Orphaned manifest dirs without ArgoCD Applications.** Manifest dirs can exist in the repo without any ArgoCD Application referencing them. This happens when a tool (e.g. trivy-operator) is removed from the cluster but its manifest files are left behind. These dirs waste space and confuse radar/triage. To detect: `grep -r '<dir-name>' argocd/` — if no Application CR references the path, the dir is orphaned. Verify the namespace doesn't exist in cluster (`kubectl get ns <name>`), then delete the dir from the manifest repo.

## Verification

After adoption, verify all checks pass:

1. All ArgoCD Applications show `Synced` + `Healthy`
2. All pods `Running` with `0` restarts
3. No Infisical resources remain (if migrated): `kubectl get configmap,sa | grep infisical` returns empty
4. ExternalSecret shows `SecretSynced` status
5. No Infisical references in manifest files: `grep -rl infisical <dir> --include="*.yaml"` returns empty

## References

- `references/argocd-app-structure.md` — Detailed structure for manifest repo directories, Application CRD fields, and repo secret matching
- `references/envoyfilter-cors-wildcard.md` — Istio EnvoyFilter Lua-based CORS for wildcard origin matching (HTTPRoute CORS filter only supports exact match)

## HTTPRoute + Route53 DNS Management

When exposing services internally via Gateway API HTTPRoutes, DNS records in Route53 must be managed alongside the HTTPRoute. There is no external-dns running in prd cluster — DNS updates are manual.

### 1. List HTTPRoutes with internal.gift.id hostnames

```bash
kubectl get httproutes -A -o json | jq -r \
  '.items[] | select(.spec.hostnames[] | test("internal\\.gift\\.id$")) | "\(.metadata.namespace)/\(.metadata.name) -> \(.spec.hostnames | join(", "))"'
```

### 2. Compare with Route53 records

```bash
# Get hosted zone ID for internal.gift.id
aws route53 list-hosted-zones --profile default | \
  jq -r '.HostedZones[] | select(.Name | test("gift\\.id")) | "\(.Id) \(.Name)"'

# List all A/CNAME records (skip TXT, SRV, SOA, NS, CAA)
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --profile default | \
  jq -r '.ResourceRecordSets[] | select(.Type == "A" or .Type == "CNAME") | "\(.Name) \(.Type) -> \(.AliasTarget.DNSName // (.ResourceRecords[].Value))"'
```

Compare HTTPRoute hostnames against Route53 records to find:
- HTTPRoute exists but no DNS record (external-dns not running — create manually)
- DNS record exists but no HTTPRoute (stale/legacy, or non-k8s service like databases, vault)

### 3. Create HTTPRoute pointing to a service

Pattern for internal gateway (istio):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <route-name>
  namespace: <service-namespace>
spec:
  hostnames:
    - <hostname>.internal.gift.id
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: internal-gateway
      namespace: istio-system
      sectionName: https-internal
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: <service-name>
          port: <port>
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
```

Verify route accepted:
```bash
kubectl get httproute <name> -n <ns> -o json | \
  jq '.status.parents[].conditions[] | select(.type=="Accepted" or .type=="ResolvedRefs") | .type + ": " + .status'
# Should show Accepted: True, ResolvedRefs: True
```

### 4. Update Route53 DNS record

When switching from old nginx ingress ELB to istio internal gateway, update the CNAME:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --profile default \
  --change-batch '{
    "Changes": [
      {
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "<hostname>.internal.gift.id.",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [{"Value": "<old-elb-dns>"}]
        }
      },
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "<hostname>.internal.gift.id.",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [{"Value": "<new-elb-dns>"}]
        }
      }
    ]
  }'
```

Istio internal gateway ELB: `k8s-istiosys-internal-d4c853b20e-aac37acf9d38e5db.elb.ap-southeast-3.amazonaws.com`
Old nginx internal ELB: `k8s-ingressc-nginxint-e3b169e33d-b945edbfbeeb3d09.elb.ap-southeast-3.amazonaws.com`

### 5. Verify DNS + HTTP access

```bash
# Check Route53 record updated
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --profile default | \
  jq -r '.ResourceRecordSets[] | select(.Name == "<hostname>.internal.gift.id.") | "\(.Name) \(.Type) -> \(.ResourceRecords[].Value)"'

# DNS resolves to istio gateway IPs (not old nginx)
dig +short <hostname>.internal.gift.id

# HTTP returns expected content
curl -sk https://<hostname>.internal.gift.id/<path> | head -15

# If curl hits old ELB (DNS cache), flush macOS DNS cache:
dscacheutil -flushcache
# Or bypass cache with --resolve:
curl -sk --resolve <hostname>:443:<istio-gateway-ip> https://<hostname>.internal.gift.id/<path>
```

### Pitfalls

- **No external-dns in prd cluster**: external-dns namespace exists but has no running pods. DNS records must be updated manually via `aws route53 change-resource-record-sets`. Check if external-dns is running before assuming auto-creation.
- **macOS DNS cache stale after Route53 update**: `dig` shows correct CNAME but `curl` connects to old IP. Cause: Tailscale DNS resolver (100.66.255.254) or macOS mDNSResponder caches the old CNAME. Fix: `dscacheutil -flushcache` + wait for TTL (300s), or use `curl --resolve` to bypass cache.
- **Route53 CNAME change is DELETE+CREATE**: Route53 doesn't support UPSERT for CNAME-to-CNAME changes. Use DELETE old + CREATE new in same change batch. Both must be in the same `Changes` array for atomic operation.
- **50 records in Route53 have no HTTPRoute**: Expected — these are non-k8s services (databases: mongodb, RDS, clickhouse; infra: vault, kafka, loki, tempo; legacy ap-southeast-1 ELB records). Don't create HTTPRoutes for these.
- **HTTPRoute for Helm-managed services**: If the namespace is Helm-managed (e.g. trivy-system), add the HTTPRoute YAML to the manifest repo in a separate dir (e.g. `trivy-system/vulnof-httproute.yaml`) so it's tracked in git, even though the rest of the namespace is Helm-managed.

## See also

- `kubernetes-job-troubleshooting` — Diagnosing stuck/crashing pods in k8s (companion skill for pod-level issues)
- `helm-service-upgrades` — Upgrading helm charts on k8s (for helm-managed apps, not raw manifests)
- `gitlab-operations` — Using glab CLI to investigate commits that caused deployment failures

## Batch Enforcing Autosync + Prune + SelfHeal

When apps exist but have inconsistent sync policies (e.g., automated=true but prune=false, selfHeal=false), batch-patch all at once:

```bash
# List all apps that DON'T have all 3 settings enabled
kubectl get applications -n argocd -o json | \
  jq -r '.items[] | select(.spec.syncPolicy.automated.enabled != true or .spec.syncPolicy.automated.prune != true or .spec.syncPolicy.automated.selfHeal != true) | .metadata.name'

# Patch each app — use kubectl patch (strategic merge), NOT kubectl apply with partial spec
# kubectl apply with partial spec fails because it replaces the entire spec (requires all required fields)
kubectl patch application <app-name> -n argocd --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":{"enabled":true,"prune":true,"selfHeal":true}}}}'
```

Also update the YAML files in the manifest repo's `argocd/` directory to match, so git stays source of truth. Use Python yaml.safe_dump_all to batch-update all files.

## HTTPRoute vs Route53 DNS Comparison

To find DNS records missing from Route53 or HTTPRoutes missing DNS records:

```bash
# Get all HTTPRoute hostnames ending in internal.gift.id
kubectl get httproutes -A -o json | \
  jq -r '.items[] | select(.spec.hostnames[] | test("internal\\.gift\\.id$")) | "\(.metadata.namespace)/\(.metadata.name) -> \(.spec.hostnames | join(", "))"'

# Get all Route53 A/CNAME records (filter out TXT, SRV, SOA, NS, CAA)
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --profile default | \
  jq -r '.ResourceRecordSets[] | select(.Type == "A" or .Type == "CNAME") | "\(.Name) \(.Type) -> \(.AliasTarget.DNSName // (.ResourceRecords[].Value))"'

# Compare: strip trailing dots, compute set difference in both directions
```
