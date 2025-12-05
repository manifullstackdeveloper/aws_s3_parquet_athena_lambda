"""
Unit tests for Lambda function using pytest.

Run with: pytest test_unit.py -v
"""

import json
import pytest
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime
import pandas as pd
from io import BytesIO


# Mock AWS clients before importing lambda_function
@pytest.fixture(autouse=True)
def mock_aws_clients():
    """Mock AWS clients for all tests"""
    with patch('boto3.client') as mock_client:
        # Create mock S3 client
        mock_s3 = Mock()
        mock_ssm = Mock()
        
        def client_factory(service_name, **kwargs):
            if service_name == 's3':
                return mock_s3
            elif service_name == 'ssm':
                return mock_ssm
            return Mock()
        
        mock_client.side_effect = client_factory
        
        yield {
            's3': mock_s3,
            'ssm': mock_ssm
        }


@pytest.fixture
def sample_json_array():
    """Sample JSON array data"""
    return [
        {
            "s3Filename": "test1.json",
            "source": "lca-persist",
            "statusCode": 200,
            "patientId": "PT-001",
            "latencyMs": 100
        },
        {
            "s3Filename": "test2.json",
            "source": "lca-persist",
            "statusCode": 400,
            "patientId": "PT-002",
            "latencyMs": 150
        }
    ]


@pytest.fixture
def sample_json_object():
    """Sample JSON single object"""
    return {
        "s3Filename": "test.json",
        "source": "dxa-persist",
        "statusCode": 200,
        "patientId": "PT-003",
        "latencyMs": 200
    }


@pytest.fixture
def sample_nested_json():
    """Sample nested JSON"""
    return [
        {
            "id": "test1",
            "metadata": {
                "source": "lca-persist",
                "timestamp": "2025-12-03T14:30:00Z"
            },
            "status": {
                "code": 200,
                "message": "Success"
            }
        }
    ]


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
    
    def test_read_json_array(self, mock_aws_clients, sample_json_array):
        """Test reading JSON array"""
        from lambda_function import read_json_from_s3
        
        # Mock S3 response
        mock_body = Mock()
        mock_body.read.return_value = json.dumps(sample_json_array).encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        result = read_json_from_s3('test-bucket', 'test.json')
        
        assert isinstance(result, list)
        assert len(result) == 2
        assert result[0]['patientId'] == 'PT-001'
    
    def test_read_json_object(self, mock_aws_clients, sample_json_object):
        """Test reading single JSON object"""
        from lambda_function import read_json_from_s3
        
        # Mock S3 response
        mock_body = Mock()
        mock_body.read.return_value = json.dumps(sample_json_object).encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        result = read_json_from_s3('test-bucket', 'test.json')
        
        assert isinstance(result, list)
        assert len(result) == 1
        assert result[0]['patientId'] == 'PT-003'
    
    def test_read_jsonl(self, mock_aws_clients):
        """Test reading JSONL (newline-delimited JSON)"""
        from lambda_function import read_json_from_s3
        
        jsonl_content = '{"id": 1, "name": "test1"}\n{"id": 2, "name": "test2"}'
        
        # Mock S3 response
        mock_body = Mock()
        mock_body.read.return_value = jsonl_content.encode('utf-8')
        mock_aws_clients['s3'].get_object.return_value = {'Body': mock_body}
        
        result = read_json_from_s3('test-bucket', 'test.jsonl')
        
        assert isinstance(result, list)
        assert len(result) == 2
        assert result[0]['id'] == 1
        assert result[1]['id'] == 2


class TestFlattenJSON:
    """Test JSON flattening functionality"""
    
    def test_flatten_simple_json(self, sample_json_array):
        """Test flattening simple JSON"""
        from lambda_function import flatten_json
        
        df = flatten_json(sample_json_array)
        
        assert isinstance(df, pd.DataFrame)
        assert len(df) == 2
        assert 'patientId' in df.columns
        assert df['statusCode'].tolist() == [200, 400]
    
    def test_flatten_nested_json(self, sample_nested_json):
        """Test flattening nested JSON"""
        from lambda_function import flatten_json
        
        df = flatten_json(sample_nested_json)
        
        assert isinstance(df, pd.DataFrame)
        assert 'metadata_source' in df.columns
        assert 'status_code' in df.columns
        assert df['metadata_source'].iloc[0] == 'lca-persist'
    
    def test_flatten_empty_list(self):
        """Test flattening empty list raises error"""
        from lambda_function import flatten_json
        
        with pytest.raises(ValueError):
            flatten_json([])


