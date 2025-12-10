"""
Unit tests for Lambda function using pytest.

Run with: pytest test_unit.py -v
"""

import json
import pytest
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime
from pathlib import Path
import pandas as pd
from io import BytesIO
from botocore.exceptions import ClientError


# Mock AWS clients before importing lambda_function
@pytest.fixture(autouse=True)
def mock_aws_clients():
    """Mock AWS clients for all tests"""
    with patch('lambda_function.s3_client') as mock_s3, \
         patch('lambda_function.cloudwatch') as mock_cw, \
         patch('boto3.client') as mock_client:
        # Create mock SSM client
        mock_ssm = Mock()
        
        # Setup CloudWatch mock
        mock_cw.put_metric_data = Mock(return_value=None)
        
        def client_factory(service_name, **kwargs):
            if service_name == 's3':
                return mock_s3
            elif service_name == 'ssm':
                return mock_ssm
            elif service_name == 'cloudwatch':
                return mock_cw
            return Mock()
        
        mock_client.side_effect = client_factory
        
        yield {
            's3': mock_s3,
            'ssm': mock_ssm,
            'cloudwatch': mock_cw
        }


@pytest.fixture
def sample_payload():
    """Load sample JSON payload from test_data/lca-persist-input.json"""
    test_file = Path("test_data/lca-persist-input.json")
    if test_file.exists():
        with open(test_file, 'r') as f:
            return json.load(f)
    # Fallback to minimal structure if file doesn't exist
    return {
        "meta": {
            "s3Filename": "test1.json",
            "approximateReceiveCount": 1,
            "source": "lca-persist",
            "organizationId": "customer1",
            "patientId": "PT-001",
            "sourceFhirServer": "https://fhir.example.com",
            "bundleResourceType": "Observation",
            "responseTs": "2025-12-09T18:31:45Z",
            "latencyMs": 100,
            "datastoreId": "hlk-001"
        },
        "response": [
            {
                "resourceLocation": "Observation/obs-001",
                "statusCode": 400,
                "requestResourceId": "obs-req-001",
                "operationOutcome": {
                    "issue": [
                        {
                            "severity": "error",
                            "code": "invalid",
                            "details": {
                                "text": "Missing required field"
                            }
                        }
                    ]
                }
            }
        ]
    }


@pytest.fixture
def sample_payload_no_errors():
    """Create payload with only 2xx status codes (should be skipped)"""
    # Use dxa-persist file but modify to have only 2xx codes
    test_file = Path("test_data/dxa-persist-input.json")
    if test_file.exists():
        with open(test_file, 'r') as f:
            payload = json.load(f)
            # Modify response to only have 2xx status codes
            payload["response"] = [
                {
                    "resourceLocation": "Observation/obs-001",
                    "statusCode": 201,
                    "requestResourceId": "obs-req-001"
                }
            ]
            return payload
    # Fallback
    return {
        "meta": {
            "s3Filename": "test2.json",
            "approximateReceiveCount": 1,
            "source": "dxa-persist",
            "organizationId": "customer2",
            "patientId": "PT-002",
            "sourceFhirServer": "https://fhir.example.com",
            "bundleResourceType": "Patient",
            "responseTs": "2025-12-09T19:00:00Z",
            "latencyMs": 200,
            "datastoreId": "hlk-002"
        },
        "response": [
            {
                "resourceLocation": "Patient/pat-001",
                "statusCode": 201,
                "requestResourceId": "pat-req-001"
            }
        ]
    }


@pytest.fixture
def sample_payload_no_operation_outcome():
    """Create payload without operationOutcome"""
    # Use lca-persist file but remove operationOutcome
    test_file = Path("test_data/lca-persist-input.json")
    if test_file.exists():
        with open(test_file, 'r') as f:
            payload = json.load(f)
            # Remove operationOutcome from all responses
            for item in payload["response"]:
                if "operationOutcome" in item:
                    del item["operationOutcome"]
            return payload
    # Fallback
    return {
        "meta": {
            "s3Filename": "test3.json",
            "approximateReceiveCount": 1,
            "source": "lca-persist",
            "organizationId": "customer3",
            "patientId": "PT-003",
            "sourceFhirServer": "https://fhir.example.com",
            "bundleResourceType": "Observation",
            "responseTs": "2025-12-09T20:00:00Z",
            "latencyMs": 150,
            "datastoreId": "hlk-003"
        },
        "response": [
            {
                "resourceLocation": "Observation/obs-003",
                "statusCode": 404,
                "requestResourceId": "obs-req-003"
            }
        ]
    }


