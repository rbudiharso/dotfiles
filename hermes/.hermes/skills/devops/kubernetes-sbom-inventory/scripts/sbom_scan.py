#!/usr/bin/env python3
"""Scan Docker images with syft, output SBOM JSON per batch.
Usage: python3 sbom_scan.py <batch_file.json> <output_dir>
batch_file: JSON array of {image, namespaces, workloads} objects
output_dir: directory for sbom_results_<batch_name>.json
"""
import json, subprocess, sys, os, time

os.environ["PATH"] = os.path.expanduser("~/bin") + ":" + os.environ.get("PATH", "")

batch_file = sys.argv[1]
output_dir = sys.argv[2]
os.makedirs(output_dir, exist_ok=True)

with open(batch_file) as f:
    images = json.load(f)

results = []
failed = []

for i, img_info in enumerate(images):
    image = img_info["image"]
    idx = i + 1
    total = len(images)
    print(f"[{idx}/{total}] Scanning: {image}", flush=True)

    t0 = time.time()
    try:
        proc = subprocess.run(
            ["syft", image, "-o", "json"],
            capture_output=True, text=True, timeout=180
        )
        elapsed = time.time() - t0

        if proc.returncode == 0 and proc.stdout:
            data = json.loads(proc.stdout)
            artifacts = data.get("artifacts", [])
            distro = data.get("distro", {})

            packages = []
            for a in artifacts:
                packages.append({
                    "name": a.get("name", ""),
                    "version": a.get("version", ""),
                    "type": a.get("type", ""),
                    "purl": a.get("purl", ""),
                    "language": a.get("language", ""),
                    "licenses": a.get("licenses", []),
                    "cpes": a.get("cpes", []),
                })

            results.append({
                "image": image,
                "namespaces": img_info.get("namespaces", []),
                "workloads": img_info.get("workloads", []),
                "distro": {
                    "name": distro.get("name", ""),
                    "version": distro.get("versionID", ""),
                    "prettyName": distro.get("prettyName", ""),
                },
                "package_count": len(packages),
                "packages": packages,
                "scan_time_sec": round(elapsed, 1),
                "status": "success",
            })
            print(f"  -> {len(packages)} packages, {elapsed:.1f}s", flush=True)
        else:
            err = proc.stderr[-500:] if proc.stderr else "unknown error"
            results.append({
                "image": image,
                "namespaces": img_info.get("namespaces", []),
                "workloads": img_info.get("workloads", []),
                "package_count": 0,
                "packages": [],
                "scan_time_sec": round(elapsed, 1),
                "status": "failed",
                "error": err,
            })
            failed.append(image)
            print(f"  -> FAILED: {err[:100]}", flush=True)
    except subprocess.TimeoutExpired:
        results.append({
            "image": image,
            "namespaces": img_info.get("namespaces", []),
            "workloads": img_info.get("workloads", []),
            "package_count": 0,
            "packages": [],
            "scan_time_sec": 180,
            "status": "timeout",
            "error": "syft timeout after 180s",
        })
        failed.append(image)
        print(f"  -> TIMEOUT", flush=True)
    except Exception as e:
        results.append({
            "image": image,
            "namespaces": img_info.get("namespaces", []),
            "workloads": img_info.get("workloads", []),
            "package_count": 0,
            "packages": [],
            "scan_time_sec": 0,
            "status": "error",
            "error": str(e),
        })
        failed.append(image)
        print(f"  -> ERROR: {e}", flush=True)

output_file = os.path.join(output_dir, f"sbom_results_{os.path.basename(batch_file)}")
with open(output_file, "w") as f:
    json.dump(results, f, indent=2)

print(f"\nDone. {len(results)} processed, {len(failed)} failed.", flush=True)
print(f"Results: {output_file}", flush=True)
if failed:
    print(f"Failed images:", flush=True)
    for img in failed:
        print(f"  {img}", flush=True)
