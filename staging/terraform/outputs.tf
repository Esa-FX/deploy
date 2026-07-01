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

output "ftd_uploads_bucket_name" {
  description = "S3 bucket for FTD form attachments — set as S3_FTD_UPLOADS_BUCKET on crm-api"
  value       = aws_s3_bucket.ftd_uploads.bucket
}

output "ftd_uploads_bucket_arn" {
  description = "ARN of the FTD uploads bucket"
  value       = aws_s3_bucket.ftd_uploads.arn
}

output "ftd_uploads_prefix" {
  description = "Object key prefix for FTD uploads (deposit_proof, chat_evidence under ftd/)"
  value       = local.ftd_uploads_prefix
}
