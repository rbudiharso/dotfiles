# Nginx Reverse Proxy + TLS + Domain Cutover

Pattern: move an app from direct high-port TLS (e.g. 8080) to standard ports (80/443) via nginx reverse proxy. Includes Route53 DNS, Let's Encrypt cert acquisition via SSM, app config changes, and IaC updates.

## When to use

- App listens on high port (8080, 8443) with self-managed TLS
- Need standard ports (80 redirect, 443 TLS) for clean URL
- App runs as non-root user — can't bind to 80/443 directly
- Want Let's Encrypt cert renewal without app downtime

## Step-by-step

### 1. Check prerequisites

```bash
# Via SSM send-command
ssm_run("ss -tlnp | grep -E ':80 |:443 '")  # ports free?
ssm_run("which nginx 2>&1")                   # nginx installed?
ssm_run("certbot --version 2>&1")             # certbot available?
```

Check AWS SG for port 80 + 443 inbound:
```bash
aws ec2 describe-security-groups --group-ids <SG_ID> --region <R> --profile <P> --output json | \
  jq '.SecurityGroups[0].IpPermissions[] | {FromPort, ToPort, Cidrs: [.IpRanges[].CidrIp]}'
```

### 2. Open SG ports if needed

```bash
aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol tcp --port 80 --cidr 0.0.0.0/0 --region <R> --profile <P>
aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol tcp --port 443 --cidr 0.0.0.0/0 --region <R> --profile <P>
```

### 3. Create Route53 A record

```bash
# Find hosted zone
aws route53 list-hosted-zones --profile <P> --output json | jq '.HostedZones[] | {Id, Name, PrivateZone: .Config.PrivateZone}'

# Create A record (UPSERT = create or update)
cat > /tmp/r53-change.json << 'EOF'
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "app.internal.gift.id.",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "<PUBLIC_IP>"}]
    }
  }]
}
EOF
aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> --change-batch file:///tmp/r53-change.json --profile <P>

# Wait for propagation
aws route53 get-change --id /change/<CHANGE_ID> --profile <P>  # wait for INSYNC
dig +short app.internal.gift.id  # verify resolves
```

### 4. Get Let's Encrypt cert via SSM

```bash
# Certbot standalone needs port 80 free (it starts a temp HTTP server)
ssm_run("certbot certonly --standalone -d app.internal.gift.id --non-interactive --agree-tos --email admin@company.com --key-type ecdma 2>&1")
```

Verify:
```bash
ssm_run("openssl x509 -in /etc/letsencrypt/live/app.internal.gift.id/fullchain.pem -noout -subject -dates -issuer 2>&1")
```

### 5. Install + configure nginx

```bash
ssm_run("apt-get install -y nginx 2>&1 | tail -5")
```

Nginx config (write via base64 to avoid shell escaping in SSM):

```python
import base64

nginx_conf = """server {
    listen 80;
    server_name app.internal.gift.id;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name app.internal.gift.id;

    ssl_certificate /etc/letsencrypt/live/app.internal.gift.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.internal.gift.id/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}"""

encoded = base64.b64encode(nginx_conf.encode()).decode()
ssm_run(f"echo '{encoded}' | base64 -d > /etc/nginx/sites-available/app && "
        "ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app && "
        "rm -f /etc/nginx/sites-enabled/default && nginx -t 2>&1")
```

Key: `proxy_pass` uses `https://` if the backend app serves TLS (e.g. Fleetdm defaults to HTTPS). Use `http://` if app serves plain HTTP.

### 6. Update app config to listen on localhost only

```python
import base64

app_yml = """server:
  address: 127.0.0.1:8080
  cert: /etc/app/certs/fullchain.pem
  key: /etc/app/certs/privkey.pem
"""
encoded = base64.b64encode(app_yml.encode()).decode()
ssm_run(f"cp /etc/app/app.yml /etc/app/app.yml.bak.$(date +%Y%m%d%H%M%S) && "
        f"echo '{encoded}' | base64 -d > /etc/app/app.yml")
```

Pitfall: some apps (e.g. Fleetdm) default to HTTPS even without cert/key in config. Keep cert/key paths in app config to avoid startup failure. The app serves TLS on localhost:8080, nginx terminates TLS on 443 and proxies to HTTPS backend.

### 7. Copy certs to app cert dir + set renew hook

```bash
# Copy certs for app to use
ssm_run("cp /etc/letsencrypt/live/app.internal.gift.id/fullchain.pem /etc/app/certs/fullchain.pem && "
        "cp /etc/letsencrypt/live/app.internal.gift.id/privkey.pem /etc/app/certs/privkey.pem && "
        "chown app:app /etc/app/certs/*.pem && chmod 644 /etc/app/certs/fullchain.pem && chmod 600 /etc/app/certs/privkey.pem")
```

