# Terraform Destroy Guide

## Safe Destruction of Resources

### Quick Destroy (Dev/Test)

If `force_destroy_buckets = true` in your `terraform.tfvars`:

```bash
cd terraform
terraform destroy
```

This will delete **everything** including S3 buckets with all their contents.

### Production-Safe Destroy

For production environments where you want to preserve data:

#### Option 1: Set force_destroy to false

```hcl
# terraform.tfvars
force_destroy_buckets = false  # Prevent accidental data deletion
```

Then:

```bash
# This will fail if buckets contain objects (which is good for production!)
terraform destroy
```

#### Option 2: Manual Bucket Cleanup

```bash
# 1. Backup data first
aws s3 sync s3://fhir-ingest-analytics s3://backup-bucket/

# 2. Empty buckets manually
aws s3 rm s3://fhir-lca-persist/ --recursive
aws s3 rm s3://fhir-ingest-analytics/ --recursive

# 3. Now destroy
terraform destroy
```

## Partial Destroy

### Destroy Specific Resources

```bash
# Destroy only Lambda
terraform destroy -target=aws_lambda_function.analytics_lambda

# Destroy only Glue resources
terraform destroy -target=aws_glue_catalog_table.fhir_ingest_analytics
terraform destroy -target=aws_glue_catalog_database.fhir_analytics

# Destroy only S3 buckets (if force_destroy is true)
terraform destroy -target=aws_s3_bucket.source
terraform destroy -target=aws_s3_bucket.target
```

### Keep Buckets, Destroy Everything Else

```bash
# Remove buckets from state (keeps them in AWS)
terraform state rm aws_s3_bucket.source
terraform state rm aws_s3_bucket.target
terraform state rm aws_s3_bucket_versioning.source
terraform state rm aws_s3_bucket_versioning.target
terraform state rm aws_s3_bucket_server_side_encryption_configuration.source
terraform state rm aws_s3_bucket_server_side_encryption_configuration.target
terraform state rm aws_s3_bucket_notification.source_bucket_notification

# Now destroy everything else
terraform destroy
```

## Troubleshooting Destroy Issues

### Issue: Bucket not empty error

```
Error: error deleting S3 Bucket (bucket-name): BucketNotEmpty: The bucket you tried to delete is not empty
```

**Solutions:**

**A. Enable force_destroy (Dev/Test)**

```hcl
# terraform.tfvars
force_destroy_buckets = true
```

```bash
terraform apply  # Apply the change first
terraform destroy  # Now destroy works
```

**B. Empty buckets manually (Production)**

```bash
# Empty source bucket
aws s3 rm s3://fhir-lca-persist/ --recursive

# Empty target bucket
aws s3 rm s3://fhir-ingest-analytics/ --recursive

# Delete versioned objects
aws s3api delete-objects \
  --bucket fhir-ingest-analytics \
  --delete "$(aws s3api list-object-versions \
    --bucket fhir-ingest-analytics \
    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"

# Now destroy
terraform destroy
```

### Issue: Lambda function has event source mappings

```
Error: Cannot delete function because it has event source mappings
```

**Solution:**

```bash
# Remove S3 notification first
terraform destroy -target=aws_s3_bucket_notification.source_bucket_notification

# Then destroy the rest
terraform destroy
```

### Issue: Glue table in use

```
Error: Cannot delete table while it's being used
```

**Solution:**

```bash
# Wait a few seconds and retry
sleep 10
terraform destroy
```

## Best Practices

### Development Environment

```hcl
# terraform.tfvars
environment = "dev"
force_destroy_buckets = true  # OK for dev
```

### Staging Environment

```hcl
# terraform.tfvars
environment = "staging"
force_destroy_buckets = true  # Usually OK for staging
```

### Production Environment

```hcl
# terraform.tfvars
environment = "prod"
force_destroy_buckets = false  # NEVER set true in production!
```

## Complete Cleanup Script

For dev/test environments:

```bash
#!/bin/bash
# cleanup.sh - Complete cleanup script

set -e

echo "🧹 Starting cleanup..."

# Set force_destroy if not already set
if ! grep -q "force_destroy_buckets = true" terraform.tfvars; then
  echo "force_destroy_buckets = true" >> terraform.tfvars
  echo "✓ Enabled force_destroy"
fi

# Apply to enable force_destroy
echo "📝 Applying force_destroy setting..."
terraform apply -auto-approve

# Destroy everything
echo "💥 Destroying all resources..."
terraform destroy -auto-approve

echo "✅ Cleanup complete!"
```

Usage:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

## Data Backup Before Destroy

Always backup important data:

```bash
# Backup Parquet files
aws s3 sync s3://fhir-ingest-analytics/ ./backup/analytics/

# Backup JSON files
aws s3 sync s3://fhir-lca-persist/ ./backup/source/

# Verify backup
ls -lh ./backup/
```

## Selective Destroy Examples

### Keep Data, Remove Infrastructure

```bash
# Remove Lambda and related resources
terraform destroy \
  -target=aws_lambda_function.analytics_lambda \
  -target=aws_lambda_layer_version.awswrangler \
  -target=aws_iam_role.lambda_role \
  -target=aws_cloudwatch_log_group.lambda_logs

# Keep: S3 buckets, Glue catalog
```

### Remove Everything Except Glue

```bash
# Remove from state (keeps in AWS)
terraform state rm aws_glue_catalog_table.fhir_ingest_analytics
terraform state rm aws_glue_catalog_database.fhir_analytics

# Destroy rest
terraform destroy
```

## Emergency: Force Remove from State

If resources are already deleted manually:

```bash
# Remove specific resource
terraform state rm aws_lambda_function.analytics_lambda

# Remove all S3 resources
terraform state list | grep aws_s3 | xargs -I {} terraform state rm {}

# Clean state
terraform refresh
```

## Post-Destroy Verification

```bash
# Check Lambda
aws lambda list-functions --query "Functions[?FunctionName=='fhir-analytics-json-to-parquet']"

# Check S3 buckets
aws s3 ls | grep fhir

# Check Glue
aws glue get-databases --query "DatabaseList[?Name=='fhir_analytics']"

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/fhir-analytics
```

## Summary

| Environment | force_destroy_buckets | Action |
|-------------|----------------------|---------|
| **Dev** | `true` | Just run `terraform destroy` ✅ |
| **Staging** | `true` or `false` | Consider data importance |
| **Production** | `false` | Manual backup + cleanup required |

---

**⚠️ Warning:** Setting `force_destroy_buckets = true` in production can lead to **permanent data loss**. Always backup first!

