# IaC Export Patterns — EC2 to OpenTofu + Ansible

## AWS data gathering commands

Parallel batch — run all at once, no dependencies between them:

```bash
# Instance details
aws ec2 describe-instances --instance-ids <ID> --region <R> --profile <P> --output json

# VPC + subnet
VPC_ID=$(aws ec2 describe-instances --instance-ids <ID> --region <R> --profile <P> --query 'Reservations[0].Instances[0].VpcId' --output text)
aws ec2 describe-vpcs --vpc-ids $VPC_ID --region <R> --profile <P> --output json
aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region <R> --profile <P> --output json

# Security group rules
SG_ID=$(aws ec2 describe-instances ... --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
aws ec2 describe-security-groups --group-ids $SG_ID --region <R> --profile <P> --output json

# EBS volume
VOL_ID=$(aws ec2 describe-instances ... --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)
aws ec2 describe-volumes --volume-ids $VOL_ID --region <R> --profile <P> --output json

# EIP, Route53, IAM, KMS
aws ec2 describe-addresses --region <R> --profile <P> --output json
aws route53 list-hosted-zones --profile <P> --output json
aws iam get-instance-profile --instance-profile-name <NAME> --profile <P> --output json
aws kms describe-key --key-id <KMS_ID> --region <R> --profile <P> --output json
```

## OpenTofu: reference pre-existing VPC/subnet

```hcl
# variables.tf — reference by ID, do NOT create
variable "vpc_id"    { type = string; default = "vpc-xxxxx" }
variable "subnet_id" { type = string; default = "subnet-xxxxx" }

# main.tf
resource "aws_instance" "app" {
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.app.id]
  # ...
}
```

## OpenTofu: IAM role with policy attachments (non-deprecated)

```hcl
resource "aws_iam_role" "app" {
  name = "AppRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"; Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "AppInstanceProfile"
  role = aws_iam_role.app.name
}
```

## OpenTofu: security group with inline rules (preferred for import)

Use inline `ingress`/`egress` blocks — imports cleanly, no separate rule resources to manage.

```hcl
resource "aws_security_group" "app" {
  name        = "existing-sg-name"  # match live AWS name for import
  description = "existing description"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Note: `aws_security_group_rule` (separate resource) is fine for greenfield but harder to import — needs composite ID of SG + protocol + port. Prefer inline blocks when importing existing SGs.

## Ansible: role structure for a service

```
roles/fleet/
├── defaults/main.yml    # version, paths, default config values
├── tasks/main.yml       # download binary, deploy config, enable service
├── handlers/main.yml    # restart service on config change
└── templates/
    ├── fleet.yml.j2        # config file template
    └── fleet.service.j2    # systemd unit template
```

Key pattern: extract config values from live instance via SSM, template them as Jinja2 variables. Replace all passwords with `{{ vault_password | default('CHANGE_ME') }}`.

## S3 backend region check

State bucket region may differ from instance region:

```bash
# Bucket in ap-southeast-3, instance in ap-southeast-1
aws s3api get-bucket-location --bucket <BUCKET> --region <ANY> --profile <P>
# Returns: {"LocationConstraint": "ap-southeast-3"}

# Use BUCKET region in backend config, not instance region
```

## State import workflow (critical for live instances)

After generating IaC, state is empty. Must import each resource, then iterate to zero diffs.

### Import commands

```bash
cd opentofu
VARS="-var 'secret1=dummy' -var 'secret2=dummy'"  # required vars not used by infra

# EC2 instance (by instance ID)
tofu import $VARS aws_instance.app i-04817d23790ce2940

# Security group (by SG ID)
tofu import $VARS aws_security_group.app sg-0bf0c6544ed9a4089

# IAM role (by name)
tofu import $VARS aws_iam_role.app_role MyExistingRoleName

# IAM instance profile (by name)
tofu import $VARS aws_iam_instance_profile.app MyExistingProfileName

