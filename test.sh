#!/bin/bash
# Quick test script for local Lambda testing

set -e

echo "========================================="
echo "🧪 Lambda Local Testing Suite"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 not found. Please install Python 3.12+${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Python found: $(python3 --version)${NC}"
echo ""

# Check if dependencies are installed
if ! python3 -c "import pandas" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Dependencies not installed. Installing...${NC}"
    pip install -r requirements.txt -q
    pip install -r requirements-dev.txt -q
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
fi
echo ""

# Create test_data directory if it doesn't exist
if [ ! -d "test_data" ]; then
    echo "📁 Creating test_data directory..."
    mkdir -p test_data
fi

# Copy example payload if it doesn't exist in test_data
if [ ! -f "test_data/example_payload.json" ] && [ -f "example_payload.json" ]; then
    cp example_payload.json test_data/
    echo -e "${GREEN}✓ Copied example_payload.json to test_data/${NC}"
fi
echo ""

# Parse command line arguments
TEST_TYPE="${1:-all}"

case $TEST_TYPE in
    quick)
        echo "========================================="
        echo "🚀 Running Quick Local Test"
        echo "========================================="
        echo ""
        python3 test_local.py
        ;;
    
    unit)
        echo "========================================="
        echo "🔬 Running Unit Tests"
        echo "========================================="
        echo ""
        if command -v pytest &> /dev/null; then
            pytest test_unit.py -v
        else
            echo -e "${YELLOW}⚠️  pytest not found. Installing...${NC}"
            pip install pytest -q
            pytest test_unit.py -v
        fi
        ;;
    
    coverage)
        echo "========================================="
        echo "📊 Running Tests with Coverage"
        echo "========================================="
        echo ""
        if command -v pytest &> /dev/null; then
            pytest test_unit.py --cov=lambda_function --cov-report=term-missing
            echo ""
            echo -e "${GREEN}✓ Coverage report complete${NC}"
            echo ""
            echo "To view HTML coverage report:"
            echo "  pytest test_unit.py --cov=lambda_function --cov-report=html"
            echo "  open htmlcov/index.html"
        else
            echo -e "${RED}❌ pytest not found. Installing...${NC}"
            pip install pytest pytest-cov -q
            pytest test_unit.py --cov=lambda_function --cov-report=term-missing
        fi
        ;;
    
    all)
        echo "========================================="
        echo "🎯 Running All Tests"
        echo "========================================="
        echo ""
        
        # Run local test
        echo "1️⃣  Quick Local Test"
        echo "-------------------"
        python3 test_local.py --all
        
        echo ""
        echo ""
        
        # Run unit tests
        echo "2️⃣  Unit Tests"
        echo "-------------------"
        if command -v pytest &> /dev/null; then
            pytest test_unit.py -v --tb=short
        else
            echo -e "${YELLOW}⚠️  pytest not found, skipping unit tests${NC}"
            echo "Install with: pip install pytest"
        fi
        ;;
    
    help|--help|-h)
        echo "Usage: ./test.sh [command]"
        echo ""
        echo "Commands:"
        echo "  quick     - Run quick local test (default)"
        echo "  unit      - Run unit tests with pytest"
        echo "  coverage  - Run tests with coverage report"
        echo "  all       - Run all tests"
        echo "  help      - Show this help message"
        echo ""
        echo "Examples:"
        echo "  ./test.sh              # Run all tests"
        echo "  ./test.sh quick        # Quick local test"
        echo "  ./test.sh unit         # Unit tests only"
        echo "  ./test.sh coverage     # With coverage"
        exit 0
        ;;
    
    *)
        echo -e "${RED}❌ Unknown command: $TEST_TYPE${NC}"
        echo "Run './test.sh help' for usage"
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo -e "${GREEN}✅ Testing Complete!${NC}"
echo "========================================="
echo ""

