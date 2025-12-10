#!/usr/bin/env python3
"""
Test Lambda function and Athena queries end-to-end.

This script:
1. Tests Lambda function locally with sample data
2. Generates test S3 event
3. Processes JSON files and creates Parquet output
4. Provides Athena query examples to test
"""

import json
import os
import sys
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch
from datetime import datetime

# Add current directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lambda_function import lambda_handler


class MockS3Client:
    """Mock S3 client for local testing"""
    
    def __init__(self, test_data_dir="test_data"):
        self.test_data_dir = Path(test_data_dir)
        self.uploaded_files = {}
        self.file_contents = {}
        
        # Load test data files
        for test_file in self.test_data_dir.glob("*.json"):
            with open(test_file, 'r') as f:
                self.file_contents[test_file.name] = f.read()
    
    def get_object(self, Bucket, Key):
        """Mock S3 get_object - reads from local test files"""
        filename = Path(Key).name
        
        # Try to find matching test file
        for test_file in self.test_data_dir.glob("*.json"):
            if test_file.name == filename or filename in test_file.name:
                content = self.file_contents.get(test_file.name, "")
                return {
                    'Body': MockBody(content.encode('utf-8'))
                }
        
        raise Exception(f"File not found: {Key}")
    
    def head_object(self, Bucket, Key):
        """Mock S3 head_object - check if file exists"""
        if Key in self.uploaded_files:
            return {'ContentLength': len(self.uploaded_files[Key])}
        from botocore.exceptions import ClientError
        error = {'Error': {'Code': '404'}}
        raise ClientError(error, 'head_object')
    
    def put_object(self, Bucket, Key, Body):
        """Mock S3 put_object - store in memory"""
        self.uploaded_files[Key] = Body
        print(f"✅ Mock S3 Upload: s3://{Bucket}/{Key}")
        return {'ETag': 'mock-etag'}


class MockBody:
    """Mock response body"""
    def __init__(self, content):
        self.content = content
    
    def read(self):
        return self.content
    
    def decode(self, encoding='utf-8'):
        return self.content.decode(encoding)


class MockCloudWatch:
    """Mock CloudWatch client"""
    def __init__(self):
        self.metrics = []
    
    def put_metric_data(self, Namespace, MetricData):
        self.metrics.append({
            'Namespace': Namespace,
            'MetricData': MetricData
        })
        print(f"📊 Metric published: {MetricData[0]['MetricName']} = {MetricData[0]['Value']}")


def create_s3_event(bucket: str, key: str) -> dict:
    """Create S3 event for Lambda"""
    return {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": bucket},
                    "object": {"key": key}
                }
            }
        ]
    }


def test_lambda_function():
    """Test Lambda function with sample data"""
    print("=" * 70)
    print("Testing Lambda Function")
    print("=" * 70)
    
    # Setup mocks
    mock_s3 = MockS3Client()
    mock_cw = MockCloudWatch()
    
    # Set environment variables
    os.environ['SOURCE_BUCKET'] = 'fhir-lca-persist'
    os.environ['TARGET_BUCKET'] = 'fhir-ingest-analytics'
    
    with patch('lambda_function.s3_client', mock_s3), \
         patch('lambda_function.cloudwatch', mock_cw), \
         patch('awswrangler.s3.to_parquet') as mock_write:
        
        # Mock awswrangler to write to local file instead of S3
        def mock_to_parquet(df, path, **kwargs):
            output_dir = Path("output")
            output_dir.mkdir(exist_ok=True)
            
            filename = Path(path).name
            output_path = output_dir / filename
            df.to_parquet(output_path, index=False, compression='snappy')
            print(f"✅ Parquet file written: {output_path}")
            print(f"   Rows: {len(df)}, Columns: {len(df.columns)}")
            print(f"   Columns: {list(df.columns)}")
        
        mock_write.side_effect = mock_to_parquet
        
        # Test with lca-persist data
        print("\n📝 Test 1: Processing lca-persist-input.json")
        print("-" * 70)
        event1 = create_s3_event('fhir-lca-persist', 'test_data/lca-persist-input.json')
        context1 = Mock()
        context1.aws_request_id = 'test-request-001'
        
        try:
            response1 = lambda_handler(event1, context1)
            print(f"\n✅ Response Status: {response1['statusCode']}")
            body1 = json.loads(response1['body'])
            print(f"   Message: {body1['message']}")
            if 'results' in body1:
                for result in body1['results']:
                    print(f"   - {result['status']}: {result.get('source_key', 'unknown')}")
                    if result['status'] == 'success':
                        print(f"     Records processed: {result.get('records_processed', 0)}")
        except Exception as e:
            print(f"❌ Error: {str(e)}")
            import traceback
            traceback.print_exc()
        
        # Test with dxa-persist data
        print("\n📝 Test 2: Processing dxa-persist-input.json")
        print("-" * 70)
        event2 = create_s3_event('fhir-dxa-persist', 'test_data/dxa-persist-input.json')
        context2 = Mock()
        context2.aws_request_id = 'test-request-002'
        
        try:
            response2 = lambda_handler(event2, context2)
            print(f"\n✅ Response Status: {response2['statusCode']}")
            body2 = json.loads(response2['body'])
            print(f"   Message: {body2['message']}")
            if 'results' in body2:
                for result in body2['results']:
                    print(f"   - {result['status']}: {result.get('source_key', 'unknown')}")
                    if result['status'] == 'success':
                        print(f"     Records processed: {result.get('records_processed', 0)}")
        except Exception as e:
            print(f"❌ Error: {str(e)}")
            import traceback
            traceback.print_exc()
        
        print("\n" + "=" * 70)
        print("Lambda Function Test Complete")
        print("=" * 70)
        print(f"\n📊 Metrics Published: {len(mock_cw.metrics)}")
        for metric in mock_cw.metrics[:5]:  # Show first 5
            md = metric['MetricData'][0]
            print(f"   - {md['MetricName']}: {md['Value']} {md.get('Unit', '')}")