class TestPartitionColumns:
    """Test partition column addition"""
    
    def test_add_partition_columns(self, sample_json_array):
        """Test adding partition columns"""
        from lambda_function import add_partition_columns, flatten_json
        
        df = flatten_json(sample_json_array)
        df = add_partition_columns(df, 'lca-persist')
        
        assert 'source' in df.columns
        assert 'ingest_date' in df.columns
        assert 'hour' in df.columns
        assert df['source'].iloc[0] == 'lca-persist'
        
        # Check date format
        ingest_date = df['ingest_date'].iloc[0]
        assert len(ingest_date) == 10  # YYYY-MM-DD
        
        # Check hour format
        hour = df['hour'].iloc[0]
        assert len(hour) == 2  # HH


class TestOutputPath:
    """Test output path generation"""
    
    def test_generate_output_path(self):
        """Test output path generation"""
        from lambda_function import generate_output_path
        
        path = generate_output_path(
            'test-bucket',
            'lca-persist',
            'abc123-response.json'
        )
        
        assert path.startswith('s3://test-bucket/data/')
        assert 'source=lca-persist' in path
        assert 'ingest_date=' in path
        assert 'hour=' in path
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
        from botocore.exceptions import ClientError
        
        error = {'Error': {'Code': '404'}}
        mock_aws_clients['s3'].head_object.side_effect = ClientError(error, 'head_object')
        
        result = file_exists_in_s3('s3://test-bucket/test.parquet')
        
        assert result is False


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
    
    def test_get_bucket_config_from_ssm(self, mock_aws_clients, monkeypatch):
        """Test getting config from SSM when env vars not set"""
        from lambda_function import get_bucket_config
        
        # Unset environment variables
        monkeypatch.delenv('SOURCE_BUCKET', raising=False)
        monkeypatch.delenv('TARGET_BUCKET', raising=False)
        
        # Mock SSM responses
        mock_aws_clients['ssm'].get_parameter.return_value = {
            'Parameter': {'Value': 'ssm-bucket'}
        }
        
        config = get_bucket_config()
        
        assert mock_aws_clients['ssm'].get_parameter.called


class TestLambdaHandler:
    """Test Lambda handler"""
    
    @patch('lambda_function.read_json_from_s3')
    @patch('lambda_function.write_parquet_to_s3')
    def test_lambda_handler_success(
        self,
        mock_write_parquet,
        mock_read_json,
        mock_aws_clients,
        s3_event,
        sample_json_array,
        monkeypatch
    ):
        """Test successful Lambda execution"""
        from lambda_function import lambda_handler
        
        # Setup
        monkeypatch.setenv('SOURCE_BUCKET', 'fhir-lca-persist')
        monkeypatch.setenv('TARGET_BUCKET', 'fhir-ingest-analytics')
        
        mock_read_json.return_value = sample_json_array
        mock_write_parquet.return_value = None
        
        # Execute
        response = lambda_handler(s3_event, Mock())
        
        # Assert
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'success' in body['message'].lower()
    
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
        
        mock_read_json.side_effect = Exception("Test error")
        
        # Execute
        response = lambda_handler(s3_event, Mock())
        
        # Assert
        assert response['statusCode'] in [207, 500]


class TestEdgeCases:
    """Test edge cases and error conditions"""
    
    def test_empty_s3_event(self, mock_aws_clients, monkeypatch):
        """Test handling empty S3 event"""
        from lambda_function import lambda_handler
        
        monkeypatch.setenv('SOURCE_BUCKET', 'test')
        monkeypatch.setenv('TARGET_BUCKET', 'test')
        
        event = {"Records": []}
        response = lambda_handler(event, Mock())
        
        assert response['statusCode'] == 200
    
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

