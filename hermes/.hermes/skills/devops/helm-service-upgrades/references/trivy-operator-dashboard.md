# Trivy Operator Dashboard (Third-Party UI)

[raoulx24/trivy-operator-dashboard](https://github.com/raoulx24/trivy-operator-dashboard) — web UI for browsing Trivy Operator reports (vulnerabilities, config audits, exposed secrets, SBOM, RBAC, infra assessment). Built with .NET 10 + Angular 21, uses Valkey (Redis fork) as distributed cache for history.

## Static Manifest Deployment

The repo provides a static all-in-one YAML at `deploy/static/trivy-operator-dashboard.yaml`. Adapt it for your cluster:

### Key modifications from upstream defaults

1. **Images → ECR pull-through cache** (ghcr.io 403 from prd nodes):
   - `ghcr.io/raoulx24/trivy-operator-dashboard:1.9.0` → `876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/github/raoulx24/trivy-operator-dashboard:1.9.0`
   - `docker.io/valkey/valkey:7.2` → `876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/docker-hub/valkey/valkey:7.2`

2. **StorageClass**: Upstream uses `managed-csi-premium` (Azure). Change to `gp3` for AWS EBS.

3. **Namespace**: Deploy into `trivy-system` (same ns as trivy-operator) instead of separate ns.

4. **OpenTelemetry env vars**: Must include ALL OTel env vars even when disabled. Missing `OPENTELEMETRY__PROMETHEUSEXPORTERPORT` causes crash — the app tries to register Prometheus scraping endpoint even when `OPENTELEMETRY__ENABLED=false`. Set to empty string:
   ```yaml
   - name: OPENTELEMETRY__ENABLED
     value: "false"
   - name: OPENTELEMETRY__OTELENDPOINT
     value: ""
   - name: OPENTELEMETRY__OTELPROTOCOL
     value: "grpc"
   - name: OPENTELEMETRY__CONSOLEENABLED
     value: "false"
   - name: OPENTELEMETRY__ASPNETCOREINSTRUMENTATIONENABLED
     value: "true"
   - name: OPENTELEMETRY__RUNTIMEINSTRUMENTATIONENABLED
     value: "true"
   - name: OPENTELEMETRY__PROMETHEUSEXPORTERPORT
     value: ""
   ```

5. **readOnlyRootFilesystem**: App needs `/tmp` writable. Add emptyDir volume:
   ```yaml
   volumes:
     - name: tmp-volume
       emptyDir:
         sizeLimit: 1024Mi
   # Mount: /tmp
   ```

6. **Deployment strategy**: Use `Recreate` (not RollingUpdate) — PVC can only attach to one pod.

7. **RBAC**: Dashboard needs ClusterRole to read Trivy CRDs across all namespaces:
   ```yaml
   rules:
     - apiGroups: [""]
       resources: ["namespaces"]
       verbs: ["get", "watch", "list"]
     - apiGroups: ["aquasecurity.github.io"]
       resources: ["*"]
       verbs: ["get", "watch", "list"]
   ```

## Exposing via Gateway API HTTPRoute

Create HTTPRoute pointing to trivy-dashboard service (port 8900) on istio internal gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: vdb
  namespace: trivy-system
spec:
  hostnames:
    - vdb.internal.gift.id
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
          name: trivy-dashboard
          port: 8900
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
```

Then create Route53 CNAME record:
- `vdb.internal.gift.id` → `k8s-istiosys-internal-d4c853b20e-aac37acf9d38e5db.elb.ap-southeast-3.amazonaws.com`

## Verification

```bash
# Pod running (2 containers: app + valkey sidecar)
kubectl get pods -n trivy-system -l app=trivy-dashboard
# Should show 2/2 Running

# HTTPRoute accepted
kubectl get httproute vdb -n trivy-system -o json | \
  jq '.status.parents[].conditions[] | select(.type=="Accepted" or .type=="ResolvedRefs") | .type + ": " + .status'
# Should show Accepted: True, ResolvedRefs: True

# HTTP 200
curl -sk --resolve vdb.internal.gift.id:443:<istio-gateway-ip> https://vdb.internal.gift.id/ -o /dev/null -w "%{http_code}"
# Should return 200, HTML with title "TrivyOperator.Dashboard"

# App logs — should show processing Trivy reports
kubectl logs -n trivy-system -l app=trivy-dashboard -c trivy-dashboard --tail=10
# Should show "Initial Resources Processed - VulnerabilityReportCr - <namespace>"
```

## Manifest repo placement

For Helm-managed namespaces (like trivy-system), add HTTPRoute + dashboard YAMLs to manifest repo in a separate directory:

```
tada-prd-manifests/
  trivy-system/
    trivy-dashboard.yaml       # Deployment + Service + RBAC + PVC
    vdb-httproute.yaml         # HTTPRoute
    vulnof-httproute.yaml      # HTTPRoute for operator metrics
```

These are NOT managed by ArgoCD Application (trivy-system is Helm-managed), but having them in git provides version tracking and re-apply capability.
