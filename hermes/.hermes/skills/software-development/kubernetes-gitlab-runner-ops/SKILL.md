---
name: kubernetes-gitlab-runner-ops
description: Diagnose k8s CI job failures; patch gitlab-runner via helm.
---

# Kubernetes / GitLab Runner Ops

## Trigger
CI jobs on kubernetes executor failing with "node not ready", "low on resource: memory",
OOMKilled, or evicted pods. Also use when asked to tune/patch a gitlab-runner helm deployment.

## Diagnosis flow (do this before touching config)

1. **Confirm cluster/context first.** Multiple contexts often exist (e.g. `*-stg-*` vs
   `*-prd-*`). `kubectl config current-context` and `kubectl config get-contexts` —
   don't assume the default context is the one the user means. Switch explicitly with
   `kubectl config use-context <name>`.

2. **Find the runner namespace and live/recent job pods.**
   ```
   kubectl get ns | grep -iE 'gitlab|runner|ci'
   kubectl get pods -n <runner-ns> --sort-by=.metadata.creationTimestamp
   ```
   Job pods are typically named `runner-<token>-project-<id>-concurrent-<n>-<hash>`,
   separate from the runner Deployment's own pods.

3. **Check the runner's resource config** (helm-templated configmap):
   ```
   kubectl get cm <release>-gitlab-runner -n <runner-ns> -o jsonpath='{.data.config\.template\.toml}'
   ```
   Look for `cpu_request`/`memory_request` under `[runners.kubernetes]`. **Missing
   `cpu_limit`/`memory_limit` is the most common root cause** — request-only config lets
   a job pod burst unbounded, starving the node and triggering kubelet eviction
   ("low on resource: memory") even though the job's own resource ask looked reasonable.

4. **Check the actual node the job pod landed on:**
   ```
   NODE=$(kubectl get pod <job-pod> -n <ns> -o jsonpath='{.spec.nodeName}')
   kubectl describe node $NODE | grep -A5 "Allocated resources"
   ```
   Requests near/at 100% of node capacity + no limits set = the failure mode.

5. **Check cluster-wide events for autoscaler churn** (CAST.ai, Karpenter, cluster-autoscaler):
   ```
   kubectl get events -A --sort-by='.lastTimestamp' | grep -iE 'memorypressure|evicted|nodenotready|oomkill'
   ```
   If nodes are being scheduled for deletion / going NodeNotReady every few minutes
   cluster-wide, "node not ready" for your job may be autoscaler churn, NOT your test's
   memory use — a pod landing on a node mid-teardown fails regardless of its own resource
   footprint. Don't treat this as "fixed" until this event stream calms down too.

6. **Only after 1-5**, form root cause. It is very often a *combination*: no limits set
   (allows burst) + node already near 100% allocated (no headroom) + aggressive
   autoscaler churn (bad luck timing) — not the Node.js test suite itself.

## Check the app side too: V8 heap flag vs container memory_limit

A job can OOMKill even with correctly-sized runner limits if the **application's own**
test command sets a V8 heap ceiling above the container limit. For Node.js repos, grep the
test script in `package.json`:
```
node --max-old-space-size=4096 node_modules/.bin/_mocha ...   # heap allowed to grow to 4GiB
```
If `--max-old-space-size` (MiB) exceeds the pod's `memory_limit`, V8 keeps allocating toward
its own ceiling — it does NOT read the cgroup limit when the flag is set explicitly — and RSS
(heap + native buffers + connections) crosses the container limit first → kernel OOM-kills the
container (exit 137) before V8's GC ever kicks in. Tell: memory climbs steadily with no GC dip,
then dies (watched via `kubectl top pod`). Fix: lower the heap flag to ~60-70% of the container
`memory_limit` to leave room for non-heap RSS. E.g. `memory_limit=2560Mi` → `--max-old-space-size=1536`.
This is a genuine two-sided bug: right-size BOTH the runner limit (infra) AND the heap flag (app).
Note `nyc`/coverage runs wrap the same test command and add overhead — same OOM risk, worse.

