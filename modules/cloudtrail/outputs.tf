output "trail_arn" {
  description = "ARN of the organization trail."
  value       = aws_cloudtrail.org.arn
}

output "bucket_name" {
  description = "S3 bucket holding CloudTrail log files."
  value       = aws_s3_bucket.trail.bucket
}
