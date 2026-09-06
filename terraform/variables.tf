variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "employee-etl"
}

variable "data_lake_bucket_name" {
  description = "Globally-unique S3 bucket name for the data lake. Must be set explicitly - bucket names are global."
  type        = string
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications via SNS"
  type        = string
}
