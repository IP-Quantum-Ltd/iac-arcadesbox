terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "rgt-terraform-tfstate"
    key            = "chareli/test/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "chareli-lock"
  }
}