**If the coverage-wrapped run needs a different (larger) heap than the plain test run**, don't
hardcode one number that has to serve both, and don't duplicate the whole script. Parameterize
the npm script with a shell-default env var:
```json
"test:withmock": "NODE_ENV=test node --max-old-space-size=${MOCHA_MAX_OLD_SPACE_SIZE:-1536} node_modules/.bin/_mocha ..."
```
Then set the override only where needed, in that job's `variables:` block in `.gitlab-ci.yml`:
```yaml
'Coverage Check':
  variables:
    MOCHA_MAX_OLD_SPACE_SIZE: 2048
```
The plain `Unit Test` job (var unset) keeps the smaller default; `Coverage Check`/`Delta Coverage
Check` (var set) get the bigger heap nyc's instrumentation needs. Verify BOTH code paths locally
before pushing — running with the var unset and with it set to the new value — since npm scripts
are shared and a change to the default silently changes every caller.

**CRITICAL for nyc/coverage jobs: a `--max-old-space-size` CLI flag on the mocha command DOES
NOT reach the process under nyc.** `nyc` re-spawns mocha through spawn-wrap, which strips V8 CLI
flags — so `node --max-old-space-size=1536 node_modules/.bin/_mocha ...` runs with the flag under
a plain `Unit Test` job but runs on V8's *default* ~2GB heap when wrapped as `nyc -- npm run
test:withmock`. This means the `${MOCHA_MAX_OLD_SPACE_SIZE:-1536}` npm-script-arg trick above only
governs the plain test job; it silently does nothing for the coverage jobs, and any local nyc run
you do to "verify the heap size" is actually testing V8's default, not your flag. Tell: coverage
job dies with `FATAL ERROR: Reached heap limit ... JavaScript heap out of memory` regardless of
what you set the CLI arg to. **Fix: set the cap via `NODE_OPTIONS` (an env var, survives the
respawn) at the CI-job level, not as a CLI flag:**
```yaml
'Coverage Check':
  variables:
    NODE_OPTIONS: "--max-old-space-size=1536"
```
Same for `Delta Coverage Check`. Verify locally by exporting `NODE_OPTIONS` and running the nyc
command directly — that's the only way to prove the cap actually reaches the wrapped process.

**Better than raising the coverage heap at all: shrink nyc's instrumented working set to only the
MR's changed files.** The MR coverage-gate scripts (`check-mr-coverage.sh` / `-delta.sh`) typically
already filter to changed source files, so instrumenting the whole repo (~1300+ modules) is pure
waste that drives the OOM. Instead of `nyc -- npm run test:withmock`, run nyc with one
`--include=<file>` per changed file (compute via `git diff --name-only origin/<target>...HEAD`),
keeping `--all` so changed-but-untested files still report 0% and fail the gate as before. This
keeps peak RSS ~= the plain unit-test run (measured: 1.58GiB scoped vs the ~2GB+ crash from
full-repo instrumentation) — no heap bump, no bigger node, no pod-limit change needed. A wrapper
script (`deployment/script/run-mr-coverage.sh`) that builds the `--include` args from the diff and
is routed in via the `test:withmock:coverage` npm script is the clean shape. This is strictly
preferable to the infra-side fixes (bigger node, per-job KUBERNETES_MEMORY_LIMIT, runner helm
upgrade) — try it FIRST before touching cluster capacity.

**Don't assume `nyc`'s `"all": true` (instrument-every-included-file, not just executed ones) is
the main memory driver — measure before trimming it.** Tried dropping `all:true` on a repo with
~6400 files matched by `include` globs (app/lib/cli_scripts) expecting a big win: peak RSS only
dropped ~1.94GB → ~1.86GB (~80MB), not enough to matter. The real cost is coverage-map/counter
overhead for files actually *executed* by the suite, not idle instrumented files sitting unused.
Also `"all": true` is often load-bearing for a delta-coverage gate script that hard-fails when a
*changed* file has no coverage entry — removing it can silently change what "0% coverage on this
file" means for MR gating. Measure the actual RSS delta locally before touching nyc config; if it's
small, look elsewhere (heap flag, container limit) instead.

## CI-side mitigation for autoscaler node churn

Runner-config and app-side heap fixes don't stop autoscaler (CAST.ai/Karpenter) node churn
itself — that's a separate infra issue (raise with the platform team: min node count, less
aggressive consolidation). As a cheap safety net in the meantime, add a scoped retry to the
affected job in `.gitlab-ci.yml` (don't apply cluster-wide, just the job that's hitting it):
```yaml
'Unit Test':
  retry:
    max: 2
    when:
      - runner_system_failure
      - stuck_or_timeout_failure