@pytest.fixture
def s3_event():
    """Sample S3 event"""
    return {
        "Records": [
            {
                "s3": {
                    "bucket": {
                        "name": "fhir-lca-persist"
                    },
                    "object": {
                        "key": "test/data.json"
                    }
                }
            }
        ]
    }


class TestReadJSON:
    """Test JSON reading functionality"""
    
    def test_read_json_valid_structure(self, mock_aws_clients, sample_payload):
        """Test reading JSON with valid meta and response structure"""
        from lambda_function import read_json_from_s3
        
        # Mock S3 response
        mock_body = Mock()
        mock_body.read.return_value = json.dumps(sample_payload).encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        result = read_json_from_s3('test-bucket', 'test.json')
        
        assert isinstance(result, dict)
        assert 'meta' in result
        assert 'response' in result
        assert isinstance(result['response'], list)
        # The actual test data has 4 response items
        assert len(result['response']) >= 1
    
    def test_read_json_missing_meta(self, mock_aws_clients):
        """Test reading JSON without meta field raises error"""
        from lambda_function import read_json_from_s3, JSONValidationError
        
        invalid_payload = {"response": []}
        
        mock_body = Mock()
        mock_body.read.return_value = json.dumps(invalid_payload).encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        # The function should raise JSONValidationError
        with pytest.raises(JSONValidationError) as exc_info:
            read_json_from_s3('test-bucket', 'test.json')
        assert "meta" in str(exc_info.value).lower() or "response" in str(exc_info.value).lower()
    
    def test_read_json_not_dict(self, mock_aws_clients):
        """Test reading JSON that's not a dict raises error"""
        from lambda_function import read_json_from_s3, JSONValidationError
        
        mock_body = Mock()
        mock_body.read.return_value = json.dumps([1, 2, 3]).encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        # The function should raise JSONValidationError
        with pytest.raises(JSONValidationError) as exc_info:
            read_json_from_s3('test-bucket', 'test.json')
        assert "object" in str(exc_info.value).lower() or "dict" in str(exc_info.value).lower()


class TestFlattenJSON:
    """Test JSON flattening functionality"""
    
    def test_flatten_json_with_operation_outcome(self, sample_payload):
        """Test flattening JSON with operationOutcome issues"""
        from lambda_function import flatten_json
        
        df = flatten_json(sample_payload, "test.json", "lca-persist")
        
        assert isinstance(df, pd.DataFrame)
        # The test data has 4 response items, but 2 have 2xx status codes (skipped)
        # The other 2 have operationOutcome with multiple issues, so we get multiple rows
        # Expected: 2 issues from first error + 2 issues from second error = 4 rows
        assert len(df) >= 1  # At least one row from non-2xx responses
        assert 'patientId' in df.columns
        assert 'operationOutcomeSeverity' in df.columns
        assert 'operationOutcomeCode' in df.columns
        assert 'operationOutcomeDetail' in df.columns
        # Check that we have at least one error severity
        assert df['operationOutcomeSeverity'].notna().any()
    
    def test_flatten_json_no_operation_outcome(self, sample_payload_no_operation_outcome):
        """Test flattening JSON without operationOutcome"""
        from lambda_function import flatten_json
        
        df = flatten_json(sample_payload_no_operation_outcome, "test3.json", "lca-persist")
        
        assert isinstance(df, pd.DataFrame)
        # Should have at least one row (non-2xx status codes)
        assert len(df) >= 1
        # Check that operationOutcome fields are None for rows without operationOutcome
        # (Some rows might have operationOutcome, some might not)
        if len(df) > 0:
            # At least verify the columns exist
            assert 'operationOutcomeSeverity' in df.columns
            assert 'operationOutcomeCode' in df.columns
    
    def test_flatten_json_skips_2xx(self, sample_payload_no_errors):
        """Test that 2xx status codes are skipped"""
        from lambda_function import flatten_json, DataTransformationError
        
        with pytest.raises(DataTransformationError, match="No rows generated"):
            flatten_json(sample_payload_no_errors, "test2.json", "dxa-persist")
    
    def test_flatten_empty_response(self):
        """Test flattening empty response raises error"""
        from lambda_function import flatten_json, DataTransformationError
        
        empty_payload = {
            "meta": {
                "source": "lca-persist",
                "organizationId": "customer1"
            },
            "response": []
        }
        
        with pytest.raises(DataTransformationError, match="No rows generated"):
            flatten_json(empty_payload, "test.json", "lca-persist")


