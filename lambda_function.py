"""
Analytics Lambda Function: JSON to Parquet Converter

Reads JSON files from S3, flattens nested structures, converts to Parquet format,
and writes partitioned output to analytics bucket.
"""

import json
import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional
from urllib.parse import unquote_plus
from enum import Enum

import boto3
import pandas as pd
import awswrangler as wr

# Configure logging with structured format
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')


# Error categories for triage
class ErrorCategory(str, Enum):
    """Error categories for monitoring and triage"""
    CONFIGURATION = "ConfigurationError"
    S3_READ = "S3ReadError"
    S3_WRITE = "S3WriteError"
    JSON_PARSE = "JSONParseError"
    JSON_VALIDATION = "JSONValidationError"
    DATA_TRANSFORMATION = "DataTransformationError"
    PARTITIONING = "PartitioningError"
    UNKNOWN = "UnknownError"


# Custom exception classes for better error handling
class ConfigurationError(Exception):
    """Configuration-related errors"""
    category = ErrorCategory.CONFIGURATION


class S3ReadError(Exception):
    """S3 read operation errors"""
    category = ErrorCategory.S3_READ


class S3WriteError(Exception):
    """S3 write operation errors"""
    category = ErrorCategory.S3_WRITE


class JSONParseError(Exception):
    """JSON parsing errors"""
    category = ErrorCategory.JSON_PARSE


class JSONValidationError(Exception):
    """JSON validation errors"""
    category = ErrorCategory.JSON_VALIDATION


class DataTransformationError(Exception):
    """Data transformation errors"""
    category = ErrorCategory.DATA_TRANSFORMATION


class PartitioningError(Exception):
    """Partitioning errors"""
    category = ErrorCategory.PARTITIONING


def publish_metric(metric_name: str, value: float, unit: str = "Count", 
                   dimensions: Optional[List[Dict[str, str]]] = None):
    """
    Publish custom metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        unit: Unit of measurement (Count, Seconds, Bytes, etc.)
        dimensions: Optional dimensions for the metric
    """
    try:
        namespace = "FHIRAnalytics/Lambda"
        metric_data = {
            'MetricName': metric_name,
            'Value': value,
            'Unit': unit,
            'Timestamp': datetime.now(timezone.utc)
        }
        
        if dimensions:
            metric_data['Dimensions'] = dimensions
        
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[metric_data]
        )
    except Exception as e:
        logger.warning(f"Failed to publish metric {metric_name}: {str(e)}")


def log_error_with_context(error: Exception, context: Dict[str, Any], 
                          error_category: ErrorCategory):
    """
    Log error with structured context for triage.
    
    Args:
        error: The exception that occurred
        context: Additional context (bucket, key, source, etc.)
        error_category: Category of the error
    """
    error_context = {
        "error_type": type(error).__name__,
        "error_message": str(error),
        "error_category": error_category.value,
        **context
    }
    
    logger.error(
        f"[{error_category.value}] {str(error)}",
        extra={"error_context": error_context},
        exc_info=True
    )
    
    # Publish error metric
    publish_metric(
        "Errors",
        value=1.0,
        dimensions=[
            {"Name": "ErrorCategory", "Value": error_category.value},
            {"Name": "ErrorType", "Value": type(error).__name__}
        ]
    )


def get_bucket_config() -> Dict[str, str]:
    """
    Get bucket configuration from environment variables.
    
    Returns:
        Dictionary with source_bucket and target_bucket
    """
    source_bucket = os.environ.get('SOURCE_BUCKET', 'fhir-lca-persist')
    target_bucket = os.environ.get('TARGET_BUCKET', 'fhir-ingest-analytics')
    
    if not source_bucket or not target_bucket:
        raise ValueError("SOURCE_BUCKET and TARGET_BUCKET environment variables must be set")
    
    return {
        'source_bucket': source_bucket,
        'target_bucket': target_bucket
    }


