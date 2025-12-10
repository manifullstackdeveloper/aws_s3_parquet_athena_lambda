@echo off
REM Batch script for local Lambda testing on Windows
REM Usage: test.bat [quick|unit|coverage|all|help]

setlocal enabledelayedexpansion

set "TEST_TYPE=%~1"
if "%TEST_TYPE%"=="" set "TEST_TYPE=all"

echo =========================================
echo 🧪 Lambda Local Testing Suite
echo =========================================
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python 3 not found. Please install Python 3.12+
    exit /b 1
)

for /f "tokens=*" %%v in ('python --version 2^>^&1') do set PYTHON_VERSION=%%v
echo ✓ Python found: !PYTHON_VERSION!
echo.

REM Check if dependencies are installed
python -c "import pandas" >nul 2>&1
if errorlevel 1 (
    echo ⚠️  Dependencies not installed. Installing...
    pip install -r requirements.txt -q
    if exist requirements-dev.txt (
        pip install -r requirements-dev.txt -q
    )
    echo ✓ Dependencies installed
) else (
    echo ✓ Dependencies already installed
)
echo.

REM Create test_data directory if it doesn't exist
if not exist "test_data" (
    echo 📁 Creating test_data directory...
    mkdir test_data
)

REM Copy example payload if it doesn't exist in test_data
if not exist "test_data\example_payload.json" (
    if exist "example_payload.json" (
        copy "example_payload.json" "test_data\" >nul
        echo ✓ Copied example_payload.json to test_data/
    )
)
echo.

REM Run tests based on command
if /i "%TEST_TYPE%"=="quick" goto :quick
if /i "%TEST_TYPE%"=="unit" goto :unit
if /i "%TEST_TYPE%"=="coverage" goto :coverage
if /i "%TEST_TYPE%"=="all" goto :all
if /i "%TEST_TYPE%"=="help" goto :help
goto :unknown

:quick
echo =========================================
echo 🚀 Running Quick Local Test
echo =========================================
echo.
python test_local.py
goto :end

:unit
echo =========================================
echo 🔬 Running Unit Tests
echo =========================================
echo.
pytest test_unit.py -v >nul 2>&1
if errorlevel 1 (
    echo ⚠️  pytest not found. Installing...
    pip install pytest -q
    pytest test_unit.py -v
) else (
    pytest test_unit.py -v
)
goto :end

:coverage
echo =========================================
echo 📊 Running Tests with Coverage
echo =========================================
echo.
pytest test_unit.py --cov=lambda_function --cov-report=term-missing >nul 2>&1
if errorlevel 1 (
    echo ❌ pytest not found. Installing...
    pip install pytest pytest-cov -q
    pytest test_unit.py --cov=lambda_function --cov-report=term-missing
) else (
    pytest test_unit.py --cov=lambda_function --cov-report=term-missing
)
echo.
echo ✓ Coverage report complete
echo.
echo To view HTML coverage report:
echo   pytest test_unit.py --cov=lambda_function --cov-report=html
echo   start htmlcov\index.html
goto :end

:all
echo =========================================
echo 🎯 Running All Tests
echo =========================================
echo.

REM Run local test
echo 1️⃣  Quick Local Test
echo -------------------
python test_local.py --all

echo.
echo.

REM Run unit tests
echo 2️⃣  Unit Tests
echo -------------------
pytest test_unit.py -v --tb=short >nul 2>&1
if errorlevel 1 (
    echo ⚠️  pytest not found, skipping unit tests
    echo Install with: pip install pytest
) else (
    pytest test_unit.py -v --tb=short
)
goto :end

:help
echo Usage: test.bat [command]
echo.
echo Commands:
echo   quick     - Run quick local test
echo   unit      - Run unit tests with pytest
echo   coverage  - Run tests with coverage report
echo   all       - Run all tests (default)
echo   help      - Show this help message
echo.
echo Examples:
echo   test.bat              # Run all tests
echo   test.bat quick        # Quick local test
echo   test.bat unit         # Unit tests only
echo   test.bat coverage     # With coverage
exit /b 0

:unknown
echo ❌ Unknown command: %TEST_TYPE%
echo Run 'test.bat help' for usage
exit /b 1

:end
echo.
echo =========================================
echo ✅ Testing Complete!
echo =========================================
echo.