```
`runner_system_failure` covers pod-couldn't-start / node-not-ready / DeletionByTaintManager
evictions specifically. Validate the YAML parses and the job block is well-formed before
pushing (`python3 -c "import yaml; yaml.safe_load(open('.gitlab-ci.yml'))"`).

## Verifying a fix locally: use foreground with a long timeout, not background/nohup

When a test suite run exceeds the default tool timeout, prefer `terminal(timeout=300-600,
background=false)` over `nohup ... &` or `background=true`. Users may decline background
process approval outright (it's harder to inspect/kill mid-run, and its output isn't
directly in the transcript). A single foreground call with a generous timeout gives the
full real result in one shot and is the lower-friction ask. Only reach for background if
the run genuinely exceeds ~600s.

If a command needs an ad-hoc credential (e.g. a private npm/GitHub registry token) that the
user pastes directly into chat to unblock verification, tell them plainly once the check is
done that the token is now in the session log/transcript and should be rotated — don't let
it pass silently. This applies to any credential pasted mid-conversation for one-off use,
not just this registry case.

## Fix: patch gitlab-runner via helm, not the live configmap

Editing the live ConfigMap/Deployment directly gets silently reverted on the next helm
sync/reconcile. Always go through helm values.

1. Confirm it's actually helm-managed (not ArgoCD/Flux):
   ```
   helm list -n <runner-ns>
   kubectl get cm <name> -n <runner-ns> -o jsonpath='{.metadata.labels}'   # heritage: Helm
   ```
2. Pull current values (there is usually no values file on disk — helm stores them in a
   release secret):
   ```
   helm get values <release> -n <runner-ns> -o yaml > /tmp/<release>-values.yaml
   ```
   **Note:** this dump includes `runnerRegistrationToken` — treat the file as a secret,
   scrub the token before committing to git.
3. **Before picking limit numbers, get the actual node capacity — never guess a ratio.**
   A "2x request" heuristic is NOT safe by default: if `memory_limit` approaches or exceeds
   the node's real allocatable memory, a bursting job starves kubelet/CNI/kube-proxy/daemonsets
   themselves, and the whole NODE goes NotReady mid-job (taken down, not just the container) —
   this is worse than the original unbounded-request bug, and it happened from blindly
   doubling the request without checking node size.
   ```
   # find the job pod's node/instance type (CAST.ai/Karpenter label real capacity)
   kubectl get nodes -l <node-template-selector> -o json | \
     python3 -c "import json,sys; d=json.load(sys.stdin); \
     [print(n['metadata']['labels'].get('scheduling.cast.ai/instance-memory')) for n in d['items']]"
   # or directly:
   kubectl get node <node> -o jsonpath='{.status.allocatable.memory}'
   ```
   Set `memory_limit` comfortably BELOW allocatable (leave several hundred Mi headroom for
   kubelet + daemonsets: CNI, kube-proxy, istio ztunnel, EBS CSI, autoscaler agents). E.g. on
   a node with ~3.06Gi allocatable, a safe job limit is ~2.5Gi, NOT 4Gi even if "2x request"
   math says so. Example TOML:
   ```toml
   cpu_request = "1000m"
   cpu_limit = "1800m"
   memory_request = "2048Mi"
   memory_limit = "2560Mi"
   ```
   If the job's actual memory need is close to or above the safe per-node ceiling, do NOT
   keep raising the global runner limit toward node capacity — instead: (a) scope a larger
   limit to just that job via `KUBERNETES_MEMORY_LIMIT`/`KUBERNETES_MEMORY_REQUEST` CI
   variables in that project's `.gitlab-ci.yml`, or (b) get a bigger instance type added to
   the node template. Ask the user which, this is production-affecting.

   **Before proposing a per-job `KUBERNETES_MEMORY_LIMIT` bump, check CURRENT node
   allocation, not just raw allocatable capacity** — allocatable tells you the theoretical
   ceiling, but other jobs/daemonsets may already have claimed most of it:
   ```
   kubectl describe node <node> | grep -A3 "Allocated resources"
   ```
   If `Requests` is already ~90%+ or `Limits` is already >100% (overcommitted — normal for
   burstable pods, but leaves no real headroom), adding a bigger per-job limit is unsafe even
   though it "fits" under raw allocatable — it's the same NodeNotReady risk as before, just
   arrived at from the demand side instead of the limit side. Caught this exact case on
   c7g.large already at 97% request / 135% limit — do not skip this check.
4. Upgrade, pinned to the currently-deployed chart version (get it from `helm list` output,
   different runner pools — e.g. amd64 vs arm64 — can be on different chart versions):
   ```
   helm repo add gitlab https://charts.gitlab.io   # official chart repo, safe despite "untrusted" flag
   helm repo update gitlab
   helm upgrade <release> gitlab/gitlab-runner -n <runner-ns> -f /tmp/<release>-values.yaml --version <pinned-version>
   ```
5. Before running upgrade on a prod runner, check in-flight jobs and warn the user:
   ```
   kubectl get pods -n <runner-ns> | grep -v gitlab-runner-
   ```
   Restarting the runner Deployment does NOT kill already-running job pods (they're
   separate resources spawned by the runner, not part of its own Deployment) — only new
   jobs pick up the new config. Still confirm with the user before proceeding if jobs are
   live; don't just assume "safe" without saying so.
6. Verify: `kubectl rollout status deploy/<release>-gitlab-runner -n <runner-ns>`, then
   confirm a **newly spawned** job pod actually carries the new limits:
   ```
   kubectl get pod <new-job-pod> -n <runner-ns> -o jsonpath='{.spec.containers[?(@.name=="build")].resources}'
   ```
   Rollout finishing is not proof the fix works — the proof is a fresh job pod showing
   `limits` in its resource spec. CAST.ai/similar autoscalers can make rollout slow
   (provisioning fresh nodes per replica) — this is normal, not a failure, just wait longer.

## Per-job `KUBERNETES_MEMORY_LIMIT`/`KUBERNETES_MEMORY_REQUEST` in .gitlab-ci.yml is silently ignored without a matching overwrite_max_allowed on the runner

Setting `KUBERNETES_MEMORY_LIMIT`/`KUBERNETES_MEMORY_REQUEST` (or the CPU/helper equivalents)
as job `variables:` in `.gitlab-ci.yml` does **nothing on its own**. The kubernetes executor only
honors the override if the runner's `config.toml` has the matching ceiling set:
```toml
[runners.kubernetes]
  memory_limit = "2560Mi"
  memory_request = "2048Mi"
  memory_limit_overwrite_max_allowed = "4Gi"     # job can ask for up to 4Gi limit
  memory_request_overwrite_max_allowed = "4Gi"   # job can ask for up to 4Gi request
