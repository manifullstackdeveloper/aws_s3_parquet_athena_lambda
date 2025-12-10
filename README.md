# Analytics Lambda: JSON to Parquet Converter

AWS Lambda solution that reads JSON files from S3, flattens nested structures (including operationOutcome array explosion), converts to Parquet format with Snappy compression, and writes partitioned output to an analytics bucket.

## Features

- ✅ **OperationOutcome Explosion** - Arrays exploded into multiple rows
- ✅ Automatic JSON flattening using pandas
- ✅ Parquet output with Snappy compression
- ✅ Time-based partitioning (source, ingest_date, hour)
- ✅ AWS Glue catalog integration with partition projection
- ✅ Complete Terraform infrastructure as code

## Prerequisites

- AWS Account with appropriate permissions
- Terraform 1.0+
- Python 3.12+ (for local development)

## Quick Start

### 1. Build Lambda Package

```bash
./build.sh
```

This creates `lambda_function.zip` ready for deployment.

### 2. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit with your unique bucket names
vim terraform.tfvars
```

Update these values:
```hcl
source_bucket = "your-unique-source-bucket-name"
target_bucket = "your-unique-target-bucket-name"
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

This creates:
- ✅ S3 source & target buckets
- ✅ Lambda function with AWS public layer
- ✅ IAM roles & policies
- ✅ S3 event notification
- ✅ CloudWatch log group
- ✅ Glue database & table

### 4. Test End-to-End

```bash
# Upload test JSON file
aws s3 cp example_payload.json s3://your-source-bucket/test/

# Check CloudWatch logs
aws logs tail /aws/lambda/fhir-analytics-json-to-parquet --follow

# Query in Athena
# Go to https://console.aws.amazon.com/athena/
SELECT * FROM fhir_analytics.fhir_ingest_analytics LIMIT 10;
```

## Architecture

```
S3 Source (JSON) → Lambda (Conversion) → S3 Target (Parquet) → Glue/Athena (Analytics)
```

### How It Works

1. JSON files uploaded to source bucket trigger Lambda
2. Lambda reads, flattens (including operationOutcome arrays), and converts to Parquet
3. Output written to target bucket with partitioning: `source=X/ingest_date=Y/hour=Z/`
4. Glue catalog automatically recognizes partitions
5. Query immediately in Athena

## OperationOutcome Explosion

Input JSON with multiple issues in an array becomes multiple Parquet rows:

**Input (1 record):**
```json
{
  "patientId": "PT-001",
  "operationOutcome": [
    {"location": "Patient.name", "severity": "error"},
    {"location": "Patient.birthDate", "severity": "warning"}
  ]
}
```

**Output (2 rows):**
| patientId | operationOutcomeLocation | operationOutcomeSeverity |
|-----------|-------------------------|-------------------------|
| PT-001 | Patient.name | error |
| PT-001 | Patient.birthDate | warning |

## 📁 Project Structure

```
.
├── lambda_function.py           # Main Lambda handler
├── requirements.txt             # Python dependencies
├── example_payload.json         # Sample input data
├── iam_policy.json             # IAM policy document
├── athena_ddl.sql              # Athena/Glue table definitions
├── build.sh                     # Build script for deployment packages
├── README.md                    # This file
└── terraform/
    ├── main.tf                  # Main Terraform configuration
    ├── variables.tf             # Variable definitions
    └── terraform.tfvars.example # Example configuration
```

## 🔧 Prerequisites

- AWS Account with appropriate permissions
- Python 3.12+
- Terraform 1.0+
- AWS CLI configured
- S3 buckets created:
  - Source: `fhir-lca-persist`
  - Target: `fhir-ingest-analytics`

## 🚀 Quick Start

### 1. Clone and Build

```bash
# Clone or navigate to the project directory
cd aws_s3_parquet_glue_athena

# Build Lambda packages
chmod +x build.sh
./build.sh
```

This creates:
- `lambda_function.zip` - Lambda code
- `lambda_layer.zip` - Dependencies layer (awswrangler, pandas, pyarrow)

### 2. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
vim terraform.tfvars
```

Example `terraform.tfvars`:

```hcl
aws_region         = "us-east-1"
environment        = "prod"
source_bucket      = "fhir-lca-persist"
target_bucket      = "fhir-ingest-analytics"
s3_filter_prefix   = ""
log_retention_days = 30
```

### 3. Deploy with Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 4. Query in Athena

**Everything is ready!** Glue database, table, and Athena workgroup are created by Terraform.

```bash
# Open Athena Console
# https://console.aws.amazon.com/athena/

# Select:
# - WorkGroup: fhir-analytics
# - Database: fhir_analytics
# - Table: fhir_ingest_analytics

# Start querying immediately!
```

Or use AWS CLI:
```bash
aws athena start-query-execution \
  --work-group fhir-analytics \
  --query-string "SELECT * FROM fhir_analytics.fhir_ingest_analytics LIMIT 10" \
  --result-configuration OutputLocation=s3://fhir-ingest-analytics-athena-results/results/