# IAM policy attachment (format: <role-name>/<policy-arn>)
tofu import $VARS aws_iam_role_policy_attachment.app_ssm "MyRole/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
```

Key: `-var` flags go BEFORE the resource address + ID.

### Post-import plan iteration

```bash
tofu plan -detailed-exitcode $VARS
# exit 0 = no changes (goal)
# exit 2 = changes needed — fix IaC, re-plan
# exit 1 = error
```

Common fixes:
- Pin AMI ID directly (not `data "aws_ami"`) — original may be deregistered
- Match SG name + description to live AWS
- Match IAM role name + tags + description to live AWS
- Match `metadata_options` values (tokens=required, hop_limit=2, etc.)
- Remove `default_tags` from provider (existing resources don't have them)
- Use `associate_public_ip_address = true` instead of EIP if no EIP exists
- Run `aws iam list-attached-role-policies` to get actual policy list

## EIP allocation + import (post-export)

When instance uses auto-assigned public IP, allocate EIP for stable DNS:

```bash
# Allocate EIP
aws ec2 allocate-address --domain vpc --region <R> --profile <P> --output json
# Returns: {PublicIp, AllocationId}

# Associate to instance
aws ec2 associate-address --instance-id <ID> --allocation-id <ALLOC_ID> --region <R> --profile <P>

# Update Route53 A record to new EIP (same UPSERT pattern as nginx-reverse-proxy-tls.md)

# Verify
dig +short <domain>  # should resolve to EIP
```

OpenTofu resources + import:
```hcl
resource "aws_eip" "app" {
  domain = "vpc"
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
```

```bash
# Import existing EIP + association into state
tofu import $VARS aws_eip.app eipalloc-xxxxxxxx
tofu import $VARS aws_eip_association.app eipassoc-xxxxxxxx
```

Key: keep `associate_public_ip_address = true` in instance resource even with EIP — setting to `false` forces instance replacement. EIP association handles the public IP mapping.

## Verification checklist

1. `tofu fmt -check` — formatting
2. `tofu validate` — config valid
3. `tofu plan -detailed-exitcode` — must exit 0 (no changes = IaC matches live AWS)
4. `tofu state list` — all managed resources present
5. `ansible-playbook --syntax-check` — playbook syntax
6. YAML lint all `.yml` files (skip `._*` on macOS)
7. `git grep` for known secrets from instance configs
8. Check `._*` files not present (`find . -name '._*' | wc -l` == 0)
9. Check `.gitignore` covers: `*.tfvars`, `terraform.tfstate`, `.terraform/`, vault files

## Ansible template-vs-live verification

After generating Ansible Jinja2 templates, verify they render identically to live instance configs. This catches whitespace, comment line, and tab-vs-space mismatches that syntax-check alone misses.

```python
from jinja2 import Template
import subprocess, json, tempfile, os, time

def ssm_run(instance, cmd, region, profile):
    """Run command via SSM using JSON parameter file (handles special chars)."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump({"commands": [cmd]}, f)
        pf = f.name
    r = subprocess.run(
        f"aws ssm send-command --instance-ids {instance} "
        f"--document-name AWS-RunShellScript --parameters file://{pf} "
        f"--region {region} --profile {profile} --output json",
        shell=True, capture_output=True, text=True, timeout=30)
    os.unlink(pf)
    cid = json.loads(r.stdout)["Command"]["CommandId"]
    time.sleep(6)
    r2 = subprocess.run(
        f"aws ssm get-command-invocation --command-id {cid} "
        f"--instance-id {instance} --region {region} --profile {profile} --output json",
        shell=True, capture_output=True, text=True, timeout=30)
    return json.loads(r2.stdout)["StandardOutputContent"].strip()

# Render template with real values from instance
with open("roles/fleet/templates/fleet.yml.j2") as f:
    rendered = Template(f.read()).render(**vars_dict).strip()

# Fetch live config
live = ssm_run(INSTANCE, "grep -vE '^#|^$' /etc/fleet/fleet.yml", REGION, PROFILE)

# Normalize + compare
live_n = "\n".join(l.strip() for l in live.splitlines() if l.strip())
exp_n = "\n".join(l.strip() for l in rendered.splitlines() if l.strip())
assert live_n == exp_n, f"Template differs from live config"
```

Key gotchas:
- Template `.j2` files must NOT have comment lines (e.g. `# Config...`) — live configs don't have them
- MySQL config on Ubuntu uses tabs for alignment, not spaces — match the tab style in template
- Use real secret values (from instance configs) for comparison, not dummy values
- `grep -vE '^#|^$'` on live config strips comments + blank lines for fair comparison
