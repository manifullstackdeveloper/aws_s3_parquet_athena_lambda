#!/bin/bash
set -e

echo "========================================="
echo "Building Lambda Deployment Package"
echo "========================================="

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf package
rm -f lambda_function.zip
rm -rf layer
rm -f lambda_layer.zip

# Create Lambda function ZIP
echo ""
echo "Creating Lambda function ZIP..."
zip -r lambda_function.zip lambda_function.py

echo "✅ Lambda function package created: lambda_function.zip"

# Build Lambda Layer
echo ""
echo "Building Lambda layer with dependencies..."
echo "This will install awswrangler and its dependencies..."

mkdir -p layer/python
pip install -r requirements.txt -t layer/python/ --upgrade

echo ""
echo "Creating layer ZIP..."
cd layer
zip -r ../lambda_layer.zip python/
cd ..

echo "✅ Lambda layer created: lambda_layer.zip"

# Show file sizes
echo ""
echo "========================================="
echo "Build Summary"
echo "========================================="
echo "Lambda function size: $(du -h lambda_function.zip | cut -f1)"
echo "Lambda layer size:    $(du -h lambda_layer.zip | cut -f1)"
echo ""
echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "1. cd terraform"
echo "2. cp terraform.tfvars.example terraform.tfvars"
echo "3. Edit terraform.tfvars with your values"
echo "4. terraform init"
echo "5. terraform plan"
echo "6. terraform apply"