```

### 5. Test

Upload a test JSON file:

```bash
aws s3 cp example_payload.json s3://fhir-lca-persist/test/
```

Check CloudWatch Logs and S3 target bucket for results.

## ⚙️ Configuration

### Environment Variables

The Lambda function is configured via environment variables (set by Terraform):

| Variable | Default | Description |
|----------|---------|-------------|
| `SOURCE_BUCKET` | `fhir-lca-persist` | Source S3 bucket |
| `TARGET_BUCKET` | `fhir-ingest-analytics` | Target S3 bucket |
| `LOG_LEVEL` | `INFO` | Logging level |

**Note:** These are automatically set by Terraform - no manual configuration needed.

## 📦 Deployment

### Manual Deployment (without Terraform)

If you prefer manual deployment:

```bash
# Create Lambda function
aws lambda create-function \
  --function-name fhir-analytics-json-to-parquet \
  --runtime python3.12 \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --timeout 300 \
  --memory-size 512

# Publish layer
aws lambda publish-layer-version \
  --layer-name awswrangler-layer \
  --zip-file fileb://lambda_layer.zip \
  --compatible-runtimes python3.12

# Update function to use layer
aws lambda update-function-configuration \
  --function-name fhir-analytics-json-to-parquet \
  --layers arn:aws:lambda:REGION:ACCOUNT_ID:layer:awswrangler-layer:1
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Lambda

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.12'
      - name: Build
        run: ./build.sh
      - name: Deploy with Terraform
        working-directory: terraform
        run: |
          terraform init
          terraform apply -auto-approve
```

## 🔍 Athena Setup

**All Athena resources are automatically created by Terraform!**

- ✅ Glue Database: `fhir_analytics`
- ✅ Glue Table: `fhir_ingest_analytics`
- ✅ Athena WorkGroup: `fhir-analytics`
- ✅ Query Results Bucket: `{target-bucket}-athena-results`

**No manual SQL execution needed!** Just run `terraform apply` and start querying.

### Query Examples

```sql
-- Count records by source
SELECT source, COUNT(*) as total
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date = '2025-12-03'
GROUP BY source;

-- Error analysis
SELECT statusCode, COUNT(*) as error_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE statusCode >= 400
  AND ingest_date >= '2025-12-01'
GROUP BY statusCode
ORDER BY error_count DESC;

-- Latency analysis
SELECT 
  source,
  AVG(latencyMs) as avg_latency,
  MAX(latencyMs) as max_latency,
  APPROX_PERCENTILE(latencyMs, 0.95) as p95_latency
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date >= '2025-12-01'
GROUP BY source;
```

## Testing

Upload a JSON file and verify it's processed:

```bash
# Upload test file
aws s3 cp example_payload.json s3://your-source-bucket/test/

# Check logs
aws logs tail /aws/lambda/fhir-analytics-json-to-parquet --follow

# Verify Parquet output
aws s3 ls s3://your-target-bucket/data/ --recursive

# Query in Athena
aws athena start-query-execution \
  --query-string "SELECT * FROM fhir_analytics.fhir_ingest_analytics LIMIT 10" \
  --result-configuration OutputLocation=s3://your-athena-results/
```

## Monitoring

**Monitoring is automatically configured by Terraform!**

### CloudWatch Alarms (Auto-created)
- Error rate alarm
- Duration alarm (80% of timeout)
- Throttles alarm
- Fatal errors alarm

### Custom Metrics (Published by Lambda)
- `Errors` - By error category
- `FilesProcessed` - Successfully processed files
- `FilesFailed` - Failed file processing
- `InvocationDuration` - Execution time
- `ParquetWriteDuration` - Write performance
- `RecordsProcessed` - Number of records

### View Logs

```bash
aws logs tail /aws/lambda/fhir-analytics-json-to-parquet --follow
```

### Error Triage

Errors are categorized for easy triage:
- `ConfigurationError` - Config issues
- `S3ReadError` - S3 read failures
- `S3WriteError` - S3 write failures
- `JSONParseError` - JSON parsing errors
- `JSONValidationError` - Schema validation
- `DataTransformationError` - Data processing issues
- `PartitioningError` - Partition generation issues

View error breakdown in CloudWatch Metrics → `FHIRAnalytics/Lambda` namespace.

## Troubleshooting

**Athena returns no data:**
- Check that Parquet files exist in S3
- Verify partition projection is enabled in Glue table

**Lambda timeout:**
- Increase timeout in `terraform/variables.tf` or AWS console
- Default is 300 seconds (5 minutes)

**Permission errors:**
- Verify IAM role has S3 read/write permissions
- Check CloudWatch logs for detailed error messages

**Duplicate column error in Athena:**
- The Glue table schema has been fixed to not include partition columns in data columns
- Run `terraform apply` to update the table

## S3 Output Structure

```
s3://your-target-bucket/data/
├── source=lca-persist/
│   └── ingest_date=2025-12-05/
│       └── hour=14/
│           └── file.parquet
└── source=dxa-persist/
    └── ingest_date=2025-12-05/
        └── hour=15/
            └── file.parquet
```

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Note:** Set `force_destroy_buckets = true` in `terraform.tfvars` to allow bucket deletion with contents.

## Documentation

- **README.md** (this file) - Quick start guide
- **docs/DEPLOYMENT_GUIDE.md** - Detailed deployment instructions
- **docs/PROJECT_STRUCTURE.md** - Project organization
- **docs/** - Additional reference documentation

---

**Production-ready AWS Lambda solution for JSON to Parquet conversion with Glue/Athena integration.**

