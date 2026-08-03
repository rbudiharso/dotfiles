---
name: kubernetes-sbom-inventory
description: "Use when generating SBOM or image inventory from k8s."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [kubernetes, k8s, sbom, syft, inventory, security, compliance, ecr, images]
---

# Kubernetes Cluster SBOM & Image Inventory

Generate a Software Bill of Materials (SBOM) from all container images running in a Kubernetes cluster. Enumerate workloads, extract images, filter system/EKS add-ons, scan each image with syft, and aggregate into CSV + summary.

## When to Use

- User asks for SBOM of images running in a k8s cluster
- Need a container image inventory (what's running, where, which version)
- Security/compliance audit of cluster workloads
- Need to identify :latest tags, stale images, or unscannable images
- User wants to know all software/libraries inside running container images

## Phase 1: Enumerate Workload Images

### 1. Get all workload types across all namespaces

```bash
# Deployments, StatefulSets, DaemonSets, Jobs, CronJobs — all at once
for resource in deployments statefulsets daemonsets jobs cronjobs; do
  kubectl get "$resource" -A -o json 2>/dev/null
done
```

Or via execute_code with subprocess for structured processing. Extract from:
- **Deployment/StatefulSet/DaemonSet**: `spec.template.spec.containers[].image` + `spec.template.spec.initContainers[].image`
- **Job**: `spec.template.spec.containers[].image` + initContainers
- **CronJob**: `spec.jobTemplate.spec.template.spec.containers[].image` + initContainers

### 2. Filter system/EKS add-ons

Exclude these from SBOM — they are platform-managed, not user workloads:

**By namespace** (user requested kube-* exclusion):
- `kube-system`, `kube-node-lease`, `kube-public` — all kube-* namespaces

**By image pattern** (EKS add-on images):
- `eksbuild` in image string (AWS EKS-managed builds)
- `public.ecr.aws/eks/` prefix
- `amazon-k8s-cni` (VPC CNI)
- `amazon/aws-network-policy-agent`
- `registry.k8s.io/dns/k8s-dns-node-cache` (node-local-dns)

**By known EKS add-on workload name** (in kube-system):
- `aws-node`, `kube-proxy`, `coredns`, `ebs-csi-controller`, `ebs-csi-node`, `ebs-csi-node-windows`, `metrics-server`, `aws-load-balancer-controller`, `eks-node-monitoring-agent`, `dcgm-server`, `node-local-dns`

**IMPORTANT**: Do NOT exclude custom Tada workloads that happen to be in kube-system (e.g. `eni-blackhole-monitor`, `node-watchdog`, `castai-eviction-annotation-cleaner`, `evicted-pod-cleaner`). Only exclude by the patterns above. When user says "exclude kube-* namespaces", exclude ALL workloads in those namespaces regardless of origin.

**Borderline cases**: `cert-manager` with eksbuild images = exclude (EKS add-on). `ingress-controller` with `registry.k8s.io/ingress-nginx` = exclude if EKS-managed. When unclear, check if image has `eksbuild` tag — that's the definitive EKS add-on signal.

### 3. Parse image references

Split full image string into registry, repository, tag, digest:

```python
def parse_image(image):
    # Remove digest: image@sha256:...
    # Remove tag: find last : after last / 
    # Registry: first / part if it contains . or : or known registry name
    # Default registry: docker.io
```

## Phase 2: Scan Images with Syft

### 1. Install syft

```bash
# macOS — install to ~/bin (avoid /usr/local/bin permission issues)
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b ~/bin
export PATH="$HOME/bin:$PATH"
```

### 2. Configure ECR authentication

```bash
# Login to ECR (ap-southeast-3)
aws ecr get-login-password --region ap-southeast-3 | docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com
```

**Pitfall: credsStore interference**: If `~/.docker/config.json` has `"credsStore": "desktop"`, syft may not read auths correctly. Set it to empty string:
```bash
cat ~/.docker/config.json | jq '.credsStore = ""' > /tmp/dc && cp /tmp/dc ~/.docker/config.json
```

**Pitfall: cross-region ECR stale images**: Images may reference `876683363342.dkr.ecr.ap-southeast-1.amazonaws.com` but that endpoint returns 400/401. The correct endpoint for us-east-1 is `876683363342.dkr.ecr.us-east-1.amazonaws.com`. However, if the repo doesn't exist in us-east-1 either, the image is stale — pods run from cached image on nodes but image can't be pulled/scanned externally. Mark as unscannable and skip.

### 3. Verify syft works

```bash
# Test on a small public image
syft alpine:latest -o json | jq '.artifacts | length'
# Test on ECR image
syft 876683363342.dkr.ecr.ap-southeast-3.amazonaws.com/<repo>:<tag> -o json | jq '.artifacts | length'
```

Syft pulls images directly via oci-registry protocol — no Docker daemon needed. Each image takes 10-180s depending on size.

### 4. Pre-flight verification (before launching scan)

Before running the scan script, verify all inputs in a single terminal call:

```bash
ls -la /tmp/sbom_scan.py /tmp/sbom_batch_N.json && python3 --version && which syft && mkdir -p /tmp/sbom_output && ls /tmp/sbom_output/
```

Confirm:
- Scan script exists and is readable
- Batch JSON file exists (check size — empty file = bad input)
- `syft` on PATH (`~/bin/syft` on macOS)
- Output directory exists (create with `mkdir -p`)
- Python 3 available

If any missing, fix before launching — a background process that fails immediately wastes a notification cycle.

### 5. Run batch scan as background process

**⚠️ CRITICAL — do not poll actively on long batches.** This is the #1 mistake. A 99-image batch takes 1.5-2.5+ hours (54-144s per image, avg ~85s). The `process wait` tool clamps to ~60s per call regardless of requested timeout. Active polling burns through tool-call iteration limits before the job finishes.

**Observed data (batch 3, 99 images):** Hit iteration limit at image 36/99 after 20+ successive `process wait` calls. Process was still running (would have completed ~2hr later). All 36 scanned images succeeded — results were never collected because iterations exhausted.

**Correct pattern for batches >20 images:**

1. Launch with `terminal(background=true, notify_on_complete=true)`:
   ```
   python3 /tmp/sbom_scan.py /tmp/sbom_batch_N.json /tmp/sbom_output
   ```
2. Do ONE `process poll` to confirm it started (see `[1/N]` line in output).
3. STOP. Do not call `process wait` in a loop. Rely on the `notify_on_complete` callback — it fires exactly once when the process exits.
4. When notified, read results: `process log` for full output, or `read_file` on the output JSON.
5. Report success/fail counts from the script's final summary line: `Done. N processed, M failed.`

**When active monitoring IS needed** (e.g. user asks for progress mid-run): use `process poll` sparingly — every few minutes, not every 60s. Each poll is a tool-call iteration. A 2-hour job polled every 60s = 120 iterations, will hit limits.

**For small batches (≤8 images, all known-fast):** foreground `terminal(timeout=600)` is fine. Background + notify only needed for long jobs.

**⚠️ Foreground timeout + no-resume = lost work**: The scan script (`scripts/sbom_scan.py`) writes its single output JSON ONLY after all images complete — there is no checkpointing or resume logic. If a foreground `terminal(timeout=600)` run is killed mid-batch, the output directory stays empty and ALL scan work is lost. This compounds with slow images: a batch of 16 images where 3 take 125-179s each easily exceeds 600s foreground max. When in doubt, always use background mode. The only safe foreground use is ≤8 images with no known slow images (bridge, campaign-logger, dashboard, tadakado families are consistently slow — see `references/batch-scan-empirical-data.md`).

### 6. Batch + parallel scan

For large clusters (200+ unique images), split into batches and delegate to parallel subagents:

```python
import math
batch_size = math.ceil(len(unique_images) / 3)
# Save each batch to /tmp/sbom_batch_N.json
# Delegate: python3 /tmp/sbom_scan.py /tmp/sbom_batch_N.json /tmp/sbom_output
```

**Parallel subagent pattern (delegate_task)**: Dispatch 3 leaf subagents, each running the scan script on one batch file. Each subagent runs independently with its own terminal session. Results re-enter conversation as consolidated message when ALL finish.

**IMPORTANT — subagent iteration limits**: Subagents have ~50 tool-call iterations. A 99-image batch at ~85s/image takes 1.5-2.5 hours. Subagents that actively poll (process wait/poll every 60s) will exhaust iterations at ~36-67/99 images. The scan process keeps running in the background after the subagent exits — the script writes output only at completion. After subagents report back, check if processes are still alive and wait for the output files:
```bash
# Check if scan processes still running
ps aux | grep sbom_scan.py | grep -v grep
# Wait for completion, then collect results
ls /tmp/sbom_output/sbom_results_*.json
```

**Better approach for future**: Instead of having subagents poll, have them launch with `terminal(background=true, notify_on_complete=true)` and stop after confirming start. The parent session then waits for all 3 notify callbacks. Or simply run the 3 batches as 3 background terminal processes from the parent session and use a single watcher loop.

Scan script template: see `scripts/sbom_scan.py` — runs syft per image, extracts packages (name, version, type, purl, language, licenses, cpes), outputs JSON per batch.

**Timeout**: Set 180s per image in the scan script. Some large images (keycloak, temporal) may take longer.

**Failed images**: Track separately. Common failures: stale ECR refs, ghcr.io `:latest` tag doesn't exist (use specific version), rate-limited registries, third-party registry auth issues (e.g. `docker.getoutline.com` — may need separate login or may not support anonymous OCI pulls).

## Phase 3: Aggregate + Output

### 1. Merge batch results

```python
import json, glob

all_results = []
for f in sorted(glob.glob("/tmp/sbom_output/sbom_results_*.json")):
    with open(f) as fh:
        all_results.extend(json.load(fh))

# Separate success + failed
success = [r for r in all_results if r["status"] == "success"]
failed = [r for r in all_results if r["status"] != "success"]
print(f"Success: {len(success)}, Failed: {len(failed)}")
```

### 2. Generate CSV — image inventory

Columns: namespace, kind, workload, container, registry, repository, tag, digest, full_image

### 3. Generate CSV — per-package SBOM

For aggregated package-level SBOM across all images:
```python
package_rows = []
for r in success:
    for pkg in r["packages"]:
        package_rows.append({
            "image": r["image"],
            "namespace": ",".join(r.get("namespaces", [])),
            "workloads": ",".join(r.get("workloads", [])),
            "distro": r["distro"]["prettyName"],
            "package_name": pkg["name"],
            "package_version": pkg["version"],
            "package_type": pkg["type"],
            "package_language": pkg.get("language", ""),
            "purl": pkg.get("purl", ""),
            "licenses": ";".join(pkg.get("licenses", [])),
        })
```

### 4. Generate MD summary

Include:
- Overview table (total entries, unique images, namespaces, excluded count)
- Workload type breakdown
- Registry distribution
- Top namespaces by container count
- Images using :latest tag (security risk flag)
- Excluded items list
- All unique images listing
- Per-image package count + distro
- Failed/unscannable images list with reasons

### 5. Output files

- `sbom-<cluster>.csv` — image inventory
- `sbom-<cluster>-summary.md` — summary report
- `sbom-<cluster>-packages.csv` — aggregated package-level SBOM (all packages across all images)
- `sbom-<cluster>-unique-packages.csv` — unique packages with image count (sorted by most used)
- `sbom-<cluster>-cyclonedx.json` — CycloneDX 1.5 format SBOM (container + library components)
- `sbom-<cluster>-report.md` — full report with stats, distributions, failed scans, methodology

### 6. License format handling

Syft license field can be list of strings OR list of dicts. Handle both:

```python
def format_licenses(lics):
    if not lics:
        return ""
    parts = []
    for l in lics:
        if isinstance(l, dict):
            parts.append(l.get("license", l.get("name", str(l))))
        else:
            parts.append(str(l))
    return ";".join(parts)
```

Failing to handle dict format causes `TypeError: sequence item 0: expected str instance, dict found` during CSV generation.

### 7. CycloneDX JSON structure

Container image components + library components in one `components` array:

```python
# Container components
{"type": "container", "name": <repo>, "version": <tag>, "purl": "pkg:docker/<image>", "bom-ref": <image>,
 "properties": [image:full, image:distro, image:namespaces, image:workloads, image:package_count]}

# Library components (unique packages)
{"type": "library", "name": <pkg>, "version": <ver>, "purl": <purl>, "bom-ref": <purl>,
 "properties": [package:type, package:language]}
```

Use `uuid.uuid4()` for `serialNumber`. Metadata component type is `platform` with cluster name.

## Pitfalls

- **ACTIVE POLLING KILLS LONG BATCH SCANS — THE #1 MISTAKE**: `process wait` clamps to ~60s per call. Polling a 99-image batch (1.5-2.5hr) in a loop burns all tool-call iterations before job completes. Use `notify_on_complete=true` and stop. Do one `process poll` to confirm start, then wait for the notification. See Phase 2 §5 above. **Observed three times now**: 67/99 (batch 1), 36/99 (batch 3), 66/99 (batch 1 rerun) — all hit iteration limit mid-scan despite the skill documenting this. **LOAD THIS SKILL BEFORE RUNNING ANY SBOM BATCH >8 IMAGES.** The problem is always the same: agent launches scan, polls repeatedly, exhausts iterations, leaves scan orphaned.
- **Foreground timeout loses all work on slow batches**: Batch 1 (99 images) hit 600s foreground limit at image 16. Script has no resume — output dir empty, 16 scans wasted. Always background for >8 images. See Phase 2 §5.
- **Pre-flight check prevents silent failures**: Verify script, batch file, syft binary, and output dir exist in one `ls` call before launching background process. Failed background launches waste notification cycles.
- **eksbuild is the definitive EKS add-on signal**: Some workloads like cert-manager run from EKS add-on images (`eksbuild` tag). Exclude these. But custom workloads in non-kube namespaces with ECR images (e.g. Tada's own eni-blackhole-monitor) should be kept — only exclude by eksbuild pattern or kube-* namespace, not by ECR account.
- **Stale cross-region ECR images**: `ap-southeast-1` ECR endpoint may not exist for the account. Images referenced this way are stale — pods run from node cache but can't be scanned. Skip + report.
- **credsStore: "desktop" breaks syft auth**: Syft's oci-registry provider reads `~/.docker/config.json` auths but credsStore "desktop" intercepts. Set to empty string before scanning.
- **Docker daemon not needed**: Syft pulls via oci-registry protocol directly. Don't waste time starting Docker Desktop.
- **ghcr.io :latest tags often don't exist**: Many ghcr.io images only have version tags (e.g. `v2.8.0`), not `:latest`. If syft fails with MANIFEST_UNKNOWN, check actual tags.
- **Jobs accumulate**: k8s Jobs from CronJobs create many entries with same image. Deduplicate by image before scanning to avoid redundant scans.
- **User wants kube-* exclusion to be total**: When user says "exclude kube-* namespaces", exclude ALL workloads in those namespaces — including custom ones like eni-blackhole-monitor, node-watchdog, castai cleaners. Don't try to preserve custom workloads in kube-system.
- **Beta-tagged ECR images may not exist**: `dashboard:3.73.10-d38d07db-beta` returned `MANIFEST_UNKNOWN: Requested image not found`. Beta pre-release tags may be garbage-collected from ECR after promotion. Report as failed/unscannable — don't retry.
- **Some Docker Hub images fail without containerd**: `debezium/debezium-ui` failed with `containerd: containerd not available: no grpc connection or services is available`. Syft's oci-registry provider sometimes needs containerd for certain public images. Not all Docker Hub images fail this way (confluentinc succeeded) — likely image-manifest-format dependent. No fix without installing containerd; mark as failed.
- **syft timeout on large runner images**: `runners/temporal-general1:be3c5099` timed out at 180s. Runner images with 1400-1900 packages can approach the timeout. Consider raising timeout to 300s for known-large image families, or accept the failure and report it.
- **Completed full-cluster SBOM results (prd, 2026-08-01)**: 297 images attempted, 291 scanned, 6 failed. 257,571 total packages, 23,114 unique. Top types: npm (13,917), go-module (4,091), deb (1,908), java-archive (1,162), apk (1,153). Output: 151MB packages CSV, 9MB CycloneDX JSON, unique-packages CSV, MD report. 3 parallel batches of ~99 images, total scan time ~57 minutes across 3 subagents.

## References

- `references/syft-ecr-setup.md` — Detailed syft + ECR auth setup, troubleshooting 401/400 errors, cross-region stale image detection
- `references/batch-scan-empirical-data.md` — Per-image scan times, slow-image families, failure modes from real batches (batch 1: 99 images)
- `scripts/sbom_scan.py` — Batch scanning script: runs syft per image, extracts package metadata, outputs JSON results
