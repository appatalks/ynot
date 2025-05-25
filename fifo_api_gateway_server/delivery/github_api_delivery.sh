#!/bin/bash

# Fetch the data from the local API
response=$(curl -k -s -X GET https://localhost/api/deliver)

# Extract the data field from the response
data=$(echo $response | jq -r '.data')

# Parse the JSON string to extract headers and URL
accept=$(echo $data | jq -r '.headers.Accept')
authorization=$(echo $data | jq -r '.headers.Authorization')
api_version=$(echo $data | jq -r '.headers["X-GitHub-Api-Version"]')
url=$(echo $data | jq -r '.url')

# Mask the Authorization header for logging
masked_authorization=$(echo $authorization | sed 's/\(.\{10\}\).*$/\1****/')

# Make the API call to GitHub and log the response
github_response=$(curl -k -s -L -H "Accept: $accept" -H "Authorization: $authorization" -H "X-GitHub-Api-Version: $api_version" $url)

# Log the request/response to a file along with masked headers
echo "Request: curl -k -s -L -H Accept: $accept -H Authorization: $masked_authorization -H X-GitHub-Api-Version: $api_version $url" >> github_api_response.log 
echo "Response: $github_response" >> github_api_response.log

# Print the response to the console (optional)
echo $github_response