def print_athena_queries():
    """Print Athena query examples for testing"""
    print("\n" + "=" * 70)
    print("Athena Query Examples")
    print("=" * 70)
    
    queries = """
-- 1. Count all records
SELECT COUNT(*) as total_records
FROM fhir_analytics.fhir_ingest_analytics;

-- 2. Count by source
SELECT 
  source,
  COUNT(*) as record_count
FROM fhir_analytics.fhir_ingest_analytics
GROUP BY source
ORDER BY record_count DESC;

-- 3. View latest data (last 24 hours)
SELECT 
  source,
  ingest_date,
  hour,
  COUNT(*) as records,
  COUNT(DISTINCT s3Filename) as files
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date >= DATE_FORMAT(DATE_ADD('day', -1, CURRENT_DATE), '%Y-%m-%d')
GROUP BY source, ingest_date, hour
ORDER BY ingest_date DESC, hour DESC;

-- 4. Error analysis by status code
SELECT 
  source,
  statusCode,
  COUNT(*) as error_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE statusCode IS NOT NULL
  AND statusCode NOT BETWEEN 200 AND 299
GROUP BY source, statusCode
ORDER BY error_count DESC;

-- 5. Operation outcome analysis
SELECT 
  operationOutcomeSeverity,
  operationOutcomeCode,
  COUNT(*) as occurrence_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NOT NULL
GROUP BY operationOutcomeSeverity, operationOutcomeCode
ORDER BY occurrence_count DESC
LIMIT 20;

-- 6. Latency analysis
SELECT 
  source,
  ingest_date,
  AVG(latencyMs) as avg_latency_ms,
  MAX(latencyMs) as max_latency_ms,
  MIN(latencyMs) as min_latency_ms,
  APPROX_PERCENTILE(latencyMs, 0.95) as p95_latency_ms
FROM fhir_analytics.fhir_ingest_analytics
WHERE latencyMs IS NOT NULL
  AND ingest_date >= DATE_FORMAT(DATE_ADD('day', -7, CURRENT_DATE), '%Y-%m-%d')
GROUP BY source, ingest_date
ORDER BY ingest_date DESC;

-- 7. Patient activity
SELECT 
  patientId,
  COUNT(*) as request_count,
  COUNT(DISTINCT requestResourceId) as unique_resources,
  MAX(responseTs) as last_request
FROM fhir_analytics.fhir_ingest_analytics
WHERE patientId IS NOT NULL
  AND ingest_date >= DATE_FORMAT(DATE_ADD('day', -1, CURRENT_DATE), '%Y-%m-%d')
GROUP BY patientId
ORDER BY request_count DESC
LIMIT 50;

-- 8. Files processed today
SELECT 
  source,
  COUNT(DISTINCT s3Filename) as unique_files,
  COUNT(*) as total_records
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date = CAST(CURRENT_DATE AS VARCHAR)
GROUP BY source;

-- 9. Error details with messages
SELECT 
  source,
  statusCode,
  operationOutcomeSeverity,
  operationOutcomeCode,
  operationOutcomeDetail,
  COUNT(*) as count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeDetail IS NOT NULL
  AND ingest_date = CAST(CURRENT_DATE AS VARCHAR)
GROUP BY source, statusCode, operationOutcomeSeverity, operationOutcomeCode, operationOutcomeDetail
ORDER BY count DESC
LIMIT 30;

-- 10. Data quality check - check for nulls
SELECT 
  source,
  COUNT(*) as total_rows,
  SUM(CASE WHEN patientId IS NULL THEN 1 ELSE 0 END) as null_patient_id,
  SUM(CASE WHEN customerId IS NULL THEN 1 ELSE 0 END) as null_customer_id,
  SUM(CASE WHEN statusCode IS NULL THEN 1 ELSE 0 END) as null_status_code
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date >= DATE_FORMAT(DATE_ADD('day', -7, CURRENT_DATE), '%Y-%m-%d')
GROUP BY source;
"""
    
    print(queries)
    print("\n" + "=" * 70)
    print("How to Run Athena Queries:")
    print("=" * 70)
    print("""
1. Go to AWS Athena Console: https://console.aws.amazon.com/athena/

2. Select Workgroup: fhir-analytics (or your configured workgroup)

3. Select Database: fhir_analytics

4. Copy and paste any query above into the query editor

5. Click "Run query"

6. View results in the results panel below

Note: Make sure:
- Glue database and table are created (via Terraform)
- Parquet files exist in S3 target bucket
- IAM permissions are configured for Athena access
- Query results bucket is configured
""")


def main():
    """Main test function"""
    print("\n" + "=" * 70)
    print("Lambda Function & Athena Test Suite")
    print("=" * 70)
    
    # Test Lambda function
    test_lambda_function()
    
    # Print Athena queries
    print_athena_queries()
    
    print("\n✅ Testing complete!")
    print("\nNext steps:")
    print("1. Review output Parquet files in ./output/ directory")
    print("2. Deploy to AWS using: cd terraform && terraform apply")
    print("3. Upload test files to S3 source bucket")
    print("4. Run Athena queries in AWS Console")


if __name__ == '__main__':
    main()