Renewal hook (auto-copies renewed certs + restarts app):
```bash
ssm_run("mkdir -p /etc/letsencrypt/renewal-hooks/deploy && "
        "cat > /etc/letsencrypt/renewal-hooks/deploy/app-copy-certs.sh << 'HOOKEOF'\n"
        "#!/bin/bash\n"
        "cp /etc/letsencrypt/live/app.internal.gift.id/fullchain.pem /etc/app/certs/fullchain.pem\n"
        "cp /etc/letsencrypt/live/app.internal.gift.id/privkey.pem /etc/app/certs/privkey.pem\n"
        "chown app:app /etc/app/certs/*.pem\n"
        "chmod 644 /etc/app/certs/fullchain.pem\n"
        "chmod 600 /etc/app/certs/privkey.pem\n"
        "systemctl restart app.service\n"
        "HOOKEOF\n"
        "chmod +x /etc/letsencrypt/renewal-hooks/deploy/app-copy-certs.sh")
```

### 8. Restart all services + verify

```bash
ssm_run("systemctl daemon-reload && systemctl restart app.service && sleep 3 && "
        "systemctl restart nginx && sleep 1 && "
        "systemctl is-active app.service && systemctl is-active nginx")

# Direct healthz (backend)
ssm_run("curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8080/healthz")  # 200

# Via nginx (external)
ssm_run("curl -sk -o /dev/null -w '%{http_code}' https://app.internal.gift.id/healthz")  # 200

# HTTP redirect
ssm_run("curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://app.internal.gift.id/healthz")  # 301 https://...

# TLS cert check
ssm_run("curl -sk https://app.internal.gift.id/healthz -v 2>&1 | grep -E 'subject:|issuer:|expire'")

# Port check
ssm_run("ss -tlnp | grep -E ':80 |:443 |:8080 '")
# Expect: nginx on 0.0.0.0:80 + 0.0.0.0:443, app on 127.0.0.1:8080
```

### 9. Update agent configs (if app has enrolled agents)

For Fleetdm Orbit agents, update the fleet URL:
```bash
ssm_run("sed -i 's|ORBIT_FLEET_URL=.*|ORBIT_FLEET_URL=https://app.internal.gift.id|' /etc/default/orbit")
ssm_run("systemctl restart orbit.service")
```

### 10. Update IaC

Create nginx Ansible role:
```
roles/nginx/
├── defaults/main.yml    # domain, backend URL, SSL cert paths
├── tasks/main.yml       # install nginx, deploy config, enable site
├── handlers/main.yml    # restart nginx
└── templates/
    └── app.conf.j2      # nginx server block template
```

Update playbook to include nginx role after app role, before agent roles:
```yaml
- name: Install and configure Nginx reverse proxy
  hosts: app_group
  become: yes
  roles:
    - role: nginx
```

Update app role defaults:
- `app_server_url`: change from `https://old-domain:8080` to `https://new-domain` (no port)
- `certbot_domain`: change to new domain
- App config template: add `server.address: 127.0.0.1:8080`

### 11. Post-migration: purge old services

After confirming app works via nginx on RDS/external DB:
```bash
# Stop + disable old local DB (if migrated to RDS)
ssm_run("systemctl stop mysql.service && systemctl disable mysql.service")

# Purge packages + remove data dir (reclaims disk)
ssm_run("apt-get purge -y mysql-server mysql-client mysql-common 2>&1 | tail -5")
ssm_run("rm -rf /var/lib/mysql /var/log/mysql /etc/mysql")
ssm_run("apt-get autoremove -y 2>&1 | tail -5")

# Verify disk reclaimed
ssm_run("df -h /")
```

Example: purging MySQL freed 19GB (92% → 42% disk usage on 39GB volume).

## Pitfalls

1. **App defaults to HTTPS**: Fleetdm serves HTTPS even without cert/key in config. If you remove cert/key thinking nginx handles TLS, app fails to start with "transport: https" + missing cert error. Keep cert/key in app config — app serves HTTPS on localhost:8080, nginx proxies to HTTPS backend.

2. **SSM shell escaping**: Nginx config contains `$host`, `$remote_addr` etc. — shell interprets these as variables. Use base64 encoding to write config files via SSM:
   ```python
   encoded = base64.b64encode(config.encode()).decode()
   ssm_run(f"echo '{encoded}' | base64 -d > /path/to/config")
   ```

3. **Certbot needs port 80**: Standalone plugin starts a temp HTTP server on port 80. Ensure port 80 is free + SG allows inbound 80.

4. **Renew hook must restart app too**: If app uses copied certs (not reading from letsencrypt dir directly), renew hook must copy certs + restart app, not just nginx.

5. **Old certbot renew hooks**: Remove old domain's renew hooks to avoid errors when old cert is deleted.

6. **Systemd ExecStop**: Some service files have broken ExecStop commands (e.g. using `$(ps aux | grep ...)` which may fail). If service fails to restart cleanly, check `systemctl status` for ExecStop failures — may need to fix the service file.

## Ansible nginx role template

### defaults/main.yml
```yaml
nginx_app_domain: "app.internal.gift.id"
nginx_app_backend: "https://127.0.0.1:8080"
nginx_ssl_cert: "/etc/letsencrypt/live/{{ nginx_app_domain }}/fullchain.pem"
nginx_ssl_key: "/etc/letsencrypt/live/{{ nginx_app_domain }}/privkey.pem"
```

### templates/app.conf.j2
```nginx
server {
    listen 80;
    server_name {{ nginx_app_domain }};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name {{ nginx_app_domain }};

    ssl_certificate {{ nginx_ssl_cert }};
    ssl_certificate_key {{ nginx_ssl_key }};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass {{ nginx_app_backend }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```
