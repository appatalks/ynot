#!/usr/bin/env bash
set -e

API_DELIVER_ENDPOINT="https://localhost:5000/api/deliver"

fetch_data_from_api_gateway() {
  curl -k -s -X GET "$API_DELIVER_ENDPOINT" -H "Content-Type: application/json"
}

results=$(fetch_data_from_api_gateway)
data=$(echo "$results" | jq -r '.data')
decoded_data=$(echo "$data")
url=$(echo "$decoded_data" | jq -r '.headers.url')
response=$(curl -s "$url")

# Print response from Yahoo Finance API
echo "$response"