def read_json_from_s3(bucket: str, key: str) -> Dict[str, Any]:
    """
    Read JSON file from S3.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        
    Returns:
        JSON object with 'meta' and 'response' structure
        
    Raises:
        S3ReadError: If S3 read fails
        JSONParseError: If JSON parsing fails
        JSONValidationError: If JSON structure is invalid
    """
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Publish metric for file size
        file_size = len(content.encode('utf-8'))
        publish_metric("InputFileSize", file_size, "Bytes", [
            {"Name": "Bucket", "Value": bucket}
        ])
        
    except Exception as e:
        error_context = {"bucket": bucket, "key": key, "operation": "s3_get_object"}
        log_error_with_context(e, error_context, ErrorCategory.S3_READ)
        raise S3ReadError(f"Failed to read from s3://{bucket}/{key}: {str(e)}") from e
    
    try:
        # Parse JSON - expecting structure with 'meta' and 'response'
        data = json.loads(content)
    except json.JSONDecodeError as e:
        error_context = {"bucket": bucket, "key": key, "operation": "json_parse"}
        log_error_with_context(e, error_context, ErrorCategory.JSON_PARSE)
        raise JSONParseError(f"Invalid JSON in s3://{bucket}/{key}: {str(e)}") from e
    
    try:
        # Validate structure
        if not isinstance(data, dict):
            raise JSONValidationError(f"Expected JSON object, got {type(data)}")
        
        if 'meta' not in data or 'response' not in data:
            raise JSONValidationError("JSON must contain 'meta' and 'response' fields")
        
        if not isinstance(data['response'], list):
            raise JSONValidationError("'response' field must be an array")
        
        return data
            
    except JSONValidationError:
        raise
    except Exception as e:
        error_context = {"bucket": bucket, "key": key, "operation": "json_validation"}
        log_error_with_context(e, error_context, ErrorCategory.JSON_VALIDATION)
        raise JSONValidationError(f"JSON validation failed: {str(e)}") from e


def flatten_json(payload: Dict[str, Any], s3_filename: str, source: str) -> pd.DataFrame:
    """
    Flatten nested JSON structure (meta + response array) into pandas DataFrame.
    Explodes operationOutcome.issue arrays into multiple rows.
    
    Args:
        payload: JSON object with 'meta' and 'response' structure
        s3_filename: Original S3 filename
        source: Source identifier (dxa-persist, lca-persist, etc.)
        
    Returns:
        Flattened pandas DataFrame with exploded operationOutcome rows
        
    Raises:
        DataTransformationError: If transformation fails
    """
    if not payload or 'meta' not in payload or 'response' not in payload:
        raise ValueError("Payload must contain 'meta' and 'response' fields")
    
    meta = payload['meta']
    response_items = payload['response']
    
    if not isinstance(response_items, list):
        raise ValueError("'response' must be an array")
    
    receive_count = meta.get('approximateReceiveCount') or meta.get('approxmiateReceiveCount')
    
    meta_data = {
        's3Filename': s3_filename,
        'source': source,
        'approximateReceiveCount': receive_count,
        'customerId': meta.get('organizationId'),
        'patientId': meta.get('patientId'),
        'sourceFhirServer': meta.get('sourceFhirServer'),
        'bundleResourceType': meta.get('bundleResourceType'),
        'responseTs': meta.get('responseTs'),
        'latencyMs': meta.get('latencyMs'),
        'datastoreId': meta.get('datastoreId')
    }
    
    flattened_rows = []
    skipped_count = 0
    
    for response_item in response_items:
        status_code = response_item.get('statusCode')
        
        if status_code is not None and 200 <= status_code <= 299:
            skipped_count += 1
            continue
        
        base_row = {
            'requestResourceId': response_item.get('requestResourceId'),
            'statusCode': status_code,
            'operationOutcomeLocation': response_item.get('resourceLocation')
        }
        
        row = {**meta_data, **base_row}
        operation_outcome = response_item.get('operationOutcome')
        
        if operation_outcome and isinstance(operation_outcome, dict):
            issues = operation_outcome.get('issue', [])
            
            if issues and isinstance(issues, list) and len(issues) > 0:
                for issue in issues:
                    issue_row = row.copy()
                    issue_row['operationOutcomeSeverity'] = issue.get('severity')
                    issue_row['operationOutcomeCode'] = issue.get('code')
                    
                    details = issue.get('details', {})
                    if isinstance(details, dict):
                        issue_row['operationOutcomeDetail'] = details.get('text')
                    else:
                        issue_row['operationOutcomeDetail'] = details
                    
                    flattened_rows.append(issue_row)
            else:
                row['operationOutcomeSeverity'] = None
                row['operationOutcomeCode'] = None
                row['operationOutcomeDetail'] = None
                flattened_rows.append(row)
        else:
            row['operationOutcomeSeverity'] = None
            row['operationOutcomeCode'] = None
            row['operationOutcomeDetail'] = None
            flattened_rows.append(row)
    
    if skipped_count > 0:
        logger.info(f"Skipped {skipped_count} response items with 2xx status codes")
    
    if not flattened_rows:
        if len(response_items) > 0:
            logger.warning(f"All {len(response_items)} response items were skipped (all had 2xx status codes)")
        error_context = {
            "s3_filename": s3_filename,
            "source": source,
            "response_items_count": len(response_items)
        }
        error = DataTransformationError("No rows generated from response array (all items had 2xx status codes)")
        log_error_with_context(error, error_context, ErrorCategory.DATA_TRANSFORMATION)
        raise error
    
    df = pd.DataFrame(flattened_rows)
    
    required_columns = {
        's3Filename': 'string',
        'source': 'string',
        'approximateReceiveCount': 'Int64',
        'customerId': 'string',
        'patientId': 'string',
        'sourceFhirServer': 'string',
        'requestResourceId': 'string',
        'bundleResourceType': 'string',
        'statusCode': 'Int64',
        'operationOutcomeLocation': 'string',
        'operationOutcomeSeverity': 'string',
        'operationOutcomeCode': 'string',
        'operationOutcomeDetail': 'string',
        'responseTs': 'string',
        'latencyMs': 'Int64',
        'datastoreId': 'string'
    }
    
    for col, dtype in required_columns.items():
        if col not in df.columns:
            df[col] = None
    
    if 'responseTs' in df.columns and df['responseTs'].notna().any():
        df['responseTs'] = pd.to_datetime(df['responseTs'], errors='coerce', utc=True)
    
    logger.info(f"Flattened {len(flattened_rows)} rows from {len(response_items)} response items")
    logger.info(f"Columns: {list(df.columns)}")
    
    return df


