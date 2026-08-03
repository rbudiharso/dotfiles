# Vault Credential Workflow for RDS PostgreSQL

## Overview
Store RDS DB credentials in Vault KV. Agent sources them at connection time. Password never appears in chat transcript.

## Vault Setup
- **URL:** https://vault.internal.gift.id
- **Auth:** OIDC (Google), tokens expire in 1h
- **KV mount:** `secret/` (KV v2)
- **Secret path:** `secret/rds/leadgen`
- **Fields:** host, port, database, username, password

## Store Credentials (one-time)
```bash
VAULT_ADDR=https://vault.internal.gift.id vault kv put secret/rds/leadgen \
  host="jkt-prd-infra-rds-leadgeneration.ctqfatwx6bi8.ap-southeast-3.rds.amazonaws.com" \
  port="5432" \
  database="postgres" \
  username="leadgen_dbmaster" \
  password="<password>"
```

## Connect (each session)
```bash
export VAULT_ADDR=https://vault.internal.gift.id

# Verify token
vault token lookup

# If 403, re-auth:
# vault login -address=https://vault.internal.gift.id

# Source credentials
export PGPASSWORD=$(vault kv get -field=password secret/rds/leadgen)
HOST=$(vault kv get -field=host secret/rds/leadgen)
PORT=$(vault kv get -field=port secret/rds/leadgen)
DB=$(vault kv get -field=database secret/rds/leadgen)
USER=$(vault kv get -field=username secret/rds/leadgen)

# Connect
psql "host=$HOST port=$PORT dbname=$DB user=$USER" -c "SELECT current_user, current_database();"
```

## Connect to a Different Database on Same RDS
Same host/credentials, just change dbname in psql:
```bash
psql "host=$HOST port=$PORT dbname=tada_catalog_int_production user=$USER" -c "SELECT 1;"
```

## Token Expiry
- OIDC tokens expire 1h after issue
- `vault token lookup` returns 403 when expired
- Re-auth: `vault login -address=https://vault.internal.gift.id`
- User provides new token, write to `~/.vault-token`
- Do NOT store tokens in memory — they expire; always check `vault token lookup` first

## Security Notes
- If password was exposed in chat before Vault setup, rotate it
- Update rotated password in both RDS and Vault: `vault kv patch secret/rds/leadgen password="<new>"`
- Vault `database/` engine also available — could enable dynamic creds (future enhancement)
- IAM database auth alternative: RDS Postgres supports IAM tokens, 15-min expiry, no static password

## Multiple RDS Instances
Store each as separate Vault path:
- `secret/rds/leadgen` — lead generation DB
- `secret/rds/staging-db` — staging RDS (host, port, database, username, password)
- `secret/rds/<other>` — other instances
Same workflow, different path.

## Vault MCP vs CLI
The Vault MCP server (`mcp__vault__*` tools) requires its own token in Hermes config — does NOT inherit `VAULT_TOKEN` from shell. If MCP returns "vault token not provided for session", fall back to `vault` CLI with env vars. The `database/` engine also has dynamic readonly role: `vault read database/roles/readonly` → get ephemeral creds with SELECT-only access (TTL 1h).
