terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Local variables
locals {
  function_name = "fhir-analytics-json-to-parquet"
  source_bucket = var.source_bucket
  target_bucket = var.target_bucket
  
  common_tags = {
    Project     = "FHIR Analytics"
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
}

# ============================================================================
# S3 Buckets
# ============================================================================

# Source bucket for JSON files
resource "aws_s3_bucket" "source" {
  bucket        = local.source_bucket
  force_destroy = var.force_destroy_buckets  # Allow destroy even with objects
  
  tags = merge(
    local.common_tags,
    {
      Name = "FHIR Source Bucket"
      Purpose = "JSON file ingestion"
    }
  )
}

# Enable encryption on source bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Target bucket for Parquet files
resource "aws_s3_bucket" "target" {
  bucket        = local.target_bucket
  force_destroy = var.force_destroy_buckets  # Allow destroy even with objects
  
  tags = merge(
    local.common_tags,
    {
      Name = "FHIR Analytics Bucket"
      Purpose = "Parquet file storage"
    }
  )
}

# Enable encryption on target bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "target" {
  bucket = aws_s3_bucket.target.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy for source bucket (retention)
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.s3_retention_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "delete-old-files"
    status = "Enabled"

    filter {}

    expiration {
      days = var.s3_retention_days
    }
  }

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.source]
}

# Lifecycle policy for target bucket (retention)
resource "aws_s3_bucket_lifecycle_configuration" "target" {
  count  = var.s3_retention_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.target.id

  rule {
    id     = "delete-old-files"
    status = "Enabled"

    filter {}

    expiration {
      days = var.s3_retention_days
    }
  }

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.target]
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${local.function_name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.function_name}-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}*"
      },
      {
        Sid    = "S3SourceRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.source_bucket}",
          "arn:aws:s3:::${local.source_bucket}/*"
        ]
      },
      {
        Sid    = "S3TargetWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:HeadObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.target_bucket}",
          "arn:aws:s3:::${local.target_bucket}/*"
        ]
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "FHIRAnalytics/Lambda"
          }
        }
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to retention_in_days if manually changed
      retention_in_days
    ]
  }
}

# Lambda Layer for awswrangler (Python dependencies)
# Option 1: Use AWS public layer (recommended)
# Option 2: Build and use custom layer
resource "aws_lambda_layer_version" "awswrangler" {
  count = var.use_aws_public_layer ? 0 : 1
  
  layer_name          = "awswrangler-layer"
  description         = "AWS Data Wrangler and dependencies"
  compatible_runtimes = ["python3.12"]
  
  filename = var.lambda_layer_zip_path
  
  source_code_hash = var.lambda_layer_zip_path != "" && fileexists(var.lambda_layer_zip_path) ? filebase64sha256(var.lambda_layer_zip_path) : null
}

# AWS Public Layer ARNs for awswrangler (AWSSDKPandas)
# https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
locals {
  aws_sdk_pandas_layer_arns = {
    "us-east-1"      = "arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python312:13"
    "us-east-2"      = "arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python312:13"
    "us-west-1"      = "arn:aws:lambda:us-west-1:336392948345:layer:AWSSDKPandas-Python312:13"
    "us-west-2"      = "arn:aws:lambda:us-west-2:336392948345:layer:AWSSDKPandas-Python312:13"
    "eu-west-1"      = "arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python312:13"
    "eu-central-1"   = "arn:aws:lambda:eu-central-1:336392948345:layer:AWSSDKPandas-Python312:13"
    "ap-southeast-1" = "arn:aws:lambda:ap-southeast-1:336392948345:layer:AWSSDKPandas-Python312:13"
    "ap-northeast-1" = "arn:aws:lambda:ap-northeast-1:336392948345:layer:AWSSDKPandas-Python312:13"
  }
  
  layer_arn = var.use_aws_public_layer ? lookup(local.aws_sdk_pandas_layer_arns, var.aws_region, local.aws_sdk_pandas_layer_arns["us-east-1"]) : aws_lambda_layer_version.awswrangler[0].arn
}

# ============================================================================
# Lambda Function - JSON to Parquet Converter
# ============================================================================
# Architecture Flow:
#   S3 Source Bucket (fhir-lca-persist) 
#     -> [S3 Event Notification] 
#   Lambda Function (fhir-analytics-json-to-parquet)
#     -> [Writes Parquet files]
#   S3 Target Bucket (fhir-ingest-analytics/data/)
#     -> [Partitioned by: source/ingest_date/hour/]
#   AWS Glue Catalog (fhir_analytics.fhir_ingest_analytics)
#     -> [Queryable via Athena]
# ============================================================================

