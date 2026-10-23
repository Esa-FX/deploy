output "web_acl_arn" {
  description = "Regional web ACL ARN (associate additional pools by adding ARNs and re-applying)."
  value       = aws_wafv2_web_acl.cognito.arn
}

output "web_acl_id" {
  description = "Web ACL ID."
  value       = aws_wafv2_web_acl.cognito.id
}

output "associated_user_pool_arns" {
  description = "User pools this ACL is associated with."
  value       = [for a in aws_wafv2_web_acl_association.cognito : a.resource_arn]
}
