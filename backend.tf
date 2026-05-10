terraform {
  backend "s3" {
    encrypt = true
    bucket  = "arcadebox-prod-terraform-state"
    key     = "arcadesbox/test/terraform.tfstate"
    region  = "us-east-1"
    # dynamodb_table = "arcadesbox-prod-terraform-locks"
    use_lockfile = true
  }
}

