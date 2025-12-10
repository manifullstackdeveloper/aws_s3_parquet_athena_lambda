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

variable "s3_retention_days" {
  description = "Number of days to retain files in S3 buckets before deletion. Set to 0 to disable retention policy (keep files indefinitely)."
  type        = number
  default     = 0
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

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup for queries"
  type        = string
  default     = "fhir-analytics"
}

variable "athena_results_retention_days" {
  description = "Number of days to retain Athena query results in S3. Set to 0 to disable retention policy (keep results indefinitely)."
  type        = number
  default     = 30
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB (128-10240, must be multiple of 64)"
  type        = number
  default     = 512
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (0 = no limit, set to limit concurrent executions for cost control)"
  type        = number
  default     = 10
}

variable "error_rate_threshold" {
  description = "Error rate threshold for CloudWatch alarms (number of errors per period)"
  type        = number
  default     = 5
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications (leave empty to disable email alerts)"
  type        = string
  default     = ""
}

variable "enable_staleness_alarm" {
  description = "Enable alarm for no invocations in 24 hours (staleness check)"
  type        = bool
  default     = false
}

variable "enable_sns_alerts" {
  description = "Enable SNS topic creation for CloudWatch alarms. Set to false if you don't have SNS permissions or want to use existing topics."
  type        = bool
  default     = false
}

variable "create_athena_workgroup" {
  description = "Create Athena workgroup. Set to false if workgroup already exists (use 'terraform import' to import existing workgroup instead)."
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch metric alarms for Lambda monitoring. Set to false if you don't have CloudWatch PutMetricAlarm permissions."
  type        = bool
  default     = false
}

