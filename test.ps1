# PowerShell script for local Lambda testing on Windows
# Usage: .\test.ps1 [quick|unit|coverage|all|help]

param(
    [string]$TestType = "all"
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🧪 Lambda Local Testing Suite" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Python is available
try {
    $pythonVersion = python --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Python not found"
    }
    Write-Host "✓ Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Python 3 not found. Please install Python 3.12+" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Check if dependencies are installed
try {
    python -c "import pandas" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Dependencies not installed"
    }
    Write-Host "✓ Dependencies already installed" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Dependencies not installed. Installing..." -ForegroundColor Yellow
    pip install -r requirements.txt -q
    if (Test-Path "requirements-dev.txt") {
        pip install -r requirements-dev.txt -q
    }
    Write-Host "✓ Dependencies installed" -ForegroundColor Green
}
Write-Host ""

# Create test_data directory if it doesn't exist
if (-not (Test-Path "test_data")) {
    Write-Host "📁 Creating test_data directory..."
    New-Item -ItemType Directory -Path "test_data" | Out-Null
}

# Copy example payload if it doesn't exist in test_data
if (-not (Test-Path "test_data/example_payload.json") -and (Test-Path "example_payload.json")) {
    Copy-Item "example_payload.json" "test_data/"
    Write-Host "✓ Copied example_payload.json to test_data/" -ForegroundColor Green
}
Write-Host ""

# Run tests based on command
switch ($TestType.ToLower()) {
    "quick" {
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "🚀 Running Quick Local Test" -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""
        python test_local.py
    }
    
    "unit" {
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "🔬 Running Unit Tests" -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""
        try {
            pytest test_unit.py -v
        } catch {
            Write-Host "⚠️  pytest not found. Installing..." -ForegroundColor Yellow
            pip install pytest -q
            pytest test_unit.py -v
        }
    }
    
    "coverage" {
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "📊 Running Tests with Coverage" -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""
        try {
            pytest test_unit.py --cov=lambda_function --cov-report=term-missing
            Write-Host ""
            Write-Host "✓ Coverage report complete" -ForegroundColor Green
            Write-Host ""
            Write-Host "To view HTML coverage report:"
            Write-Host "  pytest test_unit.py --cov=lambda_function --cov-report=html"
            Write-Host "  Start-Process htmlcov/index.html"
        } catch {
            Write-Host "❌ pytest not found. Installing..." -ForegroundColor Red
            pip install pytest pytest-cov -q
            pytest test_unit.py --cov=lambda_function --cov-report=term-missing
        }
    }
    
    "all" {
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "🎯 Running All Tests" -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Run local test
        Write-Host "1️⃣  Quick Local Test" -ForegroundColor Yellow
        Write-Host "-------------------"
        python test_local.py --all
        
        Write-Host ""
        Write-Host ""
        
        # Run unit tests
        Write-Host "2️⃣  Unit Tests" -ForegroundColor Yellow
        Write-Host "-------------------"
        try {
            pytest test_unit.py -v --tb=short
        } catch {
            Write-Host "⚠️  pytest not found, skipping unit tests" -ForegroundColor Yellow
            Write-Host "Install with: pip install pytest"
        }
    }
    
    "help" {
        Write-Host "Usage: .\test.ps1 [command]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  quick     - Run quick local test"
        Write-Host "  unit      - Run unit tests with pytest"
        Write-Host "  coverage  - Run tests with coverage report"
        Write-Host "  all       - Run all tests (default)"
        Write-Host "  help      - Show this help message"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\test.ps1              # Run all tests"
        Write-Host "  .\test.ps1 quick        # Quick local test"
        Write-Host "  .\test.ps1 unit         # Unit tests only"
        Write-Host "  .\test.ps1 coverage     # With coverage"
        exit 0
    }
    
    default {
        Write-Host "❌ Unknown command: $TestType" -ForegroundColor Red
        Write-Host "Run '.\test.ps1 help' for usage"
        exit 1
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ Testing Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

