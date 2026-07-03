# Staging vs production environment parity

Production should behave like staging with **only infrastructure identifiers changed**. Application config (VoIP vendor, SMTP provider) stays the same.

## Identical across environments (copy from staging)

| Area | Variables / settings |
|------|---------------------|
| VoIP PBX | `VOIP_PROVIDER=asterisk-ami`, all `AMI_*`, all `SFTP_*` |
| SMTP | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `FTD_NOTIFY_TO` |
| Issabel style | `AMI_ORIGINATE_STYLE=issabel`, `AMI_CHANNEL_TECH=SIP`, `AMI_LEAD_PHONE_FORMAT=id_local` |
| Recording fetch | `AMI_RECORDING_FETCH=sftp-glob`, `AMI_RECORDING_PATH`, timezone `Asia/Jakarta` |

## Different per environment

| Variable | Staging | Production |
|----------|---------|------------|
| `ENVIRONMENT` | `staging` | `production` |
| Cognito pool / client | `ap-southeast-3_diSA1PdqG` / `3pm8c13n...` | `ap-southeast-3_Oxz4wxhRL` / `5pm21ljg...` |
| CRM URL | `crm.staging.esandardev.com` | `crm.esandardev.com` |
| API URL | `api.staging.esandardev.com` | `api.esandardev.com` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| `S3_FTD_UPLOADS_BUCKET` | `esafx-staging-ftd-uploads-*` | `esafx-production-ftd-uploads-*` |
| `S3_RECORDINGS_BUCKET` | `esafx-staging-call-recordings-*` | `esafx-production-call-recordings-*` |
| Secrets Manager prefix | `esafx/staging/*` | `esafx/production/*` |
| VoIP topology | voip on same app EC2 (`http://voip-gateway:8006`) | dedicated voip EC2 (private IP `:8006`) |
| VoIP whitelist IP | staging EC2 public IP | `terraform output voip_elastic_ip` |

## Token pairing (critical)

These must always match within an environment:

| CRM (`crm-service`) | VoIP (`voip-gateway-service`) | Source |
|-------------------|-------------------------------|--------|
| `VOIP_GATEWAY_TOKEN` | `INTERNAL_TOKEN` | `service-tokens` secret → `client` key |

Sync scripts set both automatically:

- Staging: `deploy/staging/sync-service-tokens-env.sh`
- Production: `deploy/production/sync-service-tokens-env.sh`

**Mismatch symptom:** click-to-call returns 401 and may log the user out (fixed in CRM SPA for upstream token errors; still fix the token).

## S3 buckets

| Bucket purpose | Terraform (staging) | Terraform (production) |
|----------------|-------------------|------------------------|
| FTD attachments | `deploy/staging/terraform/ftd-uploads.tf` | `deploy/production/terraform/s3.tf` |
| Call recordings | `deploy/staging/terraform/call-recordings.tf` | `deploy/production/terraform/s3.tf` |
| CRM frontend | staging frontend bucket | `crm_frontend_bucket_name` output |

CRM EC2 IAM needs `s3:PutObject`/`GetObject` on `ftd/*` prefix. VoIP EC2 needs `s3:PutObject` on `recordings/*`.

## Env file templates

| Service | Staging | Production |
|---------|---------|------------|
| crm-api | `.env.staging.example` | `.env.production.example` |
| voip-gateway | `.env.staging.example` | `.env.production.example` |
| CRM SPA | `.env.staging.example` | `.env.production.example` |

## Bootstrap scripts

`deploy/production/bootstrap-linux-ec2.sh` writes:

- CRM: `S3_FTD_UPLOADS_BUCKET`, `VOIP_GATEWAY_TOKEN`, `S3_RECORDINGS_BUCKET`
- VoIP: `INTERNAL_TOKEN`, recordings bucket (AMI vars must be copied from staging manually)

SMTP is **not** in bootstrap — copy from staging or use `sync-smtp-env.sh` when Secrets Manager secret exists.
