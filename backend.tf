# This is a Cloudflare R2 bucket, not AWS
# export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY with the Cloudflare creds
#
terraform {
  backend "s3" {
    bucket = "31fcea5432d93058-bucket-tfstate"
    key    = "terraform.tfstate"
    endpoints = {
      s3 = "https://ac5ad90cf6f83abc85ee304a2bb2de73.r2.cloudflarestorage.com"
    }
    region = "us-east-1"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
