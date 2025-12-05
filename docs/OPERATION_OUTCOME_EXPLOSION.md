# OperationOutcome Array Explosion

## Overview

The Lambda function automatically **explodes** `operationOutcome` arrays into multiple Parquet rows. Each operationOutcome entry becomes a separate row with the same base record information.

## Input JSON Structure

```json
{
  "s3Filename": "test.json",
  "patientId": "PT-001",
  "statusCode": 422,
  "operationOutcome": [
    {
      "location": "Patient.name[0]",
      "severity": "error",
      "code": "invalid",
      "detail": "Name is required"
    },
    {
      "location": "Patient.birthDate",
      "severity": "warning",
      "code": "missing",
      "detail": "Birth date not provided"
    }
  ],
  "responseTs": "2025-12-05T12:00:00.000Z",
  "latencyMs": 350
}
```

## Output Parquet Rows

This single JSON record becomes **2 Parquet rows**:

| s3Filename | patientId | statusCode | operationOutcomeLocation | operationOutcomeSeverity | operationOutcomeCode | operationOutcomeDetail | responseTs | latencyMs |
|------------|-----------|------------|-------------------------|-------------------------|---------------------|----------------------|------------|-----------|
| test.json | PT-001 | 422 | Patient.name[0] | error | invalid | Name is required | 2025-12-05T12:00:00Z | 350 |
| test.json | PT-001 | 422 | Patient.birthDate | warning | missing | Birth date not provided | 2025-12-05T12:00:00Z | 350 |

## Visual Flow

```mermaid
graph TD
    A[Input JSON<br/>1 record] --> B{Has<br/>operationOutcome<br/>array?}
    B -->|No| C[Single Row<br/>NULL outcome fields]
    B -->|Yes, empty| C
    B -->|Yes, 1 item| D[Single Row<br/>with outcome data]
    B -->|Yes, N items| E[N Rows<br/>exploded]
    
    E --> E1[Row 1: Base + Outcome[0]]
    E --> E2[Row 2: Base + Outcome[1]]
    E --> E3[Row N: Base + Outcome[N-1]]
    
    style A fill:#4CAF50,color:#fff
    style E fill:#FF9800,color:#fff
    style E1 fill:#2196F3,color:#fff
    style E2 fill:#2196F3,color:#fff
    style E3 fill:#2196F3,color:#fff
```

## Example Scenarios

### Scenario 1: Success (No Issues)

**Input:**
```json
{
  "s3Filename": "success.json",
  "patientId": "PT-001",
  "statusCode": 200,
  "operationOutcome": []
}
```

**Output:** 1 row with NULL operationOutcome fields

| patientId | statusCode | operationOutcomeLocation | operationOutcomeSeverity | operationOutcomeCode | operationOutcomeDetail |
|-----------|------------|-------------------------|-------------------------|---------------------|----------------------|
| PT-001 | 200 | NULL | NULL | NULL | NULL |

---

### Scenario 2: Single Issue

**Input:**
```json
{
  "s3Filename": "single-issue.json",
  "patientId": "PT-002",
  "statusCode": 400,
  "operationOutcome": [
    {
      "location": "Patient.identifier",
      "severity": "error",
      "code": "invalid",
      "detail": "Missing required identifier"
    }
  ]
}
```

**Output:** 1 row with operationOutcome data

| patientId | statusCode | operationOutcomeLocation | operationOutcomeSeverity | operationOutcomeCode | operationOutcomeDetail |
|-----------|------------|-------------------------|-------------------------|---------------------|----------------------|
| PT-002 | 400 | Patient.identifier | error | invalid | Missing required identifier |

---

### Scenario 3: Multiple Issues

**Input:**
```json
{
  "s3Filename": "multi-issue.json",
  "patientId": "PT-003",
  "statusCode": 422,
  "operationOutcome": [
    {
      "location": "Patient.name[0]",
      "severity": "error",
      "code": "invalid",
      "detail": "Name is required"
    },
    {
      "location": "Patient.birthDate",
      "severity": "warning",
      "code": "missing",
      "detail": "Birth date not provided"
    },
    {
      "location": "Patient.identifier[0]",
      "severity": "error",
      "code": "invalid",
      "detail": "Invalid identifier format"
    }
  ]
}
```

**Output:** 3 rows (exploded from 1 input record)

| patientId | statusCode | operationOutcomeLocation | operationOutcomeSeverity | operationOutcomeCode | operationOutcomeDetail |
|-----------|------------|-------------------------|-------------------------|---------------------|----------------------|
| PT-003 | 422 | Patient.name[0] | error | invalid | Name is required |
| PT-003 | 422 | Patient.birthDate | warning | missing | Birth date not provided |
| PT-003 | 422 | Patient.identifier[0] | error | invalid | Invalid identifier format |

---

## Athena Queries

### Count issues by severity

