output "state_bucket_name" {
  description = "Put this in the TF_STATE_BUCKET GitHub variable and in live/backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Put this in the AWS_PLAN_ROLE_ARN GitHub secret."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Put this in the AWS_APPLY_ROLE_ARN GitHub secret."
  value       = aws_iam_role.apply.arn
}
