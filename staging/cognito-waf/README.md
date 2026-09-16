# Staging Cognito WAF

Protects existing staging user pools (CRM staff + backoffice) with the shared `modules/cognito-waf` ACL.

Does **not** attach to `esafx-staging-clients` (public signup — different rate limits).

## Apply

```bash
cd deploy/staging/cognito-waf
terraform init
terraform plan
terraform apply
```

Isolated state — will not touch `staging/terraform` S3 buckets.

## Future pool

Append the pool ID to `user_pool_ids` in `terraform.tfvars`, then `terraform apply`.
