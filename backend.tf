# terraform {
#   backend "s3" {
#     bucket = "zenobi-terraform-bucket"
#     key    = "environments2"
#     region = "us-east-1"
#     dynamodb_table = "zenobi-terraform-eks-state-lock"
#     encrypt = true
#   }
# }