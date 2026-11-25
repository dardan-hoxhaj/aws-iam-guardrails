output "analyzer_arn" {
  description = "ARN of the organization analyzer."
  value       = aws_accessanalyzer_analyzer.this.arn
}
