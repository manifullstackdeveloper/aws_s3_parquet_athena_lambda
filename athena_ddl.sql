-- ========================================
-- Glue Database Creation
-- ========================================

CREATE DATABASE IF NOT EXISTS fhir_analytics
COMMENT 'FHIR Analytics Database for ingested data'
LOCATION 's3://fhir-ingest-analytics/';


-- ========================================
-- Main Analytics Table (Based on Jira Story)
-- ========================================

CREATE EXTERNAL TABLE IF NOT EXISTS fhir_analytics.fhir_ingest_analytics (
  s3Filename                STRING COMMENT 'Original S3 filename',
  source                    STRING COMMENT 'Source bucket identifier',
  approximateReceiveCount   INT COMMENT 'Approximate receive count',
  customerId                STRING COMMENT 'Customer identifier',
  patientId                 STRING COMMENT 'Patient identifier',
  sourceFhirServer          STRING COMMENT 'Source FHIR server URL',
  requestResourceId         STRING COMMENT 'Resource ID from request',
  bundleResourceType        STRING COMMENT 'FHIR bundle resource type',
  statusCode                INT COMMENT 'HTTP status code',
  operationOutcomeLocation  STRING COMMENT 'Operation outcome location',
  operationOutcomeSeverity  STRING COMMENT 'Operation outcome severity',
  operationOutcomeCode      STRING COMMENT 'Operation outcome code',
  operationOutcomeDetail    STRING COMMENT 'Operation outcome detail message',
  responseTs                TIMESTAMP COMMENT 'Response timestamp',
  latencyMs                 INT COMMENT 'Latency in milliseconds',
  datastoreId               STRING COMMENT 'Datastore identifier'
)
PARTITIONED BY (
  source STRING COMMENT 'Source system (lca-persist, dxa-persist)',
  ingest_date STRING COMMENT 'Ingestion date (YYYY-MM-DD)',
  hour STRING COMMENT 'Ingestion hour (HH)'
)
STORED AS PARQUET
LOCATION 's3://fhir-ingest-analytics/data/'
TBLPROPERTIES (
  'parquet.compression'='SNAPPY',
  'projection.enabled'='true',
  'projection.source.type'='enum',
  'projection.source.values'='lca-persist,dxa-persist',
  'projection.ingest_date.type'='date',
  'projection.ingest_date.range'='2025-01-01,NOW',
  'projection.ingest_date.format'='yyyy-MM-dd',
  'projection.hour.type'='integer',
  'projection.hour.range'='00,23',
  'projection.hour.digits'='2',
  'storage.location.template'='s3://fhir-ingest-analytics/data/source=${source}/ingest_date=${ingest_date}/hour=${hour}'
);


-- ========================================
-- Partition Management (if not using projection)
-- ========================================

-- Add partitions manually (example)
-- ALTER TABLE fhir_analytics.fhir_ingest_analytics ADD IF NOT EXISTS
--   PARTITION (source='lca-persist', ingest_date='2025-12-03', hour='14')
--   LOCATION 's3://fhir-ingest-analytics/data/source=lca-persist/ingest_date=2025-12-03/hour=14/';

-- Discover partitions automatically (run after new data arrives)
-- MSCK REPAIR TABLE fhir_analytics.fhir_ingest_analytics;


-- ========================================
-- Sample Queries
-- ========================================

-- Query 1: Count records by source and date
SELECT 
  source,
  ingest_date,
  COUNT(*) as record_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE ingest_date >= '2025-12-01'
GROUP BY source, ingest_date
ORDER BY ingest_date DESC, source;


-- Query 2: Error analysis (non-2xx status codes)
SELECT 
  source,
  statusCode,
  operationOutcomeSeverity,
  operationOutcomeCode,
  COUNT(*) as error_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE statusCode NOT BETWEEN 200 AND 299
  AND ingest_date = CAST(CURRENT_DATE AS VARCHAR)
GROUP BY source, statusCode, operationOutcomeSeverity, operationOutcomeCode
ORDER BY error_count DESC;


-- Query 3: Latency analysis
SELECT 
  source,
  ingest_date,
  hour,
  AVG(latencyMs) as avg_latency_ms,
  MAX(latencyMs) as max_latency_ms,
  MIN(latencyMs) as min_latency_ms,
  APPROX_PERCENTILE(latencyMs, 0.95) as p95_latency_ms
FROM fhir_analytics.fhir_ingest_analytics
WHERE latencyMs IS NOT NULL
  AND ingest_date >= DATE_FORMAT(DATE_ADD('day', -7, CURRENT_DATE), '%Y-%m-%d')
GROUP BY source, ingest_date, hour
ORDER BY ingest_date DESC, hour DESC;


-- Query 4: Patient activity
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
LIMIT 100;


-- Query 5: Operation outcome details
SELECT 
  operationOutcomeSeverity,
  operationOutcomeCode,
  operationOutcomeDetail,
  COUNT(*) as occurrence_count
FROM fhir_analytics.fhir_ingest_analytics
WHERE operationOutcomeCode IS NOT NULL
  AND ingest_date = CAST(CURRENT_DATE AS VARCHAR)
GROUP BY operationOutcomeSeverity, operationOutcomeCode, operationOutcomeDetail
ORDER BY occurrence_count DESC
LIMIT 50;

