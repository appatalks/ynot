#!/bin/bash

set -euo pipefail

# Configuration
MAX_ITERATIONS=${MAX_ITERATIONS:-1000}
SLEEP_BETWEEN_TESTS=${SLEEP_BETWEEN_TESTS:-1}
LOG_FILE=${LOG_FILE:-"stress-test-$(date -u +%Y%m%dT%H%M%SZ).log"}
GITHUB_TOKEN=${GITHUB_TOKEN:-""}

# Counters
SUCCESS_COUNT=0
FAILURE_COUNT=0
ITERATION=0

# URLs to test
urls=(
  "https://api.github.com"
)

echo "=== GitHub Connect API Stress Test ===" | tee -a "$LOG_FILE"
echo "Start: $(date -u)" | tee -a "$LOG_FILE"
echo "Max iterations: $MAX_ITERATIONS" | tee -a "$LOG_FILE"
echo "Sleep between tests: ${SLEEP_BETWEEN_TESTS}s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Certificate revocation check
echo "Checking certificate revocation connectivity..." | tee -a "$LOG_FILE"
results=$(curl -vvk https://api.github.com/ -w '\n%{certs}\n' 2>&1 || true)
if [[ $results == *"unable to check revocation"* ]]; then
  echo "⚠ Certificate revocation authority unreachable (firewall/proxy issue)" | tee -a "$LOG_FILE"
else
  echo "✓ Certificate revocation authority reachable" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# Stress test loop
while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "=== Iteration $ITERATION at $TIMESTAMP ===" | tee -a "$LOG_FILE"

  ITERATION_FAILED=false

  for url in "${urls[@]}"; do
    if [[ -n "$GITHUB_TOKEN" ]]; then
      CURL_OUTPUT=$(curl -L -o /dev/null -s -w "http_code:%{http_code}\ntime_namelookup:%{time_namelookup}\ntime_connect:%{time_connect}\ntime_appconnect:%{time_appconnect}\ntime_pretransfer:%{time_pretransfer}\ntime_starttransfer:%{time_starttransfer}\ntime_total:%{time_total}" -H "Authorization: Bearer $GITHUB_TOKEN" "$url" 2>/dev/null || echo "http_code:000")
    else
      CURL_OUTPUT=$(curl -L -o /dev/null -s -w "http_code:%{http_code}\ntime_namelookup:%{time_namelookup}\ntime_connect:%{time_connect}\ntime_appconnect:%{time_appconnect}\ntime_pretransfer:%{time_pretransfer}\ntime_starttransfer:%{time_starttransfer}\ntime_total:%{time_total}" "$url" 2>/dev/null || echo "http_code:000")
    fi

    HTTP_CODE=$(echo "$CURL_OUTPUT" | grep "^http_code:" | cut -d: -f2)
    TIME_DNS=$(echo "$CURL_OUTPUT" | grep "^time_namelookup:" | cut -d: -f2)
    TIME_CONNECT=$(echo "$CURL_OUTPUT" | grep "^time_connect:" | cut -d: -f2)
    TIME_TLS=$(echo "$CURL_OUTPUT" | grep "^time_appconnect:" | cut -d: -f2)
    TIME_TTFB=$(echo "$CURL_OUTPUT" | grep "^time_starttransfer:" | cut -d: -f2)
    TIME_TOTAL=$(echo "$CURL_OUTPUT" | grep "^time_total:" | cut -d: -f2)

    TIME_DNS_MS=$(awk "BEGIN {printf \"%.0f\", $TIME_DNS * 1000}")
    TIME_CONNECT_MS=$(awk "BEGIN {printf \"%.0f\", $TIME_CONNECT * 1000}")
    TIME_TLS_MS=$(awk "BEGIN {printf \"%.0f\", ($TIME_TLS - $TIME_CONNECT) * 1000}")
    TIME_TTFB_MS=$(awk "BEGIN {printf \"%.0f\", $TIME_TTFB * 1000}")
    TIME_TOTAL_MS=$(awk "BEGIN {printf \"%.0f\", $TIME_TOTAL * 1000}")

    if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
      echo "  ✓ $url → HTTP $HTTP_CODE (Total: ${TIME_TOTAL_MS}ms | DNS: ${TIME_DNS_MS}ms | TCP: ${TIME_CONNECT_MS}ms | TLS: ${TIME_TLS_MS}ms | TTFB: ${TIME_TTFB_MS}ms)" | tee -a "$LOG_FILE"
    else
      echo "  ✗ $url → HTTP $HTTP_CODE (Total: ${TIME_TOTAL_MS}ms) [FAILED]" | tee -a "$LOG_FILE"
      ITERATION_FAILED=true
    fi
  done

  if $ITERATION_FAILED; then
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    echo "  Result: FAILED" | tee -a "$LOG_FILE"
  else
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo "  Result: SUCCESS" | tee -a "$LOG_FILE"
  fi

  echo "" | tee -a "$LOG_FILE"

  # Exit early on first failure if requested
  if [[ "${EXIT_ON_FAILURE:-false}" == "true" ]] && $ITERATION_FAILED; then
    echo "Exiting on first failure (EXIT_ON_FAILURE=true)" | tee -a "$LOG_FILE"
    break
  fi

  sleep "$SLEEP_BETWEEN_TESTS"
done

# Summary
echo "=== Summary ===" | tee -a "$LOG_FILE"
echo "End: $(date -u)" | tee -a "$LOG_FILE"
echo "Total iterations: $ITERATION" | tee -a "$LOG_FILE"
echo "Successful: $SUCCESS_COUNT" | tee -a "$LOG_FILE"
echo "Failed: $FAILURE_COUNT" | tee -a "$LOG_FILE"
echo "Success rate: $(awk "BEGIN {printf \"%.2f\", ($SUCCESS_COUNT / $ITERATION) * 100}")%" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"

if [[ $FAILURE_COUNT -gt 0 ]]; then
  exit 1
fi