```
Without the `*_overwrite_max_allowed` keys, GitLab Runner silently falls back to the static
`memory_limit`/`memory_request` and the job variable is a no-op — no error, no warning, just
the old limit still in effect. Before proposing a per-job memory override as "no helm change
needed", check the runner's live config first:
```
kubectl get cm <release>-gitlab-runner -n <ns> -o jsonpath='{.data.config\.template\.toml}' \
  | grep -i overwrite_max_allowed
```
If missing, the per-job variable route requires a helm upgrade anyway (to add the
`overwrite_max_allowed` line) — it's not actually helm-upgrade-free. Set the `*_overwrite_max_allowed`
value comfortably above what any job will realistically request, but still bounded (not `""`
which enables unlimited overwrite) — it's a ceiling other jobs on the runner also inherit, not
a per-job-only knob.

## When the user questions an assumption or says "stop" mid-flight, pause — don't keep building the diff

If the user asks a clarifying/skeptical question about something you just stated (e.g. "is it
not the pod memory limit?") or says "stop", treat that as a request to explain or halt, not as
something to route around while continuing to prepare the next helm/config change. Answer the
question directly first, or stop immediately, before touching more files — especially once
prod-affecting changes (helm upgrades, runner config) are in flight. Piling on more edits after
a "stop" (even edits you'd already started) reads as ignoring the instruction.

## Verify the WHOLE node-template pool has rolled over, not just the one pod's node

When checking whether a CAST.ai/Karpenter node-template resize took effect, don't just inspect
the node the current job pod landed on — list every node under that template label and confirm
they're all the new instance type before treating a memory-limit bump as safe:
```
kubectl get nodes -l scheduling.cast.ai/node-template=<template> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.node\.kubernetes\.io/instance-type}{"\t"}{.status.allocatable.memory}{"\n"}{end}'
```
A mixed fleet (some old small nodes still in rotation alongside new bigger ones) means a pod
limit sized for the new capacity can still land on an old node and repeat the NodeNotReady
failure — confirm the whole pool, not a sample of one.

## Bigger node won't help if job pods are pinned to a different node-template

When the fix is "give the job more memory via a bigger instance type", verify the job pods
can actually LAND on the bigger node before assuming a node-template resize solved anything.
The runner's kubernetes executor pins job pods with a `node_selector` in its helm values /
config.template.toml, e.g.:
```toml
[runners.kubernetes.node_selector]
  "scheduling.cast.ai/node-template" = "gitlab-runners-arm64"
  "kubernetes.io/arch" = "arm64"
