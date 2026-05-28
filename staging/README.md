# Staging deploy (EC2)

Deploy order matches [architecture.md](../../architecture.md) §11 and the EC2 staging plan.

## 1. Provision AWS

```bash
cd infra/staging/terraform
terraform apply
```

Record `mt_ec2_private_ip`, RDS endpoints, Cognito IDs, and Secrets Manager paths from outputs.

## 2. Configure `.env.staging` per service

Copy each `*.env.staging.example` → `.env.staging` and fill from Terraform outputs + Secrets Manager:

| Service | File |
|---------|------|
| identity | `identity-service/.env.staging` |
| pii-vault | `pii-vault-service/.env.staging` |
| crm-api | `crm-service/.env.staging` |
| client | `client-service/.env.staging` |
| mt-bridge | `mt-bridge-service/.env.staging` |
| CRM build | `crm/.env.staging` |

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

## 4. MT EC2

```bash
./deploy/staging/deploy-mt-ec2.sh
```

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
