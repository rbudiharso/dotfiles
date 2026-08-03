# Percona Backup for MongoDB (PBM) Stuck Backup

Session-specific detail from diagnosing a stuck mongodb-backup CronJob pod on prd EKS cluster (Jul 31, 2026).

## Infrastructure Context

- PBM backup runs as a k8s CronJob in `backup` namespace on `jkt-prd-infra-eks-tada` cluster
- CronJob: `mongodb-backup`, schedule `0 20 * * *` (daily 20:00 UTC / 03:00 WIB)
- Image: `public.ecr.aws/tada/pbm:2.4.1`
- ServiceAccount: `pbm-backup` (IRSA for S3 access)
- MongoDB connection via secret `mongodb-credentials` key `MONGODB_URI`
- PBM agents run on MongoDB EC2 instances (NOT k8s pods): 10.30.4.158 [P], 10.30.4.21 [S], 10.30.4.103 [S]
- Backup target: S3 bucket `jkt-prd-infra-eks-s3-mongodb-rs0-backup` in `ap-southeast-3`
- Replica set: `rs0`, MongoDB 4.4.30, PBM 2.4.1
- PITR (Point-in-Time Recovery) enabled with oplog streaming

## Failure Mode: Agent Reports OK but Backup Produces 0 Bytes

### Symptoms
- Job pod Running 31h+ (normal backup takes ~2h for ~206GB)
- Logs show `pbm backup --wait` polling forever (thousands of dots)
- `pbm status` shows all 3 agents OK
- `pbm describe-backup <name>` shows status `running`, size `0 B`, `last_write_time: 1970-01-01T00:00:00Z` (epoch = never wrote)
- Backup always selects same secondary node (10.30.4.21)
- `pbm status` "Currently running" shows the backup, but it never progresses

### Root Cause (Confirmed via SSM)
PBM agent on node 10.30.4.21 was restarted by systemd 2 minutes after backup started, killing the in-progress mongodump process. The backup lock was never released. New agent (different PID) sees stale lock, PITR slicer pauses forever, PBM metadata still shows backup "running" — but the actual mongodump worker is dead. `pbm backup --wait` polls forever because the backup is technically "running" in PBM's metadata.

**Timeline from journalctl:**
```
Jul 29 20:00:04 — backup started, pbm-agent PID 1878
Jul 29 20:02:45 — systemd: "Stopping Percona Backup for MongoDB Agent..."
Jul 29 20:03:16 — systemd: "Started Percona Backup for MongoDB Agent." — new PID 1896
Jul 29 20:03:17 — new agent starts PITR routine, sees stale backup lock
```

**Key insight:** The backup WAS progressing (mongodump was dumping collections) when the agent was killed. The "0 bytes" in `pbm describe-backup` is misleading — PBM doesn't update size until backup completes. A fresh backup triggered after clearing locks ran normally (5-7% progress in 2 min), proving the agent CAN execute backups — the failure was the mid-backup restart, not a persistent agent issue.

### Diagnosis Steps

1. **Check pbm status from a pod with credentials:**
   ```bash
   kubectl --context jkt-prd-infra-eks-tada -n backup exec <pod> -- pbm status
   ```
   Look for: agent health, currently running backups, snapshot list with sizes.

2. **Describe the stuck backup:**
   ```bash
   kubectl --context jkt-prd-infra-eks-tada -n backup exec <pod> -- pbm describe-backup <backup-name>
   ```
   Key fields: `status`, `size_h`, `last_write_time` (epoch 0 = never wrote), `replsets[].node` (which node is doing the backup).

3. **Check if node is an EKS node or external EC2:**
   ```bash
   kubectl get nodes -o wide | grep <node-ip>
   ```
   If not found, it's an external EC2 instance — can't diagnose via kubectl, need SSH.

### Resolution Steps

1. **Cancel the stuck backup:**
   ```bash
   kubectl --context jkt-prd-infra-eks-tada -n backup exec <pod> -- pbm cancel-backup
   ```
   Output: "Backup cancellation has started"

2. **Wait for cancellation to take effect:**
   ```bash
   sleep 10
   kubectl --context jkt-prd-infra-eks-tada -n backup exec <pod> -- pbm status | grep -A5 "Currently running"
   ```
   Should show "(none)" when cancelled.

