# AWS Glue Setup - Automatic with Terraform

## Overview

The Terraform configuration **automatically creates** all necessary AWS Glue resources:
- ✅ Glue Database (`fhir_analytics`)
- ✅ Glue Table (`fhir_ingest_analytics`)
- ✅ Partition Projection (enabled)
- ✅ Table Schema (16 columns + 3 partition keys)

**No manual SQL execution required!** 🎉

## What Gets Created

### 1. Glue Database

```hcl
resource "aws_glue_catalog_database" "fhir_analytics" {
  name        = "fhir_analytics"
  description = "FHIR Analytics Database for ingested data"
  location_uri = "s3://fhir-ingest-analytics/"
}
```

### 2. Glue Table

**Table Name:** `fhir_ingest_analytics`

**Data Columns (16):**
1. `s3Filename` (string)
2. `source` (string)
3. `approximateReceiveCount` (int)
4. `customerId` (string)
5. `patientId` (string)
6. `sourceFhirServer` (string)
7. `requestResourceId` (string)
8. `bundleResourceType` (string)
9. `statusCode` (int)
10. `operationOutcomeLocation` (string)
11. `operationOutcomeSeverity` (string)
12. `operationOutcomeCode` (string)
13. `operationOutcomeDetail` (string)
14. `responseTs` (string)
15. `latencyMs` (int)
16. `datastoreId` (string)

**Partition Keys (3):**
1. `source` (string) - Source system (lca-persist, dxa-persist)
2. `ingest_date` (string) - Date in YYYY-MM-DD format
3. `hour` (string) - Hour in HH format (00-23)

### 3. Partition Projection

**Automatic partition discovery** without MSCK REPAIR:

```hcl
parameters = {
  "projection.enabled"              = "true"
  "projection.source.type"          = "enum"
  "projection.source.values"        = "lca-persist,dxa-persist"
  "projection.ingest_date.type"     = "date"
  "projection.ingest_date.range"    = "2025-01-01,NOW"
  "projection.ingest_date.format"   = "yyyy-MM-dd"
  "projection.hour.type"            = "integer"
  "projection.hour.range"           = "00,23"
  "projection.hour.digits"          = "2"
  "storage.location.template"       = "s3://bucket/data/source=${source}/ingest_date=${ingest_date}/hour=${hour}"
}
```

## Verification

### After Terraform Apply

Check outputs:

```bash
cd terraform
terraform output

# You should see:
# glue_database_name = "fhir_analytics"
# glue_table_name = "fhir_ingest_analytics"
# glue_table_location = "s3://fhir-ingest-analytics/data/"
```

### Using AWS CLI

```bash
# Check database
aws glue get-database --name fhir_analytics

# Check table
aws glue get-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics

# View table schema
aws glue get-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics \
  --query 'Table.StorageDescriptor.Columns[*].[Name,Type,Comment]' \
  --output table

# Check partition keys
aws glue get-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics \
  --query 'Table.PartitionKeys[*].[Name,Type,Comment]' \
  --output table
```

### Using AWS Console

1. Go to **AWS Glue Console** → **Databases**
2. Click on `fhir_analytics`
3. View tables → Click `fhir_ingest_analytics`
4. Review schema and partitions

## Querying in Athena

### Setup Athena

```bash
# Set query results location (one-time)
aws athena create-work-group \
  --name fhir-analytics \
  --configuration "ResultConfigurationUpdates={OutputLocation=s3://your-athena-results/}"
```

### Example Queries

**The table is immediately queryable** after Terraform apply:

```sql
-- 1. Check if table exists
SHOW TABLES IN fhir_analytics;

-- 2. Describe table
DESCRIBE fhir_analytics.fhir_ingest_analytics;

-- 3. Show partitions (with projection, this isn't needed!)
SHOW PARTITIONS fhir_analytics.fhir_ingest_analytics;

-- 4. Count records
SELECT COUNT(*) FROM fhir_analytics.fhir_ingest_analytics;

-- 5. View sample data
SELECT * FROM fhir_analytics.fhir_ingest_analytics LIMIT 10;

-- 6. Query specific partition
SELECT * 
FROM fhir_analytics.fhir_ingest_analytics
WHERE source = 'lca-persist'
  AND ingest_date = '2025-12-05'
  AND hour = '15'
LIMIT 10;
```

## Partition Projection Benefits

### Without Partition Projection

❌ Need to run `MSCK REPAIR TABLE` after each new data load  
❌ Manual partition management  
❌ Slower queries  
❌ Glue API calls cost money

### With Partition Projection (Enabled)

✅ **Automatic** partition discovery  
✅ **No** `MSCK REPAIR TABLE` needed  
✅ **Faster** query planning  
✅ **Lower** costs (no Glue API calls)  
✅ **Infinite** partitions without pre-creation

## Customization

### Change Partition Sources

Edit `terraform/variables.tf`:

```hcl
variable "glue_partition_sources" {
  default = ["lca-persist", "dxa-persist", "new-source"]
}
```

### Change Date Range

```hcl
variable "glue_partition_date_start" {
  default = "2024-01-01"  # Earlier start date
}
```

### Add More Columns

Edit `terraform/main.tf` and add to the `columns` block:

```hcl
columns {
  name    = "new_field"
  type    = "string"
  comment = "Description of new field"
}
```

Then run:

```bash
terraform apply
```

## Troubleshooting

### Issue: Table not found in Athena

**Solution:**
```sql
-- Refresh Athena metadata
MSCK REPAIR TABLE fhir_analytics.fhir_ingest_analytics;

-- Or just wait a few seconds and retry
```

### Issue: Partition not found

**Check partition projection is enabled:**

```bash
aws glue get-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics \
  --query 'Table.Parameters."projection.enabled"'
```

Should return: `"true"`

### Issue: Schema mismatch

**Check Parquet file schema vs Glue table:**

```python
import pandas as pd

# Read Parquet file
df = pd.read_parquet('output/example_payload.parquet')
print(df.columns)

# Compare with Glue schema
# All columns should match
```

## Migration from Manual DDL

If you previously created the table manually:

```bash
# Delete old table
aws glue delete-table \
  --database-name fhir_analytics \
  --name fhir_ingest_analytics

# Apply Terraform to recreate
cd terraform
terraform apply
```

## Summary

✅ **Glue Database**: Created automatically by Terraform  
✅ **Glue Table**: Created automatically with full schema  
✅ **Partition Projection**: Enabled for automatic discovery  
✅ **No Manual Steps**: Everything via `terraform apply`  
✅ **Athena Ready**: Query immediately after deployment  

**The `athena_ddl.sql` file is now optional** - use it only as a reference for the schema!

---

**Next:** Just run `terraform apply` and start querying! 🚀