```sql
SELECT 
  operationOutcomeSeverity,
  COUNT(*) as issue_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeSeverity IS NOT NULL
  AND ingest_date >= '2025-12-01'
GROUP BY operationOutcomeSeverity
ORDER BY issue_count DESC;
```

### Most common error codes

```sql
SELECT 
  operationOutcomeCode,
  COUNT(*) as occurrence_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NOT NULL
  AND ingest_date >= '2025-12-01'
GROUP BY operationOutcomeCode
ORDER BY occurrence_count DESC
LIMIT 10;
```

### Records with multiple issues

```sql
SELECT 
  s3Filename,
  patientId,
  COUNT(*) as issue_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NOT NULL
  AND ingest_date >= '2025-12-01'
GROUP BY s3Filename, patientId
HAVING COUNT(*) > 1
ORDER BY issue_count DESC;
```

### Error details by patient

```sql
SELECT 
  patientId,
  operationOutcomeLocation,
  operationOutcomeSeverity,
  operationOutcomeCode,
  operationOutcomeDetail
FROM fhir_analytics.fhir_ingest_analytics
WHERE patientId = 'PT-003'
  AND operationOutcomeCode IS NOT NULL
ORDER BY operationOutcomeSeverity DESC;
```

## Implementation Details

### Lambda Function Logic

```python
# Check if operationOutcome array exists and has items
has_operation_outcomes = any(
    isinstance(record.get('operationOutcome'), list) 
    and len(record.get('operationOutcome', [])) > 0
    for record in records
)

if has_operation_outcomes:
    # Explode operationOutcome arrays into separate rows
    df = pd.json_normalize(
        records,
        record_path=['operationOutcome'],  # Explode this array
        meta=[
            's3Filename',
            'patientId',
            'statusCode',
            # ... other base fields
        ],
        errors='ignore'
    )
else:
    # No operationOutcome arrays, process normally
    df = pd.json_normalize(records)
    # Add NULL columns for operationOutcome fields
```

### Benefits

1. **Detailed Analysis**: Each issue is a separate row for easy filtering
2. **Aggregation**: Count issues by severity, code, or location
3. **Efficiency**: Parquet columnar format for fast queries
4. **Flexibility**: Query all issues or just specific types
5. **Scalability**: Handles 0 to N operationOutcome entries per record

## Testing

Test files are provided in `test_data/`:

```bash
# Test no issues (empty array)
python test_local.py --file test_single_object.json

# Test single issue
python test_local.py --file example_payload.json

# Test multiple issues (3 outcomes → 3 rows)
python test_local.py --file test_multiple_outcomes.json
```

### Expected Results

**Input:** 1 record with 3 operationOutcome entries  
**Output:** 3 Parquet rows

```
[INFO] Flattened 3 records with 16 columns
```

## Row Count Implications

### Before Explosion

**3 JSON records** in file → expect **3 Parquet rows**

### After Explosion

**3 JSON records** with:
- Record 1: 0 operationOutcome → 1 row
- Record 2: 1 operationOutcome → 1 row
- Record 3: 2 operationOutcome → 2 rows

**Total: 4 Parquet rows** (not 3!)

## Best Practices

### 1. Understand Row Multiplication

Be aware that Parquet row counts != JSON record counts when operationOutcome arrays exist.

### 2. Use DISTINCT for Record Counts

```sql
-- Correct: Count unique records
SELECT COUNT(DISTINCT s3Filename) as record_count
FROM fhir_analytics.fhir_ingest_analytics;

-- Incorrect: Counts rows (includes duplicates from explosion)
SELECT COUNT(*) as row_count
FROM fhir_analytics.fhir_ingest_analytics;
```

### 3. Filter Appropriately

```sql
-- All rows (including exploded)
SELECT * FROM fhir_analytics.fhir_ingest_analytics;

-- Only records with issues
SELECT * FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NOT NULL;

-- Only records without issues
SELECT * FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NULL;
```

### 4. Aggregation by Record

```sql
-- Issues per record
SELECT 
  s3Filename,
  COUNT(*) as total_issues,
  SUM(CASE WHEN operationOutcomeSeverity = 'error' THEN 1 ELSE 0 END) as errors,
  SUM(CASE WHEN operationOutcomeSeverity = 'warning' THEN 1 ELSE 0 END) as warnings
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NOT NULL
GROUP BY s3Filename;
```

## Troubleshooting

### Issue: Duplicate rows in output

**Cause:** This is expected! Each operationOutcome entry becomes a separate row.

**Solution:** Use `DISTINCT` or `GROUP BY` in queries to deduplicate.

### Issue: NULL operationOutcome fields

**Cause:** Record had empty `operationOutcome: []` array.

**Solution:** This is correct behavior for successful responses.

### Issue: Row count mismatch

**Cause:** Explosion creates more rows than input records.

**Solution:** Count unique `s3Filename` instead of rows.

---

**Key Takeaway:** One JSON record with N operationOutcome entries → N Parquet rows! 🎯

