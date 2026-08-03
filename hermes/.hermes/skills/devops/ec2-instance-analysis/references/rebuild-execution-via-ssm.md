# Rebuild Execution — Running Ansible on Fresh Instance

When `tofu destroy` + `tofu apply` recreates an EC2 instance, the Ansible
aws_ssm connection plugin may be broken on macOS (Python 3.14 crashes with
`expected string or bytes-like object, got 'NoneType'` on Gathering Facts
and every task). This reference covers the workaround pattern.

## Prerequisites

- `session-manager-plugin` at `~/.local/bin/`
- AWS CLI with SSM permissions
- S3 bucket accessible via presigned URL (any bucket in same account)

## Pattern: run playbook locally on instance via SSM

Instead of `ansible-playbook` from macOS → aws_ssm → instance,
run `ansible-playbook` ON the instance itself via SSM send-command.

### Step 1: Install ansible + awscli on instance

```python
# Via SSM send-command
ssm_send("apt-get update -qq && apt-get install -y -qq ansible git python3-pip awscli 2>&1 | tail -5")
```

### Step 2: Transfer repo to instance

GitLab/GitHub clone may fail (no deploy key on fresh instance). Use S3
presigned URL instead:

```python
import tarfile, io

# Create minimal tarball (exclude .git, opentofu, README — only Ansible files)
INCLUDE = ['ansible.cfg', 'group_vars', 'inventory', 'playbooks', 'roles']
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w:gz') as tar:
    for item in INCLUDE:
        tar.add(os.path.join(REPO, item), arcname=item,
                filter=lambda info: None if os.path.basename(info.name).startswith('._') else info)

# Upload to S3
subprocess.run(f"aws s3 cp {tmpf} s3://{BUCKET}/{KEY} --region ap-southeast-3", shell=True)

# Generate presigned URL (1hr expiry)
url = subprocess.run(f"aws s3 presign s3://{BUCKET}/{KEY} --expires-in 3600", shell=True, capture_output=True, text=True).stdout.strip()

# Download on instance (wget available by default on Ubuntu)
ssm_send(f"wget -q '{url}' -O /root/repo.tar.gz && cd /root && rm -rf fleet-mdm && mkdir fleet-mdm && tar xzf repo.tar.gz -C fleet-mdm && rm repo.tar.gz && echo OK")

# CLEANUP S3 after transfer
subprocess.run(f"aws s3 rm s3://{BUCKET}/{KEY}", shell=True)
```

Key: presigned URL works because wget follows HTTPS. Instance IAM role does
NOT need S3 read access — the presigned URL carries auth.

### Step 3: Create localhost inventory on instance

```bash
echo '[fleet_mdm]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3' > /root/fleet-mdm/inventory/localhost.yml
```

### Step 4: Run playbook with secrets via extra-vars

```python
cmd = f"""cd /root/fleet-mdm && \
ansible-playbook playbooks/site.yml --inventory inventory/localhost.yml \
  -e "fleet_mysql_password=SECRET mysql_fleet_password=SECRET orbit_enroll_secret=SECRET" \
  2>&1 | tail -300
"""
res = ssm_send(cmd, wait=120)  # may need 300+ for full playbook
```

### Step 5: Verify via SSM

```python
checks = [
    ("healthz localhost:8080", "curl -sk -o /dev/null -w '%{http_code}' https://localhost:8080/healthz"),
    ("fleet.service", "systemctl is-active fleet"),
    # etc.
]
```

## ansible.cfg changes for local-run pattern

```ini
# gathering=explicit (not smart — facts may fail on fresh instance)
gathering = explicit
# stdout_callback=default (yaml callback removed in ansible-core 2.13+)
stdout_callback = default
```

## SSM send-command polling pattern

SSM commands may exceed 30s wait. Use poll loop:

```python
def ssm_poll(cid, timeout=600):
    start = time.time()
    while time.time() - start < timeout:
        r = subprocess.run(f"aws ssm get-command-invocation --command-id {cid} --instance-id {INSTANCE} --region {REGION} --profile {PROFILE} --output json", shell=True, capture_output=True, text=True, timeout=30)
        res = json.loads(r.stdout)
        if res["Status"] not in ["Pending", "InProgress", "Delayed"]:
            return res
        time.sleep(15)
    return res
```

## Common rebuild failures

1. **AMI deregistered**: `tofu apply` fails with `empty result`. Fix: update
   AMI to latest Ubuntu 22.04:
   ```bash
   aws ec2 describe-images --owners 099720109477 \
     --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
     --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text --region ap-southeast-1
   ```

2. **Docker apt_key deprecated**: See rebuild-confidence-gap-closure.md.

3. **Fleet download 404**: URL format is `fleet_v{version}_linux.tar.gz` not
   `fleet.zip`. See rebuild-confidence-gap-closure.md.

4. **Orbit TUF expired**: Use `--disable-updates`. See rebuild-confidence-gap-closure.md.

5. **Fleet service crash loop (203/EXEC)**: Binary not found at
   `/usr/local/bin/fleet`. Check stat-based idempotency — binary may not have
   been installed if `fleet_download.changed` was false. Use stat check
   instead.

6. **Healthz returns empty body**: Fleet still initializing. Wait 10-15s
   after `systemctl restart fleet`. Check `journalctl -u fleet` for errors.

7. **community.docker module incompatible**: Ansible 2.10 can't load
   community.docker plugins. Use `command: docker pull` instead of
   `community.docker.docker_image`.

## Post-rebuild verification

32-point ad-hoc check covering:
- OpenTofu: fmt, validate, plan (0 diffs), state resource count
- Ansible: syntax-check, code assertions on changed paths
- Live services: all systemd units active, healthz 200 (localhost/nginx/public)
- HTTP 301 redirect, disk usage, binary presence
- No hardcoded secrets, no macOS `._` files

All 32 checks should pass for a confident rebuild.
