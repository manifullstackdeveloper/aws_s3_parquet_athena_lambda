# Local Testing Guide

Complete guide for testing the Lambda function locally without deploying to AWS.

## Table of Contents

- [Quick Start](#quick-start)
- [Testing Methods](#testing-methods)
- [Unit Tests](#unit-tests)
- [Local Simulation](#local-simulation)
- [Docker Testing](#docker-testing)
- [AWS SAM Testing](#aws-sam-testing)
- [Debugging](#debugging)

---

## Quick Start

### 1. Install Dependencies

```bash
# Install production dependencies
pip install -r requirements.txt

# Install development/testing dependencies
pip install -r requirements-dev.txt
```

### 2. Run Local Tests

```bash
# Simple local test
python test_local.py

# Test with specific file
python test_local.py --file example_payload.json

# Run all test files
python test_local.py --all
```

### 3. Run Unit Tests

```bash
# Run all unit tests
pytest test_unit.py -v

# Run with coverage
pytest test_unit.py --cov=lambda_function --cov-report=html

# Run specific test
pytest test_unit.py::TestReadJSON::test_read_json_array -v
```

---

## Testing Methods

### Method 1: Simple Python Script (Fastest)

Use `test_local.py` for quick testing without AWS dependencies.

```bash
python test_local.py
```

**Pros:**
- ✅ Fast execution
- ✅ No AWS credentials needed
- ✅ Easy debugging
- ✅ Mocks all AWS services

**Cons:**
- ❌ Not 100% identical to Lambda environment
- ❌ Mocking may not catch all issues

### Method 2: Unit Tests with pytest

Use `test_unit.py` for comprehensive testing.

```bash
pytest test_unit.py -v
```

**Pros:**
- ✅ Comprehensive test coverage
- ✅ CI/CD integration
- ✅ Code coverage reports
- ✅ Fast execution

**Cons:**
- ❌ Requires test writing
- ❌ Mocked environment

### Method 3: Docker + Lambda Runtime

Test in actual Lambda runtime environment.

```bash
docker run --rm -v "$PWD":/var/task \
  -e SOURCE_BUCKET=fhir-lca-persist \
  -e TARGET_BUCKET=fhir-ingest-analytics \
  public.ecr.aws/lambda/python:3.12 \
  python test_local.py
```

**Pros:**
- ✅ Identical to Lambda environment
- ✅ Tests dependencies
- ✅ Architecture validation

**Cons:**
- ❌ Slower than native Python
- ❌ Requires Docker

### Method 4: AWS SAM Local

Test with full AWS Lambda emulation.

```bash
sam local invoke -e test_event.json
```

**Pros:**
- ✅ Most realistic testing
- ✅ Tests Lambda triggers
- ✅ API Gateway integration

**Cons:**
- ❌ Requires SAM CLI installation
- ❌ Slower execution
- ❌ More complex setup

---

## Unit Tests

### Running Unit Tests

```bash
# Run all tests
pytest test_unit.py -v

# Run specific test class
pytest test_unit.py::TestReadJSON -v

# Run with coverage
pytest test_unit.py --cov=lambda_function --cov-report=term-missing

# Generate HTML coverage report
pytest test_unit.py --cov=lambda_function --cov-report=html
open htmlcov/index.html
```

### Test Structure

```python
# test_unit.py structure
class TestReadJSON:          # JSON reading tests
class TestFlattenJSON:       # Flattening tests
class TestPartitionColumns:  # Partition logic tests
class TestOutputPath:        # Path generation tests
class TestFileExists:        # S3 existence checks
class TestConfiguration:     # Config loading tests
class TestLambdaHandler:     # End-to-end tests
class TestEdgeCases:         # Edge cases & errors
```

### Adding New Tests

```python
import pytest

def test_my_new_feature(mock_aws_clients):
    """Test description"""
    from lambda_function import my_function
    
    # Setup
    test_data = {...}
    
    # Execute
    result = my_function(test_data)
    
    # Assert
    assert result == expected
```

---

## Local Simulation

### Basic Usage

```bash
# Test with default example file
python test_local.py

# Test with custom JSON file
python test_local.py --file my_test_data.json

# Run all test files
python test_local.py --all
```

### Creating Test Data

Create JSON files in `test_data/` directory:

```bash
mkdir -p test_data

# Create test file
cat > test_data/my_test.json << EOF
[
  {
    "s3Filename": "test.json",
    "source": "lca-persist",
    "statusCode": 200,
    "patientId": "PT-TEST"
  }
]
EOF

# Test it
python test_local.py --file my_test.json
```

### Test Data Formats

**JSON Array:**
```json
[
  {"id": 1, "name": "test1"},
  {"id": 2, "name": "test2"}
]
```

**JSON Object:**
```json
{
  "id": 1,
  "name": "test"
}
```

**JSONL (newline-delimited):**
```
{"id": 1, "name": "test1"}
{"id": 2, "name": "test2"}
```

### Expected Output

```
======================================================================
🧪 LOCAL LAMBDA TESTING
======================================================================

📁 Created test file: test_data/example_payload.json
📄 Test file: test_data/example_payload.json

🚀 Invoking Lambda handler...

[INFO] Processing file: s3://fhir-lca-persist/example_payload.json
[INFO] Read 3 JSON records
[INFO] Flattened 3 records with 16 columns
[INFO] Output path: s3://fhir-ingest-analytics/data/source=lca-persist/ingest_date=2025-12-05/hour=10/example_payload.parquet

======================================================================
✅ LAMBDA EXECUTION COMPLETED
======================================================================

📊 Response:
{
  "statusCode": 200,
  "body": "{...}"
}

📤 Files that would be uploaded to S3:
  ✓ s3://fhir-ingest-analytics/data/source=lca-persist/ingest_date=2025-12-05/hour=10/example_payload.parquet
    - Records: 3
    - Columns: ['s3Filename', 'source', 'statusCode', ...]
```

---

## Docker Testing

### Build Custom Test Image

```bash
# Create Dockerfile for testing
cat > Dockerfile.test << EOF
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY lambda_function.py .
COPY test_local.py .
COPY test_data/ test_data/

CMD ["python", "test_local.py"]
EOF

# Build image
docker build -f Dockerfile.test -t lambda-test .

# Run tests
docker run --rm lambda-test
```

### Test with Lambda Runtime Interface Emulator

```bash
# Build Lambda image
cat > Dockerfile.lambda << EOF
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY lambda_function.py .

CMD ["lambda_function.lambda_handler"]
EOF

# Build
docker build -f Dockerfile.lambda -t lambda-function .

# Run Lambda
docker run -p 9000:8080 \
  -e SOURCE_BUCKET=fhir-lca-persist \
  -e TARGET_BUCKET=fhir-ingest-analytics \
  lambda-function

# Invoke (in another terminal)
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d @test_event.json
```

---

## AWS SAM Testing

### 1. Install SAM CLI

```bash
# macOS
brew install aws-sam-cli

# Linux
pip install aws-sam-cli

# Verify
sam --version
```

### 2. Create SAM Template

```bash
cat > template.yaml << EOF
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  AnalyticsFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: fhir-analytics-test
      Runtime: python3.12
      Handler: lambda_function.lambda_handler
      CodeUri: .
      MemorySize: 512
      Timeout: 300
      Environment:
        Variables:
          SOURCE_BUCKET: fhir-lca-persist
          TARGET_BUCKET: fhir-ingest-analytics
      Events:
        S3Event:
          Type: S3
          Properties:
            Bucket: !Ref SourceBucket
            Events: s3:ObjectCreated:*

  SourceBucket:
    Type: AWS::S3::Bucket
EOF
```

### 3. Test with SAM

```bash
# Build
sam build

# Test locally
sam local invoke AnalyticsFunction -e test_event.json

# Start local API
sam local start-lambda

# Invoke via AWS SDK
aws lambda invoke \
  --function-name AnalyticsFunction \
  --endpoint-url http://localhost:3001 \
  --payload file://test_event.json \
  output.json
```

---

## Debugging

### VS Code Debugging

Create `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Lambda Locally",
      "type": "python",
      "request": "launch",
      "program": "${workspaceFolder}/test_local.py",
      "console": "integratedTerminal",
      "env": {
        "SOURCE_BUCKET": "fhir-lca-persist",
        "TARGET_BUCKET": "fhir-ingest-analytics"
      }
    },
    {
      "name": "Debug Unit Tests",
      "type": "python",
      "request": "launch",
      "module": "pytest",
      "args": [
        "test_unit.py",
        "-v",
        "-s"
      ],
      "console": "integratedTerminal"
    }
  ]
}
```

### PyCharm Debugging

1. Right-click `test_local.py`
2. Select "Debug 'test_local'"
3. Set breakpoints as needed

### Command Line Debugging

```bash
# Add breakpoint in code
import pdb; pdb.set_trace()

# Run with debugger
python -m pdb test_local.py

# Useful pdb commands
# n - next line
# s - step into
# c - continue
# l - list code
# p variable - print variable
# q - quit
```

### Logging

```python
# Increase log verbosity
import logging
logging.basicConfig(level=logging.DEBUG)

# Or set environment variable
export LOG_LEVEL=DEBUG
python test_local.py
```

---

## Common Test Scenarios

### Test Success Case

```bash
python test_local.py --file example_payload.json
```

### Test Single Object

```bash
python test_local.py --file test_single_object.json
```

### Test JSONL Format

```bash
python test_local.py --file test_jsonl.json
```

### Test Error Handling

```bash
# Create invalid JSON
echo "invalid json" > test_data/invalid.json
python test_local.py --file invalid.json
```

### Test Large File

```python
# Generate large test file
import json

records = [{"id": i, "data": "x"*100} for i in range(10000)]
with open('test_data/large.json', 'w') as f:
    json.dump(records, f)
```

```bash
python test_local.py --file large.json
```

---

## Performance Testing

### Measure Execution Time

```bash
time python test_local.py
```

### Memory Profiling

```bash
pip install memory_profiler

# Add decorator to functions
@profile
def my_function():
    pass

# Run with profiler
python -m memory_profiler test_local.py
```

### Benchmark Different File Sizes

```python
import time
import json

for size in [100, 1000, 10000]:
    records = [{"id": i} for i in range(size)]
    
    with open(f'test_data/test_{size}.json', 'w') as f:
        json.dump(records, f)
    
    start = time.time()
    # Run test
    duration = time.time() - start
    print(f"{size} records: {duration:.2f}s")
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Test Lambda

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: actions/setup-python@v4
        with:
          python-version: '3.12'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-dev.txt
      
      - name: Run unit tests
        run: pytest test_unit.py -v --cov=lambda_function
      
      - name: Run local tests
        run: python test_local.py --all
```

---

## Troubleshooting

### Issue: Module not found

```bash
# Ensure dependencies are installed
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### Issue: AWS credentials error

```bash
# Mocked tests shouldn't need credentials
# If needed, set dummy credentials
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

### Issue: Test data not found

```bash
# Ensure test_data directory exists
mkdir -p test_data

# Copy example payload
cp example_payload.json test_data/
```

### Issue: Import errors

```bash
# Add current directory to PYTHONPATH
export PYTHONPATH="${PYTHONPATH}:${PWD}"
python test_local.py
```

---

## Best Practices

1. **Always test locally** before deploying
2. **Use pytest fixtures** for reusable test data
3. **Mock AWS services** to avoid costs
4. **Test edge cases** (empty data, errors, large files)
5. **Measure coverage** - aim for >80%
6. **Automate tests** in CI/CD pipeline
7. **Version test data** alongside code
8. **Document test scenarios** in comments

---

## Next Steps

1. ✅ Run local tests: `python test_local.py`
2. ✅ Run unit tests: `pytest test_unit.py -v`
3. ✅ Check coverage: `pytest --cov=lambda_function`
4. ✅ Fix any failures
5. ✅ Deploy to AWS: `terraform apply`
6. ✅ Run integration tests against AWS

---

**Happy Testing! 🧪**