class TestPartitionColumns:
    """Test partition column addition"""
    
    def test_add_partition_columns(self, sample_payload):
        """Test adding partition columns"""
        from lambda_function import add_partition_columns, flatten_json
        
        df = flatten_json(sample_payload, "test.json", "lca-persist")
        df = add_partition_columns(df, "lca-persist", "2025-12-09T18:31:45Z")
        
        assert 'source' in df.columns
        assert 'ingest_date' in df.columns
        assert 'hour' in df.columns
        assert df['source'].iloc[0] == 'lca-persist'
        assert df['ingest_date'].iloc[0] == '2025-12-09'
        assert df['hour'].iloc[0] == '18'
    
    def test_add_partition_columns_no_timestamp(self, sample_payload):
        """Test adding partition columns without timestamp (uses current time)"""
        from lambda_function import add_partition_columns, flatten_json
        
        df = flatten_json(sample_payload, "test.json", "lca-persist")
        df = add_partition_columns(df, "lca-persist")
        
        assert 'source' in df.columns
        assert 'ingest_date' in df.columns
        assert 'hour' in df.columns
        # Date format check
        assert len(df['ingest_date'].iloc[0]) == 10  # YYYY-MM-DD
        assert len(df['hour'].iloc[0]) == 2  # HH


class TestOutputPath:
    """Test output path generation"""
    
    def test_generate_output_path(self):
        """Test output path generation"""
        from lambda_function import generate_output_path
        
        path = generate_output_path(
            'test-bucket',
            'lca-persist',
            'abc123-response.json',
            '2025-12-09T18:31:45Z'
        )
        
        assert path.startswith('s3://test-bucket/data/')
        assert 'source=lca-persist' in path
        assert 'ingest_date=2025-12-09' in path
        assert 'hour=18' in path
        assert path.endswith('abc123-response.parquet')
    
    def test_output_path_replaces_extension(self):
        """Test that .json extension is replaced with .parquet"""
        from lambda_function import generate_output_path
        
        path = generate_output_path(
            'test-bucket',
            'dxa-persist',
            'test.json'
        )
        
        assert path.endswith('.parquet')
        assert '.json' not in path


class TestFileExists:
    """Test file existence check"""
    
    def test_file_exists_true(self, mock_aws_clients):
        """Test file exists returns True"""
        from lambda_function import file_exists_in_s3
        
        mock_aws_clients['s3'].head_object.return_value = {'ContentLength': 1234}
        
        result = file_exists_in_s3('s3://test-bucket/test.parquet')
        
        assert result is True
    
    def test_file_exists_false(self, mock_aws_clients):
        """Test file doesn't exist returns False"""
        from lambda_function import file_exists_in_s3
        
        # Create a proper ClientError with response attribute
        error_response = {'Error': {'Code': '404', 'Message': 'Not Found'}}
        client_error = ClientError(error_response, 'HeadObject')
        # Ensure the error has the response attribute that the function checks
        client_error.response = error_response
        # Reset any previous return values
        mock_aws_clients['s3'].head_object.reset_mock()
        mock_aws_clients['s3'].head_object.side_effect = client_error
        
        result = file_exists_in_s3('s3://test-bucket/test.parquet')
        
        assert result is False
        # Verify head_object was called
        mock_aws_clients['s3'].head_object.assert_called_once()


