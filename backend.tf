terraform {
  backend "s3" {
    bucket = "999757602161-us-east-1-tfstate"
    key    = "terraform/tfstate/poc.tfstat"
    region = "us-east-1"
  }
}