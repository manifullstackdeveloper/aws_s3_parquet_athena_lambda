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

# Data Flow Architecture
output "data_flow_architecture" {
  description = "Complete data flow architecture: S3 Source -> Lambda -> S3 Target"
  value = {
    source = {
      bucket      = local.source_bucket
      bucket_arn  = aws_s3_bucket.source.arn
      trigger     = "S3 Event Notification (ObjectCreated)"
      filter      = "${var.s3_filter_prefix}*.json"
    }
    processor = {
      lambda_function = aws_lambda_function.analytics_lambda.function_name
      lambda_arn      = aws_lambda_function.analytics_lambda.arn
      description     = "Converts JSON to Parquet with partitioning"
    }
    destination = {
      bucket         = local.target_bucket
      bucket_arn     = aws_s3_bucket.target.arn
      output_path    = "s3://${local.target_bucket}/data/"
      partition_path = "s3://${local.target_bucket}/data/source={source}/ingest_date={date}/hour={hour}/"
    }
    catalog = {
      database = aws_glue_catalog_database.fhir_analytics.name
      table    = aws_glue_catalog_table.fhir_ingest_analytics.name
      location = aws_glue_catalog_table.fhir_ingest_analytics.storage_descriptor[0].location
    }
    athena = {
      workgroup      = var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].name : var.athena_workgroup_name
      workgroup_arn   = var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].arn : "arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup_name}"
      results_bucket = aws_s3_bucket.athena_results.id
      query_policy   = aws_iam_policy.athena_query.arn
    }
  }
}

# Athena Outputs
output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].name : var.athena_workgroup_name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].arn : "arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup_name}"
}

output "athena_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.id
}

output "athena_results_bucket_arn" {
  description = "ARN of Athena results bucket"
  value       = aws_s3_bucket.athena_results.arn
}

output "athena_query_policy_arn" {
  description = "ARN of IAM policy for Athena queries (attach to users/roles who need to query)"
  value       = aws_iam_policy.athena_query.arn
}

output "athena_query_instructions" {
  description = "Instructions for querying Athena"
  value = <<-EOT
  
  # Athena Query Setup Instructions:
  
  1. Attach IAM Policy to your user/role:
     Policy ARN: ${aws_iam_policy.athena_query.arn}
  
  2. Use Athena Workgroup: ${var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].name : var.athena_workgroup_name}
  
  3. Query Results Location: s3://${aws_s3_bucket.athena_results.id}/results/
  
  4. Example Query:
     SELECT * FROM ${aws_glue_catalog_database.fhir_analytics.name}.${aws_glue_catalog_table.fhir_ingest_analytics.name}
     WHERE ingest_date = '2025-01-15'
     LIMIT 10;
  
  5. In Athena Console:
     - Go to: https://console.aws.amazon.com/athena/
     - Select workgroup: ${var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].name : var.athena_workgroup_name}
     - Select database: ${aws_glue_catalog_database.fhir_analytics.name}
     - Run queries!
  
  EOT
}

# Monitoring Outputs
output "sns_topic_arn" {
  description = "ARN of SNS topic for Lambda alerts"
  value       = var.enable_sns_alerts ? aws_sns_topic.lambda_alerts[0].arn : null
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names for monitoring"
  value = var.enable_cloudwatch_alarms ? {
    errors           = aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name
    custom_errors     = aws_cloudwatch_metric_alarm.custom_error_rate[0].alarm_name
    duration         = aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name
    throttles        = aws_cloudwatch_metric_alarm.lambda_throttles[0].alarm_name
    fatal_errors     = aws_cloudwatch_metric_alarm.fatal_errors[0].alarm_name
    no_invocations   = var.enable_staleness_alarm ? aws_cloudwatch_metric_alarm.no_invocations[0].alarm_name : null
  } : null
}

output "monitoring_instructions" {
  description = "Instructions for monitoring and error triage"
  value = <<-EOT
  
  # Monitoring & Error Triage:
  
  1. CloudWatch Alarms:
     ${var.enable_cloudwatch_alarms ? join("\n     ", [
       "- Error Rate: ${aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name}",
       "- Duration: ${aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name}",
       "- Throttles: ${aws_cloudwatch_metric_alarm.lambda_throttles[0].alarm_name}",
       "- Fatal Errors: ${aws_cloudwatch_metric_alarm.fatal_errors[0].alarm_name}"
     ]) : "     - Not configured (set enable_cloudwatch_alarms = true)"}
  
  2. SNS Topic for Alerts: ${var.enable_sns_alerts ? aws_sns_topic.lambda_alerts[0].arn : "Not configured (set enable_sns_alerts = true)"}
     ${var.enable_sns_alerts && var.alert_email != "" ? "   - Email subscription: ${var.alert_email}" : "   - No email subscription configured"}
  
  3. Custom Metrics Namespace: FHIRAnalytics/Lambda
     - Errors: Error count by category
     - ErrorsByCategory: Error breakdown by type
     - FilesProcessed: Successfully processed files
     - FilesFailed: Failed file processing
     - InvocationDuration: Function execution time
     - ParquetWriteDuration: Parquet write time
     - RecordsProcessed: Number of records processed
  
  4. Error Categories for Triage:
     - ConfigurationError: Configuration issues
     - S3ReadError: S3 read failures
     - S3WriteError: S3 write failures
     - JSONParseError: JSON parsing errors
     - JSONValidationError: JSON validation failures
     - DataTransformationError: Data transformation issues
     - PartitioningError: Partitioning failures
     - UnknownError: Unhandled errors
  
  5. View Logs:
     aws logs tail /aws/lambda/${aws_lambda_function.analytics_lambda.function_name} --follow
  
  6. View Metrics:
     - Go to CloudWatch Console → Metrics → FHIRAnalytics/Lambda
     - Filter by ErrorCategory dimension for error triage
  
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
    data_flow        = "${local.source_bucket} -> Lambda -> ${local.target_bucket}/data/"
    athena_workgroup  = var.create_athena_workgroup ? aws_athena_workgroup.fhir_analytics[0].name : var.athena_workgroup_name
    athena_results_bucket = aws_s3_bucket.athena_results.id
  }
}

