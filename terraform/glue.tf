# ============================================================================
# AWS Glue Resources (Alternative modular approach)
# ============================================================================
# This file is an alternative to having Glue resources in main.tf
# You can use either approach - both are included for flexibility

# Uncomment below if you want to keep Glue configuration separate from main.tf

# resource "aws_glue_catalog_database" "fhir_analytics" {
#   name        = var.glue_database_name
#   description = "FHIR Analytics Database for ingested data"
#   
#   location_uri = "s3://${var.target_bucket}/"
#   
#   tags = {
#     Project     = "FHIR Analytics"
#     ManagedBy   = "Terraform"
#     Environment = var.environment
#   }
# }

# resource "aws_glue_catalog_table" "fhir_ingest_analytics" {
#   name          = var.glue_table_name
#   database_name = aws_glue_catalog_database.fhir_analytics.name
#   description   = "FHIR ingestion analytics with operationOutcome explosion"
#   
#   table_type = "EXTERNAL_TABLE"
#   
#   parameters = {
#     "EXTERNAL"                        = "TRUE"
#     "parquet.compression"             = "SNAPPY"
#     "projection.enabled"              = "true"
#     "projection.source.type"          = "enum"
#     "projection.source.values"        = join(",", var.glue_partition_sources)
#     "projection.ingest_date.type"     = "date"
#     "projection.ingest_date.range"    = "${var.glue_partition_date_start},NOW"
#     "projection.ingest_date.format"   = "yyyy-MM-dd"
#     "projection.hour.type"            = "integer"
#     "projection.hour.range"           = "00,23"
#     "projection.hour.digits"          = "2"
#     "storage.location.template"       = "s3://${var.target_bucket}/data/source=$${source}/ingest_date=$${ingest_date}/hour=$${hour}"
#   }
#   
#   storage_descriptor {
#     location      = "s3://${var.target_bucket}/data/"
#     input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
#     output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
#     
#     ser_de_info {
#       name                  = "ParquetHiveSerDe"
#       serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
#       
#       parameters = {
#         "serialization.format" = "1"
#       }
#     }
#     
#     # Define all columns
#     dynamic "columns" {
#       for_each = var.glue_table_columns
#       content {
#         name    = columns.value.name
#         type    = columns.value.type
#         comment = lookup(columns.value, "comment", "")
#       }
#     }
#   }
#   
#   # Partition keys
#   dynamic "partition_keys" {
#     for_each = var.glue_partition_keys
#     content {
#       name    = partition_keys.value.name
#       type    = partition_keys.value.type
#       comment = lookup(partition_keys.value, "comment", "")
#     }
#   }
# }

