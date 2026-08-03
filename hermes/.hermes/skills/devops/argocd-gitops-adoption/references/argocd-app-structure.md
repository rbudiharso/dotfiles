# ArgoCD Application Structure and Repo Secret Matching

## Manifest repo directory layout

Each ArgoCD-managed app lives in a subdirectory under the namespace directory:

```
<manifest-repo>/
  <namespace>/
    <app-name>/
      application.yaml          # ArgoCD Application CRD
      deployment.yaml           # Kubernetes Deployment
      service.yaml              # Service
      httproute.yaml            # Gateway API HTTPRoute
      externalsecret.yaml       # ExternalSecret (vault-backed)
      secretstore.yaml          # SecretStore (vault connection)
      serviceaccount.yaml       # SA for vault auth
      mtls.yaml                 # Istio PeerAuthentication
    <other-app>/
      application.yaml
      ...
    waypoint/                   # Istio waypoint — NO application.yaml
      deployment.yaml
      service.yaml
```

## Application CRD anatomy

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>              # must be unique in argocd namespace
  namespace: argocd             # Applications always live in argocd ns
spec:
  destination:
    namespace: <target-ns>      # where resources are deployed
    server: https://kubernetes.default.svc  # in-cluster, not external
  project: <project>            # MUST match repo secret scope (see below)
  source:
    path: <ns>/<app-dir>        # relative path in manifest repo
    repoURL: https://gitlab.gift.id/infra/<manifest-repo>.git
    targetRevision: HEAD        # track main branch
  syncPolicy:
    automated:
      enabled: true             # auto-sync without manual trigger
    syncOptions:
    - CreateNamespace=true      # create ns if it doesn't exist
  ignoreDifferences:            # cluster-injected fields to skip
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/template/metadata/annotations/autoscaling.cast.ai~1recommendation-applied-at
```

## Repo secret matching

ArgoCD stores Git credentials as Kubernetes secrets in the `argocd` namespace, named `repo-<hash>`. Each secret is scoped to a specific ArgoCD project.

### Finding which secret to use

```bash
# List all repo secrets
kubectl --context <ctx> -n argocd get secrets | grep "^repo-"

# Check each secret's URL + project
for secret in $(kubectl --context <ctx> -n argocd get secrets -o name | grep repo); do
  url=$(kubectl --context <ctx> -n argocd get $secret -o jsonpath='{.data.url}' 2>/dev/null | base64 -d 2>/dev/null)
  project=$(kubectl --context <ctx> -n argocd get $secret -o jsonpath='{.data.project}' 2>/dev/null | base64 -d 2>/dev/null)
  echo "$secret  url=$url  project=$project"
done
```

### Matching logic

1. Find a repo secret where `url` matches your `repoURL`
2. Check that secret's `project` field
3. Use that project name in your Application spec

If multiple secrets exist for the same URL but different projects, pick the one whose project you want to use. The project determines which ArgoCD AppProject the Application belongs to, which controls RBAC and destination restrictions.

### Common error when project doesn't match

```
Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unknown desc = failed to list refs: authentication required:
HTTP Basic: Access denied.
```

This means no repo secret matches both the URL AND the project. Fix by changing the Application's `spec.project` to match a working app that uses the same repo URL.

### Checking AppProject restrictions

```bash
kubectl --context <ctx> -n argocd get appproject <project> -o yaml | grep -A5 sourceRepos
```

If `sourceRepos` is empty or `*`, any repo URL is allowed. The restriction is at the repo secret level, not the project level.

## HTTPRoute vs Ingress

When adopting namespaces that use old `networking.k8s.io/v1 Ingress` resources:

1. Check if the live cluster already has HTTPRoutes replacing the ingress:
```bash
kubectl --context <ctx> -n <ns> get httproute
```

2. If HTTPRoutes exist in the cluster but ingress exists in the manifest repo, replace the ingress manifest with the HTTPRoute manifest.

3. HTTPRoute structure:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <name>
  namespace: <ns>
spec:
  hostnames:
  - <hostname>
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: external-gateway
    namespace: istio-system
    sectionName: https-usetada-dev  # or "http" for non-TLS
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: <service-name>
      port: 80
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
```

4. For URL rewrite (old nginx `rewrite-target` annotation):
```yaml
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          replacePrefixMatch: /
          type: ReplacePrefixMatch
```
