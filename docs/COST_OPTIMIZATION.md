# Cost Optimization Guide

## S3 Versioning - Not Required! 💰

**S3 versioning is disabled by default** to reduce costs. It's not needed for this Lambda use case.

### Cost Impact

| Feature | Monthly Cost | Required? |
|---------|---------------|-----------|
| S3 Versioning (disabled) | $0.00 | ❌ No |
| S3 Versioning (enabled) | $0.023/GB stored | ❌ No |
| S3 Standard Storage | $0.023/GB | ✅ Yes |

**Example:** 10GB with versioning = $0.23 + $0.23 = **$0.46/month**  
**Without versioning:** 10GB = **$0.23/month** (50% savings)

### When to Enable Versioning

✅ **Enable if:**
- Production environment with compliance requirements
- Need to recover from accidental deletions
- Audit trail required

❌ **Disable if:**
- Development/testing (default)
- Cost optimization priority
- Data can be regenerated

### Configuration

**Default (Cost Optimized):**
```hcl
# terraform.tfvars
enable_s3_versioning = false  # Saves ~50% on storage costs
```

**Production (If Needed):**
```hcl
# terraform.tfvars
enable_s3_versioning = true  # For compliance/audit
```

## Other Cost Optimizations

### 1. CloudWatch Log Retention

**Default:** 7 days  
**Cost:** $0.50/GB ingested + $0.03/GB/month stored

**Optimize:**
```hcl
# terraform/variables.tf
variable "log_retention_days" {
  default = 1  # Instead of 7 or 30
}
```

**Savings:** ~85% reduction in log storage costs

### 2. Lambda Memory & Reserved Concurrency

**Default:** 512MB, Reserved Concurrency: 10  
**Cost:** $0.0000166667/GB-second

**Optimize:**
```hcl
# terraform/terraform.tfvars
lambda_memory_size = 256  # For small files
lambda_reserved_concurrency = 5  # Limit concurrent executions
```

**Benefits:**
- Reserved concurrency prevents runaway costs from unexpected scaling
- Memory tuning reduces compute costs
- Configurable via Terraform variables

### 3. S3 Storage Class

**Default:** Standard  
**Cost:** $0.023/GB

**For Archive Data:**
```hcl
# Add lifecycle policy in terraform/main.tf
resource "aws_s3_bucket_lifecycle_configuration" "target" {
  bucket = aws_s3_bucket.target.id
  
  rule {
    id     = "archive-old-data"
    status = "Enabled"
    
    transition {
      days          = 90
      storage_class = "STANDARD_IA"  # $0.0125/GB (45% cheaper)
    }
  }
}
```

### 4. Athena Query Optimization

**Cost:** $5/TB scanned

**Optimize:**
```sql
-- Bad: Scans all data
SELECT * FROM table;

-- Good: Uses partition pruning
SELECT * FROM table
WHERE source = 'lca-persist'
  AND ingest_date = '2025-12-05'
  AND hour = '14';
```

**Savings:** 99%+ reduction in scan costs

### 5. Delete Unused Resources

```bash
# Delete old CloudWatch logs
aws logs delete-log-group --log-group-name /aws/lambda/fhir-analytics-json-to-parquet

# Empty test buckets
aws s3 rm s3://your-bucket/test/ --recursive

# Delete old Parquet files (if not needed)
aws s3 rm s3://your-bucket/data/ --recursive
```

## Cost Breakdown (Optimized)

### Development/Testing (1GB data, 1000 invocations/month)

| Service | Cost |
|---------|------|
| Lambda (1000 invocations @ 256MB) | $0.10 |
| S3 Storage (1GB, no versioning) | $0.02 |
| S3 Requests | $0.01 |
| CloudWatch Logs (100MB, 1 day retention) | $0.05 |
| Athena (10 queries @ 10MB each) | $0.00 |
| **Total** | **~$0.18/month** |

### Production (100GB data, 100K invocations/month)

| Service | Cost |
|---------|------|
| Lambda (100K invocations @ 512MB) | $10.00 |
| S3 Storage (100GB, no versioning) | $2.30 |
| S3 Requests | $0.50 |
| CloudWatch Logs (10GB, 7 day retention) | $5.00 |
| Athena (1000 queries @ 100MB each) | $5.00 |
| **Total** | **~$22.80/month** |

## Cost Monitoring

### Set Up Billing Alerts

```bash
# Create budget alert
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "lambda-analytics-budget",
    "BudgetLimit": {"Amount": "10", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "your-email@example.com"
    }]
  }]'
```

### Check Current Costs

```bash
# Daily cost
aws ce get-cost-and-usage \
  --time-period Start=2025-12-05,End=2025-12-06 \
  --granularity DAILY \
  --metrics BlendedCost

# By service
aws ce get-cost-and-usage \
  --time-period Start=2025-12-01,End=2025-12-08 \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=SERVICE
```

## Summary

✅ **S3 Versioning:** Disabled by default (saves ~50% storage cost)  
✅ **Log Retention:** 7 days default (reduce to 1 day for dev)  
✅ **Lambda Memory:** 512MB default (reduce to 256MB for small files)  
✅ **Partition Queries:** Always use partition filters in Athena  
✅ **Cleanup:** Delete test resources regularly  

**Expected cost for testing:** < $0.20/month  
**Expected cost for production:** ~$20-30/month (100GB, 100K invocations)

---

**Remember:** The $5 you saw was likely from:
1. VPC NAT Gateway (if used) - $30-45/month
2. Many Athena queries without partition filters
3. S3 versioning enabled (if it was on)
4. Long CloudWatch log retention

Disable versioning and optimize the above to keep costs low! 💰

