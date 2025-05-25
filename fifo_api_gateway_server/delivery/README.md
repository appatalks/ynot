## API Endpoint Integration Examples

----

### Example: GitHub API Integration

- Save GitHub API Call:
  ```bash
  curl -k -X POST https://127.0.0.1:5000/api/save -H "Content-Type: application/json" -d '{"data": "{\"headers\": {\"Accept\": \"application/vnd.github+json\", \"Authorization\": \"Bearer 
  <TOKEN>\", \"X-GitHub-Api-Version\": \"2022-11-28\"}, \"url\": \"https://git.example.com/api/v3/user\"}"}'
  {"status": "success"}
  ```

- Retrieve GitHub API Call:
  ```bash
  bash github_api_delivery.sh
  { "login": "octocat", "id": 10, ... }
  ```

----

### Example: OpenAI API Integration

- Save OpenAI API Call
  ```bash
  curl -k -X POST https://127.0.0.1:5000/api/save -H "Content-Type: application/json" -d '{"data": "{\"openai_token\": \"<OPENAI_API_KEY>\", \"data\": {\"model\": \"gpt-4\", \"messages\": 
  [{\"role\": \"system\", \"content\": \"You are a helpful assistant.\"}, {\"role\": \"user\", \"content\": \"Hello!\"}]}}"}'
  {"status":"success"}
  ```

- Retrieve OpenAI API Call:
  ```bash
  bash openai_api_delivery.sh 
  { "id": "c***", "object": "chat.completion", "created": 1***, "model": "gpt-4-0613", "choices": [ { "index": 0, "message": { "role": "assistant", 
  "content": "Hello! How can I assist you today?" } ... }
  ```

----

### Example: Yahoo Finance API Integration

- Save Yahoo Finance API Call
  ```bash
  curl -k -X POST https://localhost:5000/api/save -H "Content-Type: application/json" -d '{"data": "{\"headers\": {\"Accept\": 
  \"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8\", \"url\": 
  \"https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d\"}}"}'
  {"status":"success"}
  ```

- Retrieve Yahoo Finance API Call:
  ```bash
  bash api_fifo_yahoo.sh
  {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL" ... },
  ```
