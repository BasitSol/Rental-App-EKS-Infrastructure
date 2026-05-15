terraform {
  backend "s3" {
    bucket         = "rentalapp-terraform-state-eks-prod"
    key            = "environments/eks-production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "rentalapp-terraform-locks"
  }
}