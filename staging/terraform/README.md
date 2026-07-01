# Staging Terraform — call recordings & FTD uploads

Provisions S3 buckets and app EC2 IAM policies for:

- VoIP call recording ingest + CRM playback
- FTD form attachment uploads (deposit proof, chat evidence)

## Apply

```bash
cd deploy/staging/terraform
terraform init
terraform apply
```

## Outputs (env staging)

After apply, set on **crm-api** `.env.staging`:

```bash
terraform output -raw call_recordings_bucket_name
# → S3_RECORDINGS_BUCKET

terraform output -raw ftd_uploads_bucket_name
# → S3_FTD_UPLOADS_BUCKET
```

```env
S3_RECORDINGS_BUCKET=<call_recordings_bucket_name output>
S3_RECORDINGS_PREFIX=recordings
S3_FTD_UPLOADS_BUCKET=<ftd_uploads_bucket_name output>
AWS_REGION=ap-southeast-3
```

VoIP gateway also needs `S3_RECORDINGS_BUCKET` and `S3_RECORDINGS_PREFIX`.

When `S3_FTD_UPLOADS_BUCKET` is set, uploads go to `ftd/deposit_proof/...` and `ftd/chat_evidence/...` in that bucket. If unset (local dev), files land under `FTD_LOCAL_UPLOAD_DIR` (default `/tmp/ftd-uploads`).

IAM is attached to `esafx-staging-ec2-app-role` (override with `-var app_ec2_role_name=...` if different).
