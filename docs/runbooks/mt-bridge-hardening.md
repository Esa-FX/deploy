# MT bridge hardening (per-caller tokens, callers SG, firewall)

Deploy-repo changes for EsaFX mt-bridge security: separate service tokens per caller, dedicated MT security group, Windows firewall tightening, optional dealer webhook secret.

**Prerequisites:** Application PRs deployed that read `MT_BRIDGE_TOKEN_*`, per-caller `MT_BRIDGE_SERVICE_TOKEN` on crm/client, and fail-closed dealer webhook when `DEALER_WEBHOOK_SECRET` is set. crm `INTERNAL_SERVICE_TOKEN` rotation uses `crm_internal` only when you pass `--rotate-crm-internal` (after the crm build that enforces it is live).

Never log secret values. Do not pass secrets in SSM command parameters.

## Secret keys (`esafx/<env>/service-tokens`)

| Secret key | Env var(s) |
|------------|------------|
| `client` | crm `CLIENT_SERVICE_TOKEN`; client `INTERNAL_SERVICE_TOKEN` (normal sync only) |
| `crm_internal` | crm `INTERNAL_SERVICE_TOKEN`; voip/whatsapp `CRM_INTERNAL_TOKEN` — **only** via `--rotate-crm-internal` (whatsapp staging only) |
| `mt_bridge_crm` / `mt_bridge_client` | crm / client `MT_BRIDGE_SERVICE_TOKEN` |
| `pii_vault` | crm `PII_VAULT_SERVICE_TOKEN`; pii-vault `SERVICE_TOKEN`; voip/whatsapp `PII_VAULT_SERVICE_TOKEN` |
| `mt_bridge_admin` | MT host `MT_BRIDGE_TOKEN_ADMIN` (Windows sync script) |
| `mt_bridge` | Legacy — remove after both environments pass (see below) |

**Pairings (must stay aligned; not changed by `--rotate-crm-internal`):**

- crm `CLIENT_SERVICE_TOKEN` == client `INTERNAL_SERVICE_TOKEN` (`client` key)
- crm `VOIP_GATEWAY_TOKEN` == voip `INTERNAL_TOKEN`
- crm `WHATSAPP_GATEWAY_TOKEN` == whatsapp `INTERNAL_TOKEN`

Normal sync **does not rewrite** either side of gateway pairs (crm `VOIP_GATEWAY_TOKEN` / `WHATSAPP_GATEWAY_TOKEN` or voip/whatsapp `INTERNAL_TOKEN`). Provision or rotate those pairs together out of band so they stay equal. client-service has **no** `CRM_INTERNAL_TOKEN`.

**`--rotate-crm-internal`** updates **only** crm `INTERNAL_SERVICE_TOKEN` and gateway `CRM_INTERNAL_TOKEN` (voip + whatsapp on staging; voip only in production). Run it as a separate invocation after the normal mt_bridge sync.

Webhook: `esafx/<env>/mt-bridge-webhook` → `dealer_webhook` → `DEALER_WEBHOOK_SECRET` on MT host (opt-in).

Staging secret values were created manually; **no** staging Terraform manages those strings.

### After staging and production pass

1. Confirm all callers use per-caller MT tokens (not legacy `mt_bridge`).
2. Delete the `mt_bridge` key from `esafx/staging/service-tokens` and `esafx/production/service-tokens` (console or controlled JSON merge — do not paste values into tickets).
3. **Production Terraform note:** `client`, `pii_vault`, `mt_bridge`, `CLIENT_SERVICE_TOKEN`, and `INTERNAL_SERVICE_TOKEN` in `secrets_kms_eventbridge.tf` still share one `random_password.service_tokens` today. Splitting those into independent passwords is a **later** Terraform task; this runbook only adds distinct keys for `crm_internal` and `mt_bridge_*`.

## Terraform backend (production)

`production/terraform/versions.tf` documents the intended remote backend (commented until configured):

```hcl
# backend "s3" {
#   bucket         = "esafx-terraform-state"
#   key            = "production/terraform.tfstate"
#   region         = "ap-southeast-3"
#   encrypt        = true
#   dynamodb_table = "esafx-terraform-locks"
# }
```

When enabled: state in S3 with `encrypt = true`, locking via DynamoDB. No KMS key is specified in that block (SSE-S3 default unless you add `kms_key_id` later).

---

## Staging rollout

Look up instance IDs by tag (do not commit IDs to git):

```bash
aws ec2 describe-instances --region ap-southeast-3 \
  --filters "Name=tag:Environment,Values=staging" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,PrivateIpAddress]' --output table
```

Set `APP_INSTANCE_ID` / `MT_INSTANCE_ID` for the app compose host and Windows MT host, or configure `APP_INSTANCE_TAG_*` / `MT_INSTANCE_TAG_*` for `apply-mt-bridge-callers-sg.sh` (defaults: `Tier=app-staging`, `Tier=mt-bridge`).

Security group names: `esafx-staging-app-sg`, `esafx-staging-alb-sg`, plus new `esafx-staging-mt-bridge-callers-sg` and `esafx-staging-mt-sg`.

### 1. Confirm secrets (key names only)

```bash
aws secretsmanager get-secret-value --secret-id esafx/staging/service-tokens --region ap-southeast-3 \
  --query SecretString --output text | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"
```

### 2. Sync Linux env files (app EC2)