def add_partition_columns(df: pd.DataFrame, source: str, response_ts: Optional[str] = None) -> pd.DataFrame:
    """
    Add partition columns to DataFrame.
    Uses responseTs if available, otherwise current time.
    
    Args:
        df: Input DataFrame
        source: Source identifier
        response_ts: Optional response timestamp (ISO format)
        
    Returns:
        DataFrame with partition columns added
    """
    if response_ts:
        try:
            ts = datetime.fromisoformat(response_ts.replace('Z', '+00:00'))
            ingest_date = ts.strftime('%Y-%m-%d')
            hour = ts.strftime('%H')
        except (ValueError, AttributeError):
            logger.warning(f"Could not parse responseTs '{response_ts}', using current time")
            now = datetime.now(timezone.utc)
            ingest_date = now.strftime('%Y-%m-%d')
            hour = now.strftime('%H')
    else:
        now = datetime.now(timezone.utc)
        ingest_date = now.strftime('%Y-%m-%d')
        hour = now.strftime('%H')
    
    df['source'] = source
    df['ingest_date'] = ingest_date
    df['hour'] = hour
    
    return df


def generate_output_path(target_bucket: str, source: str, filename: str, response_ts: Optional[str] = None) -> str:
    """
    Generate S3 output path with partitioning.
    Uses responseTs from payload if available, otherwise current time.
    
    Args:
        target_bucket: Target S3 bucket
        source: Source identifier
        filename: Original filename
        response_ts: Optional response timestamp (ISO format)
        
    Returns:
        Full S3 path for output
    """
    if response_ts:
        try:
            ts = datetime.fromisoformat(response_ts.replace('Z', '+00:00'))
            ingest_date = ts.strftime('%Y-%m-%d')
            hour = ts.strftime('%H')
        except (ValueError, AttributeError):
            logger.warning(f"Could not parse responseTs '{response_ts}', using current time")
            now = datetime.now(timezone.utc)
            ingest_date = now.strftime('%Y-%m-%d')
            hour = now.strftime('%H')
    else:
        now = datetime.now(timezone.utc)
        ingest_date = now.strftime('%Y-%m-%d')
        hour = now.strftime('%H')
    
    base_name = os.path.splitext(os.path.basename(filename))[0]
    parquet_filename = f"{base_name}.parquet"
    s3_path = f"s3://{target_bucket}/data/source={source}/ingest_date={ingest_date}/hour={hour}/{parquet_filename}"
    
    return s3_path


def file_exists_in_s3(s3_path: str) -> bool:
    """
    Check if file exists in S3.
    
    Args:
        s3_path: Full S3 path (s3://bucket/key)
        
    Returns:
        True if file exists, False otherwise
    """
    try:
        if not s3_path.startswith('s3://'):
            return False
            
        path_parts = s3_path[5:].split('/', 1)
        bucket = path_parts[0]
        key = path_parts[1] if len(path_parts) > 1 else ''
        
        s3_client.head_object(Bucket=bucket, Key=key)
        return True
    except Exception as e:
        error_code = None
        if hasattr(e, 'response') and 'Error' in e.response:
            error_code = e.response['Error'].get('Code')
        
        if error_code == '404' or '404' in str(e):
            return False
        else:
            logger.warning(f"Error checking file existence: {str(e)}")
            return False


