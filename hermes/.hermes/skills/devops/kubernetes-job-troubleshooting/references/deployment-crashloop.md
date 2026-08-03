# Deployment CrashLoopBackOff Diagnosis

Session-specific detail from diagnosing a stuck prudential-api Deployment pod on stg EKS cluster (Jul 31, 2026).

## Scenario

Deployment `prudential-api` in namespace `prudential` on `jkt-stg-infra-eks-tada` — pod `prudential-api-79f8cb9f99-wvh42` in CrashLoopBackOff, 90 restarts over 7h24m.

## Symptoms

- Pod 0/1 Running, CrashLoopBackOff, 90 restarts
- Logs: `Error: Cannot find module 'tsconfig-paths/register'` → container exits immediately
- 3 other pods (older ReplicaSet) Running fine with 0-2 restarts
- Deployment status: "ReplicaSet prudential-api-79f8cb9f99 is progressing" — stuck mid-rollout

## Root Cause

Deployment rev 77 rolled out new image `prudential/api:3611110d`. Image missing `tsconfig-paths` in node_modules — runtime entrypoint `/app/dist/bin/www.js` requires `tsconfig-paths/register` which doesn't exist in the image.

Old revision 75 (image `ab2c8468`) had 3 pods running fine — service stayed up during broken rollout because the old RS kept serving.

## Diagnosis Steps

### 1. Find the pod + check status

```bash
kubectl --context jkt-stg-infra-eks-tada get pod -A | grep prudential-api
```

Found 4 pods: 1 CrashLoopBackOff (new RS), 3 Running (old RS).

### 2. Get logs

```bash
kubectl --context jkt-stg-infra-eks-tada -n prudential logs prudential-api-79f8cb9f99-wvh42 --tail=30
```

Output:
```
Error: Cannot find module 'tsconfig-paths/register'
Require stack:
- /app/dist/bin/www.js
    at Module._resolveFilename (node:internal/modules/cjs/loader:1207:15)
  code: 'MODULE_NOT_FOUND'
```

### 3. Check ReplicaSets

```bash
kubectl --context jkt-stg-infra-eks-tada -n prudential get rs -l app=prudential-api
```

Two active ReplicaSets:
- `prudential-api-79f8cb9f99` rev=77, desired=1, image=3611110d (BROKEN)
- `prudential-api-c7fcd6986` rev=75, desired=3, image=ab2c8468 (WORKING)

### 4. Check deployment revision

```bash
kubectl --context jkt-stg-infra-eks-tada -n prudential get deploy prudential-api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'
# Output: 77
```

Rev 77 = broken RS. Rev 75 = working RS.

### 5. Confirm rollout is stuck

```bash
kubectl --context jkt-stg-infra-eks-tada -n prudential rollout status deploy/prudential-api
# "Waiting for deployment prudential-api rollout to finish: 1 out of 3 new replicas have been updated..."
```

## Resolution

### Rollback to working revision

```bash
kubectl --context jkt-stg-infra-eks-tada -n prudential rollout undo deploy/prudential-api --to-revision=75
```

Output (with cosmetic warning):
```
Warning: resource deployments/prudential-api was previously managed with 'kubectl apply'.
Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation...
deployment.apps/prudential-api rolled back
```

### Verify

```bash
kubectl --context jkt-stg-infra-eks-tada -n prudential rollout status deploy/prudential-api
# "deployment prudential-api successfully rolled out"

kubectl --context jkt-stg-infra-eks-tada -n prudential get pods -l app=prudential-api
# 3 pods Running, CrashLoop pod gone
```

## Key Patterns

- **Old RS keeps service alive during broken rollout**: Kubernetes Deployment rollout creates new RS before scaling down old RS. If new pods crash, old pods keep running. Service stays available but rollout is stuck.
- **`rollout undo --to-revision=<N>`**: Fastest fix for broken image. Find the working revision from `get rs` output (the one with READY pods). No need to build a new image first.
- **`rollout status` tells you if it's stuck**: "Waiting for rollout to finish: N out of M replicas updated" that never completes = stuck rollout.
- **RS revision annotation**: `deployment.kubernetes.io/revision` on the RS tells you which rollout revision it is. Match it against the Deployment's current revision to identify old vs new.
- **Scaling broken RS to 0 doesn't always work**: Deployment controller may restore replicas if it thinks the RS is still the active revision. Always use `rollout undo` as the primary fix.
- **Image build issue vs runtime issue**: `Cannot find module` is an image build issue — the module was never installed in the image. Fix the Dockerfile/CI pipeline, not the k8s config.

## Node.js Missing Module Pattern

`tsconfig-paths/register` is commonly in `devDependencies` but required at runtime in TypeScript projects that compile to JS but still need path resolution. The image build likely ran `npm prune --production` or `npm ci --omit=dev` which stripped it.

Fix options:
1. **Revert to `module-alias/register`** (CORRECT for compiled-to-dist projects): Change `bin/www.ts` back to `import 'module-alias/register'`. This is the original resolver — `module-alias` reads `_moduleAliases` from `package.json` (already in prod image) and maps `@` → `./dist/src` correctly. No Dockerfile changes needed.
2. Move `tsconfig-paths` to `dependencies` in package.json (PARTIAL FIX — also needs Dockerfile changes): Requires adding `COPY tsconfig.json ./` to the production Dockerfile stage AND the path mappings must be adjusted to point to `dist/src/*` instead of `src/*`. Without these additional changes, `tsconfig-paths/register` loads but can't resolve `@/` imports because `tsconfig.json` isn't in the image.
3. Use a separate build step that resolves paths during compilation, not at runtime

### Why `tsconfig-paths` doesn't work for production (compiled JS)

`tsconfig-paths/register` hooks Node.js `require()` to resolve `@/*` paths using `tsconfig.json` at runtime. But:
- `tsconfig.json` maps `@/*` → `src/*` (source directory)
- Production image only has `dist/` (compiled JS), no `src/`
- `tsconfig.json` is typically NOT copied to the production Docker stage
- Even if copied, the mapping points to the wrong directory

`module-alias/register` works because:
- Reads `_moduleAliases` from `package.json` (already copied to prod image)
- Maps `@` → `./dist/src` (correct for production layout)
- Designed specifically for compiled-to-production workflows

### Actual fix applied (Jul 31, 2026)

Commit `5d64681` on `develop` branch:
- `bin/www.ts`: reverted `import 'tsconfig-paths/register'` → `import 'module-alias/register'`
- `package.json`: removed `tsconfig-paths` from dependencies (no longer needed)
- CI pipeline succeeded, deploy succeeded, 3/3 pods Running with 0 restarts

This pattern applies to any devDependency that runtime code transitively requires — `dotenv`, `ts-node`, etc.
