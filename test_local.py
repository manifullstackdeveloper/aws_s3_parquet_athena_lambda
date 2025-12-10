"""
Local testing script for Lambda function.

This script simulates Lambda execution locally without requiring AWS deployment.
It mocks S3 operations and allows you to test the Lambda logic end-to-end.
"""

import json
import os
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime
import tempfile

# Add current directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class MockS3Client:
    """Mock S3 client for local testing"""
    
    def __init__(self, local_files_dir="test_data"):
        self.local_files_dir = Path(local_files_dir)
        self.uploaded_files = {}
        
    def get_object(self, Bucket, Key):
        """Mock S3 get_object"""
        file_path = self.local_files_dir / Key
        if not file_path.exists():
            raise Exception(f"File not found: {file_path}")
        
        with open(file_path, 'r') as f:
            content = f.read()
        
        return {
            'Body': MockBody(content)
        }
    
    def head_object(self, Bucket, Key):
        """Mock S3 head_object - check if file exists"""
        if Key in self.uploaded_files:
            return {'ContentLength': 1234}
        # Simulate file not found
        from botocore.exceptions import ClientError
        error = {'Error': {'Code': '404'}}
        raise ClientError(error, 'head_object')
    
    def put_object(self, Bucket, Key, Body):
        """Mock S3 put_object"""
        self.uploaded_files[Key] = Body
        print(f"✅ Mock S3 Upload: s3://{Bucket}/{Key}")
        return {'ETag': 'mock-etag'}


class MockBody:
    """Mock response body"""
    def __init__(self, content):
        self.content = content
        
    def read(self):
        return self.content.encode('utf-8')


class MockSSMClient:
    """Mock SSM client for local testing"""
    
    def __init__(self):
        self.parameters = {
            '/myapp/source-bucket': 'fhir-lca-persist',
            '/myapp/target-bucket': 'fhir-ingest-analytics'
        }
    
    def get_parameter(self, Name, WithDecryption=True):
        """Mock SSM get_parameter"""
        if Name in self.parameters:
            return {
                'Parameter': {
                    'Value': self.parameters[Name]
                }
            }
        raise Exception(f"Parameter not found: {Name}")


def create_test_event(filename="example_payload.json"):
    """Create a mock S3 event for testing"""
    return {
        "Records": [
            {
                "eventVersion": "2.1",
                "eventSource": "aws:s3",
                "awsRegion": "us-east-1",
                "eventTime": datetime.utcnow().isoformat() + "Z",
                "eventName": "ObjectCreated:Put",
                "s3": {
                    "s3SchemaVersion": "1.0",
                    "configurationId": "test-config",
                    "bucket": {
                        "name": "fhir-lca-persist",
                        "arn": "arn:aws:s3:::fhir-lca-persist"
                    },
                    "object": {
                        "key": filename,
                        "size": 1024
                    }
                }
            }
        ]
    }


def setup_test_environment():
    """Setup test environment with mock AWS services"""
    
    # Create test data directory
    test_data_dir = Path("test_data")
    test_data_dir.mkdir(exist_ok=True)
    
    # Set environment variables
    os.environ['SOURCE_BUCKET'] = 'fhir-lca-persist'
    os.environ['TARGET_BUCKET'] = 'fhir-ingest-analytics'
    os.environ['LOG_LEVEL'] = 'INFO'
    
    # Create mock AWS clients
    mock_s3 = MockS3Client(test_data_dir)
    mock_ssm = MockSSMClient()
    
    return mock_s3, mock_ssm


def test_lambda_locally(json_file="example_payload.json"):
    """
    Test Lambda function locally with mock AWS services.
    
    Args:
        json_file: Name of JSON file in test_data directory
    """
    print("=" * 70)
    print("🧪 LOCAL LAMBDA TESTING")
    print("=" * 70)
    print()
    
    # Setup test environment
    mock_s3, mock_ssm = setup_test_environment()
    
    # Ensure test file exists
    test_file = Path("test_data") / json_file
    if not test_file.exists():
        # Copy example payload if test file doesn't exist
        example = Path("dxa-persist-input.json")
        if example.exists():
            test_file.parent.mkdir(exist_ok=True)
            import shutil
            shutil.copy(example, test_file)
            print(f"📁 Created test file: {test_file}")
        else:
            print(f"❌ Error: Test file not found: {test_file}")
            return False
    
    print(f"📄 Test file: {test_file}")
    print()
    
    # Patch AWS clients
    with patch('boto3.client') as mock_boto_client:
        def client_factory(service_name, **kwargs):
            if service_name == 's3':
                return mock_s3
            elif service_name == 'ssm':
                return mock_ssm
            return Mock()
        
        mock_boto_client.side_effect = client_factory
        
        # Mock awswrangler.s3.to_parquet to avoid actual S3 writes
        with patch('awswrangler.s3.to_parquet') as mock_wr_parquet:
            mock_wr_parquet.return_value = None
            
            # Import Lambda function (after patching)
            import lambda_function
            
            # Create test event
            event = create_test_event(json_file)
            context = Mock()
            context.request_id = "test-request-123"
            context.function_name = "test-function"
            
            print("🚀 Invoking Lambda handler...")
            print()
            
            try:
                # Invoke Lambda
                response = lambda_function.lambda_handler(event, context)
                
                print()
                print("=" * 70)
                print("✅ LAMBDA EXECUTION COMPLETED")
                print("=" * 70)
                print()
                print("📊 Response:")
                print(json.dumps(response, indent=2))
                print()
                
                # Show uploaded files
                if mock_s3.uploaded_files or mock_wr_parquet.called:
                    print("📤 Files that would be uploaded to S3:")
                    if mock_wr_parquet.called:
                        for call in mock_wr_parquet.call_args_list:
                            path = call.kwargs.get('path') or call.args[1] if len(call.args) > 1 else 'unknown'
                            df = call.kwargs.get('df') or call.args[0] if len(call.args) > 0 else None
                            if df is not None:
                                print(f"  ✓ {path}")
                                print(f"    - Records: {len(df)}")
                                print(f"    - Columns: {list(df.columns)}")
                    print()
                
                return True
                
            except Exception as e:
                print()
                print("=" * 70)
                print("❌ LAMBDA EXECUTION FAILED")
                print("=" * 70)
                print()
                print(f"Error: {str(e)}")
                import traceback
                print()
                print("Traceback:")
                traceback.print_exc()
                return False


def run_all_tests():
    """Run all local tests"""
    print("=" * 70)
    print("🧪 RUNNING ALL LOCAL TESTS")
    print("=" * 70)
    print()
    
    test_files = [
        "dxa-persist-input.json"
    ]
    
    results = []
    for test_file in test_files:
        test_path = Path("test_data") / test_file
        if test_path.exists():
            print(f"\n{'='*70}")
            print(f"Testing: {test_file}")
            print('='*70)
            success = test_lambda_locally(test_file)
            results.append((test_file, success))
    
    # Summary
    print("\n" + "=" * 70)
    print("📊 TEST SUMMARY")
    print("=" * 70)
    for test_file, success in results:
        status = "✅ PASSED" if success else "❌ FAILED"
        print(f"{status}: {test_file}")
    print()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Test Lambda function locally")
    parser.add_argument(
        '--file',
        default='dxa-persist-input.json',
        help='JSON file to test (in test_data directory)'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='Run all tests'
    )
    
    args = parser.parse_args()
    
    if args.all:
        run_all_tests()
    else:
        success = test_lambda_locally(args.file)
        sys.exit(0 if success else 1)