def write_parquet_to_s3(df: pd.DataFrame, s3_path: str) -> None:
    """
    Write DataFrame to S3 as Parquet with Snappy compression.
    Ensures schema matches the expected flattened schema.
    
    Args:
        df: DataFrame to write
        s3_path: Target S3 path
        
    Raises:
        S3WriteError: If write operation fails
    """
    if file_exists_in_s3(s3_path):
        logger.warning(f"File already exists: {s3_path}. Skipping write.")
        publish_metric("DuplicateFileSkipped", 1.0)
        return
    
    schema_columns = [
        's3Filename', 'source', 'approximateReceiveCount', 'customerId',
        'patientId', 'sourceFhirServer', 'requestResourceId', 'bundleResourceType',
        'statusCode', 'operationOutcomeLocation', 'operationOutcomeSeverity',
        'operationOutcomeCode', 'operationOutcomeDetail', 'responseTs',
        'latencyMs', 'datastoreId'
    ]
    
    for col in schema_columns:
        if col not in df.columns:
            df[col] = None
    
    data_columns = [col for col in schema_columns if col not in ['source', 'ingest_date', 'hour']]
    
    try:
        start_time = datetime.now(timezone.utc)
        wr.s3.to_parquet(
            df=df[data_columns],
            path=s3_path,
            compression='snappy',
            index=False,
            dataset=False
        )
        write_duration = (datetime.now(timezone.utc) - start_time).total_seconds()
        
        publish_metric("ParquetWriteDuration", write_duration, "Seconds")
        publish_metric("RecordsProcessed", len(df), "Count")
        publish_metric("ParquetFilesWritten", 1.0)
        
        logger.info(f"Successfully wrote Parquet file to {s3_path} with {len(df)} rows in {write_duration:.2f}s")
        
    except Exception as e:
        error_context = {
            "s3_path": s3_path,
            "rows_count": len(df),
            "operation": "parquet_write"
        }
        log_error_with_context(e, error_context, ErrorCategory.S3_WRITE)
        raise S3WriteError(f"Failed to write Parquet to {s3_path}: {str(e)}") from e


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for S3 event processing.
    
    Args:
        event: S3 event notification
        context: Lambda context
        
    Returns:
        Response dictionary
    """
    invocation_start = datetime.now(timezone.utc)
    request_id = context.aws_request_id if context else "unknown"
    
    try:
        logger.info(f"[{request_id}] Received event with {len(event.get('Records', []))} records")
        
        publish_metric("Invocations", 1.0)
        
        try:
            config = get_bucket_config()
            source_bucket = config['source_bucket']
            target_bucket = config['target_bucket']
            logger.info(f"[{request_id}] Configuration - Source: {source_bucket}, Target: {target_bucket}")
        except Exception as e:
            error_context = {"request_id": request_id, "operation": "config_load"}
            log_error_with_context(e, error_context, ErrorCategory.CONFIGURATION)
            publish_metric("FatalErrors", 1.0, dimensions=[
                {"Name": "ErrorCategory", "Value": ErrorCategory.CONFIGURATION.value}
            ])
            raise
        
        results = []
        record_errors = {}
        
        for idx, record in enumerate(event.get('Records', [])):
            bucket = None
            key = None
            try:
                s3_info = record['s3']
                bucket = s3_info['bucket']['name']
                key = unquote_plus(s3_info['object']['key'])
                
                logger.info(f"[{request_id}] Processing record {idx+1}/{len(event.get('Records', []))}: s3://{bucket}/{key}")
                
                json_payload = read_json_from_s3(bucket, key)
                logger.info(f"[{request_id}] Read JSON payload with {len(json_payload.get('response', []))} response items")
                
                s3_filename = os.path.basename(key)
                
                source = 'unknown'
                if 'meta' in json_payload and 'source' in json_payload['meta']:
                    source = json_payload['meta']['source']
                else:
                    if 'lca-persist' in bucket or 'lca-persist' in key:
                        source = 'lca-persist'
                    elif 'dxa-persist' in bucket or 'dxa-persist' in key:
                        source = 'dxa-persist'
                    elif 'lca' in bucket or 'lca' in key:
                        source = 'lca'
                    elif 'dxa' in bucket or 'dxa' in key:
                        source = 'dxa'
                
                logger.info(f"[{request_id}] Source determined: {source}")
                
                df = flatten_json(json_payload, s3_filename, source)
                
                response_ts = None
                if 'meta' in json_payload and 'responseTs' in json_payload['meta']:
                    response_ts = json_payload['meta']['responseTs']
                
                try:
                    df = add_partition_columns(df, source, response_ts)
                except Exception as e:
                    error_context = {
                        "request_id": request_id,
                        "bucket": bucket,
                        "key": key,
                        "source": source,
                        "operation": "partitioning"
                    }
                    log_error_with_context(e, error_context, ErrorCategory.PARTITIONING)
                    raise PartitioningError(f"Failed to add partition columns: {str(e)}") from e
                
                output_path = generate_output_path(target_bucket, source, key, response_ts)
                logger.info(f"[{request_id}] Output path: {output_path}")
                
                write_parquet_to_s3(df, output_path)
                
                results.append({
                    'status': 'success',
                    'source_bucket': bucket,
                    'source_key': key,
                    'output_path': output_path,
                    'records_processed': len(df)
                })
                
                logger.info(f"[{request_id}] Successfully processed {key}")
                
            except (S3ReadError, JSONParseError, JSONValidationError, 
                    DataTransformationError, S3WriteError, PartitioningError) as e:
                error_category = e.category if hasattr(e, 'category') else ErrorCategory.UNKNOWN
                error_context = {
                    "request_id": request_id,
                    "bucket": bucket or "unknown",
                    "key": key or "unknown",
                    "record_index": idx
                }
                log_error_with_context(e, error_context, error_category)
                
                record_errors[error_category.value] = record_errors.get(error_category.value, 0) + 1
                
                results.append({
                    'status': 'error',
                    'source_bucket': bucket or 'unknown',
                    'source_key': key or 'unknown',
                    'error_type': type(e).__name__,
                    'error_category': error_category.value,
                    'error': str(e)
                })
                
            except Exception as e:
                error_context = {
                    "request_id": request_id,
                    "bucket": bucket or "unknown",
                    "key": key or "unknown",
                    "record_index": idx,
                    "error_type": type(e).__name__
                }
                log_error_with_context(e, error_context, ErrorCategory.UNKNOWN)
                
                record_errors[ErrorCategory.UNKNOWN.value] = record_errors.get(ErrorCategory.UNKNOWN.value, 0) + 1
                
                results.append({
                    'status': 'error',
                    'source_bucket': bucket or 'unknown',
                    'source_key': key or 'unknown',
                    'error_type': type(e).__name__,
                    'error_category': ErrorCategory.UNKNOWN.value,
                    'error': str(e)
                })
        
        successful = sum(1 for r in results if r['status'] == 'success')
        failed = sum(1 for r in results if r['status'] == 'error')
        
        publish_metric("FilesProcessed", successful, "Count")
        if failed > 0:
            publish_metric("FilesFailed", failed, "Count")
        
        for error_category, count in record_errors.items():
            publish_metric("ErrorsByCategory", count, "Count", [
                {"Name": "ErrorCategory", "Value": error_category}
            ])
        
        duration = (datetime.now(timezone.utc) - invocation_start).total_seconds()
        publish_metric("InvocationDuration", duration, "Seconds")
        
        logger.info(f"[{request_id}] Completed: {successful} successful, {failed} failed in {duration:.2f}s")
        
        return {
            'statusCode': 200 if failed == 0 else 207,
            'body': json.dumps({
                'message': f'Processed {successful} files successfully, {failed} failed',
                'request_id': request_id,
                'duration_seconds': duration,
                'error_breakdown': record_errors,
                'results': results
            })
        }
        
    except ConfigurationError as e:
        error_context = {"request_id": request_id, "operation": "lambda_handler"}
        log_error_with_context(e, error_context, ErrorCategory.CONFIGURATION)
        publish_metric("FatalErrors", 1.0, dimensions=[
            {"Name": "ErrorCategory", "Value": ErrorCategory.CONFIGURATION.value}
        ])
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Configuration error',
                'request_id': request_id,
                'error': str(e),
                'error_category': ErrorCategory.CONFIGURATION.value
            })
        }
        
    except Exception as e:
        error_context = {"request_id": request_id, "operation": "lambda_handler"}
        log_error_with_context(e, error_context, ErrorCategory.UNKNOWN)
        publish_metric("FatalErrors", 1.0, dimensions=[
            {"Name": "ErrorCategory", "Value": ErrorCategory.UNKNOWN.value}
        ])
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Internal error',
                'request_id': request_id,
                'error': str(e),
                'error_category': ErrorCategory.UNKNOWN.value
            })
        }

