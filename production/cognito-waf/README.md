# Production Cognito WAF

Same module as staging. Protects `esafx-production-staff`. Apply only when asked — staging is applied first.

```bash
cd deploy/production/cognito-waf
terraform init
terraform plan
terraform apply
```

Future pool: append ID to `user_pool_ids` in `terraform.tfvars`.
