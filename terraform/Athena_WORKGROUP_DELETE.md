# Athena WorkGroup Deletion Guide

## Problem

AWS Athena WorkGroups cannot be deleted if they contain query execution history. You'll see this error:

```
Error: deleting Athena WorkGroup (fhir-analytics): InvalidRequestException: 
WorkGroup fhir-analytics is not empty
```

## Solutions

### Option 1: Remove from Terraform State (Keep WorkGroup in AWS)

If you want to keep the WorkGroup in AWS but remove it from Terraform management:

```bash
cd terraform
terraform state rm aws_athena_workgroup.fhir_analytics
terraform apply  # This will skip the workgroup
```

**Note:** The WorkGroup will remain in AWS but won't be managed by Terraform.

### Option 2: Wait for Query History to Expire

AWS automatically deletes query history after 45 days. After that, you can delete the workgroup:

```bash
# Wait 45 days, then:
cd terraform
terraform destroy -target=aws_athena_workgroup.fhir_analytics
```

### Option 3: Delete Other Resources First

If you're doing a full destroy, delete other resources first, then handle the workgroup separately:

```bash
cd terraform

# Destroy everything except the workgroup
terraform destroy \
  -target=aws_cloudwatch_metric_alarm.lambda_errors \
  -target=aws_cloudwatch_metric_alarm.custom_error_rate \
  -target=aws_cloudwatch_metric_alarm.lambda_duration \
  -target=aws_cloudwatch_metric_alarm.lambda_throttles \
  -target=aws_cloudwatch_metric_alarm.fatal_errors \
  -target=aws_sns_topic.lambda_alerts \
  -target=aws_lambda_function.analytics_lambda \
  -target=aws_glue_catalog_table.fhir_ingest_analytics \
  -target=aws_glue_catalog_database.fhir_analytics \
  -target=aws_s3_bucket.athena_results \
  -target=aws_s3_bucket.target \
  -target=aws_s3_bucket.source

# Then remove workgroup from state
terraform state rm aws_athena_workgroup.fhir_analytics
```

### Option 4: Manual Cleanup via AWS Console

1. Go to [Athena Console](https://console.aws.amazon.com/athena/)
2. Select the workgroup: `fhir-analytics`
3. Go to "History" tab
4. Delete saved queries (if any)
5. Note: Query execution history cannot be manually deleted - it expires after 45 days

## Recommended Approach

For development environments:
- Use **Option 1** - Remove from Terraform state and keep the workgroup

For production environments:
- Use **Option 2** - Wait for query history to expire, then delete

## Prevention

To prevent this issue in the future, you can:

1. **Add lifecycle block** (already added):
   ```hcl
   lifecycle {
     prevent_destroy = false
   }
   ```

2. **Use separate workgroups** for different environments to isolate query history

3. **Set query result retention** in the workgroup configuration to auto-delete old results

## Current WorkGroup Status

Check query execution count:
```bash
aws athena list-query-executions \
  --work-group fhir-analytics \
  --query 'length(QueryExecutionIds)'
```

List query executions:
```bash
aws athena list-query-executions --work-group fhir-analytics
```

