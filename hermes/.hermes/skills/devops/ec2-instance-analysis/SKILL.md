---
name: ec2-instance-analysis
description: Use when inventorying or analyzing an EC2 instance via SSM, or exporting a live EC2 instance to IaC (OpenTofu + Ansible).
tags:
  - aws
  - ec2
  - ssm
  - inventory
  - devops
---

# EC2 Instance Analysis via SSM

Analyze EC2 instances using AWS CLI `describe-instances` + SSM `send-command` to inventory installed software, determine purpose, and identify issues. No SSH required — SSM agent does the work.

## Prerequisites

- AWS CLI configured with profile + region
- Target instance must have SSM agent online (check via `describe-instance-information`)
- IAM role on instance needs `AmazonSSMManagedInstanceCore` or similar

## Workflow

### 1. Instance metadata

```bash
aws ec2 describe-instances --instance-ids <ID> --region <REGION> --profile <PROFILE> --output json | \
  jq '.Reservations[0].Instances[0] | {InstanceId, InstanceType, State: .State.Name, PrivateIpAddress, PublicIpAddress, Tags: [.Tags[] | {Key, Value}], LaunchTime, ImageId, SecurityGroups: [.SecurityGroups[] | {GroupId, GroupName}], IamInstanceProfile: .IamInstanceProfile.Arn, KeyName}'
```

### 2. SSM agent status

```bash
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=<ID>" --region <REGION> --profile <PROFILE> --output json | \
  jq '.InstanceInformationList[0] | {InstanceId, PlatformName, PlatformType, PingStatus, AgentVersion}'
```

### 3. Run inspection commands via SSM

Send multiple `send-command` calls in parallel, then batch `get-command-invocation`. Keep each command as a separate array element — avoid complex shell quoting inside JSON parameters.

**Round 1 — system overview:**
```
commands=["cat /etc/os-release"]
commands=["docker --version", "docker ps --format \"{{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}\"", "docker images --format \"{{.Repository}}:{{.Tag}} | {{.Size}}\""]
commands=["ss -tlnp", "systemctl list-units --type=service --state=running --no-pager"]
commands=["ls -la /opt/", "ls -la /srv/", "ls -la /home/", "df -h", "free -h", "uptime"]
```

**Round 2 — deep dive based on round 1 findings:**
- Service configs: `cat /etc/<service>/<config>.yml`
- Service status: `systemctl status <service>.service --no-pager`
- Installed binaries: `which <binary>`, `<binary> --version`
- Databases: `mysql -e "SHOW DATABASES;"`, `redis-cli info`
- Certificates: `certbot certificates`, `openssl x509 -in <cert> -noout -dates`

### 4. Collect results

```bash
aws ssm get-command-invocation --command-id <ID> --instance-id <INSTANCE> --region <REGION> --profile <PROFILE> --query 'StandardOutputContent' --output text
```

Poll after ~5-6 seconds. Check `Status` field — `Failed` commands have details in `StandardErrorContent`.

### 5. Synthesize summary

Produce structured output: identity, purpose, installed components, issues found, architecture diagram.

## Phase 2: Export to IaC (OpenTofu + Ansible)

After analysis, export the instance to Infrastructure as Code. Split into OpenTofu (AWS infra) + Ansible (software provisioning).

### OpenTofu structure

```
opentofu/
├── providers.tf       # provider + S3 backend
├── variables.tf       # all input vars (instance_type, vpc_id, subnet_id, etc.)
├── data_sources.tf    # current account/region + AMI lookup
├── main.tf            # EC2 instance + EIP + Route53 (if zone exists)
├── security_group.tf  # inline ingress/egress rules (preferred for import)
├── iam.tf             # IAM role + policy attachments + instance profile
├── outputs.tf         # instance_id, private_ip, public_ip, sg_id
└── *.tfvars.example   # non-secret values (secrets via CI/CD vars)
```

### Ansible structure

```
ansible.cfg            # INI format, NOT YAML (no --- prefix!)
inventory/hosts.yml    # static or dynamic inventory
group_vars/<group>.yml # non-secret vars; secrets via vault
playbooks/site.yml     # main playbook calling all roles
roles/<role>/
  ├── defaults/main.yml
  ├── tasks/main.yml
  ├── handlers/main.yml
  └── templates/*.j2   # Jinja2 templates for config files + systemd units
```