# Lambda Function
resource "aws_lambda_function" "analytics_lambda" {
  function_name = local.function_name
  description   = "Convert JSON files from ${local.source_bucket} to Parquet format and write to ${local.target_bucket}/data/ with partitioning (source/ingest_date/hour)"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  
  layers = [
    local.layer_arn
  ]
  
  # Cost optimization: Reserved concurrency to prevent runaway costs
  # Only set if value is greater than 0 (0 means no limit)
  reserved_concurrent_executions = var.lambda_reserved_concurrency > 0 ? var.lambda_reserved_concurrency : null
  
  environment {
    variables = {
      SOURCE_BUCKET = local.source_bucket
      TARGET_BUCKET = local.target_bucket
      LOG_LEVEL     = "INFO"
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
  
  tags = merge(
    local.common_tags,
    {
      SourceBucket     = local.source_bucket
      TargetBucket     = local.target_bucket
      DataFlow         = "S3-to-Lambda-to-S3"
      OutputLocation   = "s3://${local.target_bucket}/data/"
    }
  )
}

# ============================================================================
# S3 Event Trigger Configuration
# ============================================================================
# Configures S3 source bucket to trigger Lambda on JSON file uploads
# Flow: S3 Source -> Lambda -> S3 Target (Parquet output)
# ============================================================================

# S3 Bucket Notification Permission
# Allows S3 to invoke Lambda function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analytics_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${local.source_bucket}"
}

# S3 Bucket Notification
# Triggers Lambda when JSON files are created in source bucket
resource "aws_s3_bucket_notification" "source_bucket_notification" {
  bucket = aws_s3_bucket.source.id
  
  lambda_function {
    lambda_function_arn = aws_lambda_function.analytics_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.s3_filter_prefix
    filter_suffix       = ".json"
  }
  
  depends_on = [aws_lambda_permission.s3_invoke]
}

# Note: Lambda writes output to target bucket (${local.target_bucket}/data/)
# This is configured in the Lambda function code and IAM permissions above.
# The target bucket path follows: s3://${local.target_bucket}/data/source={source}/ingest_date={date}/hour={hour}/

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# ============================================================================
# AWS Glue Catalog - Database and Table
# ============================================================================

# Glue Database
resource "aws_glue_catalog_database" "fhir_analytics" {
  name        = "fhir_analytics"
  description = "FHIR Analytics Database for ingested data"
  
  location_uri = "s3://${local.target_bucket}/"
  
  tags = local.common_tags
}

# Glue Table with Partition Projection
resource "aws_glue_catalog_table" "fhir_ingest_analytics" {
  name          = "fhir_ingest_analytics"
  database_name = aws_glue_catalog_database.fhir_analytics.name
  description   = "FHIR ingestion analytics with operationOutcome explosion"
  
  table_type = "EXTERNAL_TABLE"
  
  parameters = {
    "EXTERNAL"                        = "TRUE"
    "parquet.compression"             = "SNAPPY"
    "projection.enabled"              = "true"
    "projection.source.type"          = "enum"
    "projection.source.values"        = join(",", var.glue_partition_sources)
    "projection.ingest_date.type"     = "date"
    "projection.ingest_date.range"    = "2025-01-01,NOW"
    "projection.ingest_date.format"   = "yyyy-MM-dd"
    "projection.hour.type"            = "integer"
    "projection.hour.range"           = "00,23"
    "projection.hour.digits"          = "2"
    "storage.location.template"       = "s3://${local.target_bucket}/data/source=$${source}/ingest_date=$${ingest_date}/hour=$${hour}"
  }
  
  storage_descriptor {
    location      = "s3://${local.target_bucket}/data/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    
    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      
      parameters = {
        "serialization.format" = "1"
      }
    }
    
    columns {
      name = "s3Filename"
      type = "string"
      comment = "Original S3 filename"
    }
    
    columns {
      name = "approximateReceiveCount"
      type = "int"
      comment = "Approximate receive count"
    }
    
    columns {
      name = "customerId"
      type = "string"
      comment = "Customer identifier"
    }
    
    columns {
      name = "patientId"
      type = "string"
      comment = "Patient identifier"
    }
    
    columns {
      name = "sourceFhirServer"
      type = "string"
      comment = "Source FHIR server URL"
    }
    
    columns {
      name = "requestResourceId"
      type = "string"
      comment = "Resource ID from request"
    }
    
    columns {
      name = "bundleResourceType"
      type = "string"
      comment = "FHIR bundle resource type"
    }
    
    columns {
      name = "statusCode"
      type = "int"
      comment = "HTTP status code"
    }
    
    columns {
      name = "operationOutcomeLocation"
      type = "string"
      comment = "Operation outcome location"
    }
    
    columns {
      name = "operationOutcomeSeverity"
      type = "string"
      comment = "Operation outcome severity"
    }
    
    columns {
      name = "operationOutcomeCode"
      type = "string"
      comment = "Operation outcome code"
    }
    
    columns {
      name = "operationOutcomeDetail"
      type = "string"
      comment = "Operation outcome detail message"
    }
    
    columns {
      name = "responseTs"
      type = "timestamp"
      comment = "Response timestamp"
    }
    
    columns {
      name = "latencyMs"
      type = "int"
      comment = "Latency in milliseconds"
    }
    
    columns {
      name = "datastoreId"
      type = "string"
      comment = "Datastore identifier"
    }
    
    # Note: ingest_date and hour are added by Lambda as partition columns
    # They should NOT be in the data columns, only in partition_keys below
  }
  
  partition_keys {
    name = "source"
    type = "string"
    comment = "Source system (lca-persist, dxa-persist)"
  }
  
  partition_keys {
    name = "ingest_date"
    type = "string"
    comment = "Ingestion date (YYYY-MM-DD)"
  }
  
  partition_keys {
    name = "hour"
    type = "string"
    comment = "Ingestion hour (HH)"
  }
  
  depends_on = [aws_glue_catalog_database.fhir_analytics]
}

