# Test Data

Sample JSON files for testing the Lambda function.

## Test Files

| File | Description | Records | operationOutcome | Expected Rows |
|------|-------------|---------|------------------|---------------|
| `example_payload.json` | Mixed scenarios | 3 | 0, 1, 2 | 4 rows |
| `test_success.json` | Success case | 1 | 0 (empty) | 1 row |
| `test_single_error.json` | Single error | 1 | 1 error | 1 row |
| `test_multiple_errors.json` | Multiple errors | 1 | 3 errors | 3 rows (exploded) |

## Usage

### Upload to AWS for Testing

```bash
# Upload a test file
aws s3 cp test_data/example_payload.json s3://your-source-bucket/test/

# Watch the logs
aws logs tail /aws/lambda/fhir-analytics-json-to-parquet --follow
```

### OperationOutcome Explosion Example

**Input:** `test_multiple_errors.json` (1 record with 3 operationOutcome entries)

**Output:** 3 Parquet rows

| patientId | operationOutcomeLocation | operationOutcomeSeverity |
|-----------|-------------------------|-------------------------|
| PT-ERROR-002 | Patient.name[0] | error |
| PT-ERROR-002 | Patient.birthDate | warning |
| PT-ERROR-002 | Patient.identifier[0] | error |

## Schema

Each JSON file follows this structure (s3Filename and source are added by Lambda):

```json
{
  "approximateReceiveCount": integer,
  "customerId": "string",
  "patientId": "string",
  "sourceFhirServer": "string",
  "requestResourceId": "string",
  "bundleResourceType": "string",
  "statusCode": integer,
  "operationOutcome": [
    {
      "location": "string",
      "severity": "string",
      "code": "string",
      "detail": "string"
    }
  ],
  "responseTs": "timestamp",
  "latencyMs": integer,
  "datastoreId": "string"
}
```

