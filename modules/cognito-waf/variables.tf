variable "name" {
  description = "Web ACL name (also used as CloudWatch metric prefix). Must be unique per region."
  type        = string
}

variable "user_pool_arns" {
  description = "Cognito user pool ARNs to associate. One ACL per environment; add ARNs for new pools."
  type        = list(string)

  validation {
    condition     = length(var.user_pool_arns) > 0
    error_message = "Provide at least one Cognito user pool ARN."
  }
}

variable "rate_limit_per_ip" {
  description = "Block an IP after this many requests in the evaluation window (all public Cognito ops)."
  type        = number
  default     = 2000
}

variable "rate_limit_sensitive_per_ip" {
  description = "Block an IP after this many ForgotPassword/SignUp/ResendConfirmationCode requests."
  type        = number
  default     = 80
}

variable "rate_limit_global" {
  description = "Block after this many requests from all IPs combined (volumetric backstop)."
  type        = number
  default     = 10000
}

variable "evaluation_window_sec" {
  description = "Rate-limit window in seconds (AWS allows 60, 120, 300, 600)."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags applied to the web ACL."
  type        = map(string)
  default     = {}
}