# ============================================================================
# Athena Resources - Query Configuration
# ============================================================================

# S3 Bucket for Athena Query Results
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.target_bucket}-athena-results"
  force_destroy = var.force_destroy_buckets
  
  tags = merge(
    local.common_tags,
    {
      Name = "Athena Query Results Bucket"
      Purpose = "Athena query result storage"
    }
  )
}

# Enable encryption on Athena results bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy for Athena results bucket (optional cleanup)
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  count  = var.athena_results_retention_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "delete-old-results"
    status = "Enabled"

    filter {
      prefix = "results/"
    }

    expiration {
      days = var.athena_results_retention_days
    }
  }

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.athena_results]
}

# Athena Workgroup
# Note: If workgroup already exists, set create_athena_workgroup = false
# and import it: terraform import aws_athena_workgroup.fhir_analytics fhir-analytics
resource "aws_athena_workgroup" "fhir_analytics" {
  count       = var.create_athena_workgroup ? 1 : 0
  name        = var.athena_workgroup_name
  description = "Athena workgroup for FHIR analytics queries"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "FHIR Analytics Athena Workgroup"
    }
  )

  lifecycle {
    # Prevent deletion if workgroup has query history
    # Use terraform destroy with -target to remove other resources first
    # Or manually delete query history before destroying workgroup
    prevent_destroy = false
  }
}

# IAM Policy for Athena Queries
# This policy can be attached to users/roles who need to query Athena
resource "aws_iam_policy" "athena_query" {
  name        = "${local.function_name}-athena-query-policy"
  description = "IAM policy for querying Athena and accessing Glue catalog"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQueryAccess"
        Effect = "Allow"
        Action = [
          "athena:BatchGetQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetQueryResultsStream",
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:ListQueryExecutions",
          "athena:GetWorkGroup"
        ]
        Resource = concat(
          var.create_athena_workgroup ? [aws_athena_workgroup.fhir_analytics[0].arn] : ["arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup_name}"],
          ["arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:datacatalog/*"]
        )
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.fhir_analytics.name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.fhir_analytics.name}/*"
        ]
      },
      {
        Sid    = "S3DataReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target.arn,
          "${aws_s3_bucket.target.arn}/*"
        ]
      },
      {
        Sid    = "S3ResultsWriteAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.athena_results.arn}/results/*"
        ]
      },
      {
        Sid    = "S3ResultsListAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.athena_results.arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "results/*"
            ]
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# ============================================================================
# CloudWatch Monitoring & Alarms
# ============================================================================

# SNS Topic for Alerts (optional - requires SNS permissions)
resource "aws_sns_topic" "lambda_alerts" {
  count        = var.enable_sns_alerts ? 1 : 0
  name         = "${local.function_name}-alerts"
  display_name = "FHIR Analytics Lambda Alerts"
  
  tags = merge(
    local.common_tags,
    {
      Name = "Lambda Alerts Topic"
    }
  )
}

# SNS Topic Subscription (email - optional, can be configured via variable)
resource "aws_sns_topic_subscription" "lambda_alerts_email" {
  count     = var.enable_sns_alerts && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.lambda_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Alarm: High Error Rate
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.function_name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors lambda error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.analytics_lambda.function_name
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch Alarm: Custom Error Rate (from custom metrics)
resource "aws_cloudwatch_metric_alarm" "custom_error_rate" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.function_name}-custom-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "FHIRAnalytics/Lambda"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors custom error rate from application"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch Alarm: Duration (approaching timeout)
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.function_name}-high-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300  # 5 minutes
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors lambda execution duration (warning at 80% of timeout)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.analytics_lambda.function_name
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch Alarm: Throttles
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors lambda throttles"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.analytics_lambda.function_name
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch Alarm: Fatal Errors (from custom metrics)
resource "aws_cloudwatch_metric_alarm" "fatal_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.function_name}-fatal-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FatalErrors"
  namespace           = "FHIRAnalytics/Lambda"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This metric monitors fatal errors that prevent function execution"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch Alarm: No Invocations (staleness check)
resource "aws_cloudwatch_metric_alarm" "no_invocations" {
  count               = var.enable_cloudwatch_alarms && var.enable_staleness_alarm ? 1 : 0
  alarm_name          = "${local.function_name}-no-invocations"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = 86400  # 24 hours
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors if lambda hasn't been invoked in 24 hours"
  treat_missing_data  = "breaching"

  dimensions = {
    FunctionName = aws_lambda_function.analytics_lambda.function_name
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = local.common_tags
}

# Outputs moved to outputs.tf

