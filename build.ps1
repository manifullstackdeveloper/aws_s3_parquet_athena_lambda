# PowerShell build script for Lambda deployment package on Windows
# Usage: .\build.ps1

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Building Lambda Deployment Package" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
if (Test-Path "package") { Remove-Item -Recurse -Force "package" }
if (Test-Path "lambda_function.zip") { Remove-Item -Force "lambda_function.zip" }
if (Test-Path "layer") { Remove-Item -Recurse -Force "layer" }
if (Test-Path "lambda_layer.zip") { Remove-Item -Force "lambda_layer.zip" }

# Create Lambda function ZIP
Write-Host ""
Write-Host "Creating Lambda function ZIP..." -ForegroundColor Yellow

if (-not (Test-Path "lambda_function.py")) {
    Write-Host "❌ Error: lambda_function.py not found" -ForegroundColor Red
    exit 1
}

Compress-Archive -Path "lambda_function.py" -DestinationPath "lambda_function.zip" -Force

if (-not (Test-Path "lambda_function.zip")) {
    Write-Host "❌ Error: Failed to create lambda_function.zip" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Lambda function package created: lambda_function.zip" -ForegroundColor Green

# Build Lambda Layer
Write-Host ""
Write-Host "Building Lambda layer with dependencies..." -ForegroundColor Yellow
Write-Host "This will install awswrangler and its dependencies..." -ForegroundColor Yellow

New-Item -ItemType Directory -Force -Path "layer\python" | Out-Null

# Check if pip is available
try {
    $pipVersion = pip --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "pip not found"
    }
} catch {
    Write-Host "❌ Error: pip not found. Please install Python with pip." -ForegroundColor Red
    exit 1
}

pip install -r requirements.txt -t layer\python\ --upgrade

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error: Failed to install dependencies" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Creating layer ZIP..." -ForegroundColor Yellow

# Compress the python directory contents
Compress-Archive -Path "layer\python\*" -DestinationPath "lambda_layer.zip" -Force

if (-not (Test-Path "lambda_layer.zip")) {
    Write-Host "❌ Error: Failed to create lambda_layer.zip" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Lambda layer created: lambda_layer.zip" -ForegroundColor Green

# Show file sizes
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Build Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$funcSize = (Get-Item "lambda_function.zip").Length / 1MB
$layerSize = (Get-Item "lambda_layer.zip").Length / 1MB

Write-Host "Lambda function size: $([math]::Round($funcSize, 2)) MB" -ForegroundColor White
Write-Host "Lambda layer size:    $([math]::Round($layerSize, 2)) MB" -ForegroundColor White

Write-Host ""
Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. cd terraform"
Write-Host "2. Copy-Item terraform.tfvars.example terraform.tfvars"
Write-Host "3. Edit terraform.tfvars with your values"
Write-Host "4. terraform init"
Write-Host "5. terraform plan"
Write-Host "6. terraform apply"
Write-Host ""

