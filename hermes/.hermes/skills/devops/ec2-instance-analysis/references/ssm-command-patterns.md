# SSM Command Patterns for EC2 Inventory

Ready-to-use command batches for `aws ssm send-command --parameters commands=[...]`.
Send in parallel, collect with `get-command-invocation` after 5-6s sleep.

## Pattern: System Overview (Round 1)

Four parallel send-command calls:

**Call A — OS + resources:**
```
["cat /etc/os-release", "df -h", "free -h", "uptime"]
```

**Call B — Docker:**
```
["docker --version", "docker ps --format \"{{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}\"", "docker images --format \"{{.Repository}}:{{.Tag}} | {{.Size}}\""]
```

**Call C — Services + ports:**
```
["ss -tlnp", "systemctl list-units --type=service --state=running --no-pager"]
```

**Call D — Key directories:**
```
["ls -la /opt/", "ls -la /srv/", "ls -la /home/"]
```

## Pattern: Application Deep Dive (Round 2)

Based on services found in round 1:

**Service config + status:**
```
["cat /etc/<service>/<config>.yml", "systemctl status <service>.service --no-pager"]
```

**Binary versions:**
```
["which <binary>", "<binary> --version"]
```

**Database inspection (MySQL):**
```
["mysql -u <user> -p<pass> <db> -e \"SHOW TABLES;\""]
```

**Database inspection (Redis):**
```
["redis-cli info server", "redis-cli info keyspace"]
```

**Certificate status:**
```
["certbot certificates", "openssl x509 -in <cert_path> -noout -dates"]
```

## Pattern: Security Audit

```
["iptables -L -n", "cat /etc/ssh/sshd_config | grep -E \"PermitRootLogin|PasswordAuthentication|Port\"", "last -10", "who"]
```

## Pattern: Web Server Inventory

```
["nginx -v 2>&1", "apache2 -v 2>/dev/null", "cat /etc/nginx/sites-enabled/* 2>/dev/null", "ls /etc/nginx/conf.d/ 2>/dev/null"]
```

## Send + Collect Template

```bash
# Send
CMD_ID=$(aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunShellScript" \
  --parameters commands='["command1", "command2"]' \
  --region <REGION> --profile <PROFILE> --output json | jq -r '.Command.CommandId')

# Collect (after 5-6s)
aws ssm get-command-invocation \
  --command-id $CMD_ID \
  --instance-id <INSTANCE_ID> \
  --region <REGION> --profile <PROFILE> \
  --query 'StandardOutputContent' --output text
```

## Quoting Rules

- Each command is a separate string in the JSON array
- Double quotes inside commands must be escaped: `\\\"`
- Go template variables in docker format strings need escaped braces: `{{.Names}}`
- No subshells `$(...)`, process substitution `<(...)`, or heredocs in SSM commands
- If a command needs complex shell logic, write it as a single-line `bash -c '...'` — but test quoting carefully

## JSON Parameter File (for commands with special characters)

When commands contain `<`, `>`, `(`, `|`, `{`, `}`, or nested quotes, inline `--parameters commands='...'` fails with shell parsing errors (`syntax error near unexpected token`). Use a JSON parameter file instead:

```python
import json, tempfile, subprocess, os

with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump({"commands": [
        "grep -E '<address>|<port>|<protocol>' /var/ossec/etc/ossec.conf | head -10",
        "docker images --format '{{.Repository}}:{{.Tag}}'",
        "systemctl list-units --type=service --state=running --no-pager --plain | awk '{print $1}'"
    ]}, f)
    params_file = f.name

subprocess.run(
    f"aws ssm send-command --instance-ids {INSTANCE} "
    f"--document-name AWS-RunShellScript --parameters file://{params_file} "
    f"--region {REGION} --profile {PROFILE} --output json",
    shell=True, capture_output=True, text=True
)
os.unlink(params_file)
```

The JSON file is read directly by AWS CLI — no shell interpretation, no escaping needed. This is the only reliable way to run commands with `<`, `>`, `{}`, `()` via SSM from Python.
