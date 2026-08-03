# GitLab Commit Investigation via glab api

Trace a broken deployment, failed CI job, or production issue back to its source commit using the GitLab API via `glab api`. Useful when you have an image tag (commit SHA), pipeline ID, or branch name and need to find what changed and why it broke.

## Finding a repo by name

`glab repo search` hits gitlab.com only — for self-hosted instances, use the API:

```bash
# Search projects on self-hosted instance (MCP tool works too)
glab api "projects?search=prudential&per_page=10" | python3 -c "
import json,sys
for p in json.load(sys.stdin):
    print(f\"{p['id']}  {p['path_with_namespace']}  default={p['default_branch']}  last={p['last_activity_at'][:10]}\")
"
```

Or via MCP tool:
```
mcp__gitlab__glab_repo_search(flags={"search": "prudential", "output": "json"})
```

Returns project ID, path, default branch, last activity. Note: MCP `glab_repo_search` may return empty for self-hosted even with results — fall back to `glab api` in terminal.

## Getting commit details by SHA

Image tags in k8s deployments are often commit SHAs (e.g. `prudential/api:3611110d`). Look them up directly:

```bash
glab api "projects/<project-id>/repository/commits/<sha>"
```

Key fields:
- `title`, `message`, `author_name`, `created_at` / `committed_date`
- `stats.additions`, `stats.deletions` — size of change
- `last_pipeline.id`, `last_pipeline.status` — CI status (success/failed/running)
- `last_pipeline.ref` — branch the commit was on
- `parent_ids` — for understanding merge history

## Getting the commit diff

```bash
glab api "projects/<project-id>/repository/commits/<sha>/diff" | python3 -c "
import json,sys
for f in json.load(sys.stdin):
    new = 'NEW' if f.get('new_file') else ('DEL' if f.get('deleted_file') else 'MOD')
    adds = f['diff'].count('\n+')
    dels = f['diff'].count('\n-')
    print(f\"{f['new_path']}  ({new})  +{adds} -{dels}\")
"
```

Then drill into specific files:
```bash
glab api "projects/<project-id>/repository/commits/<sha>/diff" | python3 -c "
import json,sys
for f in json.load(sys.stdin):
    if f['new_path'] in ('package.json', 'bin/www.ts'):
        print(f'=== {f[\"new_path\"]} ===')
        print(f['diff'][:2000])
"
```

## Checking CI pipeline status + job logs

```bash
# List jobs in a pipeline
glab api "projects/<project-id>/pipelines/<pipeline-id>/jobs" | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    print(f'{j[\"name\"]:30} {j[\"status\"]:10} {j[\"stage\"]:15} {j[\"created_at\"][:19]}')
"

# Get a specific job's log (trace)
JOB_ID=$(glab api "projects/<project-id>/pipelines/<pipeline-id>/jobs" | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if j['name'] == 'build-staging-jkt-stg':
        print(j['id'])
")
glab api "projects/<project-id>/jobs/$JOB_ID/trace" | tail -40
```

Job trace shows the actual build output — npm install logs, build errors, timeouts. Useful for determining if the image was actually built successfully or if a failed pipeline still resulted in a deployment (manual push, etc).

## Common investigation flow

1. Pod CrashLoopBackOff with `Cannot find module 'X'` → image tag is commit SHA
2. `glab api projects/<id>/repository/commits/<sha>` → get commit title, author, pipeline status
3. `glab api projects/<id>/repository/commits/<sha>/diff` → see what files changed
4. Focus on: `package.json` (dependency changes), entrypoint files (`bin/www.ts`, `src/index.ts`), `Dockerfile`
5. Check if changed dependency is in `devDependencies` vs `dependencies` — multi-stage Docker builds with `npm install --production` strip devDeps
6. `glab api projects/<id>/pipelines/<pipeline-id>/jobs` → check if CI pipeline passed
7. If pipeline failed but image deployed → image was pushed manually or from a different pipeline run

## Pitfalls

- `glab api "projects/<id>/repository/commits?per_page=5"` — `--per-page` is NOT a valid glab flag. Pass as query param in the URL: `?per_page=5`
- `glab api` output may have `ERROR` prefix or extra whitespace — pipe through `python3 -c "import json,sys; ..."` for clean parsing
- MCP `glab_repo_search` may return empty for self-hosted instances even when projects exist. Fall back to `glab api "projects?search=<term>"` in terminal.
- Commit SHA in image tag is usually the short SHA (8 chars), but API accepts both short and full SHAs.
- Pipeline status `failed` doesn't always mean the image wasn't deployed — check ECR/registry for the image tag directly, or check k8s deployment history.
