# Production Docmost EC2 + ALB host rule

Dedicated wiki is **production**: `https://wiki.esandardev.com` → hover graph (nginx :8080).
Docmost remains on the instance :3000 with no public hostname.

Content still compares **staging vs main** git branches (coverage flags). Infra is not a staging stack.

Isolated terraform state from `deploy/production/terraform` (core VPC). Data sources attach to existing prod VPC + ALB.

Requires Terraform >= 1.6. This stack has no `backend` block, so state is local. State files must never be committed (`*.tfstate`, `*.tfstate.*`, `.terraform/`, `*.tfplan` are gitignored). A plan that wants to create resources that already exist means the wrong state was used, so stop.

The wiki ALB listener rule authenticates with the production Cognito app client named `esafx-wiki-alb` before forwarding to the wiki target group; plan should show an in-place update of `aws_lb_listener_rule.wiki`, not a new rule or a destroy.

```bash
cd deploy/production/terraform-docmost
terraform init
terraform plan
terraform apply
```

Then: `bash deploy/production/ssm-send-docmost.sh`