```
If someone provisions a 7GB node under a *different* template (e.g. `arm64`, not
`gitlab-runners-arm64`), job pods will NOT schedule onto it — the selector hard-filters them
back onto the old (small) pool. Symptom: new node exists and is Ready, but `kubectl get pod
<job-pod> -o wide` still shows it on the old c7g.large with the old limits. Confirm the pod's
node vs. the intended pool:
```
kubectl get nodes -l scheduling.cast.ai/node-template -L node.kubernetes.io/instance-type,scheduling.cast.ai/node-template
kubectl get pod <job-pod> -n <ns> -o jsonpath='{.spec.nodeName}'   # what it actually landed on
kubectl get cm <release>-gitlab-runner -n <ns> -o jsonpath='{.data.config\.template\.toml}' | grep -A3 node_selector
```
Two ways to route job pods to the bigger capacity: (a) resize the SAME template the selector
targets (`gitlab-runners-arm64`) in the CAST.ai console, so the existing selector stays valid —
cleanest, no helm change; or (b) change the runner's `node_selector` to the new template via
`helm upgrade` — but that reroutes ALL future CI job pods cluster-wide, and if the new template
has only one node it's a concurrency/capacity risk. Option (b) is prod-affecting; get explicit
confirmation, don't default into it.

Also: the pod's own `memory_limit` comes from the runner helm config, NOT the node size — a
job on a 7GB node is still capped at whatever `memory_limit` says (e.g. 2560Mi). Raising node
size WITHOUT also raising the pod limit (helm values) or a per-job `KUBERNETES_MEMORY_LIMIT`
gives the job zero extra room. Both must move.

**CAST.ai node templates are managed in the CAST.ai SaaS console/API, not as kubectl CRDs** —
`kubectl get nodetemplates...` returns `the server doesn't have a resource type`. You can read
node labels (`scheduling.cast.ai/node-template`, instance-type, allocatable) via kubectl but
cannot inspect or edit the template's instance-type constraints from the cluster. If the fix
needs a template resize, that's a console action the user does; say so rather than trying kubectl.

## Pitfalls
- Don't patch the ConfigMap/Deployment directly on a helm-managed release — reverted on
  next sync.
- A bigger node under a different CAST.ai template does nothing if job pods are `node_selector`-
  pinned to the old template — check where the pod actually landed, not just that a big node exists.
- Don't assume default kubectl context is the right cluster — confirm explicitly.
- Don't declare victory once limits are set if autoscaler churn events are still firing;
  that's a separate, unresolved contributor.
- Different arch pools (amd64/arm64) often run different chart versions and have separate
  values/configmaps — check and patch both, don't assume config is shared.
- **Never set memory_limit by a request multiplier alone — check the node's real
  allocatable memory first.** A limit that approaches node capacity causes the whole node
  to go NotReady under load (kubelet/daemonsets starved), which is a worse failure than the
  original unbounded-request bug. Always compute limit vs. `kubectl get node -o
  jsonpath='{.status.allocatable.memory}'` (or the CAST.ai/Karpenter instance-memory label),
  not vs. the request value.
- A job OOMKilled (exit code 137, all containers killed together, `job-status=failed` with
  `error=command terminated with exit code 137`) while the **node stays Ready** is the
  CORRECT/contained outcome of a properly-sized limit — don't mistake it for a regression
  from the earlier "node crashes" bug. It means the limit is doing its job; the fix now is
  either raising memory for that specific job (see above) or reducing the job's actual
  memory footprint, not re-loosening the runner-wide limit.
