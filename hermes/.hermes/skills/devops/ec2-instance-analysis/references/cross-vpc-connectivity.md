# Cross-VPC Connectivity & RDS Migration Feasibility

## Diagnosing Cross-VPC Connectivity (EC2 → RDS/other VPC)

When an EC2 instance can't reach a resource in another VPC, check in this order:

### 1. VPC peering connections

```bash
aws ec2 describe-vpc-peering-connections --region <R> --profile <P> --output json | \
  jq '[.VpcPeeringConnections[] | select(.Status.Code=="active") | {
    VpcPeeringConnectionId,
    RequesterVpcId: .RequesterVpcInfo.VpcId,
    RequesterCidr: .RequesterVpcInfo.CidrBlock,
    AccepterVpcId: .AccepterVpcInfo.VpcId,
    AccepterCidr: .AccepterVpcInfo.CidrBlock
  }]'
```

Look for a peering connection where requester/accepter matches your two VPC IDs. Status must be `active`.

### 2. Route tables (both directions)

Check Fleet VPC route tables for a route to the RDS VPC CIDR:
```bash
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<FLEET_VPC>" --region <R> --profile <P> --output json | \
  jq '[.RouteTables[] | {RouteTableId, Routes: [.Routes[] | select(.VpcPeeringConnectionId != null) | {DestinationCidrBlock, VpcPeeringConnectionId, State}]}]'
```

Check RDS VPC route tables for a route back to the Fleet VPC CIDR:
```bash
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<RDS_VPC>" --region <R> --profile <P> --output json | \
  jq '[.RouteTables[] | {RouteTableId, Routes: [.Routes[] | select(.DestinationCidrBlock=="<FLEET_CIDR>")]}]'
```

Key: routes must be `active`, not `blackhole`. A `blackhole` state means the peering connection was deleted or the CIDR overlap exists.

### 3. Map EC2 subnet to route table

The EC2 instance's subnet may use a specific route table (subnet association) or the VPC main route table. Check:
```bash
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=<SUBNET_ID>" --region <R> --profile <P> --output json | \
  jq '[.RouteTables[] | {RouteTableId, Routes: [.Routes[] | select(.DestinationCidrBlock=="<RDS_CIDR>")]}]'
```

If empty, the subnet uses the VPC main route table (no explicit subnet association). Check the main route table instead.

### 4. Security group inbound rules on the target

```bash
aws ec2 describe-security-groups --group-ids <RDS_SG_ID> --region <R> --profile <P> --output json | \
  jq '.SecurityGroups[0] | {
    GroupName, VpcId,
    IngressRules: [.IpPermissions[] | {
      FromPort, ToPort, IpProtocol,
      SourceCidrs: [.IpRanges[]?.CidrIp],
      SourceSGs: [.UserIdGroupPairs[]?.GroupId]
    }]
  }'
```

Check if the EC2 instance's private IP falls within any allowed CIDR. If not, the SG blocks traffic even with peering + routes in place. This is the most common failure point.

### 5. TCP test from EC2 via SSM

```bash
# Via SSM send-command (use JSON parameter file for reliability)
ssm_run("timeout 5 bash -c 'echo > /dev/tcp/<RDS_HOST>/3306 && echo CONNECTED || echo FAILED'")
```

If this times out (exit 124), the SG is blocking. If it connects, the path is open.

### Common failure: peering + routes OK, SG blocks

VPC peering is active, route tables have entries in both directions, but the RDS SG doesn't allow the EC2's private IP CIDR. Fix: add an inbound rule to the RDS SG for the EC2's IP (e.g. `172.16.3.195/32`) on the target port. This is a prod change — get explicit go-ahead.

## RDS Migration Feasibility Checklist

Before migrating an EC2-local MySQL DB to an existing RDS instance:

