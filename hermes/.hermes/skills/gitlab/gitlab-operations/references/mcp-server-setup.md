# GitLab MCP Server Setup

How to add the GitLab MCP server to Hermes Agent using `glab mcp serve`.

## Prerequisites

- `glab` CLI installed (`brew install glab` on macOS)
- glab authenticated to your GitLab instance (`glab auth login`)
- For self-hosted: `glab auth login --hostname gitlab.gift.id`

## Adding the server

```bash
hermes mcp add gitlab --command glab --args mcp serve
```

This connects to the glab MCP server, discovers 204 tools, and prompts:

```
Enable all 204 tools? [Y/n/select]:
```

### Non-TTY / piped stdin

If running in a non-interactive context (piped stdin, no TTY), the prompt is
auto-cancelled and no tools are saved. Pipe `Y` to auto-accept all tools:

```bash
echo "Y" | hermes mcp add gitlab --command glab --args mcp serve
```

To select specific tools instead of all, pipe `select` and then choose — but
this requires interactive input, so in non-TTY contexts stick with `Y`.

### Verifying

```bash
hermes mcp list          # should show 'gitlab' with 204 tools
hermes mcp test gitlab   # test the connection
```

Then start a new Hermes session — MCP tools load at startup, not hot-reload.
The tools appear as `mcp__gitlab__glab_*` (204 tools).

## Config written

The command writes to `~/.hermes/config.yaml` under `mcp_servers`:

```yaml
mcp_servers:
  gitlab:
    command: "glab"
    args: ["mcp", "serve"]
```

No `env` block needed — glab uses its own config at `~/.config/glab-cli/config.yml`
for auth tokens. Hermes env filtering strips secrets from subprocess env, but
glab doesn't need env tokens if already authenticated via `glab auth login`.

## Removing

```bash
hermes mcp remove gitlab
```

## Tool subsets

204 tools is a lot of context. To select only specific tool groups:

```bash
hermes mcp configure gitlab
```

This opens an interactive picker to toggle individual tools on/off. Useful if
you only need MR + CI tools and want to reduce context overhead.

## Self-hosted instance notes

The glab MCP server inherits glab's configured instances. If glab is
authenticated to both gitlab.com and gitlab.gift.id, the MCP tools can access
both — BUT the default host is gitlab.com (see SKILL.md pitfall). Always pass
the full URL form `gitlab.gift.id/<group>/<project>` to target the self-hosted
instance via MCP tools.
