# Production deploy (AWS)

Production mirrors staging architecture with **tiered EC2** (core / crm / voip / mt), separate Cognito pool, and `*.esandardev.com` hostnames.

## Phase 1 — Terraform (this folder)

### Prerequisites

- AWS account with permissions for VPC, EC2, RDS, ElastiCache, ALB, Cognito, CloudFront, S3, Route 53, ACM, Secrets Manager, KMS, EventBridge, SQS
- Public hosted zone for `esandardev.com` in the same account
- Terraform >= 1.5
- Optional: S3 backend + DynamoDB lock table (uncomment in `versions.tf`)

### Initial sizing (scale later)

| Resource | Default |
|----------|---------|
| core / crm / voip EC2 | `t3.small` |
| mt EC2 (Windows) | `t3.small` |
| RDS core + trading | `db.t3.small` |
| ElastiCache Redis | `cache.t3.small` |

### Apply

```bash
cd deploy/production/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if needed

terraform init
terraform plan -out=production.tfplan
terraform apply production.tfplan
```

First apply creates ACM DNS validation records automatically when `create_acm_certificates = true`. Allow a few minutes for certificate validation before ALB/CloudFront become healthy.

### Key outputs (save after apply)

```bash
terraform output
```

| Output | Use |
|--------|-----|
| `core_ec2_private_ip` | identity, pii-vault, audit-log inter-service URLs on crm/voip hosts |
| `crm_ec2_private_ip` | crm-api + client-service host |
| `voip_ec2_private_ip` | voip-gateway from crm (east-west within VPC) |
| `voip_elastic_ip` | **Give to VoIP vendor for AMI/SIP whitelist** (stable outbound source IP) |
| `mt_ec2_private_ip` | `MT_BRIDGE_SERVICE_URL` on crm + client |
| `rds_core_endpoint` / `rds_trading_endpoint` | Postgres in `.env.production` |
| `redis_endpoint` | Redis URL |
| `cognito_user_pool_id`, `cognito_app_client_id`, `cognito_domain` | CRM SPA + identity |
| `crm_frontend_bucket_name`, `cloudfront_distribution_id` | CRM static deploy |
| `call_recordings_bucket_name`, `ftd_uploads_bucket_name` | voip / crm S3 |
| `audit_event_bus_name`, `audit_sqs_queue_url` | audit-log-service |
| Secret ARNs | populate Secrets Manager values used by compose |

### Architecture

```
crm.esandardev.com  → CloudFront → S3 (CRM SPA)
api.esandardev.com  → ALB → core:8000 (identity default)
                      ├─ /api/v1/crm/*, /api/v1/intake/* → crm:8001
                      ├─ /api/v1/client/* → crm:8002
                      ├─ /users/*, /internal/*, /staff → core:8000
                      └─ /ws → crm:8001

core EC2   — identity, pii-vault, audit-log
crm EC2    — crm-api, client-service
voip EC2   — voip-gateway
mt EC2     — mt-bridge (Windows)
RDS        — esafx_core, esafx_trading
```

Production VPC CIDR is `10.1.0.0/16` (staging uses `10.0.0.0/16`).

**VoIP static IP:** the voip EC2 runs in a public subnet with a dedicated Elastic IP (`voip_elastic_ip` output). Provide that address to the PBX vendor for whitelisting. It persists across instance stop/start; only `terraform destroy` or manual disassociation changes it.

## Phase 2 — Deploy application tiers

On each EC2 (via SSM), clone service repos under `/opt/esafx` and `git pull origin main`. Copy each `*.env.staging.example` → `.env.production` using `terraform output` + Secrets Manager, then set **cross-host URLs**:

| Variable | Example (replace with terraform output) |
|----------|----------------------------------------|
| `IDENTITY_SERVICE_URL` | `http://10.1.133.252:8000` on CRM EC2 |
| `PII_VAULT_SERVICE_URL` | `http://10.1.133.252:8004` on CRM EC2 |
| `AUDIT_LOG_SERVICE_URL` | `http://10.1.133.252:8005` on CRM EC2 |
| `VOIP_GATEWAY_URL` | `http://10.1.12.152:8006` on CRM EC2 |
| `MT_BRIDGE_SERVICE_URL` | `http://10.1.143.205:8003` on CRM EC2 |
| `CLIENT_SERVICE_URL` | `http://client:8000` inside CRM compose only |

### Deploy order

```bash
# 1. Core EC2
./deploy/production/deploy-core-ec2.sh

# 2. VoIP EC2
./deploy/production/deploy-voip-ec2.sh

# 3. MT EC2 (Windows — mt-bridge-service deploy/ec2-deploy.ps1)

# 4. CRM EC2 (after core + MT are up)
./deploy/production/deploy-crm-ec2.sh
```

Compose files: `docker-compose.core.yml`, `docker-compose.voip.yml`, `docker-compose.crm.yml`.

## Phase 3 — Legacy CSV import

See `crm-service/docs/legacy-csv-import.md`. Import leads before clients; use `--sync-mt5` for MT5 account linking.

### Post-apply (Phase 2 — not in Terraform)

1. SSM into each EC2 tier; clone service repos and `git pull origin main`
2. Copy each `*.env.production.example` → `.env.production` using Terraform outputs + Secrets Manager
3. Run docker compose per tier (compose files to be added under `deploy/production/`)
4. Deploy CRM frontend to S3 + invalidate CloudFront
5. Migrate staff from staging Cognito → production pool (separate script)
6. Run legacy CSV import scripts (Phase 3)

### Destroy

RDS instances have `deletion_protection = true`. Disable in Terraform before destroy.

```bash
terraform destroy
```
