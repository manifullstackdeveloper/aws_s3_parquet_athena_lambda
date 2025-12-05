# ============================================================================
# Terraform Outputs
# ============================================================================

# Lambda Outputs
output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.analytics_lambda.arn
}

output "lambda_layer_arn" {
  description = "ARN of the Lambda layer being used"
  value       = local.layer_arn
}

output "using_aws_public_layer" {
  description = "Whether AWS public layer is being used"
  value       = var.use_aws_public_layer
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.analytics_lambda.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# Glue Outputs
output "glue_database_name" {
  description = "Glue database name"
  value       = aws_glue_catalog_database.fhir_analytics.name
}

output "glue_table_name" {
  description = "Glue table name"
  value       = aws_glue_catalog_table.fhir_ingest_analytics.name
}

output "glue_table_location" {
  description = "S3 location for Glue table"
  value       = aws_glue_catalog_table.fhir_ingest_analytics.storage_descriptor[0].location
}

# S3 Outputs
output "source_bucket" {
  description = "Source S3 bucket for JSON files"
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "ARN of source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "target_bucket" {
  description = "Target S3 bucket for Parquet files"
  value       = aws_s3_bucket.target.id
}

output "target_bucket_arn" {
  description = "ARN of target S3 bucket"
  value       = aws_s3_bucket.target.arn
}

# Query Examples
output "athena_query_examples" {
  description = "Example Athena queries to run"
  value = <<-EOT
  
  # Example Athena Queries:
  
  # 1. Count all records
  SELECT COUNT(*) FROM ${aws_glue_catalog_database.fhir_analytics.name}.${aws_glue_catalog_table.fhir_ingest_analytics.name};
  
  # 2. Count by source
  SELECT source, COUNT(*) as total 
  FROM ${aws_glue_catalog_database.fhir_analytics.name}.${aws_glue_catalog_table.fhir_ingest_analytics.name}
  GROUP BY source;
  
  # 3. View latest data
  SELECT * FROM ${aws_glue_catalog_database.fhir_analytics.name}.${aws_glue_catalog_table.fhir_ingest_analytics.name}
  WHERE ingest_date = (SELECT MAX(ingest_date) FROM ${aws_glue_catalog_database.fhir_analytics.name}.${aws_glue_catalog_table.fhir_ingest_analytics.name})
  LIMIT 10;
  
  # 4. Error analysis
  SELECT operationOutcomeCode, COUNT(*) as error_count
  FROM ${aws_glue_catalog_database.fhir_analytics.name}.${aws_glue_catalog_table.fhir_ingest_analytics.name}
  WHERE operationOutcomeCode IS NOT NULL
  GROUP BY operationOutcomeCode
  ORDER BY error_count DESC;
  
  EOT
}

# Deployment Summary
output "deployment_summary" {
  description = "Deployment summary with all important information"
  value = {
    lambda_function   = aws_lambda_function.analytics_lambda.function_name
    lambda_arn        = aws_lambda_function.analytics_lambda.arn
    source_bucket     = local.source_bucket
    target_bucket     = local.target_bucket
    glue_database     = aws_glue_catalog_database.fhir_analytics.name
    glue_table        = aws_glue_catalog_table.fhir_ingest_analytics.name
    s3_data_location  = "s3://${local.target_bucket}/data/"
    partition_projection_enabled = aws_glue_catalog_table.fhir_ingest_analytics.parameters["projection.enabled"]
  }
}

