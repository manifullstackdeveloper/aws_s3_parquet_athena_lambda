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

# SSM Parameters for configuration (optional)
resource "aws_ssm_parameter" "source_bucket" {
  count = var.create_ssm_parameters ? 1 : 0
  
  name  = "/myapp/source-bucket"
  type  = "String"
  value = local.source_bucket
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "target_bucket" {
  count = var.create_ssm_parameters ? 1 : 0
  
  name  = "/myapp/target-bucket"
  type  = "String"
  value = local.target_bucket
  
  tags = local.common_tags
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

# Enable versioning on source bucket (optional)
resource "aws_s3_bucket_versioning" "source" {
  count = var.enable_s3_versioning ? 1 : 0
  
  bucket = aws_s3_bucket.source.id
  
  versioning_configuration {
    status = "Enabled"
  }
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

# Enable versioning on target bucket (optional)
resource "aws_s3_bucket_versioning" "target" {
  count = var.enable_s3_versioning ? 1 : 0
  
  bucket = aws_s3_bucket.target.id
  
  versioning_configuration {
    status = "Enabled"
  }
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
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/myapp/*"
        ]
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

# Lambda Function
resource "aws_lambda_function" "analytics_lambda" {
  function_name = local.function_name
  description   = "Convert JSON files to Parquet format with partitioning"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512
  
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  
  layers = [
    local.layer_arn
  ]
  
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
  
  tags = local.common_tags
}

# S3 Bucket Notification Permission
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analytics_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${local.source_bucket}"
}

# S3 Bucket Notification
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
    "projection.source.values"        = "lca-persist,dxa-persist"
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
      type = "string"
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

# Outputs moved to outputs.tf