3. **Delete the job pod** (the `pbm backup --wait` command doesn't exit after external cancel):
   ```bash
   kubectl --context jkt-prd-infra-eks-tada -n backup delete pod <pod>
   ```
   Job controller creates a new pod automatically.

4. **Check if new backup succeeds:**
   ```bash
   sleep 15
   kubectl --context jkt-prd-infra-eks-tada -n backup logs <new-pod> --tail=10
   kubectl --context jkt-prd-infra-eks-tada -n backup exec <new-pod> -- pbm describe-backup <new-backup-name>
   ```

5. **If same failure recurs** (same node, 0 bytes), the problem is on the EC2 instance, not the job. Need SSH or SSM to check:
   - `journalctl -u pbm-agent` or `/var/log/pbm/` for agent errors
   - Disk space on temp/backup directory
   - mongod connectivity from pbm-agent
   - Whether mongod on that node is functioning as secondary properly

### SSM Diagnosis (No Session Manager Plugin Required)

If `aws ssm start-session` fails with "SessionManagerPlugin is not found", use `send-command` instead — no plugin needed:

```bash
# Send command to EC2 instance via SSM Run Command
CMD_ID=$(aws --profile default --region ap-southeast-3 ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo journalctl -u pbm-agent --no-pager -n 30"]' \
  --output json | python3 -c "import json,sys; print(json.load(sys.stdin)['Command']['CommandId'])")

# Wait, then get output
sleep 5
aws --profile default --region ap-southeast-3 ssm get-command-invocation \
  --command-id "$CMD_ID" --instance-id <instance-id> \
  --query 'StandardOutputContent' --output text
```

**Finding the EC2 instance ID from a MongoDB node IP:**
```bash
aws --profile default --region ap-southeast-3 ec2 describe-instances \
  --filters "Name=private-ip-address,Values=10.30.4.*" \
  --query "Reservations[].Instances[].{Id:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name'].Value|[0]}" \
  --output table
```

**Instance may have multiple IPs:** Each MongoDB EC2 instance had 2 private IPs (e.g. rs0-1 had both 10.30.4.21 and 10.30.4.118). PBM used the old IP (10.30.4.21) which was still attached. Filter by `10.30.4.*` to find all MongoDB instances.

**Key journalctl queries for PBM agent diagnosis:**
```bash
# Check if agent was restarted (PID change = restart)
sudo journalctl -u pbm-agent --no-pager --since="<start-time>" --until="<end-time>" | grep -E "start|restart|stop|kill|signal"

# Check backup progress (mongodump output shows collection + bytes)
sudo journalctl -u pbm-agent --no-pager -n 20

# Check for stale lock (PITR slicer paused = lock held)
sudo journalctl -u pbm-agent --no-pager | grep "oplog slicer is paused for lock"
```

**Resource check on MongoDB EC2:**
```bash
df -h /tmp /data
free -h
# PBM uses /data for temp backup files, /tmp for mongodump workspace
```

### Running ad-hoc PBM commands

When the original pod is stuck/deleted, create a helper pod:

```bash
cat <<'EOF' | kubectl --context jkt-prd-infra-eks-tada -n backup apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pbm-helper
  namespace: backup
spec:
  restartPolicy: Never
  serviceAccountName: pbm-backup
  containers:
  - name: pbm
    image: public.ecr.aws/tada/pbm:2.4.1
    command: ["/bin/sh", "-c", "pbm status && pbm list"]
    env:
    - name: PBM_MONGODB_URI
      valueFrom:
        secretKeyRef:
          name: mongodb-credentials
          key: MONGODB_URI
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 256Mi
EOF
```

## PBM CLI Reference

| Command | Purpose |
|---------|---------|
| `pbm status` | Cluster health, running ops, backup list with sizes |
| `pbm list` | Snapshot list (completed + failed backups) |
| `pbm describe-backup <name>` | Detailed backup status: size, node, write time |
| `pbm cancel-backup` | Cancel currently running backup |
| `pbm config --list` | Show PBM config (S3, PITR, compression settings) |
| `pbm backup --wait` | Start backup and wait for completion (blocking) |
| `pbm backup` | Start backup without waiting (returns immediately) |
| `pbm version` | PBM version info |

## Key Patterns

- **"0 bytes" is misleading**: `pbm describe-backup` shows `size_h: 0 B` and `last_write_time: epoch 0` even when mongodump IS actively dumping data. PBM only updates size metadata after backup completes. Check the pbm-agent journal on the EC2 instance for actual progress (mongodump prints collection names + byte counts).
- **Stale lock after agent restart**: If pbm-agent is restarted (systemd stop/start, instance reboot, package update) while a backup is running, the backup lock is never released. New agent sees the lock, pauses PITR oplog slicer, and PBM metadata shows backup "running" forever. Fix: `pbm cancel-backup` to release the lock.
- **PID change = agent restart**: Compare pbm-agent PIDs in journalctl. PID 1878 → 1896 means agent was killed and restarted. This is the smoking gun for mid-backup agent death.
- **Backup name format**: ISO timestamp `2026-07-29T20:00:03Z` — matches the cronjob trigger time
- **Job pod name format**: `mongodb-backup-<jobid>-<pod-suffix>` (e.g. `mongodb-backup-29755920-8n85l`)
- **PBM selects secondary for backup**: Not the primary. If the selected secondary is broken, all backups fail.
- **PITR continues working even when snapshots fail**: Oplog chunks keep streaming to S3 independently. PITR chunks showed 35.03GB even though snapshots were all 0B/cancelled.
- **Cancelled backups show as `!canceled` in pbm list**: Not `error` — they're explicitly cancelled, not failed.
- **`pbm status` vs `pbm list`**: `status` shows running + recent with sizes + errors. `list` shows all snapshots (successful and failed). Use both for full picture.
- **Last successful backup before failure**: Check `pbm list` for the most recent snapshot with non-zero size + `restore_to_time` — that's the last good backup for recovery planning.

## Environment Facts

- MongoDB nodes are EC2 instances in ap-southeast-3, NOT EKS nodes
- PBM agents (v2.4.1) run on each MongoDB EC2 instance directly
- Backup snapshots are ~206GB logical (mongodump), taking ~2h each
- S3 bucket: `jkt-prd-infra-eks-s3-mongodb-rs0-backup`
- CronJob also has a cleanup job: `mongodb-backup-cleanup` (schedule `0 21 * * *`)
