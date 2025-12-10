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
from datetime import datetime, timezone
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
        # Key might be a full path like "test_data/lca-persist-input.json" or just "lca-persist-input.json"
        # Extract just the filename
        key_path = Path(Key)
        filename = key_path.name
        
        # Try to find the file in test_data directory
        file_path = self.local_files_dir / filename
        
        # If not found, try the key as-is (in case it's already a full path)
        if not file_path.exists():
            file_path = Path(Key)
            if not file_path.exists():
                # Try relative to test_data
                file_path = self.local_files_dir / Key
                if not file_path.exists():
                    # List available files for better error message
                    available = list(self.local_files_dir.glob("*.json")) if self.local_files_dir.exists() else []
                    available_str = ", ".join([f.name for f in available]) if available else "none"
                    raise Exception(f"File not found: {Key} (available files: {available_str})")
        
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
                "eventTime": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
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
    
    # Ensure test file exists in test_data directory
    test_file = Path("test_data") / json_file
    if not test_file.exists():
        # Check if file exists with different name
        test_data_dir = Path("test_data")
        if test_data_dir.exists():
            # Try to find matching file
            matching_files = list(test_data_dir.glob(f"*{json_file}*"))
            if matching_files:
                test_file = matching_files[0]
                print(f"📁 Using matching file: {test_file}")
            else:
                # List available files
                available = list(test_data_dir.glob("*.json"))
                if available:
                    print(f"❌ Error: Test file not found: {test_file}")
                    print(f"📁 Available files in test_data/:")
                    for f in available:
                        print(f"   - {f.name}")
                    print(f"\n💡 Usage: python test_local.py --file {available[0].name}")
                    return False
                else:
                    print(f"❌ Error: No JSON files found in test_data/ directory")
                    return False
        else:
            print(f"❌ Error: test_data/ directory not found")
            return False
    
    print(f"📄 Test file: {test_file}")
    print()
    
    # Patch AWS clients - need to patch before importing lambda_function
    with patch('boto3.client') as mock_boto_client:
        def client_factory(service_name, **kwargs):
            if service_name == 's3':
                return mock_s3
            elif service_name == 'ssm':
                return mock_ssm
            elif service_name == 'cloudwatch':
                # Return a minimal mock for CloudWatch
                mock_cw = Mock()
                mock_cw.put_metric_data = Mock(return_value=None)
                return mock_cw
            return Mock()
        
        mock_boto_client.side_effect = client_factory
        
        # Mock awswrangler.s3.to_parquet to avoid actual S3 writes
        with patch('awswrangler.s3.to_parquet') as mock_wr_parquet:
            mock_wr_parquet.return_value = None
            
            # Also patch lambda_function's s3_client and cloudwatch directly
            with patch('lambda_function.s3_client', mock_s3), \
                 patch('lambda_function.cloudwatch') as mock_cw:
                
                # Setup CloudWatch mock
                mock_cw.put_metric_data = Mock(return_value=None)
                
                # Import Lambda function (after patching)
                import lambda_function
                
                # Create test event - use just the filename, not full path
                event = create_test_event(json_file)
                # Update the key in the event to just be the filename
                if 'Records' in event and len(event['Records']) > 0:
                    event['Records'][0]['s3']['object']['key'] = json_file
                
                context = Mock()
                context.aws_request_id = "test-request-123"
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
                                path = call.kwargs.get('path') or (call.args[1] if len(call.args) > 1 else 'unknown')
                                # Get df from kwargs or args, but check properly
                                df = None
                                if 'df' in call.kwargs:
                                    df = call.kwargs['df']
                                elif len(call.args) > 0:
                                    df = call.args[0]
                                
                                if df is not None:
                                    try:
                                        print(f"  ✓ {path}")
                                        print(f"    - Records: {len(df)}")
                                        print(f"    - Columns: {list(df.columns)}")
                                    except Exception as e:
                                        print(f"  ✓ {path}")
                                        print(f"    - (Error displaying df info: {e})")
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
    
    # Find all JSON files in test_data directory
    test_data_dir = Path("test_data")
    if test_data_dir.exists():
        test_files = [f.name for f in test_data_dir.glob("*.json")]
    else:
        test_files = []
    
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
        default=None,
        help='JSON file to test (in test_data directory). If not specified, uses first available file.'
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
        # If no file specified, use first available file from test_data
        if args.file is None:
            test_data_dir = Path("test_data")
            if test_data_dir.exists():
                json_files = list(test_data_dir.glob("*.json"))
                if json_files:
                    args.file = json_files[0].name
                    print(f"📁 Using default file: {args.file}")
                else:
                    print("❌ Error: No JSON files found in test_data/ directory")
                    sys.exit(1)
            else:
                print("❌ Error: test_data/ directory not found")
                sys.exit(1)
        success = test_lambda_locally(args.file)
        sys.exit(0 if success else 1)