```bash
cd /opt/esafx
./deploy/staging/sync-service-tokens-env.sh --dry-run
./deploy/staging/sync-service-tokens-env.sh
# Separate step when crm build that enforces crm_internal is live (writes only the three CRM-internal vars):
./deploy/staging/sync-service-tokens-env.sh --rotate-crm-internal
```

Script **exits with error** if required keys are missing, empty, or placeholders (`dev-internal-token`, `changeme`, etc.). Normal sync updates `client` / `mt_bridge_*` / `pii_vault` vars only. Rotation does not touch pairing keys or gateway tokens on crm.

### 3. Recreate containers (avoid 401 window)

After **mt_bridge** sync (no `--rotate-crm-internal`):

```bash
docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api client
```

After **`--rotate-crm-internal`** (crm + both gateways that call crm):

```bash
docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api voip-gateway whatsapp-gateway
```

### 4. MT host — token env (SSM PowerShell)

```powershell
cd C:\esafx\deploy
.\staging\sync-mt-bridge-tokens.ps1 -WhatIf
.\staging\sync-mt-bridge-tokens.ps1
```

Writes `C:\esafx\mt-bridge-service\.env.staging` and copies to `.env`.

### 5. Deploy new mt-bridge build

Use existing SSM/deploy flow (`deploy\ec2-deploy.ps1`).

### 6. Dealer webhook (after new mt-bridge code)

```powershell
.\staging\sync-mt-bridge-tokens.ps1 -IncludeDealerWebhook
# redeploy mt-bridge
```

### 7. Windows firewall (MT host)

```powershell
.\staging\sync-mt-bridge-firewall.ps1 -WhatIf
.\staging\sync-mt-bridge-firewall.ps1
```

Removes `mt-bridge-8003` (any source); keeps staging VPC CIDR on `esafx-mt-bridge-8003`. Idempotent if already done.

### 8. Security groups (last)

Script resolves **RDS security group** from `DB_HOST` in the CRM env file.

```bash
export APP_INSTANCE_ID=<app-host>
export MT_INSTANCE_ID=<mt-host>
./deploy/staging/apply-mt-bridge-callers-sg.sh --dry-run
./deploy/staging/apply-mt-bridge-callers-sg.sh --confirm
```

End state:

- `esafx-staging-mt-bridge-callers-sg` on app instance (with `app-sg`)
- `esafx-staging-mt-sg` on MT instance only; TCP 8003 from callers SG
- RDS allows 5432 from `mt-sg`
- ALB no longer reaches `:8003` on `app-sg`

**Staging cannot** prove “voip blocked, crm allowed” via SG (crm/client/voip share one host). Verify app host → `http://<mt-private-ip>:8003/health` succeeds.

---

## Production rollout (after staging passes)

### 1. Terraform (secrets first, SG last)

```bash
cd deploy/production/terraform
terraform fmt -recursive
terraform validate
terraform plan
```

Apply in two steps if desired:

1. Secret + password changes (review live `service-tokens` JSON drift first).
2. Security group changes after tokens and mt-bridge are deployed.

### 2. Sync Linux env

On **CRM EC2** (low traffic), after mt_bridge sync:

```bash
./deploy/production/sync-service-tokens-env.sh
docker compose -f deploy/production/docker-compose.crm.yml up -d --no-deps --force-recreate crm-api client
```

**`crm_internal` rotation** (no whatsapp in production): run sync with `--rotate-crm-internal` on **both** hosts before recreates, then:

```bash
# CRM EC2
./deploy/production/sync-service-tokens-env.sh --rotate-crm-internal
docker compose -f deploy/production/docker-compose.crm.yml up -d --no-deps --force-recreate crm-api
```

**VoIP 401 window:** crm-api picks up `INTERNAL_SERVICE_TOKEN` from `crm_internal` on the CRM host while voip-gateway still sends the old `CRM_INTERNAL_TOKEN` until the VoIP host is updated. Expect **401s from voip → crm** between the two recreates. Use **low traffic** and run the VoIP step **immediately**:

```bash
# VoIP EC2 (seconds later)
./deploy/production/sync-service-tokens-env.sh --rotate-crm-internal
docker compose -f deploy/production/docker-compose.voip.yml up -d --no-deps --force-recreate voip-gateway
```

### 3. MT Windows host

```powershell
.\production\sync-mt-bridge-tokens.ps1
# deploy mt-bridge
.\production\sync-mt-bridge-tokens.ps1 -IncludeDealerWebhook
.\production\sync-mt-bridge-firewall.ps1
```

### 4. Verify

- From CRM EC2: `curl -sf http://<mt_private_ip>:8003/health`
- From VoIP EC2: same URL should **time out** (callers SG not on voip)

---

## Rollback

| Step | Rollback |
|------|----------|
| Security groups (staging script) | Re-attach `app-sg` to MT instance; remove `mt-sg` from MT; restore ALB `8000-8003` on `app-sg` if needed |
| Security groups (production TF) | Revert Terraform commit; `terraform apply` previous mt-sg ingress source |
| Firewall | Recreate `mt-bridge-8003` only if emergency (break-glass; avoid any-source rule) |
| Tokens | **Roll back mt-bridge application build first** (new build rejects legacy `mt_bridge`). Then re-sync legacy `mt_bridge` into caller env vars and recreate containers together. crm_internal rollback only if matching crm/voip builds are reverted. |
| Webhook | Remove `DEALER_WEBHOOK_SECRET` from MT `.env.staging` / `.env` and redeploy mt-bridge |

Do not delete new secret keys in Secrets Manager during rollback unless you are completing the post-migration cleanup step for `mt_bridge`.
