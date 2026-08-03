User (rb) works at Tada; GitLab instance gitlab.gift.id, repos under gitlab.gift.id/services/* and core-services/*. Node.js/Express repo at /Users/rb/Code/Tada/bridge (project 'distribution') uses mocha/nyc (not jest), private npm packages under @usetada/* via npm.pkg.github.com (needs GITHUB_TOKEN env var, configured in project .npmrc).
§
SSM: use `send-command` not `start-session`. session-manager-plugin now installed at ~/.local/bin/ (extracted from pkg, no sudo). For ansible aws_ssm plugin on macOS: set OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES + ansible_aws_ssm_plugin path var. AWS profile default.
§
User prefers foreground commands with generous timeouts over background/nohup processes for test runs and verification — explicitly denied a background terminal run mid-task. Wants real executed proof (actual command output) before accepting a fix as verified, not inferred/plausible results.
§
User expects confirmation before helm upgrades / infra changes affecting prod clusters, especially when jobs are in-flight, even though impact is often minimal — treat prod k8s changes as requiring an explicit go-ahead.
§
Radar MCP server-side kubeconfig determines target cluster — switching kubectl context does NOT change radar's target. Always check `cluster.name` in get_dashboard response before acting on radar issues. kubectl delete/apply ran against stg when radar was showing prd — wasted a full HPA deletion cycle. Always run `kubectl config current-context` before kubectl delete/apply AND verify `get_dashboard` cluster.name matches.
§
Vault at vault.internal.gift.id. ExternalSecret k8s auth: mountPath kubernetes-stg/prd, role <svc>-stg-reader, SA <svc>-staging, path secret/data/<ns>/<env>/<svc>/env. RDS staging: secret/rds/staging-db (10.31.2.210:5432, user staging_dbs_root, 126 DBs). Vault MCP needs own token in config — does NOT inherit shell VAULT_TOKEN.