- To live-monitor a specific job pod (status/memory/node health) while it runs, poll on an
  interval — pod may vanish (job finished, GitLab runner cleans it up) with no
  OOMKilled reason in `kubectl get events`; the real verdict lives in the runner manager
  pod's logs (`kubectl logs <runner-manager-pod> | grep <job-pod-name>`), which report
  `job-status=failed` with `exit_code=137` even after the pod object is already gone:
  ```
  while true; do
    kubectl get pod <pod> -n <ns> -o jsonpath='{.status.phase}'
    kubectl top pod <pod> -n <ns> --containers
    kubectl get node <node> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
    sleep 15
  done
  ```
- Two distinct OOM signatures, don't conflate them: (a) **container cgroup OOMKill** — pod
  killed by kernel, exit code 137, node stays Ready; caused by RSS crossing the pod
  `memory_limit`. (b) **V8 internal heap-limit crash** — process aborts itself with
  `FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory` plus a
  `<--- Last few GCs --->` dump, no cgroup kill involved; caused by allocation exceeding
  `--max-old-space-size` itself. The nyc-wrapped coverage job tends to hit (b) first because its
  heap flag is the binding constraint; the plain test job hits (a). Fix for (b) is raising the
  heap flag (scoped per-job, see above); fix for (a) is raising the container limit or cutting the
  app's memory footprint.
- When verifying a Node.js test-command fix locally on macOS (outside the Linux CI container),
  watch for macOS AppleDouble artifacts (`._*` resource-fork files) inside `node_modules` —
  some loaders (e.g. glob-based module scanners) `require()` them and throw
  `SyntaxError: Invalid or unexpected token`. This is a local-only noise source, not a real bug;
  `find node_modules -name '._*' -delete` clears it. Prefer letting the actual CI job verify when
  the local OS differs from the runner's image (Alpine/Linux) — it's the authoritative environment.

## Don't reach for suite-sharding to dodge an OOM without checking test isolation first

Splitting a single mocha suite into shards/parallel jobs (each its own pod/process) is a
tempting way to bound per-process memory under nyc — but it silently breaks if the suite has
**load-order-dependent shared mock state**. Many legacy suites accumulate module-level
`sinon.stub()`/singleton mocks that one testmock file sets up and a later file (in the same
process) implicitly depends on, because in a full single-process run they always execute in the
same relative glob order. Split the file list across processes and that ordering contract breaks:
you get spurious `before each` hook failures, `404 / expected X got Y` mismatches, and timeouts
that DO NOT occur in the full run.

Signs you've hit this (observed): round-robin split → N failures; contiguous-range split → similar
N failures but a *different* set; pass totals across shards sum to LESS than the full run by exactly
the number of new failures. Both partition strategies fail because the coupling is real cross-file
state, not a partitioning bug. Contiguous ranges are strictly better than round-robin (they preserve
each file's neighbors, only cutting at shard boundaries) but still don't guarantee correctness.

Before committing any shard split: run each shard and confirm `sum(passing) == full-run passing`
and zero new failures. If it doesn't hold, sharding is NOT a safe drop-in — making it safe requires
finding and fixing the specific shared-state leaks (module-level stubs not restored in
`afterEach`/`after`), which is open-ended work across the whole suite. Don't ship a split that
turns green tests red; fall back to a memory fix (scoped per-job limit within node headroom, or a
- A `.sort()` on the glob list has the same hazard — it reorders
loading and can break the same coupling; keep glob's natural order.

## Inspecting a colleague's/another branch's fix: use `git worktree`, not checkout-into-current-branch

When asked to review a different branch (e.g. someone else pushed a competing fix for the same
bug), do NOT `git checkout <other-branch> -- .` into your current working branch — this stages
that branch's entire file tree (including unrelated files) as changes on your current branch, and
a plain `git checkout HEAD -- .` afterward only restores *tracked* files, leaving newly-added
untracked files behind (`git status` still shows `A` entries). Recovering requires `git reset --hard
HEAD && git clean -fd`, which is a real destructive step to need mid-review. Instead, use an
isolated worktree so the other branch is checked out to a separate directory entirely:
```
git worktree add /tmp/<name> origin/<other-branch>   # separate checkout, current branch untouched
ln -s $(pwd)/node_modules /tmp/<name>/node_modules   # reuse deps instead of a fresh install
cd /tmp/<name> && npm run <verify-command>
# when done:
cd - && rm /tmp/<name>/node_modules && git worktree remove /tmp/<name> --force
```
This lets you actually run and verify the other branch's fix (don't just read the diff and trust
it — execute it) with zero risk of contaminating your own branch's working tree.
