---
name: gitlab-operations
description: "Use glab CLI and GitLab MCP tools for repos, CI, MRs, issue."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [gitlab, glab, mcp, ci, merge-requests, issues, self-hosted]
---

# GitLab Operations (glab CLI + MCP tools)

Use when interacting with GitLab via the `glab` CLI or the GitLab MCP server
(`mcp__gitlab__glab_*` tools): viewing repos, listing MRs, checking CI status,
managing issues, labels, milestones, runners, releases, etc. Covers self-hosted
GitLab instances (e.g. gitlab.gift.id) — see the critical pitfall below.

## Prerequisites

- `glab` CLI installed and authenticated (`glab auth login`)
- GitLab MCP server added to Hermes (see references/mcp-server-setup.md)

## Critical: self-hosted GitLab instances

**The #1 pitfall: glab CLI and MCP tools default to gitlab.com, not your self-hosted instance.**

If the user has a self-hosted GitLab (e.g. `gitlab.gift.id`), glab's default host
is still `gitlab.com`. Commands without an explicit host will hit gitlab.com and
get 401 Unauthorized — even though `glab auth status` shows the self-hosted
instance is configured and logged in.

### How to target the self-hosted instance

**MCP tools (`mcp__gitlab__glab_*`):** Most glab subcommands accept a full Git URL
as the repository argument instead of a bare `group/project` path:

```
# WRONG — hits gitlab.com, 401
glab_repo_view(args=["infra/tada-prd-manifests"])

# RIGHT — full URL with self-hosted host
glab_repo_view(args=["gitlab.gift.id/infra/tada-prd-manifests"])
```

For `glab repo view`, the full URL form works: `gitlab.gift.id/<group>/<project>`.
Add `-F json` flag via the `flags` parameter for machine-readable output.

**`glab repo search` has NO host override and always hits gitlab.com.** Use
`glab api` via terminal instead, or `glab repo view` with the full URL if you
know the exact path.

**Terminal `glab` commands:** Some subcommands accept the full URL form:
```bash
glab repo view gitlab.gift.id/infra/tada-prd-manifests -F json
glab api --hostname gitlab.gift.id projects/1064
```

### Diagnosing auth issues

Run `glab auth status` to see all configured instances and which are authenticated.
Multiple instances can coexist (e.g. gitlab.com + gitlab.gift.id). A 401 from an
MCP tool almost always means it targeted the wrong host, not that auth is broken.

## Tool naming convention

MCP tools from the GitLab server are registered as:
```
mcp__gitlab__glab_<command>_<subcommand>
```
Hyphens in glab subcommand names become underscores. Examples:
- `glab repo view` → `mcp__gitlab__glab_repo_view`
- `glab mr list` → `mcp__gitlab__glab_mr_list`
- `glab ci status` → `mcp__gitlab__glab_ci_status`
- `glab issue create` → `mcp__gitlab__glab_issue_create`

## Common operations

### View repo info
```
glab_repo_view(args=["gitlab.gift.id/<group>/<project>"], flags={"output": "json"})
```
Returns full project JSON: ID, description, default branch, visibility, CI config,
access level, namespace, web URLs, etc.

### List merge requests
```
glab_mr_list(flags={"output": "json"})
```
Defaults to open MRs for the current project (if in a git repo). May need
project context — check glab docs for `--group`/`--project` flags.

### Check CI pipeline status
```
glab_ci_status(flags={"output": "json"})
```
Defaults to current branch. Use `glab_ci_list` for all pipelines.

### List issues
```
glab_issue_list(flags={"output": "json"})
```

### Investigate commits + diffs via glab api

When tracing a broken deployment or failed CI job back to its source commit, use `glab api` in terminal (MCP tools don't cover commit diffs). See `references/commit-investigation.md` for the full workflow:

```bash
# Get commit details by SHA (image tags are often commit SHAs)
glab api "projects/<id>/repository/commits/<sha>"

# Get the commit diff (which files changed + what)
glab api "projects/<id>/repository/commits/<sha>/diff"

# Check pipeline status + job logs
glab api "projects/<id>/pipelines/<pipeline-id>/jobs"
glab api "projects/<id>/jobs/<job-id>/trace" | tail -40
```

Common flow: pod CrashLoop with `Cannot find module X` → image tag = commit SHA → `glab api` to get diff → find the `package.json` or entrypoint change that broke it.

## Pitfalls

- **MCP tools default to gitlab.com.** Always use full URL form
  `gitlab.gift.id/<path>` for self-hosted repos, or check `glab auth status`
  when you get 401.
- **`glab repo search` cannot target a self-hosted instance** — no host flag,
  always hits gitlab.com API. Use `glab api` or `glab repo view` with full URL.
- **`hermes mcp add` prompts for tool selection interactively.** In a non-TTY
  context (piped stdin), pipe `echo "Y"` to auto-enable all tools. See
  references/mcp-server-setup.md.
- **Env filtering strips secrets from MCP subprocess.** glab uses its own config
  at `~/.config/glab-cli/config.yml` for auth tokens — no env token needed.
  But if glab itself isn't authenticated, run `glab auth login` first.
- **204 tools is a lot of context.** If tool loading is slow or context is tight,
  use `hermes mcp configure gitlab` to select only the tool subsets you need
  (e.g. just MR + CI tools) rather than keeping all 204 enabled.
- **`--per-page` is NOT a valid glab flag.** Pass pagination as a query parameter
  in the URL instead: `glab api "projects?per_page=10"` not `glab api projects --per-page=10`.
- **MCP `glab_repo_search` may return empty for self-hosted.** Even when projects
  exist on the self-hosted instance, the MCP search tool can return `[]`. Fall back
  to `glab api "projects?search=<term>"` in terminal.

## See also

- references/mcp-server-setup.md — how to add the GitLab MCP server to Hermes
- references/commit-investigation.md — tracing broken deployments back to source commits via `glab api` (commit diff, pipeline status, job logs)
- `kubernetes-gitlab-runner-ops` skill — diagnosing k8s CI job failures and
  patching gitlab-runner via helm (companion skill for runner infrastructure)
