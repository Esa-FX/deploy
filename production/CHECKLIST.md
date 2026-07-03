# Production deployment checklist

Use this checklist for every production release. Staging should be verified first.

## Before you start

- [ ] Staging smoke-tested (login, pipeline, click-to-call, FTD upload + email)
- [ ] `staging` merged to `main` in all changed service repos
- [ ] AWS CLI + `gh` authenticated
- [ ] Terraform state current (`deploy/production/terraform`)

## 1. Infrastructure (Terraform)

```bash
cd deploy/production/terraform
terraform init
terraform plan
terraform apply   # if ftd_uploads or call_recordings bucket missing
```

Save outputs:

```bash
terraform output -raw ftd_uploads_bucket_name
terraform output -raw call_recordings_bucket_name
terraform output -raw voip_elastic_ip
terraform output -raw core_ec2_private_ip
terraform output -raw voip_ec2_private_ip
terraform output -raw mt_ec2_private_ip
terraform output -raw crm_frontend_bucket_name
terraform output -raw cloudfront_distribution_id
```

- [ ] FTD uploads bucket exists (`esafx-production-ftd-uploads-*`)
- [ ] Call recordings bucket exists
- [ ] VoIP Elastic IP given to PBX vendor for whitelist

## 2. Environment files (SSM into each EC2)

### CRM EC2 — `crm-service/.env.production`

Copy from staging `.env.staging` where values are **identical** (SMTP, same mail provider). Set production-specific:

| Variable | Source |
|----------|--------|
| `S3_FTD_UPLOADS_BUCKET` | `terraform output ftd_uploads_bucket_name` |
| `S3_RECORDINGS_BUCKET` | `terraform output call_recordings_bucket_name` |
| `VOIP_GATEWAY_URL` | `http://<voip_ec2_private_ip>:8006` |
| `VOIP_GATEWAY_TOKEN` | Secrets Manager `esafx/production/service-tokens` → `client` |
| `IDENTITY_SERVICE_URL` | `http://<core_ec2_private_ip>:8000` |
| `PII_VAULT_SERVICE_URL` | `http://<core_ec2_private_ip>:8004` |
| `AUDIT_LOG_SERVICE_URL` | `http://<core_ec2_private_ip>:8005` |
| `MT_BRIDGE_SERVICE_URL` | `http://<mt_ec2_private_ip>:8003` |
| `SMTP_*`, `FTD_NOTIFY_TO` | Same as staging |

Or run on CRM EC2 after `.env.production` exists:

```bash
./deploy/production/sync-service-tokens-env.sh
./deploy/production/sync-smtp-env.sh   # if esafx/production/smtp secret exists
```

Template: [`crm-service/.env.production.example`](../../crm-service/.env.production.example)

### VoIP EC2 — `voip-gateway-service/.env.production`

Copy **AMI/SFTP block exactly from staging** (same PBX). Change only:

| Variable | Production value |
|----------|------------------|
| `S3_RECORDINGS_BUCKET` | production call recordings bucket |
| `PII_VAULT_SERVICE_URL` | `http://<core_ip>:8004` |
| `AUDIT_LOG_SERVICE_URL` | `http://<core_ip>:8005` |
| `INTERNAL_TOKEN` | same as `VOIP_GATEWAY_TOKEN` on CRM |

```bash
./deploy/production/sync-service-tokens-env.sh
```

Template: [`voip-gateway-service/.env.production.example`](../../voip-gateway-service/.env.production.example)

### Staff VoIP extensions

Each sales user needs `voip_extension` in identity DB. See [`identity-service/docs/production-deploy.md`](../../identity-service/docs/production-deploy.md).

- [ ] CRM `.env.production` has `S3_FTD_UPLOADS_BUCKET`, `VOIP_GATEWAY_TOKEN`, `SMTP_ENABLED=true`
- [ ] VoIP `.env.production` has `VOIP_PROVIDER=asterisk-ami` + full AMI/SFTP (not `mock`)
- [ ] `VOIP_GATEWAY_TOKEN` (crm) = `INTERNAL_TOKEN` (voip)

## 3. Deploy backend tiers (order matters)

On each host: `cd /opt/esafx && git pull origin main`

```bash
# Core EC2
./deploy/production/deploy-core-ec2.sh

# VoIP EC2
./deploy/production/deploy-voip-ec2.sh

# MT Windows EC2 (if needed)
# powershell -File deploy/production/bootstrap-mt-ec2.ps1

# CRM EC2
./deploy/production/deploy-crm-ec2.sh
```

- [ ] `curl http://127.0.0.1:8000/health` on core
- [ ] `curl http://127.0.0.1:8006/health` on voip
- [ ] `curl http://127.0.0.1:8001/health` on crm

## 4. CRM frontend (S3 + CloudFront)

From laptop:

```bash
cd crm
npm ci
npx vite build
aws s3 sync dist/ s3://$(terraform output -raw crm_frontend_bucket_name)/ \
  --delete --cache-control "public, max-age=31536000, immutable" --exclude "index.html"
aws s3 cp dist/index.html s3://$(terraform output -raw crm_frontend_bucket_name)/index.html \
  --cache-control "no-cache, no-store, must-revalidate"
aws cloudfront create-invalidation \
  --distribution-id $(cd ../deploy/production/terraform && terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

Template: [`crm/.env.production.example`](../../crm/.env.production.example)

- [ ] `VITE_USE_MOCKS=false`
- [ ] Cognito redirect URLs match `crm.esandardev.com`

## 5. Data (first production cutover only)

- [ ] Staff import: `deploy/production/run-staff-import.sh`
- [ ] VoIP extensions assigned per user
- [ ] Legacy CSV: `crm-service/docs/legacy-csv-import.md`

## 6. Smoke tests

| Test | Expected |
|------|----------|
| Login at https://crm.esandardev.com | Success, no redirect loop |
| Open pipeline / leads | Data loads |
| Click-to-call on lead | **User stays logged in**; call initiates |
| FTD form + attachment | Object in S3 `ftd/deposit_proof/...` |
| FTD submit email | `ftd_form_history.email_sent` in DB |
| WebSocket / notifications | Connected |

## 7. Rollback

- Revert `git pull` on EC2 to previous commit and re-run tier deploy script
- Redeploy previous frontend build from S3 versioning (if enabled) or rebuild from prior git tag

## Related docs

- [ENV-PARITY.md](./ENV-PARITY.md) — staging vs production variable matrix
- [README.md](./README.md) — architecture and Terraform
- Per-service: `*/docs/production-deploy.md`