### IaC export workflow

1. **Gather AWS infra data**: `describe-instances`, `describe-vpcs`, `describe-subnets`, `describe-security-groups`, `describe-volumes`, `describe-addresses`, `list-hosted-zones`, `get-instance-profile`, `kms describe-key`.
2. **Gather software data via SSM** (Phase 1 above): package versions, config files, systemd units, service statuses.
3. **Generate OpenTofu**: Reference pre-existing VPC/subnet by ID (don't recreate). Use inline `ingress`/`egress` blocks in `aws_security_group` (not separate `aws_security_group_rule` resources — inline imports cleaner). Pin AMI ID directly if original is deregistered. EIP only if one exists on the instance.
4. **Generate Ansible roles**: One role per software component. Template all config files + systemd units as `.j2`. Store secrets as vault variables.
5. **Configure S3 backend**: Check bucket region (may differ from instance region). Enable bucket versioning. Create DynamoDB lock table if missing.
6. **Import existing resources into state** (Phase 3 below — critical for live instances).
7. **Verify**: `tofu fmt -check`, `tofu validate`, `tofu plan -detailed-exitcode` (must exit 0 = no changes), `ansible-playbook --syntax-check`, YAML lint, secret scan (`git grep` for hardcoded passwords).
8. **Commit + push**.

### S3 backend setup

```bash
# Check bucket exists + region
aws s3api get-bucket-location --bucket <BUCKET> --region <REGION> --profile <PROFILE>

# Enable versioning if not already
aws s3api put-bucket-versioning --bucket <BUCKET> --versioning-configuration Status=Enabled --region <BUCKET_REGION> --profile <PROFILE>

# Create DynamoDB lock table if missing
aws dynamodb create-table \
  --table-name <LOCK_TABLE> \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region <BUCKET_REGION> --profile <PROFILE>
```

Backend block in `providers.tf`:
```hcl
backend "s3" {
  bucket         = "<BUCKET>"
  key            = "<project>/terraform.tfstate"
  region         = "<BUCKET_REGION>"  # may differ from instance region!
  encrypt        = true
  dynamodb_table = "<LOCK_TABLE>"
}
```

## Phase 3: Import Existing Resources into State

After generating IaC files, the state is empty — `tofu plan` shows everything as "create". Must import each existing AWS resource so OpenTofu manages it. Then iterate until `tofu plan` shows zero changes.

### Step 1: Import each resource

```bash
cd opentofu

# EC2 instance
tofu import -var 'secret1=dummy' -var 'secret2=dummy' aws_instance.fleet_mdm i-04817d23790ce2940

# Security group
tofu import -var 'secret1=dummy' -var 'secret2=dummy' aws_security_group.fleet_mdm sg-0bf0c6544ed9a4089

# IAM role (by name)
tofu import -var 'secret1=dummy' -var 'secret2=dummy' aws_iam_role.fleet_mdm_instance_role AmazonSSMRoleForInstancesQuickSetup

# IAM instance profile (by name)
tofu import -var 'secret1=dummy' -var 'secret2=dummy' aws_iam_instance_profile.fleet_mdm AmazonSSMRoleForInstancesQuickSetup

# IAM policy attachments (format: <role-name>/<policy-arn>)
tofu import -var 'secret1=dummy' -var 'secret2=dummy' aws_iam_role_policy_attachment.fleet_mdm_ssm "AmazonSSMRoleForInstancesQuickSetup/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
```

Key: `-var` flags go BEFORE the resource address + ID. If vars are required but not used by infra resources, pass dummy values.

### Step 2: Plan and fix diffs

```bash
tofu plan -detailed-exitcode -var 'secret1=dummy' -var 'secret2=dummy'
```

Exit codes: 0 = no changes (goal), 2 = changes needed, 1 = error.

Common diffs after import and their fixes:

| Diff | Cause | Fix |
|------|-------|-----|
| AMI mismatch | `data "aws_ami"` picks latest, instance has older AMI | Pin AMI ID directly instead of data source. Note: original AMI may be deregistered — still valid in state, just not discoverable via `describe-images` |
| SG name mismatch | IaC uses new name, AWS has original name | Match IaC SG name to existing AWS SG name |
| IAM role tags/description | IaC omits tags, AWS has them (or vice versa) | Add `tags` + `description` to IaC to match live AWS exactly |
| metadata_options mismatch | `http_tokens`, `http_put_response_hop_limit` differ | Read actual values from `describe-instances` output, set in IaC |
| Policy attachment mismatch | IaC lists wrong policies | `aws iam list-attached-role-policies --role-name <NAME>` to get actual list, update IaC |
| `managed_policy_arns` deprecation | Old inline arg on `aws_iam_role` | Use separate `aws_iam_role_policy_attachment` resources |
| Default tags diff | IaC `default_tags` adds tags existing resources don't have | Remove `default_tags` from provider block when importing existing resources |
| SG rules as separate resources | `aws_security_group_rule` resources don't import cleanly | Use inline `ingress`/`egress` blocks in `aws_security_group` instead |
| EIP not needed | IaC creates EIP, instance uses auto-assigned public IP | Remove EIP resource, set `associate_public_ip_address = true` |
| `credit_specification` block | t2 instances have this, IaC doesn't set it | Usually auto-managed, but may need `ignore_changes` |
| `hibernation` field | Defaults differ | Usually auto-managed |

### Step 3: Iterate until exit 0

Fix each diff, re-run `tofu plan -detailed-exitcode`, repeat until:
```
No changes. Your infrastructure matches the configuration.
EXIT: 0
```

### Step 4: Verify state matches live AWS

```bash
tofu state list                    # all managed resources present
tofu state show aws_instance.X     # key attributes match live AWS
```

## Pitfalls

- **SSM filter key**: `describe-instance-information` uses `Key=InstanceIds` (plural), NOT `Key=InstanceId`. Wrong key = ValidationException.
- **Shell quoting in JSON**: Complex commands with nested quotes/parens cause `Syntax error: "(" unexpected`. The SSM agent runs commands via `/bin/sh` (not bash) and the JSON parameter parsing mangles escaping. Keep commands simple — one flat command per array element. Avoid subshells, process substitution, or deeply nested quoting.
- **Local scripts not on instance**: Passing `bash /tmp/script.sh` fails — the script is on YOUR machine, not the target. Must inline all commands.
- **AMI lookup failures**: `describe-images` may return null for AMIs from other accounts, deregistered AMIs, or marketplace images. Don't block on this — OS info is available via SSM `cat /etc/os-release`.
- **MySQL access**: Shell user often lacks MySQL credentials. Check service config files (e.g. `/etc/fleet/fleet.yml`) for DB credentials, or use `mysql -u <user> -p<pass> <db> -e "..."`.
- **Expired certs**: Always check `certbot certificates` output for `INVALID: EXPIRED` — common on long-running instances where auto-renewal broke.
- **Disk pressure**: `df -h` showing >90% is critical. Flag immediately.
- **Command timeout**: If `get-command-invocation` returns `Pending`, wait longer and re-poll. `InProgress` means still running.
- **ansible.cfg format**: Must be INI format, NOT YAML. Do NOT prefix with `---`. Ansible uses Python `configparser` which rejects YAML front matter. Error: `File contains no section headers`.
- **S3 backend region mismatch**: State bucket may be in a different region than the instance (e.g. bucket in `ap-southeast-3`, instance in `ap-southeast-1`). Always check `get-bucket-location` and use the BUCKET's region in the backend config.
- **Deprecated AWS provider args**: `managed_policy_arns` in `aws_iam_role` is deprecated. Use separate `aws_iam_role_policy_attachment` resources instead.
- **macOS ._ AppleDouble files**: macOS creates `._*` metadata files on external volumes. These contaminate YAML validation and Ansible syntax checks. Filter them out (`not f.startswith('._')`) or delete (`find . -name '._*' -delete`). Add `._*` to `.gitignore`.
- **Pre-existing VPC/subnet**: When exporting an instance in an existing VPC, reference by ID via variables — do NOT recreate the VPC/subnet in OpenTofu. Use `var.vpc_id` and `var.subnet_id`.
- **Secrets in generated code**: Config files extracted from the instance contain real passwords. Replace with `CHANGE_ME` or vault variables before committing. Run `git grep` for known secrets before push.
- **tofu import var ordering**: `-var` flags must come BEFORE the resource address and ID. `tofu import aws_instance.x i-xxx -var 'y=dummy'` fails with "Invalid number of arguments". Correct: `tofu import -var 'y=dummy' aws_instance.x i-xxx`.
- **SG inline vs separate rules for import**: `aws_security_group_rule` resources are harder to import (need SG ID + protocol + port for ID). Use inline `ingress`/`egress` blocks inside `aws_security_group` for cleaner import of existing SGs. The AWS provider handles inline rules during import automatically.
- **Deregistered AMIs in state**: Original instance AMI may be deregistered (not visible via `describe-images`). It's still valid in state — just pin the AMI ID directly in the resource instead of using `data "aws_ami"`. Add a comment with the lookup command for future rebuilds.
- **Provider default_tags on import**: Adding `default_tags` to the provider block causes diffs on every imported resource (existing resources don't have those tags). Remove `default_tags` when importing existing infrastructure. Only use it for greenfield deployments.
- **IAM policy attachments differ from expectation**: Don't assume which policies are attached. Always run `aws iam list-attached-role-policies --role-name <NAME>` and match IaC to reality. AWS Quick Setup roles often have custom policies, not just AWS-managed ones.
- **t2 credit_specification**: t2 instances have a `credit_specification` block (`cpu_credits = "standard"`) that shows as a diff after import. Usually resolves with a second plan or needs `ignore_changes`.
- **metadata_options exact values**: `http_tokens` can be `required` or `optional`, `http_put_response_hop_limit` varies (1 vs 2). Read actual values from `describe-instances` JSON, don't assume defaults.
- **mysqldump stderr contamination**: `mysqldump ... 2>&1 > dump.sql` mixes the `[Warning] Using a password on command line` message into the dump file's first line, causing `ERROR 1064` on import. Always use `2>/dev/null` to suppress stderr. Verify with `head -3 dump.sql` — first line should be `-- MySQL dump 10.13`.
- **RDS DEFINER permission on views**: RDS restricts `SUPER` privilege. Views with `DEFINER=user@localhost` fail with `ERROR 1227`. Fix: `sed 's/DEFINER=\`old\`@\`localhost\`/DEFINER=\`rds_user\`@\`%\`/'` then import the view DDL separately. Data (tables+rows) imports fine before hitting the view section at end of dump.
- **Post-migration IaC drift**: After migrating DB to RDS, update IaC (fleet defaults, group_vars, playbook conditionals) to reflect new endpoint. Verify template renders identical to live config. See `references/cross-vpc-connectivity.md` for full pattern.

## Ansible SSM Connection (no SSH key needed)

Use `amazon.aws.aws_ssm` connection plugin to run Ansible against EC2 instances without SSH keys. Requires `session-manager-plugin` binary locally.

### Inventory config

```yaml
all:
  children:
    fleet_mdm:
      hosts:
        fleet-mdm-prod:
          ansible_connection: aws_ssm
          ansible_aws_ssm_instance_id: i-04817d23790ce2940
          ansible_aws_ssm_region: ap-southeast-1
          ansible_aws_ssm_profile: default
          ansible_aws_ssm_plugin: /Users/rb/.local/bin/session-manager-plugin
          ansible_user: root
          ansible_python_interpreter: /usr/bin/python3
```

### macOS setup (without sudo)

`session-manager-plugin` installer is a .pkg that needs sudo. Extract manually:

```bash
# Download via brew (doesn't install, just caches)
brew fetch --cask session-manager-plugin

# Find the cached .pkg
ls ~/Library/Caches/Homebrew/downloads/*session-manager-plugin.pkg

# Extract (it's a cpio archive inside xar)
mkdir /tmp/ssm-extract && cd /tmp/ssm-extract
xar -xf <path-to>.pkg
tar xvf Payload  # extracts ./usr/local/sessionmanagerplugin/bin/session-manager-plugin

# Copy to user PATH
mkdir -p ~/.local/bin
cp usr/local/sessionmanagerplugin/bin/session-manager-plugin ~/.local/bin/
chmod +x ~/.local/bin/session-manager-plugin
```

### macOS fork safety (critical)

Ansible worker processes crash on macOS with:
```
objc[...]: +[NSMutableString initialize] may have been in progress in another thread when fork() was called.
ERROR! A worker was found in a dead state
```

Fix: set environment variable before running ansible:
```bash
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook ...
```

Or add to ansible.cfg `[defaults]` section: `environment = OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`

### Plugin version note

Older `amazon.aws` collection versions hardcode `/usr/local/bin/session-manager-plugin` path. Newer versions (9.1.0+) fall back to PATH. Use `ansible_aws_ssm_plugin` inventory var to override path if the binary isn't in the default location.

## SSM Command Escaping via JSON Parameter Files

When SSM commands contain special characters (`<`, `>`, `(`, `|`, `{`, `}`), inline `--parameters commands='...'` fails with shell parsing errors. Use a JSON parameter file instead:

```python
import json, tempfile, subprocess

with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump({"commands": ["grep -E '<address>|<port>' /var/ossec/etc/ossec.conf"]}, f)
    params_file = f.name

subprocess.run(
    f"aws ssm send-command --instance-ids {INSTANCE} "
    f"--document-name AWS-RunShellScript --parameters file://{params_file} "
    f"--region {REGION} --profile {PROFILE} --output json",
    shell=True, capture_output=True, text=True
)
os.unlink(params_file)
```

This avoids all shell quoting issues — the JSON file is read directly by AWS CLI, not interpreted by the shell.

## Template-vs-Live Verification Pattern

After generating Ansible templates, verify they render identically to live configs:

1. Render each `.j2` template locally with Jinja2 using real values from the instance
2. Fetch the live config via SSM `send-command`
3. Normalize whitespace (strip per-line, skip empty lines)
4. Compare byte-for-byte

```python
from jinja2 import Template

# Render template with real values extracted from instance
with open("roles/fleet/templates/fleet.yml.j2") as f:
    rendered = Template(f.read()).render(**vars_dict).strip()

# Fetch live config via SSM
live, _ = ssm_run("grep -vE '^#|^$' /etc/fleet/fleet.yml")

# Compare (normalize whitespace)
live_n = "\n".join(l.strip() for l in live.splitlines() if l.strip())
exp_n = "\n".join(l.strip() for l in rendered.splitlines() if l.strip())
assert live_n == exp_n, f"Differs:\n  live:     {repr(live_n[:200])}\n  expected: {repr(exp_n[:200])}"
```

Key: template files must NOT have comment lines (e.g. `# Fleet server configuration...`) — they cause diffs against live configs that don't have them. Remove all comments from `.j2` templates when matching live files exactly.

## Cross-VPC Connectivity & RDS Migration

When an EC2 instance needs to reach a resource in another VPC (e.g. RDS MySQL), check in order:
1. VPC peering connections (`describe-vpc-peering-connections`, status must be `active`)
2. Route tables both directions (routes must be `active`, not `blackhole`)
3. Map EC2 subnet to route table (subnet association or VPC main)
4. Security group inbound rules on target (most common failure — peering + routes OK but SG blocks EC2's IP)
5. TCP test from EC2 via SSM (`timeout 5 bash -c 'echo > /dev/tcp/<host>/<port>'`)

For RDS migration feasibility, also check: RDS instance class vs workload, storage capacity, MySQL version compatibility, existing databases sharing the RDS, and whether the application supports the target DB engine.

For migration execution (dump, import, fix DEFINER errors, update IaC), see `references/cross-vpc-connectivity.md` — the "Migration execution pitfalls" section covers mysqldump stderr contamination, RDS DEFINER permission errors on views, verification commands, and post-migration IaC updates.

See `references/cross-vpc-connectivity.md` for full diagnostic commands, RDS migration checklist, and Fleetdm database compatibility notes.

## Tips

- Send 3-4 `send-command` calls in parallel, then batch `get-command-invocation` after a sleep. Faster than serial.
- `systemctl list-units --type=service --state=running` reveals the full software stack in one command.
- `ss -tlnp` shows listening ports + process names — key for understanding what the instance does.
- Key directories to check: `/opt/`, `/srv/`, `/home/`, `/etc/<service>/` — configs reveal purpose.
- Tags (especially `Name` tag) often hint at purpose before you even connect.
- Check `LaunchTime` + `uptime` — long-running instances may have stale configs, expired certs, accumulated disk usage.
- `tofu plan` with required-but-unused sensitive vars: pass `-var 'secret=dummy'` to allow plan/import without real secrets.

## Post-migration changes

After IaC export, common follow-up work:
- **Nginx reverse proxy**: move app from direct high-port TLS to standard 80/443 via nginx. See `references/nginx-reverse-proxy-tls.md` for full workflow (Route53, Let's Encrypt, nginx config, app cutover, IaC role).
- **Database migration to RDS**: move local MySQL to managed RDS. See `references/cross-vpc-connectivity.md` for VPC peering checks, SG rules, dump/import, DEFINER fixes.
- **Post-migration cleanup**: purge old local services (e.g. MySQL) to reclaim disk — `apt-get purge -y` + `rm -rf /var/lib/mysql`.

## Rebuild confidence audit

After initial IaC export, audit for gaps that would block a clean rebuild:
- Binary/package install tasks (not just config deployment)
- System user/group creation
- Database migration tasks (e.g. `fleet prepare db`)
- TLS cert issuance (certbot standalone)
- Installer generation requiring Docker (e.g. `fleetctl package` for orbit)
- External service enrollment (orbit, wazuh agent registration)
- Playbook ordering dependencies (certbot before nginx — nginx -t needs certs)
- OpenTofu resources for cross-VPC SG rules (dynamic private IP for rebuild)
- Route53 records as managed resources (point to EIP, not instance public IP)

See `references/rebuild-confidence-gap-closure.md` for full patterns including:
- Fleet `prepare db` migration task
- Orbit install via `fleetctl package` (not apt — generates .deb with Docker)
- `aws_security_group_rule` import format (composite ID with CIDR slash)
- `aws_route53_record` import format
- Dynamic RDS SG rule using `aws_instance.private_ip`
- Wazuh full ossec.conf.j2 byte-identical template
- Playbook ordering: common → mysql → redis → docker → fleet → certbot → nginx → orbit → wazuh

## Rebuild execution

When ready to validate IaC by destroying + recreating the instance:

1. **Backup first**: EBS snapshot + AMI (`--no-reboot`)
2. **Update AMI**: original AMI may be deregistered. Find latest Ubuntu 22.04:
   ```bash
   aws ec2 describe-images --owners 099720109477 \
     --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
     --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text --region <REGION>
   ```
3. **`tofu destroy -auto-approve`** then **`tofu apply -auto-approve`**
4. **Wait for SSM agent**: poll `describe-instance-information` until `Online`
5. **Run Ansible playbook**: if aws_ssm plugin broken on macOS, run playbook
   locally on instance via SSM send-command. Transfer repo via S3 presigned URL.
6. **Verify**: all services active, healthz 200, HTTP redirect, disk usage

See `references/rebuild-execution-via-ssm.md` for the full execution pattern,
including S3 presigned URL repo transfer, localhost inventory, common rebuild
failures (deregistered AMI, Docker apt_key, Fleet download 404, Orbit TUF
expired, community.docker incompatible), and 32-point post-rebuild verification.

## References

- `references/ssm-command-patterns.md` — SSM send-command batch patterns, JSON parameter files, macOS fork-safety fix
- `references/iac-export-patterns.md` — AWS data gathering, OpenTofu import workflow, Ansible role structure, template-vs-live verification
- `references/cross-vpc-connectivity.md` — VPC peering, RDS migration, SG rules, mysqldump/import, Fleetdm DB notes
- `references/nginx-reverse-proxy-tls.md` — nginx reverse proxy setup, TLS cert via SSM, domain cutover, Ansible nginx role template
- `references/rebuild-confidence-gap-closure.md` — gap audit methodology, Fleet prepare db, Orbit fleetctl package (TUF fix, stat idempotency, Docker apt_key, binary extraction), playbook ordering, OpenTofu import formats for SG rules + Route53, dynamic RDS SG rule
- `references/rebuild-execution-via-ssm.md` — running Ansible playbook on fresh instance via SSM send-command when aws_ssm plugin broken, S3 presigned URL repo transfer, common rebuild failures, post-rebuild verification
