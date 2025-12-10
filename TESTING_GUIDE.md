# Testing Guide

## Quick Test

Run the comprehensive test script:

```bash
python test_lambda_athena.py
```

This will:
- ✅ Test Lambda function with sample data
- ✅ Generate Parquet output files
- ✅ Show CloudWatch metrics
- ✅ Display Athena query examples

## Test Results

### Lambda Function Test

The test processes two sample files:
- `lca-persist-input.json` → Creates Parquet with 4 rows
- `dxa-persist-input.json` → Creates Parquet with 4 rows

**Expected Output:**
- Status Code: 200 (success)
- Records processed: 4 per file
- Parquet files created in `./output/` directory
- CloudWatch metrics published

### Output Files

Parquet files are created in `./output/` directory:
- `lca-persist-input.parquet`
- `dxa-persist-input.parquet`

Each file contains:
- 15 columns (excluding partition columns)
- 4 rows (2xx status codes are skipped, only errors processed)
- Snappy compression

## Unit Tests

Run unit tests:

```bash
pytest test_unit.py -v
```

Expected: All 19 tests pass ✅

## Local Testing with Mock S3

Test Lambda function locally without AWS:

```bash
python test_local.py
```

## Testing in AWS

### 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Upload Test Data

```bash
# Upload test file to source bucket
aws s3 cp test_data/lca-persist-input.json \
  s3://fhir-lca-persist/test/lca-persist-input.json

# Or upload dxa-persist file
aws s3 cp test_data/dxa-persist-input.json \
  s3://fhir-dxa-persist/test/dxa-persist-input.json
```

### 3. Check Lambda Logs

```bash
# View recent logs
aws logs tail /aws/lambda/fhir-analytics-json-to-parquet --follow

# Or use CloudWatch Console
# https://console.aws.amazon.com/cloudwatch/
```

### 4. Verify Parquet Output

```bash
# List Parquet files in target bucket
aws s3 ls s3://fhir-ingest-analytics/data/ --recursive

# Download and inspect
aws s3 cp s3://fhir-ingest-analytics/data/source=lca-persist/ingest_date=2025-12-09/hour=18/lca-persist-input.parquet \
  ./output/aws-output.parquet
```

### 5. Query in Athena

1. Go to [Athena Console](https://console.aws.amazon.com/athena/)
2. Select workgroup: `fhir-analytics`
3. Select database: `fhir_analytics`
4. Run test queries (see below)

## Athena Test Queries

### Basic Queries

```sql
-- Count all records
SELECT COUNT(*) as total_records
FROM fhir_analytics.fhir_ingest_analytics;

-- Count by source
SELECT 
  source,
  COUNT(*) as record_count
FROM fhir_analytics.fhir_ingest_analytics
GROUP BY source
ORDER BY record_count DESC;
```

### Error Analysis

```sql
-- Error analysis by status code
SELECT 
  source,
  statusCode,
  COUNT(*) as error_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE statusCode IS NOT NULL
  AND statusCode NOT BETWEEN 200 AND 299
GROUP BY source, statusCode
ORDER BY error_count DESC;

-- Operation outcome details
SELECT 
  operationOutcomeSeverity,
  operationOutcomeCode,
  operationOutcomeDetail,
  COUNT(*) as count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeDetail IS NOT NULL
GROUP BY operationOutcomeSeverity, operationOutcomeCode, operationOutcomeDetail
ORDER BY count DESC
LIMIT 20;
```

### Performance Analysis

```sql
-- Latency analysis
SELECT 
  source,
  ingest_date,
  AVG(latencyMs) as avg_latency_ms,
  MAX(latencyMs) as max_latency_ms,
  APPROX_PERCENTILE(latencyMs, 0.95) as p95_latency_ms
FROM fhir_analytics.fhir_ingest_analytics
WHERE latencyMs IS NOT NULL
  AND ingest_date >= DATE_FORMAT(DATE_ADD('day', -7, CURRENT_DATE), '%Y-%m-%d')
GROUP BY source, ingest_date
ORDER BY ingest_date DESC;
```

### Data Quality Checks

```sql
-- Check for null values
SELECT 
  source,
  COUNT(*) as total_rows,
  SUM(CASE WHEN patientId IS NULL THEN 1 ELSE 0 END) as null_patient_id,
  SUM(CASE WHEN customerId IS NULL THEN 1 ELSE 0 END) as null_customer_id
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date >= DATE_FORMAT(DATE_ADD('day', -7, CURRENT_DATE), '%Y-%m-%d')
GROUP BY source;
```

## Troubleshooting

### Lambda Function Issues

**Problem:** Lambda times out
- **Solution:** Check CloudWatch logs for errors
- **Check:** File size (large files may timeout)
- **Fix:** Increase timeout in Terraform variables

**Problem:** No Parquet files created
- **Solution:** Check Lambda execution logs
- **Check:** IAM permissions for S3 write
- **Check:** Target bucket exists and is accessible

**Problem:** Errors in processing
- **Solution:** Review error categories in CloudWatch metrics
- **Check:** JSON structure matches expected format
- **Check:** Source field in meta is correct

### Athena Query Issues

**Problem:** No data returned
- **Solution:** Verify Parquet files exist in S3
- **Check:** Partition projection is enabled
- **Check:** Date range in WHERE clause matches data
- **Check:** Source values match partition values

**Problem:** Query fails with schema error
- **Solution:** Verify Glue table schema matches Parquet files
- **Check:** Run `MSCK REPAIR TABLE` if needed (not needed with projection)
- **Check:** Column names match exactly

**Problem:** Query is slow
- **Solution:** Use partition filters (source, ingest_date, hour)
- **Check:** Query only necessary columns
- **Check:** Use LIMIT for testing

## Test Checklist

- [ ] Unit tests pass (`pytest test_unit.py`)
- [ ] Local Lambda test passes (`python test_lambda_athena.py`)
- [ ] Parquet files created in `./output/`
- [ ] Terraform deployment successful
- [ ] Test files uploaded to S3 source bucket
- [ ] Lambda processes files successfully
- [ ] Parquet files appear in S3 target bucket
- [ ] Athena queries return results
- [ ] CloudWatch metrics visible
- [ ] CloudWatch alarms configured

## Next Steps

1. **Deploy to AWS:** `cd terraform && terraform apply`
2. **Upload test data:** Use AWS CLI or Console
3. **Monitor:** Check CloudWatch logs and metrics
4. **Query:** Run Athena queries to verify data
5. **Scale:** Process production data

