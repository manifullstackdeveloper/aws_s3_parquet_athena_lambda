# Error Handling & Monitoring

## Overview

The Lambda function includes comprehensive error handling with categorized errors, structured logging, and CloudWatch metrics for easy triage.

## Error Categories

Errors are categorized for monitoring and triage:

| Category | Description | Common Causes |
|----------|-------------|---------------|
| `ConfigurationError` | Configuration issues | Missing env vars, invalid config |
| `S3ReadError` | S3 read failures | File not found, permission issues |
| `S3WriteError` | S3 write failures | Bucket full, permission issues |
| `JSONParseError` | JSON parsing errors | Invalid JSON syntax |
| `JSONValidationError` | JSON validation failures | Missing required fields |
| `DataTransformationError` | Data transformation issues | All 2xx status codes (skipped) |
| `PartitioningError` | Partition generation failures | Invalid timestamp format |
| `UnknownError` | Unhandled errors | Unexpected exceptions |

## Custom Error Classes

Each error category has a custom exception class:

```python
class S3ReadError(Exception):
    """S3 read operation errors"""
    category = ErrorCategory.S3_READ

class JSONParseError(Exception):
    """JSON parsing errors"""
    category = ErrorCategory.JSON_PARSE
```

## CloudWatch Metrics

### Custom Metrics Namespace

All custom metrics are published to: `FHIRAnalytics/Lambda`

### Available Metrics

| Metric | Unit | Description |
|--------|------|-------------|
| `Invocations` | Count | Total Lambda invocations |
| `Errors` | Count | Total errors (by category) |
| `ErrorsByCategory` | Count | Error breakdown by type |
| `FilesProcessed` | Count | Successfully processed files |
| `FilesFailed` | Count | Failed file processing |
| `InvocationDuration` | Seconds | Function execution time |
| `ParquetWriteDuration` | Seconds | Parquet write time |
| `RecordsProcessed` | Count | Number of records processed |
| `InputFileSize` | Bytes | Input file size |
| `ParquetFilesWritten` | Count | Parquet files written |
| `DuplicateFileSkipped` | Count | Duplicate files skipped |
| `FatalErrors` | Count | Fatal errors preventing execution |

### Viewing Metrics

```bash
# View in AWS Console
# CloudWatch → Metrics → FHIRAnalytics/Lambda

# Filter by error category
# Add dimension: ErrorCategory = S3ReadError
```

## CloudWatch Alarms

### Automatically Created Alarms

1. **Error Rate Alarm**
   - Metric: `Errors` (AWS/Lambda)
   - Threshold: 5 errors per 5 minutes
   - Action: SNS notification

2. **Custom Error Rate**
   - Metric: `Errors` (FHIRAnalytics/Lambda)
   - Threshold: 5 errors per 5 minutes
   - Action: SNS notification

3. **Duration Alarm**
   - Metric: `Duration` (AWS/Lambda)
   - Threshold: 80% of timeout
   - Action: SNS notification

4. **Throttles Alarm**
   - Metric: `Throttles` (AWS/Lambda)
   - Threshold: > 0
   - Action: SNS notification

5. **Fatal Errors Alarm**
   - Metric: `FatalErrors` (FHIRAnalytics/Lambda)
   - Threshold: > 0
   - Action: SNS notification

6. **Staleness Alarm** (Optional)
   - Metric: `Invocations` (AWS/Lambda)
   - Threshold: No invocations in 24 hours
   - Action: SNS notification

## Structured Error Logging

Errors are logged with structured context:

```json
{
  "error_type": "S3ReadError",
  "error_message": "Failed to read from s3://bucket/key",
  "error_category": "S3ReadError",
  "bucket": "fhir-lca-persist",
  "key": "test/data.json",
  "operation": "s3_get_object",
  "request_id": "abc-123-def"
}
```

## Error Triage Workflow

1. **Check CloudWatch Alarms**
   - See which alarms are triggered
   - Review alarm history

2. **View Custom Metrics**
   - Go to CloudWatch → Metrics → FHIRAnalytics/Lambda
   - Filter by ErrorCategory dimension
   - Identify error patterns

3. **Review Logs**
   - Search by request_id for full context
   - Filter by error category
   - Use CloudWatch Logs Insights

4. **Check Error Breakdown**
   - Use `ErrorsByCategory` metric
   - Identify most common error types
   - Focus on high-frequency errors

## Example: Triage S3ReadError

```bash
# 1. Check alarm
aws cloudwatch describe-alarms --alarm-names fhir-analytics-json-to-parquet-high-error-rate

# 2. View error metric
aws cloudwatch get-metric-statistics \
  --namespace FHIRAnalytics/Lambda \
  --metric-name Errors \
  --dimensions Name=ErrorCategory,Value=S3ReadError \
  --start-time 2025-12-10T00:00:00Z \
  --end-time 2025-12-10T23:59:59Z \
  --period 3600 \
  --statistics Sum

# 3. Search logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/fhir-analytics-json-to-parquet \
  --filter-pattern "[S3ReadError]"
```

## Best Practices

1. **Monitor Error Rates**
   - Set up dashboards for error trends
   - Alert on sudden spikes

2. **Review Error Categories**
   - Focus on most common errors first
   - Address root causes, not symptoms

3. **Use Request IDs**
   - Correlate errors across logs and metrics
   - Track individual request failures

4. **Set Appropriate Thresholds**
   - Adjust alarm thresholds based on normal error rates
   - Avoid alert fatigue

5. **Regular Review**
   - Weekly error category review
   - Monthly error trend analysis

