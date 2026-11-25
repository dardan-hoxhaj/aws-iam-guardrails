# IAM Access Analyzer, organization zone of trust.
# It reads resource policies (S3, KMS, IAM role trust, etc.) and reports
# anything that grants access to a principal OUTSIDE the organization.
# External-access analysis is free. Unused-access analysis is paid and is
# deliberately not enabled here.

resource "aws_accessanalyzer_analyzer" "this" {
  analyzer_name = "${var.name_prefix}-org-external-access"
  type          = "ORGANIZATION"
}
