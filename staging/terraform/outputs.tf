output "call_recordings_bucket_name" {
  description = "S3 bucket for VoIP call recordings — set as S3_RECORDINGS_BUCKET on voip-gateway and crm-api"
  value       = aws_s3_bucket.call_recordings.bucket
}

output "call_recordings_bucket_arn" {
  description = "ARN of the call recordings bucket"
  value       = aws_s3_bucket.call_recordings.arn
}

output "call_recordings_prefix" {
  description = "Object key prefix for recordings — set as S3_RECORDINGS_PREFIX on voip-gateway"
  value       = local.recordings_prefix
}
