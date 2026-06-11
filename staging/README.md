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
| audit-log | `audit-log-service/.env.staging` |
| crm-api | `crm-service/.env.staging` |
| voip-gateway | `voip-gateway-service/.env.staging` |
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

**Always pass `--build`** on migrate runs after `git pull`; otherwise Compose reuses an old image and CRM still reads `public.alembic_version` (identity revision `002`):

```bash
cd crm-service && git pull origin main && cd ..
docker compose -f deploy/staging/docker-compose.app.yml --profile migrate run --rm --build crm-migrate
```

Verify the running image has the fix:

```bash
docker compose -f deploy/staging/docker-compose.app.yml --profile migrate run --rm --build crm-migrate \
  grep ALEMBIC_VERSION_TABLE /app/app/db/migrations/env.py
# expect: ALEMBIC_VERSION_TABLE = "alembic_version_crm"
```

**Critical:** `crm-service` and `client-service` must set:

```bash
MT_BRIDGE_SERVICE_URL=http://<mt_ec2_private_ip>:8003
```

Use the same `MT_BRIDGE_SERVICE_TOKEN` in crm, client, and mt-bridge.

**crm-api Compose networking:** from inside the `crm-api` container, use Docker service hostnames (not host `127.0.0.1` ports):

```bash
IDENTITY_SERVICE_URL=http://identity:8000
PII_VAULT_SERVICE_URL=http://pii-vault:8004
AUDIT_LOG_SERVICE_URL=http://audit-log:8005
VOIP_GATEWAY_URL=http://voip-gateway:8006
CLIENT_SERVICE_URL=http://client:8000
```

**Audit pipeline (terraform outputs):** set on `crm-service` and other publishers:

```bash
AUDIT_LOG_API_KEY=<shared secret>
EVENTBRIDGE_AUDIT_ENABLED=true
EVENTBRIDGE_AUDIT_BUS_NAME=<audit_event_bus_name output>
```

On `audit-log-service`:

```bash
SQS_QUEUE_URL=<audit_sqs_queue_url output>
AUDIT_LOG_API_KEY=<same shared secret>
```

Internal port **8005** (`http://audit-log:8005`). `deploy-app-ec2.sh` runs `audit-migrate`, starts `audit-log` before `crm-api`, and curls `:8005/health`.

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
```

User-data bootstrap installs Python 3.12, AWS CLI, Git, and opens port 8003. On a **fresh** MT host:

```powershell
# Option A — bootstrap script (clone + secrets + deploy)
# Copy bootstrap-mt-ec2.ps1 to the host first, or clone the full monorepo to C:\esafx
powershell -ExecutionPolicy Bypass -File C:\esafx\deploy\staging\bootstrap-mt-ec2.ps1

# Option B — manual (same steps)
cd C:\esafx
git clone https://github.com/Esa-FX/mt-bridge-service.git mt-bridge-service
cd mt-bridge-service
git pull origin main
.\deploy\sync-env-from-secrets.ps1 -InstallAwsCli
.\deploy\ec2-deploy.ps1
```

`ec2-deploy.ps1` verifies RDS login, runs **Alembic on esafx_trading**, and starts uvicorn on **8003**.

Confirm from MT host:

```powershell
Invoke-WebRequest -Uri http://127.0.0.1:8003/health -UseBasicParsing
```

Do **not** use `deploy-mt-ec2.sh` (Linux/bash) on the MT host.

## 4b. Seed demo clients + KPI trading data (app EC2)

Architecture: **CRM/core** on `esafx_core`, **trading** on `esafx_trading` (mt-bridge DB).

1. After MT EC2 deploy (§4), on **app EC2**:

```bash
cd /opt/esafx
git pull origin staging   # crm-service + deploy scripts

# Add TRADING_DB_* to crm-service/.env.staging (from Secrets Manager)
chmod +x deploy/staging/sync-crm-trading-db-env.sh deploy/staging/seed-staging-clients.sh
./deploy/staging/sync-crm-trading-db-env.sh

# Rebuild crm-api and seed (5–10 clients per leader + FTD/deposits/withdrawals)
./deploy/staging/seed-staging-clients.sh
# or: bash crm-service/scripts/ssm-seed-clients-staging.sh
```

2. Open CRM → Reports → KPI for the current month as a team leader.

**Note:** Escape `$` as `$$` in `.env.staging` passwords if Compose warns `The "o3" variable is not set`.

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
