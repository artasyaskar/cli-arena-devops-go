output "s3_bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.data_bucket.arn
}

output "iam_role_name" {
  description = "Name of the created IAM role"
  value       = aws_iam_role.app_role.name
}

output "iam_role_arn" {
  description = "ARN of the created IAM role"
  value       = aws_iam_role.app_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the created IAM instance profile"
  value       = aws_iam_instance_profile.app_instance_profile.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the created IAM instance profile"
  value       = aws_iam_instance_profile.app_instance_profile.arn
}

output "bucket_suffix_hex" {
  description = "Random hex suffix for the bucket name (for verification)"
  value       = random_id.bucket_suffix.hex
}
