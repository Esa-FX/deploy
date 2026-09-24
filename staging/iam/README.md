# Staging deploy IAM (developer laptop)

Least-privilege IAM for staging deploy from a developer laptop:

- **SSM** `SendCommand` / poll on staging app + MT EC2
- **Session Manager** (optional shell on staging instances)
- **S3 + CloudFront** for CRM and client area staging frontends
- **S3 bucket CORS** on the two staging frontend buckets (see below)

Secrets (`esafx/staging/github-clone`, etc.) are read **on EC2** by the instance role during SSM deploy scripts — not on the laptop.

## Staging targets

| Resource | ID / name |
|----------|-----------|
| App EC2 | `i-06e3745274ed0fac4` |
| MT EC2 | `i-082a9df5e269d8ae5` |
| CRM S3 | `esafx-crm-frontend-staging-612524168745` |
| Client S3 | `esafx-client-frontend-staging-612524168745` |
| CRM CloudFront | `E2BJOY6OD647ND` |
| Client CloudFront | `EB6R1I9TRV3B6` |

## Create user (one-time, admin credentials)

```bash
cd deploy/staging/iam

aws iam create-user --user-name figo0703

aws iam create-policy \
  --policy-name EsaFXStagingDeployFigo0703 \
  --policy-document file://figo0703-staging-deploy-policy.json

aws iam attach-user-policy \
  --user-name figo0703 \
  --policy-arn arn:aws:iam::612524168745:policy/EsaFXStagingDeployFigo0703

aws iam create-access-key --user-name figo0703
```

Store the access key secret securely; it is shown only once.

## Update policy (admin — required before CORS apply)

`figo0703` cannot publish a new IAM policy version. After merging changes to `figo0703-staging-deploy-policy.json`, an admin with `iam:CreatePolicyVersion` (or equivalent) must install the updated document on `EsaFXStagingDeployFigo0703`:

```bash
cd deploy/staging/iam

POLICY_ARN="arn:aws:iam::612524168745:policy/EsaFXStagingDeployFigo0703"

aws iam create-policy-version \
  --policy-arn "$POLICY_ARN" \
  --policy-document file://figo0703-staging-deploy-policy.json \
  --set-as-default
```

If AWS returns `LimitExceeded` (five versions), delete the oldest non-default version, then retry:

```bash
aws iam list-policy-versions --policy-arn "$POLICY_ARN"
aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id vN
```

Wait a minute for IAM propagation, then confirm `figo0703` can call `get-bucket-cors` (see smoke tests).

## Apply frontend bucket CORS

CORS rules live in `frontend-buckets-cors.json` (allowed origins: `https://crm.staging.esandardev.com`, `https://my.staging.esandardev.com`). Apply to **both** staging frontend buckets only:

```bash
cd deploy/staging/iam
chmod +x apply-frontend-bucket-cors.sh
./apply-frontend-bucket-cors.sh
```

Uses `AWS_PROFILE` (default `figo0703`) and `AWS_REGION` (default `ap-southeast-3`). The script runs `put-bucket-cors` then `get-bucket-cors` for each bucket.

**CloudFront note:** Users normally load the SPAs via CloudFront hostnames, not the S3 REST endpoint. S3 bucket CORS does not add `Access-Control-*` headers to CloudFront responses unless CloudFront is configured to forward `Origin` and emit CORS headers (e.g. response headers policy). If browser errors persist on the CloudFront URL after S3 CORS is applied, fix CloudFront separately; this repo change only sets S3 bucket CORS.

## Configure CLI (Figo's machine)

```bash
aws configure --profile figo0703
# Access Key ID / Secret from create-access-key
# Region: ap-southeast-3
# Output: json
```

## Smoke tests

```bash
aws sts get-caller-identity --profile figo0703
aws ssm describe-instance-information --region ap-southeast-3 --profile figo0703
aws s3 ls s3://esafx-crm-frontend-staging-612524168745/ --profile figo0703
aws s3api get-bucket-cors \
  --bucket esafx-crm-frontend-staging-612524168745 \
  --profile figo0703 --region ap-southeast-3
```

## Deploy examples

**Backend (SSM):** from monorepo root, use existing JSON under `deploy/staging/`:

```bash
aws ssm send-command --region ap-southeast-3 --profile figo0703 \
  --cli-input-json file://deploy/staging/ssm-deploy-ftd-backend.json
```

**Frontend:** see skills `deploy-crm-frontend` and `deploy-client-frontend` (add `--profile figo0703`).

## Rotate / revoke

```bash
aws iam list-access-keys --user-name figo0703
aws iam delete-access-key --user-name figo0703 --access-key-id <KEY_ID>
aws iam create-access-key --user-name figo0703
```