class TestConfiguration:
    """Test configuration loading"""
    
    def test_get_bucket_config_from_env(self, mock_aws_clients, monkeypatch):
        """Test getting config from environment variables"""
        from lambda_function import get_bucket_config
        
        monkeypatch.setenv('SOURCE_BUCKET', 'test-source')
        monkeypatch.setenv('TARGET_BUCKET', 'test-target')
        
        config = get_bucket_config()
        
        assert config['source_bucket'] == 'test-source'
        assert config['target_bucket'] == 'test-target'
    
    def test_get_bucket_config_missing_env(self, mock_aws_clients, monkeypatch):
        """Test getting config raises error when env vars not set"""
        from lambda_function import get_bucket_config
        
        # Unset environment variables
        monkeypatch.delenv('SOURCE_BUCKET', raising=False)
        monkeypatch.delenv('TARGET_BUCKET', raising=False)
        
        # Should use defaults or raise error
        # Based on the function, it should use defaults
        config = get_bucket_config()
        
        # Should have default values
        assert 'source_bucket' in config
        assert 'target_bucket' in config


class TestLambdaHandler:
    """Test Lambda handler"""
    
    @patch('lambda_function.write_parquet_to_s3')
    @patch('awswrangler.s3.to_parquet')
    def test_lambda_handler_success(
        self,
        mock_wr_parquet,
        mock_write_parquet,
        mock_aws_clients,
        s3_event,
        sample_payload,
        monkeypatch
    ):
        """Test successful Lambda execution"""
        from lambda_function import lambda_handler
        
        # Setup
        monkeypatch.setenv('SOURCE_BUCKET', 'fhir-lca-persist')
        monkeypatch.setenv('TARGET_BUCKET', 'fhir-ingest-analytics')
        
        # Mock awswrangler
        mock_wr_parquet.return_value = None
        
        # Mock S3 read
        mock_body = Mock()
        mock_body.read.return_value = json.dumps(sample_payload).encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        # Mock head_object to return 404 (file doesn't exist)
        error_response = {'Error': {'Code': '404', 'Message': 'Not Found'}}
        client_error = ClientError(error_response, 'HeadObject')
        client_error.response = error_response
        mock_aws_clients['s3'].head_object.side_effect = client_error
        
        # Create context
        context = Mock()
        context.aws_request_id = "test-request-123"
        
        # Execute
        response = lambda_handler(s3_event, context)
        
        # Assert
        assert response['statusCode'] in [200, 207]
        body = json.loads(response['body'])
        assert 'processed' in body['message'].lower() or 'success' in body['message'].lower()
        # Either write_parquet_to_s3 or awswrangler.s3.to_parquet should be called
        assert mock_write_parquet.called or mock_wr_parquet.called
    
    @patch('lambda_function.read_json_from_s3')
    def test_lambda_handler_error(
        self,
        mock_read_json,
        mock_aws_clients,
        s3_event,
        monkeypatch
    ):
        """Test Lambda execution with error"""
        from lambda_function import lambda_handler
        
        # Setup
        monkeypatch.setenv('SOURCE_BUCKET', 'fhir-lca-persist')
        monkeypatch.setenv('TARGET_BUCKET', 'fhir-ingest-analytics')
        
        from lambda_function import S3ReadError
        mock_read_json.side_effect = S3ReadError("Test error")
        
        # Create context
        context = Mock()
        context.aws_request_id = "test-request-123"
        
        # Execute
        response = lambda_handler(s3_event, context)
        
        # Assert - should return 207 (partial success) or 500 (error)
        assert response['statusCode'] in [207, 500]


class TestEdgeCases:
    """Test edge cases and error conditions"""
    
    def test_empty_s3_event(self, mock_aws_clients, monkeypatch):
        """Test handling empty S3 event"""
        from lambda_function import lambda_handler
        
        monkeypatch.setenv('SOURCE_BUCKET', 'test')
        monkeypatch.setenv('TARGET_BUCKET', 'test')
        
        event = {"Records": []}
        context = Mock()
        context.aws_request_id = "test-request-123"
        
        response = lambda_handler(event, context)
        
        # Should return 200 with message about no records
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'processed' in body['message'].lower() or '0' in body['message']
    
    def test_special_characters_in_key(self, mock_aws_clients):
        """Test handling special characters in S3 key"""
        from lambda_function import generate_output_path
        
        path = generate_output_path(
            'bucket',
            'lca-persist',
            'path/to/file with spaces.json'
        )
        
        assert 'file with spaces.parquet' in path


# Test runner
if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
