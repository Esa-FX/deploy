# MT bridge hardening (per-caller tokens, callers SG, firewall)

Deploy-repo changes for EsaFX mt-bridge security: separate service tokens per caller, dedicated MT security group, Windows firewall tightening, optional dealer webhook secret.

**Prerequisites:** Application PRs deployed that read `MT_BRIDGE_TOKEN_*`, per-caller `MT_BRIDGE_SERVICE_TOKEN` on crm/client, `crm_internal` on crm `INTERNAL_SERVICE_TOKEN`, and fail-closed dealer webhook when `DEALER_WEBHOOK_SECRET` is set.

Never log secret values. Do not pass secrets in SSM command parameters.

## Secret keys (`esafx/<env>/service-tokens`)

| Key | Used by |
|-----|---------|
| `client` | `CLIENT_SERVICE_TOKEN` (crm → client), `INTERNAL_SERVICE_TOKEN` (client), `INTERNAL_TOKEN` (voip/whatsapp → client) |
| `crm_internal` | `INTERNAL_SERVICE_TOKEN` (crm-api), `CRM_INTERNAL_TOKEN` (client, voip-gateway, whatsapp-gateway → crm) |
| `mt_bridge_crm` | crm-api `MT_BRIDGE_SERVICE_TOKEN` |
| `mt_bridge_client` | client-service `MT_BRIDGE_SERVICE_TOKEN` |
| `mt_bridge_admin` | MT host `MT_BRIDGE_TOKEN_ADMIN` |
| `mt_bridge` | Legacy shared token (keep until all callers migrated) |

Webhook: `esafx/<env>/mt-bridge-webhook` → `dealer_webhook` → `DEALER_WEBHOOK_SECRET` on MT host (opt-in).

Staging secret values were created manually; **no** staging Terraform manages those strings.

---

## Staging rollout

Hosts:

- App (all compose services): `i-06e3745274ed0fac4`, `esafx-staging-app-sg`
- MT Windows: `i-082a9df5e269d8ae5` (`10.0.1.75`)

### 1. Confirm secrets (key names only)

```bash
aws secretsmanager get-secret-value --secret-id esafx/staging/service-tokens --region ap-southeast-3 \
  --query SecretString --output text | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"
aws secretsmanager get-secret-value --secret-id esafx/staging/mt-bridge-webhook --region ap-southeast-3 \
  --query SecretString --output text | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"
```

### 2. Sync Linux env files (app EC2)

```bash
cd /opt/esafx
./deploy/staging/sync-service-tokens-env.sh --dry-run
./deploy/staging/sync-service-tokens-env.sh
```

Script **exits with error** if `crm_internal` or `mt_bridge_*` keys are missing/empty or `dev-internal-token`.

### 3. Recreate callers together (avoid 401 window)

After **all** env files are written:

```bash
docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api client voip-gateway
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

Removes `mt-bridge-8003` (any source); keeps VPC `10.0.0.0/16` on `esafx-mt-bridge-8003`. Idempotent if already done.

### 8. Security groups (last)

Script resolves **RDS security group** from `DB_HOST` in `/opt/esafx/crm-service/.env.staging`.

```bash
./deploy/staging/apply-mt-bridge-callers-sg.sh --dry-run
./deploy/staging/apply-mt-bridge-callers-sg.sh --confirm
```

End state:

- `esafx-staging-mt-bridge-callers-sg` on app instance (with `app-sg`)
- `esafx-staging-mt-sg` on MT instance only; TCP 8003 from callers SG
- RDS allows 5432 from `mt-sg`
- ALB no longer reaches `:8003` on `app-sg`

**Staging cannot** prove “voip blocked, crm allowed” via SG (crm/client/voip share one host). Verify app host → `http://10.0.1.75:8003/health` succeeds.

---

## Production rollout (after staging passes)

### 1. Terraform (secrets first, SG last)

```bash
cd deploy/production/terraform
terraform fmt -recursive
terraform validate
terraform plan   # expect: new passwords, webhook secret, callers SG, mt-sg 8003 source change, core+crm SG attachment — no instance replacement
```

Apply in two steps if desired:

1. Apply secret + password changes only (review `service-tokens` JSON drift first).
2. Apply security group changes after callers run new tokens and mt-bridge is deployed.

### 2. Sync Linux env

On **CRM EC2**:

```bash
./deploy/production/sync-service-tokens-env.sh
docker compose -f deploy/production/docker-compose.crm.yml up -d --no-deps --force-recreate crm-api client
```

On **VoIP EC2** immediately after:

```bash
./deploy/production/sync-service-tokens-env.sh
docker compose -f deploy/production/docker-compose.voip.yml up -d --no-deps --force-recreate voip-gateway
```

### 3. MT Windows host

```powershell
.\production\sync-mt-bridge-tokens.ps1
# deploy mt-bridge
.\production\sync-mt-bridge-tokens.ps1 -IncludeDealerWebhook
.\production\sync-mt-bridge-firewall.ps1   # VPC 10.1.0.0/16
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
| Firewall | Recreate `mt-bridge-8003` only if emergency (documented break-glass; avoid leaving any-source rule) |
| Tokens | Re-sync from legacy `mt_bridge` + old `client` for `INTERNAL_SERVICE_TOKEN` only if old app builds still running; recreate containers together |
| Webhook | Remove `DEALER_WEBHOOK_SECRET` from MT `.env.staging` / `.env` and redeploy mt-bridge |

Do not delete new secret keys in Secrets Manager during rollback.
