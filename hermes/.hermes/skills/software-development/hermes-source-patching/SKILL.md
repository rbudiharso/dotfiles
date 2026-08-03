---
name: hermes-source-patching
description: "Patch bugs in local Hermes source; verify without pytest."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, patching, source, debugging, asyncio, verification]
    related_skills: [hermes-agent, systematic-debugging]
---

# Hermes Source Patching

Patch bugs in the local Hermes Agent source tree when the user reports an error, traceback, or unexpected behavior from Hermes itself.

## When to Use

- User shows a Hermes traceback (stderr on quit, crash log, error in logs)
- User asks to fix a bug in Hermes internals
- User wants to modify Hermes behavior by patching source directly
- Source tree exists at `~/.hermes/hermes-agent/` (or `$HERMES_HOME/hermes-agent/`)

## Source Tree

```
~/.hermes/hermes-agent/           Source root (git checkout or release install)
  tools/mcp_tool.py               MCP server task management (asyncio)
  tools/                          All built-in tools
  hermes_cli/                     CLI entry point and commands
  venv/                           Release venv (NO pytest — see Verification)
  scripts/run_tests.sh            Canonical test runner (needs dev extras)
```

## Verification Without pytest

Release venv at `~/.hermes/hermes-agent/venv/` has NO pytest installed. The `scripts/run_tests.sh` runner probes `.venv`, `venv`, `~/.hermes/hermes-agent/venv` in order and skips any without pytest — all three may be skipped in a release install.

When pytest unavailable, verify patches with this escalation:

1. **Syntax check** — `ast.parse` catches indentation, syntax, encoding errors:
   ```bash
   cd ~/.hermes/hermes-agent && ./venv/bin/python -c 'import ast; ast.parse(open("tools/mcp_tool.py").read()); print("syntax OK")'
   ```

2. **Import check** — confirms module loads, dependencies resolve, no NameError:
   ```bash
   cd ~/.hermes/hermes-agent && ./venv/bin/python -c 'from tools.mcp_tool import MCPServerTask; print("import OK")'
   ```

3. **Full test suite** — only if a venv WITH pytest exists:
   ```bash
   cd ~/.hermes/hermes-agent && ./venv/bin/python -m pytest tests/tools/test_mcp_tool.py -x -q
   ```
   If `No module named pytest`, fall back to steps 1-2.

## Patching Workflow

1. **Read the traceback** — note file path, line number, function name
2. `read_file` the source at the indicated line ±20 lines for context
3. `search_files` for the error pattern — same bug may appear in multiple locations
4. Diagnose root cause (follow `systematic-debugging` skill methodology)
5. `patch` the fix — if same pattern appears in multiple places, patch all
6. Verify: syntax check → import check → (pytest if available)
7. Tell user the fix takes effect on next Hermes restart

## Common Patterns

### asyncio Shutdown Race: "Event loop is closed"

**Symptom:** `RuntimeError: Event loop is closed` traceback on Hermes quit, from `MCPServerTask.run` coroutines. Multiple identical tracebacks, one per MCP server.

**Root cause:** Event loop closes before MCP server task coroutines finish cleanup. In `finally` blocks, `t.cancel()` internally calls `call_soon` on the loop, which is already closed.

**Harmless:** Cosmetic stderr noise. No data loss. Session saves correctly. Just ugly on exit.

**Fix pattern:** Move `t.cancel()` inside the existing `try/except` block so `RuntimeError` from the closed loop is caught:

```python
# BEFORE (broken):
finally:
    for t in (shutdown_task, reconnect_task):
        if not t.done():
            t.cancel()          # <- raises if loop closed
            try:
                await t
            except (asyncio.CancelledError, Exception):
                pass

# AFTER (fixed):
finally:
    for t in (shutdown_task, reconnect_task):
        if not t.done():
            try:
                t.cancel()      # <- now caught by except
                await t
            except (asyncio.CancelledError, Exception):
                pass
```

**Key insight:** `t.cancel()` can raise `RuntimeError` on a closed loop. Always wrap it in the same try/except that handles the await. This is a general asyncio cleanup pattern, not Hermes-specific.

## Pitfalls

- **Duplicate code blocks** — `mcp_tool.py` has near-identical cleanup blocks in `_wait_for_reconnect_or_shutdown` and `_run_keepalive`. `patch` will fail with "Found N matches" — add surrounding context to disambiguate or use `replace_all=true`.
- **Release venv vs dev venv** — release venv has no pytest, no dev extras. Don't waste time probing for it; use `ast.parse` + import verification.
- **Protected skills** — `hermes-agent` and `systematic-debugging` are bundled/protected. Cannot patch them to document source-level fixes. Use this skill instead.
- **Restart required** — source patches take effect on next Hermes process start, not mid-session.
