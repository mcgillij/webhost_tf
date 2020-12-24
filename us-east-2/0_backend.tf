terraform {
  backend "s3" {
    bucket         = "mcgillij-dev-tf-state"
    region         = "us-east-2"
    key            = "mcgillij-dev/terraform.tfstate"
    dynamodb_table = "mcgillij_dev_lock_ohio"
  }
}

provider "aws" {
  region = "us-east-2"
}
