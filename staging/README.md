# Staging deploy (EC2)

Deploy order matches [architecture.md](../../architecture.md) §11 and the EC2 staging plan.

## 1. Provision AWS

```bash
cd infra/staging/terraform
terraform apply
```

Record `mt_ec2_private_ip`, RDS endpoints, Cognito IDs, and Secrets Manager paths from outputs.

## 2. Configure `.env.staging` per service

Copy each `*.env.staging.example` → `.env.staging` and fill from Terraform outputs + Secrets Manager.

| Service | File |
|---------|------|
| identity | `identity-service/.env.staging` |
| pii-vault | `pii-vault-service/.env.staging` |
| crm-api | `crm-service/.env.staging` |
| client | `client-service/.env.staging` |
| mt-bridge | `mt-bridge-service/.env.staging` |
| CRM build | `crm/.env.staging` |

**RDS (core DB):** set `DB_SSL=true` and `DB_SSL_CA_FILE=/opt/esafx/global-bundle.pem` on every service using Postgres. `deploy-app-ec2.sh` downloads the CA bundle on the host; compose mounts it into containers.

**Passwords:** use `esafx/staging/db/core` in Secrets Manager after `terraform apply` with `manage_master_user_password=false` (password matches RDS). Until then, use the RDS-managed secret (`rds!db-...` from the RDS console). No quotes around passwords; never edit passwords in PowerShell double-quoted strings (`$` expands).

**Docker Compose `$` warnings:** Compose interpolates `$VAR` in `env_file` values. If you see `The "o3" variable is not set`, a password or URL contains `$` (e.g. `...$o3...`). Escape each `$` as `$$` in `.env.staging`, or remove `$` from generated passwords when possible.

**Alembic (shared `esafx_core` DB):** each service uses its own version table (`alembic_version_identity`, `alembic_version_crm`, `alembic_version_client`). If identity migrations already ran against the old shared `public.alembic_version`, stamp once after pulling the fix:

```bash
docker compose -f deploy/staging/docker-compose.app.yml --profile migrate run --rm identity-migrate alembic stamp 002
```

Then run `./deploy/staging/deploy-app-ec2.sh` (or at least `crm-migrate`).

**Critical:** `crm-service` and `client-service` must set:

```bash
MT_BRIDGE_SERVICE_URL=http://<mt_ec2_private_ip>:8003
```

Use the same `MT_BRIDGE_SERVICE_TOKEN` in crm, client, and mt-bridge.

## 3. App EC2

```bash
chmod +x deploy/staging/deploy-app-ec2.sh deploy/staging/deploy-mt-ec2.sh
./deploy/staging/deploy-app-ec2.sh
```

## 4. MT EC2 (Windows Server)

The MT instance is **Windows** (required for `mt5manager`). Connect with SSM, then in **PowerShell**:

```powershell
# From your laptop — get instance id from EC2 console or terraform output
aws ssm start-session --target <mt-instance-id> --region ap-southeast-3

# On the Windows host
cd C:\esafx\mt-bridge-service
.\deploy\ec2-deploy.ps1
```

Clone `mt-bridge-service` to `C:\esafx\mt-bridge-service` and place `.env.staging` there first. Do **not** use `deploy-mt-ec2.sh` (Linux/bash) on the MT host.

## 5. CRM frontend

```bash
cd crm
cp .env.staging.example .env.staging   # or .env.production for build
pnpm install && pnpm build
aws s3 sync dist/ s3://<esafx-crm-frontend-staging-bucket>/ --delete
aws cloudfront create-invalidation --distribution-id <id> --paths "/*"
```

## 6. Smoke tests

```bash
export API_BASE_URL=https://api.staging.esafx.co.id
export COGNITO_TOKEN=<staff access token>
export MT_PRIVATE_IP=<from terraform output>
./infra/staging/scripts/smoke-staging.sh
```