1. **Network path**: Can the EC2 reach the RDS? (VPC peering, route tables, SG — see above)
2. **RDS capacity**: Check instance class (db.t4g.micro = 0.5 vCPU, 1GB RAM — may be too small), allocated storage vs DB size
3. **MySQL version compatibility**: `SELECT VERSION()` on both sides. Fleet supports MySQL 8.x (8.4 added in Fleet 4.55.0). RDS 8.4.x is compatible with local 8.0.x.
4. **Existing databases**: `SHOW DATABASES` on RDS — are there other databases sharing the instance? Adding workload to a shared RDS may impact performance.
5. **Application database support**: Does the application support the target database engine? (e.g. Fleetdm only supports MySQL, NOT PostgreSQL — GitHub issues #334, #30286, #34025 all closed, no PG support shipped)
6. **DB size**: `SELECT ROUND(SUM(data_length+index_length)/1024/1024,2) AS total_mb FROM information_schema.tables WHERE table_schema='<db>'` — compare to RDS free storage
7. **Downtime window**: mysqldump + restore requires downtime. Estimate: ~1 min per 10MB for small DBs.

### Migration execution pitfalls

**1. mysqldump stderr contaminates dump file**

`mysqldump` writes `[Warning] Using a password on command line interface can be insecure.` to stderr. Using `2>&1` redirect mixes this warning into the dump file:

```bash
# WRONG — warning line becomes first line of SQL, import fails with ERROR 1064
mysqldump -u user -p'pass' db 2>&1 > dump.sql
mysql -h rds < dump.sql  # ERROR 1064 at line 1: syntax error near 'mysqldump: [Warning]...'

# CORRECT — suppress stderr, dump file starts with `-- MySQL dump 10.13`
mysqldump -u user -p'pass' db 2>/dev/null > dump.sql
```

Always check `head -3 dump.sql` — first line should be `-- MySQL dump 10.13`, NOT a warning.

**2. RDS DEFINER permission error on views**

RDS restricts the `SUPER` privilege. Views dumped with `DEFINER=fleetadmin@localhost` fail on import:

```
ERROR 1227 (42000) at line 5337: Access denied; you need (at least one of) the SUPER
or ALLOW_NONEXISTENT_DEFINER privilege(s) for this operation
```

Fix: replace the DEFINER with the RDS user, then import the view DDL separately:

```bash
# Fix all DEFINER references in the dump
sed 's/DEFINER=`old_user`@`localhost`/DEFINER=`rds_user`@`%`/' dump.sql > dump_fixed.sql

# If main import failed at the view section, extract + import just the view lines
sed -n '5330,5345p' dump_fixed.sql > view_fix.sql
mysql -h <RDS_HOST> -u <RDS_USER> -p'<PASS>' <db> < view_fix.sql
```

The data (tables + rows) imports fine before hitting the view — only the view DDL at the end of the dump fails. After fixing, verify table count matches source vs target.

**3. Verify migration completeness**

```bash
# Table count (source vs target must match)
mysql -u local_user -p'pass' db -e 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema="db";'
mysql -h rds -u rds_user -p'pass' db -e 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema="db";'

# Row count
mysql -h rds -u rds_user -p'pass' db -e 'SELECT SUM(table_rows) FROM information_schema.tables WHERE table_schema="db";'

# DB size
mysql -h rds -u rds_user -p'pass' db -e 'SELECT ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb FROM information_schema.tables WHERE table_schema="db";'
```

**4. Post-migration: update application config + restart**

```bash
# Backup current config
cp /etc/fleet/fleet.yml /etc/fleet/fleet.yml.bak.$(date +%Y%m%d%H%M%S)

# Write new config pointing to RDS (via SSM send-command with heredoc)
cat > /etc/fleet/fleet.yml << 'EOF'
mysql:
  address: <RDS_HOST>:3306
  database: fleetdb
  username: <RDS_USER>
  password: <RDS_PASS>
...
EOF

# Restart + verify
systemctl restart fleet.service
systemctl is-active fleet.service  # must be "active"
curl -sk -o /dev/null -w '%{http_code}' https://localhost:8080/healthz  # must be 200
journalctl -u fleet.service --since '2 min ago' --no-pager  # check for DB errors
```

**5. Post-migration: update IaC**

After DB migration to RDS, update IaC to reflect the new state:

- `roles/<app>/defaults/main.yml`: change `mysql_address` from `127.0.0.1:3306` to RDS endpoint, update username
- `group_vars/<group>.yml`: add `use_rds: true` flag, add RDS connection vars, use vault reference for password
- `playbooks/site.yml`: make local MySQL role conditional (`when: not (use_rds | default(true))`)
- Verify template renders identical to live config (template-vs-live pattern)
- Run `ansible-playbook --syntax-check`
- Scan for hardcoded secrets: `git grep -n '<password>'`
- Commit + push

### Migration command (once connectivity confirmed)

```bash
# From the EC2 instance (has access to both local + RDS MySQL)
mysqldump -u <local_user> -p'<local_pass>' --single-transaction --routines --triggers --events --quick --hex-blob <db_name> 2>/dev/null | \
  mysql -h <RDS_HOST> -P 3306 -u <rds_user> -p'<rds_pass>' <new_db_name>
```

For large DBs or when piped import fails, dump to file first then import:
```bash
mysqldump -u <local_user> -p'<local_pass>' --single-transaction --routines --triggers --events --quick --hex-blob <db_name> 2>/dev/null > /tmp/dump.sql
mysql -h <RDS_HOST> -u <rds_user> -p'<rds_pass>' <new_db_name> < /tmp/dump.sql
```

### Post-migration: purge local MySQL (reclaim disk space)

After confirming app runs on RDS, purge local MySQL to reclaim disk:

```bash
# Stop + disable
systemctl stop mysql.service && systemctl disable mysql.service

# Purge packages
apt-get purge -y mysql-server mysql-client mysql-server-8.0 mysql-client-8.0 mysql-common mysql-server-core-8.0 mysql-client-core-8.0

# Remove data dir + config + logs
rm -rf /var/lib/mysql /var/log/mysql /etc/mysql

# Autoremove dependencies
apt-get autoremove -y

# Verify
which mysql  # should return nothing
dpkg -l | grep mysql  # should be empty

# Check reclaimed space
df -h /  # disk usage should drop significantly
```

Example: Fleet MDM reclaimed 19GB (92% → 42% disk usage) after purging local MySQL post-RDS migration.

## Fleetdm Database Notes

- Fleetdm supports MySQL ONLY. No PostgreSQL support exists or is planned (as of 2026).
- GitHub issue #334 (Feb 2021): "no plans to support PostgreSQL" — closed.
- GitHub issue #30286 (Jun 2025): customer requested PG, closed as "Done" in project board but no PG shipped.
- Community fork (ledoent/fleet, Mar 2026): experimental dual-database PR — not production-ready.
- Fleet config uses `mysql:` section in fleet.yml — no PostgreSQL config key exists.
- MySQL 8.4 support added in Fleet 4.55.0. MySQL 5.7 dropped same release.
- Compatible with Cloud SQL for MySQL and RDS for MySQL.
