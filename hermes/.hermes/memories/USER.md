User (rb) @ Tada. GitLab gitlab.gift.id, repos services/* + core-services/*. Node repo /Users/rb/Code/Tada/bridge, mocha/nyc, npm @usetada/* via npm.pkg.github.com.
§
k8s: EKS prd+stg (jkt-prd/stg-infra-eks-tada), CAST.ai. Prod changes need go-ahead. MongoDB rs0 on 3 EC2. SSM: send-command not start-session, AWS profile default.
§
rb tests new tooling on stg before prd. ECR pull-through cache: ghcr.io→github/, public.ecr.aws→cache/, docker.io→docker-hub/, quay.io→quay/, registry.k8s.io→k8s/.
§
Trivy operator was reinstalled on prd but later fully removed again (as of 2026-08-03). No trivy-system namespace, no CRDs, no resources. Orphaned trivy-system/ manifest dir cleaned from tada-prd-manifests. trivy-operator NOT helm-managed on prd currently.
§
rb likes parallel subagent delegation for bulk tasks. Wants real executed proof before accepting fixes. Prod k8s changes need explicit go-ahead.
§
ArgoCD manages stg+prd. Manifest repo tada-stg-manifest.git, project saas, auto-sync. Vault at vault.internal.gift.id replacing Infisical.