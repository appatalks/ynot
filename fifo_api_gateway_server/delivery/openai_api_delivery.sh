#!/bin/bash

# Fetch the data from the local API
response=$(curl -k -s -X GET https://127.0.0.1:5000/api/deliver)

# Extract the data field from the response
data=$(echo $response | jq -r '.data')

# Extract OpenAI API details from the data
openai_token=$(echo $data | jq -r '.openai_token')
model=$(echo $data | jq -r '.data.model')
messages=$(echo $data | jq -r '.data.messages')

# Prepare the JSON payload for the OpenAI API
payload=$(jq -n --arg model "$model" --argjson messages "$messages" '{
  model: $model,
  messages: $messages
}')

# Make the API call to OpenAI
openai_response=$(curl -s -X POST https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $openai_token" \
  -d "$payload")

# Log the response to a file
echo $openai_response >> openai_api_response.log

# Print the response to the console (optional)
echo $openai_response
