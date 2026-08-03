# TLS Certificate Conflicts: Gateway-Owned vs Manual

## Session: prd cluster cert-manager cleanup (2026-08-03)

### Symptom

Radar MCP reported 5 `IncorrectCertificate` warnings on prd cluster (`jkt-prd-infra-eks-tada`), all in `istio-system` namespace:

| Secret | Good Cert (Ready=True) | Bad Cert (Ready=False) |
|--------|----------------------|----------------------|
| `tls-buyfrom-io` | `buyfrom-io-tls` (17d, no owner) | `tls-buyfrom-io` (13d, Gateway-owned) |
| `tls-membersoft-io` | `membersoft-io-tls` (17d, no owner) | `tls-membersoft-io` (13d, Gateway-owned) |
| `tls-jointoday-co` | `jointoday-co-tls` (37d, no owner) | `tls-jointoday-co` (13d, Gateway-owned) |
| `wildcard-istio-gift-id-tls` | `wildcard-gift-id` (55d, no owner) | `wildcard-istio-gift-id-tls` (13d, Gateway-owned) |
| `wildcard-istio-usetada-com-tls` | `wildcard-usetada-com` (173d, no owner) | `wildcard-istio-usetada-com-tls` (13d, Gateway-owned) |

All bad certs were 13 days old — created when Gateway `external-gateway` was updated with `cert-manager.io/cluster-issuer: letsencrypt-production-dns01-cloudflare` annotation.

### Root Cause

Gateway `external-gateway` in `istio-system` has annotation:
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production-dns01-cloudflare
```

This causes cert-manager to auto-create Certificate objects for each TLS listener's hostname+secret pair. But manual Certificate resources (from manifest repo or prior kubectl apply) also write to the same Secrets. Both certs compete for the Secret — cert-manager detects the conflict and marks both as `Ready=False` with reason `IncorrectCertificate`.

Manual certs in manifest repo (`tada-prd-manifests/istio-system/external-gateway/`):
- `certificate-buyfrom-io.yaml` → cert `buyfrom-io-tls` → secret `tls-buyfrom-io`
- `certificate-membersoft-io.yaml` → cert `membersoft-io-tls` → secret `tls-membersoft-io`

Cluster-only manual certs (no manifest file, created manually at some point):
- `jointoday-co-tls` → secret `tls-jointoday-co`
- `wildcard-gift-id` → secret `wildcard-istio-gift-id-tls`
- `wildcard-usetada-com` → secret `wildcard-istio-usetada-com-tls`

### Verification Before Deletion

**User preference: always verify no other resources reference the cert/secret before deleting.**

```bash
# Check manifest repo for references to the secret name
grep -rl 'tls-buyfrom-io' /path/to/manifest --include='*.yaml' | grep -v 'gateway.yaml'

# Check what certs write to each conflicting secret
kubectl get cert -n istio-system -o json | python3 -c "
import json,sys
data=json.load(sys.stdin)
for c in data.get('items',[]):
    secret = c.get('spec',{}).get('secretName','')
    if secret in ['tls-buyfrom-io','tls-membersoft-io','tls-jointoday-co','wildcard-istio-gift-id-tls','wildcard-istio-usetada-com-tls']:
        ready=[cond.get('status') for cond in c.get('status',{}).get('conditions',[]) if cond.get('type')=='Ready']
        owner=[o.get('kind','')+'/'+o.get('name','') for o in c.get('metadata',{}).get('ownerReferences',[])]
        print(f'{c[\"metadata\"][\"name\"]} Ready={ready} owner={owner}')
"
```

HTTPRoutes reference the Gateway (not individual Certificate names), so deleting manual Certificate resources is safe — the Gateway-owned cert will continue serving TLS.

### Resolution Steps

1. **Delete manual Certificate files from manifest repo**:
   ```bash
   rm istio-system/external-gateway/certificate-buyfrom-io.yaml
   rm istio-system/external-gateway/certificate-membersoft-io.yaml
   ```

2. **Delete manual Certificate objects from cluster** (including cluster-only ones with no manifest file):
   ```bash
   kubectl delete cert buyfrom-io-tls membersoft-io-tls jointoday-co-tls wildcard-gift-id wildcard-usetada-com -n istio-system
   ```

3. **Clear stale cert-manager annotations from Secrets** — the old manual cert wrote `cert-manager.io/certificate-name: <old-cert-name>` to the Secret, which blocks the Gateway-owned cert from claiming it:
   ```bash
   for secret in tls-buyfrom-io tls-membersoft-io tls-jointoday-co wildcard-istio-gift-id-tls wildcard-istio-usetada-com-tls; do
     kubectl annotate secret $secret -n istio-system \
       cert-manager.io/certificate-name- \
       cert-manager.io/alt-names- \
       cert-manager.io/common-name- \
       cert-manager.io/ip-sans- \
       cert-manager.io/issuer-group- \
       cert-manager.io/issuer-kind- \
       cert-manager.io/issuer-name- \
       cert-manager.io/uri-sans-
   done
   ```

4. **If Secret still shows `IncorrectIssuer`** (stale issuer ref persists even after clearing annotations), delete the Secret entirely — cert-manager will re-create it fresh:
   ```bash
   kubectl delete secret tls-jointoday-co -n istio-system
   ```

5. **Wait ~30s** for cert-manager to reconcile. Gateway-owned certs should become `Ready=True`:
   ```bash
   kubectl get cert -n istio-system | grep -E 'tls-buyfrom|tls-membersoft|tls-jointoday|wildcard-istio'
   ```

6. **Commit + push manifest changes**. ArgoCD will sync the deletion of manual cert files.

### Key Insight

When a Gateway has `cert-manager.io/cluster-issuer` annotation, it owns cert lifecycle for all its TLS listeners. Don't also maintain manual Certificate resources for the same hostnames — let the Gateway own them. The annotation triggers cert-manager's Gateway integration (via `gateway.shim`), which creates Certificate objects automatically.

### Pitfall: Gateway immediately recreates deleted certs

If you delete a Gateway-owned Certificate (e.g. `tls-buyfrom-io`), the Gateway reconciler immediately re-creates it (within seconds). The fix is NOT to delete the Gateway-owned cert — it's to delete the manual cert that conflicts with it, then clear the Secret annotations so the Gateway-owned cert can claim the Secret.
