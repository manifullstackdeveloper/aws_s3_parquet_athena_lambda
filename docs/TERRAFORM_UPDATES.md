# Terraform Updates - Automatic Glue Setup

## 🎉 What's New

AWS Glue resources are now **automatically created** by Terraform! No more manual DDL execution required.

## 📦 What Gets Created

### 1. Glue Database
- **Name:** `fhir_analytics`
- **Location:** `s3://fhir-ingest-analytics/`
- **Description:** FHIR Analytics Database for ingested data

### 2. Glue Table
- **Name:** `fhir_ingest_analytics`
- **Format:** Parquet with Snappy compression
- **Schema:** 16 data columns + 3 partition keys
- **Partition Projection:** Enabled (automatic discovery!)

### 3. Additional Outputs
- `glue_database_name`
- `glue_table_name`
- `glue_table_location`
- `deployment_summary` (comprehensive deployment info)
- `athena_query_examples` (ready-to-use queries)

## 📂 New/Updated Files

### Created:
- `terraform/outputs.tf` - Organized outputs
- `terraform/glue.tf` - Alternative modular Glue config (commented)
- `GLUE_SETUP.md` - Complete Glue documentation

### Updated:
- `terraform/main.tf` - Added Glue resources
- `terraform/variables.tf` - Added Glue variables
- `terraform/terraform.tfvars.example` - Added Glue configuration
- `DEPLOYMENT_GUIDE.md` - Updated deployment steps
- `README.md` - Updated quick start

## 🚀 Deployment Changes

### Before (Manual):
```bash
# 1. Deploy Terraform
terraform apply

# 2. Manually run DDL in Athena
aws athena start-query-execution \
  --query-string file://athena_ddl.sql \
  ...
  
# 3. Wait and verify
```

### Now (Automatic):
```bash
# Just deploy - everything is created!
terraform apply

# Query immediately in Athena
# No manual DDL needed! 🎉
```

## 🔧 Configuration

### New Variables

Add to your `terraform.tfvars`:

```hcl
# Glue configuration
glue_database_name = "fhir_analytics"
glue_table_name = "fhir_ingest_analytics"
glue_partition_sources = ["lca-persist", "dxa-persist"]
glue_partition_date_start = "2025-01-01"
```

### Customization Options

**Change partition sources:**
```hcl
glue_partition_sources = ["lca-persist", "dxa-persist", "new-source"]
```

**Change date range:**
```hcl
glue_partition_date_start = "2024-01-01"
```

**Change database/table names:**
```hcl
glue_database_name = "my_custom_db"
glue_table_name = "my_custom_table"
```

## 📊 Terraform Outputs

After `terraform apply`, you'll see:

```
Outputs:

lambda_function_arn = "arn:aws:lambda:..."
lambda_function_name = "fhir-analytics-json-to-parquet"
lambda_role_arn = "arn:aws:iam::..."
log_group_name = "/aws/lambda/fhir-analytics-json-to-parquet"

# NEW! Glue outputs:
glue_database_name = "fhir_analytics"
glue_table_name = "fhir_ingest_analytics"
glue_table_location = "s3://fhir-ingest-analytics/data/"

# NEW! Query examples:
athena_query_examples = <<EOT
  # Example queries ready to use...
EOT

# NEW! Deployment summary:
deployment_summary = {
  lambda_function = "fhir-analytics-json-to-parquet"
  glue_database = "fhir_analytics"
  glue_table = "fhir_ingest_analytics"
  partition_projection_enabled = "true"
  ...
}
```

## 🔍 Verification

### Check Glue Resources

```bash
# List databases
aws glue get-databases --query 'DatabaseList[*].Name'

# Get specific database
aws glue get-database --name fhir_analytics

# Get table details
aws glue get-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics

# Check partition projection
aws glue get-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics \
  --query 'Table.Parameters."projection.enabled"'
```

### Query in Athena

```sql
-- Verify table exists
SHOW TABLES IN fhir_analytics;

-- Check schema
DESCRIBE fhir_analytics.fhir_ingest_analytics;

-- Query data (after uploading test files)
SELECT COUNT(*) FROM fhir_analytics.fhir_ingest_analytics;
```

## 🎯 Partition Projection

### What It Does

**Automatic partition discovery** without manual management!

- ✅ No `MSCK REPAIR TABLE` needed
- ✅ No manual `ALTER TABLE ADD PARTITION`
- ✅ Infinite partitions without pre-creation
- ✅ Faster query planning
- ✅ Lower costs (no Glue API calls)

### How It Works

```hcl
parameters = {
  "projection.enabled" = "true"
  
  # Source: enum (lca-persist, dxa-persist)
  "projection.source.type" = "enum"
  "projection.source.values" = "lca-persist,dxa-persist"
  
  # Date: from 2025-01-01 to NOW
  "projection.ingest_date.type" = "date"
  "projection.ingest_date.range" = "2025-01-01,NOW"
  "projection.ingest_date.format" = "yyyy-MM-dd"
  
  # Hour: 00 to 23
  "projection.hour.type" = "integer"
  "projection.hour.range" = "00,23"
  "projection.hour.digits" = "2"
  
  # S3 path template
  "storage.location.template" = "s3://bucket/data/source=${source}/ingest_date=${ingest_date}/hour=${hour}"
}
```

## 📚 Migration Guide

### If You Already Have Manual Glue Setup

**Option 1: Import existing resources**

```bash
# Import database
terraform import aws_glue_catalog_database.fhir_analytics fhir_analytics

# Import table
terraform import aws_glue_catalog_table.fhir_ingest_analytics fhir_analytics:fhir_ingest_analytics
```

**Option 2: Delete and recreate**

```bash
# Delete old resources
aws glue delete-table --database-name fhir_analytics --name fhir_ingest_analytics
aws glue delete-database --name fhir_analytics

# Deploy with Terraform
terraform apply
```

**Data is NOT affected** - Only metadata is recreated!

## 🎓 Best Practices

1. **Use partition projection** (enabled by default)
2. **Set appropriate date range** in `glue_partition_date_start`
3. **Add new sources** to `glue_partition_sources` as needed
4. **Version control** `terraform.tfvars`
5. **Test queries** after deployment

## 📖 Documentation

- **GLUE_SETUP.md** - Complete Glue documentation
- **DEPLOYMENT_GUIDE.md** - Updated deployment steps
- **athena_ddl.sql** - Reference only (not needed for deployment)

## 🎉 Summary

| Aspect | Before | Now |
|--------|--------|-----|
| **Glue Database** | Manual DDL | ✅ Automatic |
| **Glue Table** | Manual DDL | ✅ Automatic |
| **Partition Projection** | Manual config | ✅ Automatic |
| **Deployment Steps** | 2-step process | ✅ Single `terraform apply` |
| **Athena Queries** | After manual setup | ✅ Immediate |

---

**Just run `terraform apply` and everything is ready!** 🚀

