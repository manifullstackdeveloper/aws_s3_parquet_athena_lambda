"""
Local testing script that writes actual Parquet files to output/ directory.

This script processes JSON files and writes real Parquet files locally
so you can inspect the operationOutcome explosion results.
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime
import pandas as pd

# Add current directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import Lambda functions
from lambda_function import (
    read_json_from_s3 as read_json_logic,
    flatten_json,
    add_partition_columns
)


def read_json_from_file(file_path: str):
    """Read JSON from local file"""
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Try to parse as JSON array first, then single object
    try:
        data = json.loads(content)
        if isinstance(data, list):
            return data
        else:
            return [data]
    except json.JSONDecodeError:
        # Try JSONL (newline-delimited JSON)
        records = []
        for line in content.strip().split('\n'):
            if line.strip():
                records.append(json.loads(line))
        return records


def process_json_to_parquet(input_file: str, output_dir: str = "output"):
    """
    Process JSON file and write Parquet output locally.
    
    Args:
        input_file: Path to input JSON file
        output_dir: Directory to write Parquet files
    """
    print(f"\n{'='*70}")
    print(f"Processing: {input_file}")
    print('='*70)
    
    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(exist_ok=True)
    
    # Read JSON
    print(f"\n📄 Reading JSON file...")
    records = read_json_from_file(input_file)
    print(f"✓ Read {len(records)} JSON records")
    
    # Print input structure
    print(f"\n📊 Input Structure:")
    for i, record in enumerate(records, 1):
        outcome_count = 0
        if 'operationOutcome' in record and isinstance(record['operationOutcome'], list):
            outcome_count = len(record['operationOutcome'])
        print(f"  Record {i}: {outcome_count} operationOutcome entries")
    
    # Flatten JSON
    print(f"\n🔄 Flattening JSON...")
    df = flatten_json(records)
    print(f"✓ Flattened to {len(df)} rows with {len(df.columns)} columns")
    
    # Show columns
    print(f"\n📋 Columns: {list(df.columns)}")
    
    # Add partition columns
    source = 'lca-persist' if 'lca' in input_file else 'dxa-persist'
    df = add_partition_columns(df, source)
    
    # Generate output filename
    base_name = Path(input_file).stem
    output_file = output_path / f"{base_name}.parquet"
    
    # Write Parquet
    print(f"\n💾 Writing Parquet file...")
    df.to_parquet(output_file, compression='snappy', index=False)
    print(f"✓ Written to: {output_file}")
    
    # Show file size
    file_size = output_file.stat().st_size
    print(f"✓ File size: {file_size:,} bytes ({file_size/1024:.2f} KB)")
    
    # Display sample data
    print(f"\n📊 Sample Data (first 5 rows):")
    print("="*70)
    
    # Select key columns to display
    display_cols = [
        's3Filename', 'patientId', 'statusCode',
        'operationOutcomeLocation', 'operationOutcomeSeverity',
        'operationOutcomeCode', 'source'
    ]
    
    # Only show columns that exist
    available_cols = [col for col in display_cols if col in df.columns]
    
    pd.set_option('display.max_columns', None)
    pd.set_option('display.width', None)
    pd.set_option('display.max_colwidth', 40)
    
    print(df[available_cols].head().to_string(index=False))
    
    # Show full data for small datasets
    if len(df) <= 10:
        print(f"\n📊 All {len(df)} rows:")
        print("="*70)
        print(df[available_cols].to_string(index=False))
    
    # Statistics
    print(f"\n📈 Statistics:")
    print(f"  Input records: {len(records)}")
    print(f"  Output rows: {len(df)}")
    print(f"  Explosion ratio: {len(df) / len(records):.2f}x")
    
    # Count rows by operationOutcome presence
    has_outcome = df['operationOutcomeCode'].notna().sum()
    no_outcome = df['operationOutcomeCode'].isna().sum()
    print(f"\n  Rows with operationOutcome: {has_outcome}")
    print(f"  Rows without operationOutcome: {no_outcome}")
    
    # Read back and verify
    print(f"\n✓ Verification:")
    df_readback = pd.read_parquet(output_file)
    print(f"  Read back {len(df_readback)} rows successfully")
    print(f"  Columns match: {list(df.columns) == list(df_readback.columns)}")
    
    return output_file, df


def process_all_test_files(test_dir: str = "test_data", output_dir: str = "output"):
    """Process all JSON files in test directory"""
    print("\n" + "="*70)
    print("🧪 PROCESSING ALL TEST FILES TO PARQUET")
    print("="*70)
    
    test_path = Path(test_dir)
    if not test_path.exists():
        print(f"❌ Test directory not found: {test_dir}")
        return
    
    # Find all JSON files
    json_files = list(test_path.glob("*.json"))
    
    # Also check for example_payload.json in root
    if Path("example_payload.json").exists():
        json_files.append(Path("example_payload.json"))
    
    if not json_files:
        print(f"❌ No JSON files found in {test_dir}")
        return
    
    print(f"\nFound {len(json_files)} JSON files")
    
    results = []
    for json_file in json_files:
        try:
            output_file, df = process_json_to_parquet(str(json_file), output_dir)
            results.append({
                'input': json_file.name,
                'output': output_file.name,
                'rows': len(df),
                'status': '✅'
            })
        except Exception as e:
            print(f"\n❌ Error processing {json_file.name}: {str(e)}")
            results.append({
                'input': json_file.name,
                'output': '-',
                'rows': 0,
                'status': '❌'
            })
    
    # Summary
    print("\n" + "="*70)
    print("📊 SUMMARY")
    print("="*70)
    print(f"\n{'Input File':<30} {'Output File':<30} {'Rows':<10} {'Status'}")
    print("-"*70)
    for r in results:
        print(f"{r['input']:<30} {r['output']:<30} {r['rows']:<10} {r['status']}")
    
    print(f"\n✓ Output directory: {output_dir}/")
    print(f"✓ Total files processed: {len([r for r in results if r['status'] == '✅'])}/{len(results)}")


def inspect_parquet(parquet_file: str):
    """Inspect a Parquet file and show detailed information"""
    print("\n" + "="*70)
    print(f"🔍 INSPECTING: {parquet_file}")
    print("="*70)
    
    if not Path(parquet_file).exists():
        print(f"❌ File not found: {parquet_file}")
        return
    
    # Read Parquet
    df = pd.read_parquet(parquet_file)
    
    # Basic info
    print(f"\n📊 Basic Information:")
    print(f"  Rows: {len(df)}")
    print(f"  Columns: {len(df.columns)}")
    print(f"  File size: {Path(parquet_file).stat().st_size:,} bytes")
    
    # Schema
    print(f"\n📋 Schema:")
    print(f"{'Column':<30} {'Type':<15} {'Non-Null':<10} {'Sample Value'}")
    print("-"*70)
    for col in df.columns:
        dtype = str(df[col].dtype)
        non_null = df[col].notna().sum()
        sample = df[col].iloc[0] if len(df) > 0 and df[col].notna().any() else 'NULL'
        if isinstance(sample, str) and len(sample) > 20:
            sample = sample[:20] + "..."
        print(f"{col:<30} {dtype:<15} {non_null:<10} {sample}")
    
    # Full data
    print(f"\n📊 All Data:")
    print("="*70)
    pd.set_option('display.max_columns', None)
    pd.set_option('display.width', None)
    pd.set_option('display.max_colwidth', 50)
    print(df.to_string(index=False))
    
    # Export to CSV for easier viewing
    csv_file = Path(parquet_file).with_suffix('.csv')
    df.to_csv(csv_file, index=False)
    print(f"\n✓ Also exported to CSV: {csv_file}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Process JSON to Parquet locally")
    parser.add_argument(
        '--file',
        help='Process single JSON file'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='Process all test files'
    )
    parser.add_argument(
        '--inspect',
        help='Inspect a Parquet file'
    )
    parser.add_argument(
        '--output-dir',
        default='output',
        help='Output directory for Parquet files (default: output)'
    )
    
    args = parser.parse_args()
    
    if args.inspect:
        inspect_parquet(args.inspect)
    elif args.file:
        output_file, df = process_json_to_parquet(args.file, args.output_dir)
        print(f"\n✓ To inspect the file, run:")
        print(f"  python test_local_with_output.py --inspect {output_file}")
    elif args.all:
        process_all_test_files(output_dir=args.output_dir)
    else:
        # Default: process example_payload.json
        if Path("example_payload.json").exists():
            output_file, df = process_json_to_parquet("example_payload.json", args.output_dir)
            print(f"\n✓ To inspect the file, run:")
            print(f"  python test_local_with_output.py --inspect {output_file}")
        else:
            parser.print_help()

