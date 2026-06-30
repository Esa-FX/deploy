# Staging Terraform — call recordings

Provisions the S3 bucket and app EC2 IAM policy for VoIP call recording ingest + CRM playback.

## Apply

```bash
cd deploy/staging/terraform
terraform init
terraform apply
```

## Outputs (env staging)

After apply, set on **voip-gateway** and **crm-api** `.env.staging`:

```bash
terraform output -raw call_recordings_bucket_name
# → use as S3_RECORDINGS_BUCKET

terraform output -raw call_recordings_prefix
# → use as S3_RECORDINGS_PREFIX (voip-gateway only)
```

```env
S3_RECORDINGS_BUCKET=<call_recordings_bucket_name output>
S3_RECORDINGS_PREFIX=recordings
AWS_REGION=ap-southeast-3
```

IAM is attached to `esafx-staging-ec2-app-role` (override with `-var app_ec2_role_name=...` if different).
