variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Globally unique name for the demo S3 bucket used by Developers and the EC2 role"
  type        = string
  # Set your own value in terraform.tfvars, e.g.: s3_bucket_name = "yourname-iam-unit2-demo"
}
