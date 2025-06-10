#!/usr/bin/env python3
# Convert /var/log/github-audit.log into Elasticsearch format.
# Import with: gzip --decompress --stdout audit_log-$index.gz | /usr/local/share/enterprise/ghe-es-load-json 'http://localhost:9200/audit_log-$index.gz'

import json
import re
import os
import gzip
import argparse
import datetime
from pathlib import Path
import subprocess

def convert_log_line(line):
    """Convert a raw audit log line to Elasticsearch format"""
    # Extract the JSON part from the line (everything after 'github_audit: ')
    match = re.search(r'github_audit: (.+)$', line)
    if not match:
        return None

    try:
        # Parse the JSON data
        data = json.loads(match.group(1))

        # Extract the document ID
        doc_id = data.get("data", {}).get("_document_id")
        if not doc_id:
            # Generate a random ID if none exists
            import uuid
            doc_id = str(uuid.uuid4())

        # Get date in YYYY-MM-1 format (using first day of the month) from the timestamp
        timestamp = data.get("created_at")
        if timestamp:
            date_obj = datetime.datetime.fromtimestamp(timestamp/1000)
            # Format as YYYY-MM-1 (first day of the month) with zero-padded month
            date_str = f"{date_obj.year}-{date_obj.month:02d}-1"
        else:
            # If no timestamp, use current date but first day of month
            now = datetime.datetime.now()
            date_str = f"{now.year}-{now.month:02d}-1"

        # Create the index name with format audit_log-1-YYYY-MM-1
        index_name = f"audit_log-1-{date_str}"

        # Create the source object in the correct format
        source = {}

        # Copy over the basic fields
        for field in ["action", "actor_ip", "created_at"]:
            if field in data:
                source[field] = data[field]

        # Add timestamp if available
        if "@timestamp" in data:
            source["@timestamp"] = data["@timestamp"]
        elif "created_at" in data:
            source["@timestamp"] = data["created_at"]

        # Add business info
        if "business" in data:
            source["business"] = data["business"]
        if "business_id" in data:
            source["business_id"] = data["business_id"]

        # Add actor location if available
        if "actor_location" in data:
            source["actor_location"] = data["actor_location"]

        # Handle data object
        source["data"] = {}
        if "data" in data:
            # Copy command and other fields
            for key, value in data["data"].items():
                if key != "_document_id" and key != "@timestamp" and key != "category_type":
                    source["data"][key] = value

            # Make sure category_type is in data
            if "category_type" in data["data"]:
                source["data"]["category_type"] = data["data"]["category_type"]
            elif "category_type" in data:
                source["data"]["category_type"] = data["category_type"]

        # Create the Elasticsearch document structure exactly matching original format
        es_doc = {
            "_index": index_name,
            "_id": doc_id,
            "_source": source
        }

        # Convert to JSON with no extra spaces
        es_json = json.dumps(es_doc, separators=(',', ':'))

        return es_json, index_name
    except json.JSONDecodeError:
        print(f"Error parsing JSON: {line}")
        return None

def process_log_file(input_file, output_dir):
    """Process the GitHub audit log file and convert to Elasticsearch format"""
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Dictionary to store documents by index
    index_docs = {}

    # Read and process the input file
    with open(input_file, 'r') as f:
        for line in f:
            result = convert_log_line(line.strip())
            if result:
                es_json, index_name = result
                if index_name not in index_docs:
                    index_docs[index_name] = []
                index_docs[index_name].append(es_json)

    # Write documents to gzipped files by index
    for index_name, docs in index_docs.items():
        output_file = os.path.join(output_dir, f"{index_name}.gz")
        print(f"Writing {len(docs)} documents to {output_file}")

        # Use pigz if available, otherwise use gzip
        try:
            # Check if pigz is installed
            subprocess.run(['which', 'pigz'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            use_pigz = True
        except subprocess.CalledProcessError:
            use_pigz = False
            print("Warning: pigz not found, using standard gzip instead")

        if use_pigz:
            # Use pigz for compression
            with subprocess.Popen(['pigz', '-c'], stdin=subprocess.PIPE, stdout=open(output_file, 'wb')) as proc:
                for doc in docs:
                    proc.stdin.write((doc + '\n').encode())
        else:
            # Fall back to standard gzip
            with gzip.open(output_file, 'wt') as out:
                for doc in docs:
                    out.write(doc + '\n')

def main():
    parser = argparse.ArgumentParser(description='Convert GitHub audit logs to Elasticsearch format')
    parser.add_argument('input_file', help='Input audit log file')
    parser.add_argument('--output-dir', '-o', default='./output',
                        help='Output directory for converted logs (default: ./output)')
    args = parser.parse_args()

    process_log_file(args.input_file, args.output_dir)
    print(f"Conversion complete. Files saved to {args.output_dir}")

if __name__ == "__main__":
    main()
