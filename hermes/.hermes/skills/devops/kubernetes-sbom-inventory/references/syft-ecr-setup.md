# Syft + ECR Authentication Setup

## Installing Syft

```bash
# macOS — install to ~/bin (avoid /usr/local/bin permission issues)
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b ~/bin
export PATH="$HOME/bin:$PATH"
syft version  # verify
```

## ECR Auth for Syft

Syft's `oci-registry` provider reads `~/.docker/config.json` for credentials. Docker daemon does NOT need to be running — syft pulls directly via registry protocol.

### Standard ECR login

```bash
# ap-southeast-3 (Tada primary ECR)
aws ecr get-login-password --region ap-southeast-3 | \
  docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com
```

### credsStore "desktop" interference

If `~/.docker/config.json` has `"credsStore": "desktop"`, syft's oci-registry provider may fail to authenticate even though auth entries exist. The credential helper intercepts and returns empty creds.

**Fix**: Set credsStore to empty string:
```bash
cat ~/.docker/config.json | jq '.credsStore = ""' > /tmp/dc && cp /tmp/dc ~/.docker/config.json
```

### Cross-region ECR stale images

**Symptom**: Image reference in k8s manifest says `876683363342.dkr.ecr.ap-southeast-1.amazonaws.com/keycloak:20.0.1` but:
- `aws ecr get-login-password --region us-east-1` token returns 401 for that endpoint
- The correct endpoint is `876683363342.dkr.ecr.us-east-1.amazonaws.com` (not ap-southeast-1)
- `aws ecr describe-repositories --region us-east-1` shows empty — repo doesn't exist
- Pods still run because nodes have the image cached locally

**Root cause**: Images were pushed to a different region long ago, registry endpoint changed, but k8s manifests were never updated. Pods continue running from node cache.

**Resolution**: Mark as unscannable, skip in SBOM. Report to user as stale image references that should be updated in manifests.

### Debugging 401/400 errors

```bash
# Check which registries are in docker config
cat ~/.docker/config.json | jq '.auths | keys'

# Test ECR token directly
TOKEN=$(aws ecr get-login-password --region ap-southeast-3)
curl -s -o /dev/null -w "%{http_code}" -u "AWS:$TOKEN" \
  "https://876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/v2/<repo>/tags/list"

# Check correct proxy endpoint
aws ecr get-authorization-token --region us-east-1 | \
  jq '.authorizationData[0].proxyEndpoint'
# Returns: "https://876683363342.dkr.ecr.us-east-1.amazonaws.com"
```

### Multiple registries

For clusters with images from multiple registries, login to each:
```bash
aws ecr get-login-password --region ap-southeast-3 | docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com
# Public registries (quay.io, ghcr.io, docker.io) usually work without auth for public images
```

### Using crane as alternative

If syft auth fails, `crane` (from go-containerregistry) can also auth and pull:
```bash
crane auth login 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com \
  -u AWS -p "$(aws ecr get-login-password --region ap-southeast-3)"
crane manifest <image>  # verify image exists
```

### ECR pull-through cache

ECR pull-through cache rules let nodes pull images from upstream registries (ghcr.io, docker.io, quay.io, registry.k8s.io, public.ecr.aws) through ECR. Images are cached on first pull. Check existing rules:
```bash
aws ecr describe-pull-through-cache-rules --region ap-southeast-3
```

Tada ECR pull-through prefixes (ap-southeast-3, account 876683363342):
- `github/` -> ghcr.io (needs SecretsManager secret for GitHub auth)
- `docker-hub/` -> registry-1.docker.io (needs secret)
- `quay/` -> quay.io
- `k8s/` -> registry.k8s.io
- `cache/` -> public.ecr.aws

For syft scanning, use pull-through cache paths if direct upstream fails:
```
876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/github/aquasecurity/trivy-db:2
```

For copying images to ECR directly (bypass cache), use `crane copy`:
```bash
crane copy ghcr.io/aquasecurity/trivy-db:2 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/aquasecurity/trivy-db:2
```

## Syft output formats

```bash
syft <image> -o json          # full JSON with all artifacts
syft <image> -o json | jq '.artifacts | length'  # package count
syft <image> -o cyclonedx-json # CycloneDX SBOM format
syft <image> -o spdx-json      # SPDX SBOM format
syft <image> -o csv            # CSV format
```

Package fields: name, version, type (apk, deb, npm, pip, etc.), purl, language, licenses, cpes.
