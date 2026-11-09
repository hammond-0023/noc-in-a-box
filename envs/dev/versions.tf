terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
  }

  # Bucket and region are supplied at init time:
  #   terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<region>"
  backend "s3" {
    key          = "dev/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "noc-in-a-box"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

# Keys come from GitHub Actions secrets (TF_VAR_datadog_api_key / _app_key).
provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}
