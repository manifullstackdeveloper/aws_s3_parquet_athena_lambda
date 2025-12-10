# Mermaid Diagrams Reference

Complete collection of Mermaid diagrams for the FHIR Analytics Lambda solution.

## Table of Contents

- [System Architecture](#system-architecture)
- [Data Flow Sequence](#data-flow-sequence)
- [Lambda Processing Flow](#lambda-processing-flow)
- [Partition Structure](#partition-structure)
- [Error Handling](#error-handling)
- [Deployment Process](#deployment-process)
- [Security Architecture](#security-architecture)
- [Monitoring Dashboard](#monitoring-dashboard)
- [Testing Workflow](#testing-workflow)

---

## System Architecture

### High-Level Overview

```mermaid
graph TB
    subgraph "Data Sources"
        PL1[LCA Persistence Lambda]
        PL2[DXA Persistence Lambda]
    end
    
    subgraph "Ingestion Layer"
        S3S[S3 Source Bucket<br/>fhir-lca-persist<br/>JSON Files]
    end
    
    subgraph "Processing Layer"
        Lambda[Analytics Lambda<br/>JSON to Parquet<br/>Python 3.12 | 512MB]
        Layer[Lambda Layer<br/>awswrangler<br/>pandas | pyarrow]
    end
    
    subgraph "Configuration"
        Env[Environment Variables<br/>SOURCE_BUCKET<br/>TARGET_BUCKET<br/>LOG_LEVEL]
    end
    
    subgraph "Storage Layer"
        S3T[S3 Target Bucket<br/>fhir-ingest-analytics<br/>Partitioned Parquet]
    end
    
    subgraph "Analytics Layer"
        Glue[AWS Glue Catalog<br/>Database: fhir_analytics<br/>Table: fhir_ingest_analytics]
        Athena[Amazon Athena<br/>Presto SQL Engine]
        QS[Amazon QuickSight<br/>BI Dashboards]
    end
    
    subgraph "Observability"
        CW[CloudWatch Logs<br/>/aws/lambda/fhir-analytics*]
        Metrics[CloudWatch Metrics<br/>Invocations | Errors | Duration]
        Alarms[CloudWatch Alarms<br/>Error Rate | Latency]
    end
    
    PL1 -->|Write JSON| S3S
    PL2 -->|Write JSON| S3S
    S3S -->|S3 Event<br/>ObjectCreated| Lambda
    Layer -.->|Dependencies| Lambda
    Lambda -.->|Read Config| Env
    Lambda -->|Write Parquet<br/>Snappy| S3T
    Lambda -->|Logs| CW
    Lambda -->|Metrics| Metrics
    Metrics -->|Threshold| Alarms
    S3T -->|Partition Projection| Glue
    Glue <-->|Metadata| Athena
    Athena -->|Read Parquet| S3T
    Athena -->|Query Results| QS
    
    style Lambda fill:#4CAF50,color:#fff
    style S3S fill:#ffcdd2
    style S3T fill:#b2dfdb
    style Glue fill:#fff9c4
    style Athena fill:#b2ebf2
```

---

## Data Flow Sequence

### End-to-End Processing

```mermaid
sequenceDiagram
    autonumber
    participant User as Data Producer
    participant S3Source as S3 Source<br/>(fhir-lca-persist)
    participant EventBridge as S3 Event Notification
    participant Lambda as Analytics Lambda
    participant EnvVars as Environment Variables
    participant S3Target as S3 Target<br/>(fhir-ingest-analytics)
    participant CloudWatch as CloudWatch
    participant Glue as AWS Glue
    participant Athena as Amazon Athena
    participant Analyst as Data Analyst
    
    User->>S3Source: Upload JSON file
    S3Source->>EventBridge: Emit ObjectCreated event
    EventBridge->>Lambda: Trigger with S3 event
    
    activate Lambda
    Lambda->>CloudWatch: Log invocation start
    Lambda->>EnvVars: Read environment variables
    EnvVars-->>Lambda: Return config
    Lambda->>S3Source: Download JSON file
    S3Source-->>Lambda: Return file contents
    
    Lambda->>Lambda: Parse & validate JSON
    Lambda->>Lambda: Flatten nested structure
    Lambda->>Lambda: Add partition columns
    Lambda->>Lambda: Convert to Parquet
    
    Lambda->>S3Target: Check if file exists
    S3Target-->>Lambda: File not found
    Lambda->>S3Target: Write Parquet file
    Lambda->>CloudWatch: Log success metrics
    deactivate Lambda
    
    S3Target->>Glue: Auto-register partition
    
    Analyst->>Athena: Execute SQL query
    Athena->>Glue: Get table metadata
    Glue-->>Athena: Return schema & partitions
    Athena->>S3Target: Read Parquet files
    S3Target-->>Athena: Return data
    Athena-->>Analyst: Query results
```

---

## Lambda Processing Flow

### Internal Processing Steps

```mermaid
flowchart TD
    Start([Lambda Invoked]) --> ParseEvent[Parse S3 Event]
    ParseEvent --> ExtractInfo[Extract Bucket & Key]
    ExtractInfo --> GetConfig[Get Configuration<br/>Environment Variables]
    
    GetConfig --> DetermineSource{Determine Source<br/>System}
    DetermineSource -->|lca-persist| SourceLCA[source = lca-persist]
    DetermineSource -->|dxa-persist| SourceDXA[source = dxa-persist]
    DetermineSource -->|other| SourceUnknown[source = unknown]
    
    SourceLCA --> ReadJSON
    SourceDXA --> ReadJSON
    SourceUnknown --> ReadJSON
    
    ReadJSON[Read JSON from S3] --> ParseJSON{Parse JSON<br/>Format?}
    ParseJSON -->|Array| FlattenArray[Flatten Array]
    ParseJSON -->|Object| FlattenObject[Flatten Single Object]
    ParseJSON -->|JSONL| FlattenJSONL[Flatten JSONL]
    ParseJSON -->|Invalid| ErrorInvalid[Error: Invalid JSON]
    
    FlattenArray --> Normalize[pandas.json_normalize]
    FlattenObject --> Normalize
    FlattenJSONL --> Normalize
    
    Normalize --> CreateDF[Create DataFrame]
    CreateDF --> AddPartitions[Add Partition Columns<br/>source, ingest_date, hour]
    AddPartitions --> GeneratePath[Generate Output Path<br/>S3 partitioned structure]
    
    GeneratePath --> CheckExists{File Already<br/>Exists?}
    CheckExists -->|Yes| Skip[Skip Write<br/>Log Warning]
    CheckExists -->|No| WriteParquet[Write Parquet<br/>Snappy Compression]
    
    WriteParquet --> LogSuccess[Log Success Metrics<br/>Records, Path, Duration]
    LogSuccess --> End([Complete])
    
    Skip --> End
    ErrorInvalid --> LogError[Log Error Details]
    LogError --> End
    
    style Start fill:#4CAF50,color:#fff
    style End fill:#4CAF50,color:#fff
    style Normalize fill:#2196F3,color:#fff
    style WriteParquet fill:#2196F3,color:#fff
    style ErrorInvalid fill:#f44336,color:#fff
    style CheckExists fill:#FF9800,color:#fff
```

---

## Partition Structure

### S3 Bucket Layout

```mermaid
graph TD
    Root[s3://fhir-ingest-analytics/]
    Root --> Data[data/]
    
    Data --> LCA[source=lca-persist/]
    Data --> DXA[source=dxa-persist/]
    
    LCA --> LCADate1[ingest_date=2025-12-03/]
    LCA --> LCADate2[ingest_date=2025-12-04/]
    
    DXA --> DXADate1[ingest_date=2025-12-03/]
    
    LCADate1 --> LCAHour1[hour=14/]
    LCADate1 --> LCAHour2[hour=15/]
    LCADate2 --> LCAHour3[hour=09/]
    
    DXADate1 --> DXAHour1[hour=14/]
    
    LCAHour1 --> File1[abc123-response.parquet<br/>123 KB | 100 records]
    LCAHour1 --> File2[def456-response.parquet<br/>87 KB | 75 records]
    LCAHour2 --> File3[xyz789-response.parquet<br/>156 KB | 120 records]
    LCAHour3 --> File4[test-data.parquet<br/>45 KB | 50 records]
    DXAHour1 --> File5[ghi789-response.parquet<br/>92 KB | 80 records]
    
    style Root fill:#4CAF50,color:#fff
    style Data fill:#2196F3,color:#fff
    style LCA fill:#FF9800,color:#fff
    style DXA fill:#FF9800,color:#fff
    style File1 fill:#9C27B0,color:#fff
    style File2 fill:#9C27B0,color:#fff
    style File3 fill:#9C27B0,color:#fff
    style File4 fill:#9C27B0,color:#fff
    style File5 fill:#9C27B0,color:#fff
```

### Partition Projection Schema

```mermaid
erDiagram
    TABLE ||--o{ PARTITION : has
    PARTITION ||--|| SOURCE : filters_by
    PARTITION ||--|| DATE : filters_by
    PARTITION ||--|| HOUR : filters_by
    
    TABLE {
        string s3Filename
        string source
        int approximateReceiveCount
        string customerId
        string patientId
        string sourceFhirServer
        string requestResourceId
        string bundleResourceType
        int statusCode
        string operationOutcomeLocation
        string operationOutcomeSeverity
        string operationOutcomeCode
        string operationOutcomeDetail
        timestamp responseTs
        int latencyMs
        string datastoreId
    }
    
    PARTITION {
        string source PK
        string ingest_date PK
        string hour PK
    }
    
    SOURCE {
        string value "lca-persist, dxa-persist"
        string type "enum"
    }
    
    DATE {
        string format "YYYY-MM-DD"
        string type "date"
        string range "2025-01-01 to NOW"
    }
    
    HOUR {
        string format "HH"
        string type "integer"
        string range "00 to 23"
    }
```

---

## Error Handling

### Exception Flow

```mermaid
stateDiagram-v2
    [*] --> Processing
    
    Processing --> ReadJSON: Read JSON
    ReadJSON --> JSONError: JSON Parse Error
    ReadJSON --> Flatten: Success
    
    Flatten --> FlattenError: Flatten Error
    Flatten --> Transform: Success
    
    Transform --> TransformError: Transform Error
    Transform --> DuplicateCheck: Success
    
    DuplicateCheck --> FileExists: File Exists
    DuplicateCheck --> WriteParquet: Not Exists
    
    WriteParquet --> WriteError: S3 Write Error
    WriteParquet --> Success: Success
    
    FileExists --> LogWarning
    LogWarning --> PartialSuccess
    
    JSONError --> LogError
    FlattenError --> LogError
    TransformError --> LogError
    WriteError --> LogError
    
    LogError --> NotifyCloudWatch
    NotifyCloudWatch --> Failed
    
    Success --> [*]
    PartialSuccess --> [*]
    Failed --> [*]
    
    note right of Processing
        All errors are caught
        and logged to CloudWatch
    end note
    
    note right of DuplicateCheck
        Prevents overwriting
        existing Parquet files
    end note
```

### Error Response Structure

```mermaid
graph LR
    Error[Error Detected] --> Classify{Error Type}
    
    Classify -->|JSON Parse| E1[JSONDecodeError<br/>Status: 400<br/>Retry: No]
    Classify -->|S3 Read| E2[NoSuchKey<br/>Status: 404<br/>Retry: No]
    Classify -->|S3 Write| E3[AccessDenied<br/>Status: 403<br/>Retry: No]
    Classify -->|Transform| E4[DataError<br/>Status: 500<br/>Retry: Yes]
    Classify -->|Timeout| E5[TimeoutError<br/>Status: 504<br/>Retry: Yes]
    
    E1 --> Log[Log to CloudWatch]
    E2 --> Log
    E3 --> Log
    E4 --> Log
    E5 --> Log
    
    Log --> Metric[Emit CloudWatch Metric]
    Metric --> Response[Return Error Response]
    
    style Error fill:#f44336,color:#fff
    style E1 fill:#ff9800,color:#fff
    style E2 fill:#ff9800,color:#fff
    style E3 fill:#ff9800,color:#fff
    style E4 fill:#ff5722,color:#fff
    style E5 fill:#ff5722,color:#fff
```

---

## Deployment Process

### Terraform Deployment

```mermaid
flowchart TD
    Start([Start]) --> Clone[Clone Repository]
    Clone --> Build[Run build.sh<br/>Create ZIP files]
    Build --> CDTerraform[cd terraform/]
    CDTerraform --> CopyVars[cp terraform.tfvars.example<br/>terraform.tfvars]
    CopyVars --> EditVars[Edit terraform.tfvars<br/>Configure buckets, region]
    
    EditVars --> TFInit[terraform init<br/>Download providers]
    TFInit --> TFValidate[terraform validate<br/>Check syntax]
    TFValidate --> ValidOK{Valid?}
    ValidOK -->|No| EditVars
    ValidOK -->|Yes| TFPlan[terraform plan<br/>Preview changes]
    
    TFPlan --> ReviewPlan{Review Plan<br/>OK?}
    ReviewPlan -->|No| EditVars
    ReviewPlan -->|Yes| TFApply[terraform apply<br/>Deploy infrastructure]
    
    TFApply --> CheckResources{Resources<br/>Created?}
    CheckResources -->|Error| Debug[Check AWS permissions<br/>Review error logs]
    Debug --> TFApply
    CheckResources -->|Success| AthenaSetup[Create Athena Table<br/>Run athena_ddl.sql]
    
    AthenaSetup --> Test[Upload Test File<br/>aws s3 cp example_payload.json]
    Test --> Verify[Verify Output<br/>Check logs, S3, Athena]
    Verify --> Alarms[Setup CloudWatch Alarms]
    Alarms --> End([Deployment Complete])
    
    style Start fill:#4CAF50,color:#fff
    style End fill:#4CAF50,color:#fff
    style TFApply fill:#2196F3,color:#fff
    style CheckResources fill:#FF9800,color:#fff
    style Debug fill:#f44336,color:#fff
```

---

## Security Architecture

### IAM Permission Model

```mermaid
graph TB
    subgraph "Lambda Execution Role"
        Role[fhir-analytics-json-to-parquet-role]
        Policy[Inline Policy<br/>fhir-analytics-json-to-parquet-policy]
        ManagedPolicy[AWS Managed Policy<br/>AWSLambdaBasicExecutionRole]
    end
    
    subgraph "S3 Permissions"
        S3Read[Source Bucket<br/>s3:GetObject<br/>s3:ListBucket]
        S3Write[Target Bucket<br/>s3:PutObject<br/>s3:HeadObject<br/>s3:GetObject]
    end
    
    subgraph "Configuration Permissions"
        EnvVars[Environment Variables<br/>SOURCE_BUCKET<br/>TARGET_BUCKET<br/>LOG_LEVEL]
    end
    
    subgraph "Logging Permissions"
        CWLogs[CloudWatch Logs<br/>logs:CreateLogGroup<br/>logs:CreateLogStream<br/>logs:PutLogEvents]
    end
    
    subgraph "Optional VPC Permissions"
        VPCPerms[VPC Networking<br/>ec2:CreateNetworkInterface<br/>ec2:DescribeNetworkInterfaces<br/>ec2:DeleteNetworkInterface]
    end
    
    Role --> Policy
    Role --> ManagedPolicy
    
    Policy --> S3Read
    Policy --> S3Write
    Policy --> EnvVars
    Policy --> CWLogs
    Policy -.-> VPCPerms
    
    style Role fill:#4CAF50,color:#fff
    style Policy fill:#2196F3,color:#fff
    style ManagedPolicy fill:#2196F3,color:#fff
    style S3Read fill:#FF9800,color:#fff
    style S3Write fill:#FF9800,color:#fff
    style EnvVars fill:#9C27B0,color:#fff
    style CWLogs fill:#ff9800,color:#fff
```

### Data Encryption Flow

```mermaid
sequenceDiagram
    participant Lambda as Lambda Function
    participant KMS as AWS KMS
    participant S3Source as S3 Source<br/>(Encrypted)
    participant S3Target as S3 Target<br/>(Encrypted)
    participant EnvVars as Environment Variables<br/>(Set by Terraform)
    
    Note over S3Source: Server-Side Encryption<br/>AES-256
    
    Lambda->>S3Source: GetObject request
    S3Source->>KMS: Decrypt with KMS key
    KMS-->>S3Source: Decrypted data
    S3Source-->>Lambda: Return JSON (TLS 1.2)
    
    Lambda->>EnvVars: Read environment variables
    EnvVars-->>Lambda: Return config
    
    Note over Lambda: Process data in memory<br/>(ephemeral)
    
    Lambda->>S3Target: PutObject (Parquet)
    S3Target->>KMS: Encrypt with KMS key
    KMS-->>S3Target: Encrypted data
    S3Target-->>Lambda: Acknowledgment
    
    Note over S3Target: Server-Side Encryption<br/>AES-256
```

---

## Monitoring Dashboard

### CloudWatch Metrics Overview

```mermaid
graph TB
    subgraph "Lambda Metrics"
        Invocations[Invocations<br/>Total executions]
        Errors[Errors<br/>Failed executions]
        Duration[Duration<br/>Execution time ms]
        Throttles[Throttles<br/>Rate limiting]
        Concurrent[Concurrent Executions<br/>Parallel invocations]
    end
    
    subgraph "Custom Metrics"
        RecordsProcessed[Records Processed<br/>Per invocation]
        FileSize[File Size<br/>Input JSON size]
        ParquetSize[Parquet Size<br/>Output file size]
        LatencyBreakdown[Latency Breakdown<br/>Read, Transform, Write]
    end
    
    subgraph "Alarms"
        ErrorAlarm[Error Rate > 1%<br/>Severity: Critical]
        DurationAlarm[Duration > 240s<br/>Severity: Warning]
        ThrottleAlarm[Throttles > 0<br/>Severity: Warning]
        StaleAlarm[No Invocations 24h<br/>Severity: Info]
    end
    
    subgraph "Dashboards"
        OverviewDash[Overview Dashboard<br/>High-level KPIs]
        DetailDash[Detail Dashboard<br/>Performance metrics]
        ErrorDash[Error Dashboard<br/>Failure analysis]
    end
    
    Invocations --> OverviewDash
    Errors --> ErrorAlarm
    Errors --> ErrorDash
    Duration --> DurationAlarm
    Duration --> DetailDash
    Throttles --> ThrottleAlarm
    Concurrent --> DetailDash
    
    RecordsProcessed --> DetailDash
    FileSize --> DetailDash
    ParquetSize --> DetailDash
    LatencyBreakdown --> DetailDash
    
    ErrorAlarm --> SNS[SNS Topic<br/>Alert notifications]
    DurationAlarm --> SNS
    ThrottleAlarm --> SNS
    StaleAlarm --> SNS
    
    style ErrorAlarm fill:#f44336,color:#fff
    style DurationAlarm fill:#ff9800,color:#fff
    style ThrottleAlarm fill:#ff9800,color:#fff
    style StaleAlarm fill:#2196F3,color:#fff
```

### Log Analysis Flow

```mermaid
flowchart LR
    Lambda[Lambda Execution] -->|Write| CWLogs[CloudWatch Logs<br/>/aws/lambda/fhir-analytics*]
    CWLogs -->|Stream| LogInsights[CloudWatch Logs Insights]
    CWLogs -->|Export| S3Logs[S3 Log Archive<br/>Long-term storage]
    
    LogInsights -->|Query| ErrorQuery[Error Analysis<br/>Filter by ERROR level]
    LogInsights -->|Query| LatencyQuery[Latency Analysis<br/>Parse duration from logs]
    LogInsights -->|Query| VolumeQuery[Volume Analysis<br/>Records per invocation]
    
    ErrorQuery --> Dashboard[CloudWatch Dashboard]
    LatencyQuery --> Dashboard
    VolumeQuery --> Dashboard
    
    S3Logs --> Athena[Athena Log Queries<br/>Historical analysis]
    Athena --> QuickSight[QuickSight<br/>Log visualization]
    
    style Lambda fill:#4CAF50,color:#fff
    style CWLogs fill:#ff9800,color:#fff
    style Dashboard fill:#2196F3,color:#fff
    style Athena fill:#9C27B0,color:#fff
```

---

## Cost Analysis

### Monthly Cost Breakdown

```mermaid
pie title Monthly Cost Distribution (10K files/month)
    "Lambda Compute" : 10
    "S3 Storage (10GB)" : 23
    "S3 Requests" : 5
    "CloudWatch Logs (1GB)" : 50
    "Athena Queries" : 1
    "Data Transfer" : 1
```

### Cost Optimization Strategies

```mermaid
mindmap
  root((Cost<br/>Optimization))
    Lambda
      Right-size memory
      Reduce execution time
      Use ARM64 Graviton2
      Reserved concurrency
    S3
      Intelligent-Tiering
      Lifecycle policies
      Compression Snappy
      Delete old data
    CloudWatch
      Log retention 7-30 days
      Log sampling
      Metric filters
      Dashboard optimization
    Athena
      Partition pruning
      Column selection
      Query result caching
      Workgroup limits
    Network
      VPC endpoints S3 (if using VPC)
      Minimize data transfer
      Same-region resources
```

---

## Integration Patterns

### Event-Driven Architecture

```mermaid
graph TD
    subgraph "Source Systems"
        LCAL[LCA Persistence Lambda]
        DXAL[DXA Persistence Lambda]
        Manual[Manual Upload]
    end
    
    subgraph "Event Bus"
        S3[S3 Event Notifications]
        SNS[SNS Topic<br/>Optional fanout]
        SQS[SQS Queue<br/>Optional buffering]
    end
    
    subgraph "Processing"
        Lambda[Analytics Lambda<br/>JSON to Parquet]
        DLQ[Dead Letter Queue<br/>Failed messages]
    end
    
    subgraph "Downstream"
        Athena[Athena Queries]
        ETL[Glue ETL Jobs]
        ML[SageMaker ML]
    end
    
    LCAL -->|PutObject| S3
    DXAL -->|PutObject| S3
    Manual -->|PutObject| S3
    
    S3 -->|Direct| Lambda
    S3 -.->|Optional| SNS
    SNS -.->|Optional| SQS
    SQS -.->|Batch| Lambda
    
    Lambda -->|Failure| DLQ
    Lambda -->|Success| Athena
    Lambda -->|Success| ETL
    Lambda -->|Success| ML
    
    style Lambda fill:#4CAF50,color:#fff
    style S3 fill:#ff9800,color:#fff
    style DLQ fill:#f44336,color:#fff
```

---

## Testing Workflow

### Local Testing Flow

```mermaid
flowchart TD
    Start([Start Development]) --> WriteCode[Write/Modify Code]
    WriteCode --> LocalTest{Local Test?}
    
    LocalTest -->|Quick Test| Simple[python test_local.py]
    LocalTest -->|Unit Test| Pytest[pytest test_unit.py -v]
    LocalTest -->|Coverage| Coverage[pytest --cov]
    
    Simple --> CheckResult{Tests Pass?}
    Pytest --> CheckResult
    Coverage --> CheckResult
    
    CheckResult -->|No| Debug[Debug & Fix]
    Debug --> WriteCode
    
    CheckResult -->|Yes| Docker{Docker Test?}
    Docker -->|Optional| DockerTest[docker run lambda-test]
    Docker -->|Skip| Deploy
    DockerTest --> Deploy
    
    Deploy[Deploy to AWS<br/>terraform apply]
    Deploy --> IntegrationTest[Integration Test<br/>Real S3 Upload]
    IntegrationTest --> Validate{Validate?}
    
    Validate -->|Issues| Debug
    Validate -->|Success| End([Complete])
    
    style Start fill:#4CAF50,color:#fff
    style End fill:#4CAF50,color:#fff
    style CheckResult fill:#FF9800,color:#fff
    style Debug fill:#f44336,color:#fff
```

### Test Coverage Strategy

```mermaid
mindmap
  root((Test<br/>Strategy))
    Unit Tests
      JSON Reading
        Array format
        Object format
        JSONL format
        Invalid JSON
      Flattening
        Simple structure
        Nested objects
        Arrays
        Empty data
      Partitioning
        Date format
        Hour format
        Source detection
      Path Generation
        Extension replacement
        Special characters
        Partitioning
    Integration Tests
      S3 Read/Write
        File upload
        File download
        Permission errors
      Lambda Execution
        Event parsing
        Error handling
        Logging
      Athena Queries
        Partition discovery
        Query execution
        Result validation
    Performance Tests
      Small files 100KB
      Medium files 1-10MB
      Large files 10MB+
      Concurrent execution
    Security Tests
      IAM permissions
      Encryption
      VPC networking
```

### Testing Method Comparison

```mermaid
graph TB
    subgraph "Testing Methods"
        M1[Method 1<br/>test_local.py<br/>Python Script]
        M2[Method 2<br/>pytest<br/>Unit Tests]
        M3[Method 3<br/>Docker<br/>Lambda Runtime]
        M4[Method 4<br/>SAM CLI<br/>Full Emulation]
        M5[Method 5<br/>AWS<br/>Real Environment]
    end
    
    subgraph "Characteristics"
        Speed[Speed ⚡]
        Accuracy[Accuracy 🎯]
        Setup[Setup Complexity 🔧]
        Cost[Cost 💰]
    end
    
    M1 -->|Fastest| Speed
    M1 -->|Simple| Setup
    M1 -->|Free| Cost
    M1 -.->|Mock| Accuracy
    
    M2 -->|Fast| Speed
    M2 -->|Simple| Setup
    M2 -->|Free| Cost
    M2 -.->|Mock| Accuracy
    
    M3 -->|Medium| Speed
    M3 -->|Medium| Setup
    M3 -->|Free| Cost
    M3 -->|High| Accuracy
    
    M4 -->|Slow| Speed
    M4 -->|Complex| Setup
    M4 -->|Free| Cost
    M4 -->|Very High| Accuracy
    
    M5 -->|Slow| Speed
    M5 -->|Simple| Setup
    M5 -->|Paid| Cost
    M5 -->|100%| Accuracy
    
    style M1 fill:#4CAF50,color:#fff
    style M2 fill:#2196F3,color:#fff
    style M3 fill:#FF9800,color:#fff
    style M4 fill:#9C27B0,color:#fff
    style M5 fill:#f44336,color:#fff
```

### Test Data Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Local as test_local.py
    participant Mock as Mock AWS
    participant Lambda as lambda_function.py
    participant Output as Test Results
    
    Dev->>Local: Run python test_local.py
    Local->>Mock: Setup mock S3
    Local->>Lambda: Import function
    Local->>Mock: Mock read JSON
    Mock-->>Lambda: Return test data
    Lambda->>Lambda: Flatten JSON
    Lambda->>Lambda: Add partitions
    Lambda->>Mock: Mock write Parquet
    Mock-->>Lambda: Success
    Lambda->>Local: Return response
    Local->>Output: Print results
    Output-->>Dev: Show success/failure
    
    Note over Dev,Output: All operations are mocked<br/>No AWS credentials needed
```

---

**Note:** All diagrams are written in Mermaid syntax and can be rendered in:
- GitHub Markdown
- GitLab Markdown  
- Confluence
- VS Code (with Mermaid extension)
- Mermaid Live Editor (https://mermaid.live)

**Last Updated:** 2025-12-05  
**Version:** 1.0

