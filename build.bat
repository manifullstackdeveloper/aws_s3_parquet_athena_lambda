@echo off
REM Build script for Lambda deployment package on Windows
setlocal enabledelayedexpansion

echo =========================================
echo Building Lambda Deployment Package
echo =========================================

REM Clean previous builds
echo Cleaning previous builds...
if exist package rmdir /s /q package
if exist lambda_function.zip del /q lambda_function.zip
if exist layer rmdir /s /q layer
if exist lambda_layer.zip del /q lambda_layer.zip

REM Create Lambda function ZIP
echo.
echo Creating Lambda function ZIP...

REM Check if lambda_function.py exists
if not exist lambda_function.py (
    echo Error: lambda_function.py not found
    exit /b 1
)

REM Check if PowerShell is available (Windows 7+)
where powershell >nul 2>&1
if not errorlevel 1 goto :use_powershell
where zip >nul 2>&1
if not errorlevel 1 goto :use_zip
echo Error: Neither PowerShell nor zip command found.
echo Please install PowerShell (Windows 7+) or Git Bash with zip utility.
exit /b 1

:use_powershell
powershell -NoProfile -Command "Compress-Archive -Path lambda_function.py -DestinationPath lambda_function.zip -Force"
goto :zip_created

:use_zip
zip -r lambda_function.zip lambda_function.py

:zip_created

if not exist lambda_function.zip (
    echo Error: Failed to create lambda_function.zip
    exit /b 1
)

echo Lambda function package created: lambda_function.zip

REM Build Lambda Layer
echo.
echo Building Lambda layer with dependencies...
echo This will install awswrangler and its dependencies...

REM Check if pip is available
where pip >nul 2>&1
if errorlevel 1 (
    echo Error: pip not found. Please install Python with pip.
    exit /b 1
)

mkdir layer\python 2>nul
pip install -r requirements.txt -t layer\python\ --upgrade

if errorlevel 1 (
    echo Error: Failed to install dependencies
    exit /b 1
)

echo.
echo Creating layer ZIP...

REM Use PowerShell Compress-Archive (compress python directory to preserve structure)
where powershell >nul 2>&1
if not errorlevel 1 goto :use_powershell_layer
where zip >nul 2>&1
if not errorlevel 1 goto :use_zip_layer
echo Error: Neither PowerShell nor zip command found.
exit /b 1

:use_powershell_layer
cd layer
powershell -NoProfile -Command "Compress-Archive -Path python -DestinationPath ..\lambda_layer.zip -Force"
cd ..
goto :layer_created

:use_zip_layer
cd layer
zip -r ..\lambda_layer.zip python\
cd ..

:layer_created

if not exist lambda_layer.zip (
    echo Error: Failed to create lambda_layer.zip
    exit /b 1
)

echo Lambda layer created: lambda_layer.zip

REM Show file sizes
echo.
echo =========================================
echo Build Summary
echo =========================================

REM Get file sizes using PowerShell
where powershell >nul 2>&1
if not errorlevel 1 goto :show_sizes_powershell
REM Fallback: Use dir command (less precise)
for %%A in (lambda_function.zip) do echo Lambda function size: %%~zA bytes
for %%A in (lambda_layer.zip) do echo Lambda layer size:    %%~zA bytes
goto :sizes_done

:show_sizes_powershell
for /f "tokens=*" %%s in ('powershell -NoProfile -Command "(Get-Item lambda_function.zip).Length / 1MB | ForEach-Object { '{0:N2} MB' -f $_ }"') do set FUNC_SIZE=%%s
for /f "tokens=*" %%s in ('powershell -NoProfile -Command "(Get-Item lambda_layer.zip).Length / 1MB | ForEach-Object { '{0:N2} MB' -f $_ }"') do set LAYER_SIZE=%%s
echo Lambda function size: !FUNC_SIZE!
echo Lambda layer size:    !LAYER_SIZE!

:sizes_done

echo.
echo Build complete!
echo.
echo Next steps:
echo 1. cd terraform
echo 2. copy terraform.tfvars.example terraform.tfvars
echo 3. Edit terraform.tfvars with your values
echo 4. terraform init
echo 5. terraform plan
echo 6. terraform apply
echo.

endlocal