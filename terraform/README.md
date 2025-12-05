# Terraform Configuration

## Quick Start

### 1. Create Configuration File

```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

### 2. Update Required Variables

```hcl
source_bucket = "your-source-bucket-name"
target_bucket = "your-target-bucket-name"
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Configuration Options

### Lambda Layer Options

**Option 1: AWS Public Layer (Recommended)**

No build required, just use AWS's pre-built layer:

```hcl
use_aws_public_layer = true
lambda_layer_zip_path = ""
```

**Option 2: Custom Layer**

Build your own layer if you need custom dependencies:

```bash
# Build layer first
cd ..
./build.sh

# Then configure
```

```hcl
use_aws_public_layer = false
lambda_layer_zip_path = "../lambda_layer.zip"
```

### SSM Parameters

If your IAM user lacks SSM permissions:

```hcl
create_ssm_parameters = false
```

The Lambda will use environment variables instead.

### Glue Configuration

Customize database, table, and partitions:

```hcl
glue_database_name = "fhir_analytics"
glue_table_name = "fhir_ingest_analytics"
glue_partition_sources = ["lca-persist", "dxa-persist", "custom-source"]
glue_partition_date_start = "2024-01-01"
```

## Troubleshooting

### SSM Permission Error

```
Error: User is not authorized to perform: ssm:PutParameter
```

**Solution:** Set `create_ssm_parameters = false` in `terraform.tfvars`

### Lambda Layer Too Large

```
Error: Request must be smaller than 70167211 bytes
```

**Solution:** Use AWS public layer by setting `use_aws_public_layer = true`

### Missing IAM Permissions

Ensure your AWS credentials have permissions for:
- Lambda (create function, layer)
- IAM (create role, attach policies)
- S3 (configure notifications)
- CloudWatch (create log groups)
- Glue (create database, table)

## Minimum Required Variables

```hcl
# terraform.tfvars
source_bucket = "your-source-bucket"  # Will be created
target_bucket = "your-target-bucket"  # Will be created
lambda_zip_path = "../lambda_function.zip"
use_aws_public_layer = true
create_ssm_parameters = false
create_buckets = true  # Terraform creates buckets
```

**Note:** S3 bucket names must be globally unique. Update `source_bucket` and `target_bucket` to unique names.

## Outputs

After `terraform apply`, you'll see:

```
Outputs:

lambda_function_name = "fhir-analytics-json-to-parquet"
lambda_function_arn = "arn:aws:lambda:..."
lambda_layer_arn = "arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python312:13"
using_aws_public_layer = true
glue_database_name = "fhir_analytics"
glue_table_name = "fhir_ingest_analytics"
source_bucket = "your-source-bucket"
target_bucket = "your-target-bucket"
```

