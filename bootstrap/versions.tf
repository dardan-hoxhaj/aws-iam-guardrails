terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bootstrap stack keeps its state on your laptop (terraform.tfstate,
  # git-ignored). It creates the S3 bucket that every other stack uses for
  # remote state, so it cannot store its own state there before it exists.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
