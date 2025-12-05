# Testing Quick Start Guide

**TL;DR:** Test your Lambda locally without AWS in 30 seconds!

## 🚀 Fastest Way to Test

```bash
# One command to rule them all
./test.sh
```

## 📋 Quick Reference

### Method 1: Simple Bash Script (Recommended for Quick Tests)

```bash
# All tests
./test.sh all

# Quick local test
./test.sh quick

# Unit tests only
./test.sh unit

# With coverage
./test.sh coverage
```

### Method 2: Python Script (Most Control)

```bash
# Install dependencies first
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Test with default example file
python test_local.py

# Test with specific file
python test_local.py --file example_payload.json

# Test all files in test_data/
python test_local.py --all
```

### Method 3: Pytest (Best for CI/CD)

```bash
# All unit tests
pytest test_unit.py -v

# Specific test class
pytest test_unit.py::TestReadJSON -v

# With coverage
pytest test_unit.py --cov=lambda_function

# HTML coverage report
pytest test_unit.py --cov=lambda_function --cov-report=html
open htmlcov/index.html
```

## 📊 Testing Methods Comparison

| Method | Speed | Setup | AWS Required | Use Case |
|--------|-------|-------|--------------|----------|
| `./test.sh` | ⚡⚡⚡ | Easy | ❌ No | Quick validation |
| `python test_local.py` | ⚡⚡⚡ | Easy | ❌ No | Development |
| `pytest test_unit.py` | ⚡⚡ | Easy | ❌ No | CI/CD, coverage |
| Docker | ⚡ | Medium | ❌ No | Realistic testing |
| SAM CLI | ⚡ | Hard | ❌ No | Full emulation |
| Real AWS | ⚡ | Easy | ✅ Yes | Final validation |

## 🎯 Common Workflows

### Development Workflow

```bash
# 1. Make code changes
vim lambda_function.py

# 2. Quick test
./test.sh quick

# 3. Full test suite
./test.sh all

# 4. Deploy if tests pass
cd terraform && terraform apply
```

### Pre-Commit Workflow

```bash
# Before committing
pytest test_unit.py -v
python test_local.py --all

# If all pass, commit
git add .
git commit -m "Your changes"
```

### CI/CD Workflow

```yaml
# .github/workflows/test.yml
- name: Test
  run: |
    pip install -r requirements-dev.txt
    pytest test_unit.py --cov=lambda_function
    python test_local.py --all
```

## 📁 Test Files

Add your test JSON files to `test_data/` directory:

```bash
# Create test file
cat > test_data/my_test.json << 'EOF'
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

## ✅ Expected Output (Success)

```
======================================================================
🧪 LOCAL LAMBDA TESTING
======================================================================

📄 Test file: test_data/example_payload.json

🚀 Invoking Lambda handler...

[INFO] Processing file: s3://fhir-lca-persist/example_payload.json
[INFO] Read 3 JSON records
[INFO] Flattened 3 records with 16 columns
[INFO] Output path: s3://fhir-ingest-analytics/data/source=lca-persist/...

======================================================================
✅ LAMBDA EXECUTION COMPLETED
======================================================================

📊 Response:
{
  "statusCode": 200,
  "body": "..."
}

📤 Files that would be uploaded to S3:
  ✓ s3://fhir-ingest-analytics/data/source=lca-persist/...
    - Records: 3
    - Columns: ['s3Filename', 'source', 'statusCode', ...]
```

## 🐛 Debugging

### Enable Debug Logging

```bash
export LOG_LEVEL=DEBUG
python test_local.py
```

### Interactive Debugging

```python
# Add to lambda_function.py
import pdb; pdb.set_trace()

# Run
python test_local.py
```

### VS Code Debugging

1. Open `test_local.py`
2. Set breakpoints (click left of line numbers)
3. Press F5 or click "Run and Debug"

## 🔍 What Gets Tested?

### Functionality Tests

- ✅ JSON parsing (array, object, JSONL)
- ✅ Nested JSON flattening
- ✅ Partition column generation
- ✅ S3 path generation
- ✅ Duplicate file detection
- ✅ Error handling

### Edge Cases

- ✅ Empty JSON arrays
- ✅ Single objects
- ✅ Large files (10K+ records)
- ✅ Special characters in filenames
- ✅ Invalid JSON format
- ✅ Missing fields

## 📈 Coverage Goals

- **Target:** >80% code coverage
- **Check:** `pytest test_unit.py --cov=lambda_function`
- **Report:** `pytest test_unit.py --cov=lambda_function --cov-report=html`

## 🆘 Troubleshooting

### "Module not found" error

```bash
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### "Test file not found" error

```bash
mkdir -p test_data
cp example_payload.json test_data/
```

### "Permission denied: ./test.sh"

```bash
chmod +x test.sh
./test.sh
```

## 🎓 Next Steps

1. ✅ Run: `./test.sh quick` to verify setup
2. ✅ Review: [LOCAL_TESTING.md](LOCAL_TESTING.md) for details
3. ✅ Add: Your own test files to `test_data/`
4. ✅ Integrate: Tests into your CI/CD pipeline
5. ✅ Deploy: `cd terraform && terraform apply`

## 📚 Documentation

- **Quick Start:** This file (you are here!)
- **Complete Guide:** [LOCAL_TESTING.md](LOCAL_TESTING.md)
- **Deployment:** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Main README:** [README.md](README.md)

---

**Get testing in 3 commands:**

```bash
pip install -r requirements-dev.txt
./test.sh
# ✅ Done!
```

---

**Happy Testing! 🎉**

