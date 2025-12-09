variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "source_bucket" {
  description = "Source S3 bucket name for JSON files (will be created if it doesn't exist)"
  type        = string
  default     = "fhir-lca-persist"
}

variable "target_bucket" {
  description = "Target S3 bucket name for Parquet files (will be created if it doesn't exist)"
  type        = string
  default     = "fhir-ingest-analytics"
}

variable "create_buckets" {
  description = "Create S3 buckets if they don't exist. Set to false if buckets already exist."
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy S3 buckets even if they contain objects. Set to true for dev/test environments."
  type        = bool
  default     = true
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning. Disable to reduce costs. Not required for this use case."
  type        = bool
  default     = false
}

variable "s3_filter_prefix" {
  description = "S3 key prefix filter for notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "lambda_zip_path" {
  description = "Path to Lambda function ZIP file"
  type        = string
  default     = "../lambda_function.zip"
}

variable "lambda_layer_zip_path" {
  description = "Path to Lambda layer ZIP file (awswrangler). Leave empty to use AWS public layer."
  type        = string
  default     = ""
}

variable "use_aws_public_layer" {
  description = "Use AWS public awswrangler layer instead of custom layer"
  type        = bool
  default     = true
}

variable "create_ssm_parameters" {
  description = "Create SSM parameters for bucket configuration. Set to false if you lack SSM permissions."
  type        = bool
  default     = false
}

variable "glue_database_name" {
  description = "Glue database name"
  type        = string
  default     = "fhir_analytics"
}

variable "glue_table_name" {
  description = "Glue table name"
  type        = string
  default     = "fhir_ingest_analytics"
}

variable "glue_partition_sources" {
  description = "List of source values for partition projection"
  type        = list(string)
  default     = ["lca-persist", "dxa-persist"]
}

variable "glue_partition_date_start" {
  description = "Start date for partition projection (YYYY-MM-DD)"
  type        = string
  default     = "2025-01-01"
}

